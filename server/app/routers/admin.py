from fastapi import APIRouter, Depends, Form, HTTPException, Request
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.templating import Jinja2Templates
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models.file_record import FileRecord
from app.models.user import User
from app.services.auth_service import verify_password

router = APIRouter(prefix="/admin", tags=["admin"])
templates = Jinja2Templates(directory="app/templates/admin")


# ---- Session helpers ----

def _get_admin_id(request: Request) -> int | None:
    return request.session.get("admin_user_id")


async def _require_admin(
    request: Request,
    db: AsyncSession = Depends(get_db),
):
    uid = _get_admin_id(request)
    if uid is None:
        raise HTTPException(status_code=303, detail="Redirecting...")
    result = await db.execute(
        select(User).where(User.id == uid, User.is_admin == True)
    )
    user = result.scalar_one_or_none()
    if not user:
        request.session.clear()
        raise HTTPException(status_code=303)
    return user


# ---- Routes ----

@router.get("/login", response_class=HTMLResponse)
async def login_page(request: Request):
    return templates.TemplateResponse("login.html", {"request": request})


@router.post("/login")
async def login_action(
    request: Request,
    username: str = Form(...),
    password: str = Form(...),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(User).where(User.username == username)
    )
    user = result.scalar_one_or_none()
    if not user or not verify_password(password, user.password_hash) or not user.is_admin:
        return RedirectResponse(
            url="/admin/login?error=1", status_code=303
        )
    request.session["admin_user_id"] = user.id
    request.session["admin_username"] = user.username
    return RedirectResponse(url="/admin/dashboard", status_code=303)


@router.get("/logout")
async def logout(request: Request):
    request.session.clear()
    return RedirectResponse(url="/admin/login", status_code=303)


@router.get("/dashboard", response_class=HTMLResponse)
async def dashboard(
    request: Request,
    db: AsyncSession = Depends(get_db),
    _=Depends(_require_admin),
):
    user_count = (
        await db.execute(select(func.count()).select_from(User))
    ).scalar_one()
    file_count = (
        await db.execute(select(func.count()).select_from(FileRecord))
    ).scalar_one()

    return templates.TemplateResponse("dashboard.html", {
        "request": request,
        "user_count": user_count,
        "file_count": file_count,
        "admin_username": request.session.get("admin_username"),
    })


@router.get("/users", response_class=HTMLResponse)
async def users_list(
    request: Request,
    db: AsyncSession = Depends(get_db),
    _=Depends(_require_admin),
):
    result = await db.execute(
        select(User).order_by(User.created_at.desc())
    )
    users = result.scalars().all()
    return templates.TemplateResponse("users.html", {
        "request": request,
        "users": users,
        "admin_username": request.session.get("admin_username"),
    })


@router.get("/users/{user_id}", response_class=HTMLResponse)
async def user_detail(
    request: Request,
    user_id: int,
    db: AsyncSession = Depends(get_db),
    _=Depends(_require_admin),
):
    result = await db.execute(
        select(User).where(User.id == user_id)
    )
    view_user = result.scalar_one_or_none()
    if not view_user:
        raise HTTPException(status_code=404, detail="User not found")

    files_result = await db.execute(
        select(FileRecord)
        .where(FileRecord.user_id == user_id)
        .order_by(FileRecord.receivedAt.desc())
    )
    files = files_result.scalars().all()

    return templates.TemplateResponse("user_detail.html", {
        "request": request,
        "view_user": view_user,
        "files": files,
        "admin_username": request.session.get("admin_username"),
    })


@router.get("/files", response_class=HTMLResponse)
async def files_list(
    request: Request,
    db: AsyncSession = Depends(get_db),
    _=Depends(_require_admin),
):
    result = await db.execute(
        select(FileRecord).order_by(FileRecord.receivedAt.desc()).limit(200)
    )
    files = result.scalars().all()
    return templates.TemplateResponse("files.html", {
        "request": request,
        "files": files,
        "admin_username": request.session.get("admin_username"),
    })


@router.post("/files/{file_id}/delete")
async def delete_file(
    request: Request,
    file_id: int,
    db: AsyncSession = Depends(get_db),
    _=Depends(_require_admin),
):
    from app.services.file_service import delete_file_as_admin
    await delete_file_as_admin(db, file_id)
    return RedirectResponse(url="/admin/files", status_code=303)
