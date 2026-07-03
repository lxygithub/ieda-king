"""Admin REST API endpoints for SPA frontend."""
import json

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models.user import User
from app.services import file_service
from app.services.auth_service import verify_password, hash_password

router = APIRouter(prefix="/api/admin", tags=["admin-api"])


# ===== Auth =====

async def _get_admin_user(request: Request, db: AsyncSession) -> User:
    """Get current admin user from session. Raises 401 if not authenticated."""
    uid = request.session.get("admin_user_id")
    if uid is None:
        raise HTTPException(status_code=401, detail="Not authenticated")
    result = await db.execute(select(User).where(User.id == uid))
    user = result.scalar_one_or_none()
    if not user:
        request.session.clear()
        raise HTTPException(status_code=401, detail="User not found")
    if not user.is_admin:
        raise HTTPException(status_code=403, detail="Admin access required")
    return user


class LoginRequest(BaseModel):
    username: str
    password: str


class LoginResponse(BaseModel):
    success: bool
    user_id: int | None = None
    username: str | None = None
    is_admin: bool = False
    error: str | None = None


@router.post("/auth/login", response_model=LoginResponse)
async def api_login(
    request: Request,
    body: LoginRequest,
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(User).where(User.username == body.username))
    user = result.scalar_one_or_none()
    if not user or not verify_password(body.password, user.password_hash):
        return LoginResponse(success=False, error="用户名或密码错误")
    request.session["admin_user_id"] = user.id
    request.session["admin_username"] = user.username
    request.session["admin_is_admin"] = user.is_admin
    return LoginResponse(success=True, user_id=user.id, username=user.username, is_admin=user.is_admin)


@router.post("/auth/logout")
async def api_logout(request: Request):
    request.session.clear()
    return {"success": True}


@router.get("/auth/me")
async def api_me(request: Request, db: AsyncSession = Depends(get_db)):
    uid = request.session.get("admin_user_id")
    if uid is None:
        raise HTTPException(status_code=401, detail="Not authenticated")
    result = await db.execute(select(User).where(User.id == uid))
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=401, detail="User not found")
    return {
        "id": user.id,
        "username": user.username,
        "is_admin": user.is_admin,
    }


# ===== Dashboard =====

@router.get("/dashboard")
async def api_dashboard(request: Request, db: AsyncSession = Depends(get_db)):
    uid = request.session.get("admin_user_id")
    is_admin = request.session.get("admin_is_admin", False)
    if is_admin:
        user_count = (await db.execute(select(func.count()).select_from(User))).scalar_one()
        file_count = 0
        all_users = (await db.execute(select(User))).scalars().all()
        for u in all_users:
            file_count += await file_service.count_user_files(db, u.id)
        return {"user_count": user_count, "file_count": file_count, "is_admin": True}
    else:
        my_count = await file_service.count_user_files(db, uid)
        return {"file_count": my_count, "is_admin": False}


# ===== Users =====

@router.get("/users")
async def api_users_list(request: Request, db: AsyncSession = Depends(get_db)):
    _get_admin_user(request, db)
    result = await db.execute(select(User).order_by(User.created_at.desc()))
    users = result.scalars().all()
    return [
        {
            "id": u.id,
            "username": u.username,
            "is_admin": u.is_admin,
            "created_at": u.created_at.isoformat() if u.created_at else None,
        }
        for u in users
    ]


@router.get("/users/{user_id}")
async def api_user_detail(user_id: int, request: Request, db: AsyncSession = Depends(get_db)):
    _get_admin_user(request, db)
    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    files = await file_service.get_user_files(db, user_id)
    return {
        "user": {
            "id": user.id,
            "username": user.username,
            "is_admin": user.is_admin,
            "created_at": user.created_at.isoformat() if user.created_at else None,
        },
        "files": files,
    }


class CreateUserRequest(BaseModel):
    username: str
    password: str
    is_admin: bool = False


@router.post("/users")
async def api_create_user(
    request: Request,
    body: CreateUserRequest,
    db: AsyncSession = Depends(get_db),
):
    _get_admin_user(request, db)
    result = await db.execute(select(User).where(User.username == body.username))
    if result.scalar_one_or_none():
        raise HTTPException(status_code=409, detail="用户名已存在")
    user = User(username=body.username, password_hash=hash_password(body.password), is_admin=body.is_admin)
    db.add(user)
    await db.flush()
    return {"id": user.id, "username": user.username}


@router.delete("/users/{user_id}")
async def api_delete_user(user_id: int, request: Request, db: AsyncSession = Depends(get_db)):
    admin = _get_admin_user(request, db)
    if user_id == admin.id:
        raise HTTPException(status_code=400, detail="不能删除自己")
    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    await db.delete(user)
    return {"success": True}


class ChangePasswordRequest(BaseModel):
    new_password: str


@router.post("/users/{user_id}/change-password")
async def api_change_password(
    user_id: int,
    body: ChangePasswordRequest,
    request: Request,
    db: AsyncSession = Depends(get_db),
):
    _get_admin_user(request, db)
    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    user.password_hash = hash_password(body.new_password)
    return {"success": True}


class ChangeUsernameRequest(BaseModel):
    new_username: str


@router.post("/users/{user_id}/change-username")
async def api_change_username(
    user_id: int,
    body: ChangeUsernameRequest,
    request: Request,
    db: AsyncSession = Depends(get_db),
):
    admin = _get_admin_user(request, db)
    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    if user.is_admin:
        raise HTTPException(status_code=400, detail="不能修改管理员用户名")
    dup = await db.execute(select(User).where(User.username == body.new_username))
    if dup.scalar_one_or_none():
        raise HTTPException(status_code=409, detail="用户名已存在")
    user.username = body.new_username
    return {"success": True}


# ===== Files =====

@router.get("/files")
async def api_files_list(request: Request, db: AsyncSession = Depends(get_db)):
    _get_admin_user(request, db)
    files = await file_service.get_all_files(db)
    return files


@router.put("/files/{file_id}")
async def api_update_file(
    file_id: str,
    request: Request,
    name: str | None = None,
    tags: list[str] | None = None,
    db: AsyncSession = Depends(get_db),
):
    _get_admin_user(request, db)
    tags_json = json.dumps(tags, ensure_ascii=False) if tags is not None else None
    result = await file_service.update_file_meta(db, file_id, name=name, tags=tags_json)
    if not result:
        raise HTTPException(status_code=404, detail="File not found")
    return {"success": True}


@router.delete("/files/{file_id}")
async def api_delete_file(file_id: str, request: Request, db: AsyncSession = Depends(get_db)):
    _get_admin_user(request, db)
    await file_service.delete_file_as_admin(db, file_id)
    return {"success": True}


class BatchDeleteRequest(BaseModel):
    file_ids: list[str]


@router.post("/files/batch-delete")
async def api_batch_delete_files(
    body: BatchDeleteRequest,
    request: Request,
    db: AsyncSession = Depends(get_db),
):
    _get_admin_user(request, db)
    for fid in body.file_ids:
        await file_service.delete_file_as_admin(db, fid)
    return {"success": True, "deleted": len(body.file_ids)}
