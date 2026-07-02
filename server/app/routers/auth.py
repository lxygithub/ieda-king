from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.database import get_db
from app.models.user import User
from app.dependencies import get_current_user, bearer_scheme
from app.schemas.auth import (
    ChangePasswordRequest,
    ChangeUsernameRequest,
    LoginRequest,
    RegisterRequest,
    RegisterResponse,
    TokenResponse,
    UserResponse,
)
from app.services.auth_service import (
    create_access_token,
    hash_password,
    verify_password,
    store_token,
    remove_user_tokens,
    is_token_valid,
    remove_token,
)

router = APIRouter(prefix="/api/auth", tags=["auth"])


@router.post("/register", response_model=RegisterResponse, status_code=201)
async def register(
    req: RegisterRequest,
    db: AsyncSession = Depends(get_db),
):
    # Check duplicate
    result = await db.execute(
        select(User).where(User.username == req.username)
    )
    if result.scalar_one_or_none():
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Username already taken",
        )

    user = User(
        username=req.username,
        password_hash=hash_password(req.password),
    )
    db.add(user)
    await db.flush()
    await db.refresh(user)

    # Create per-user files table
    from app.services.file_service import ensure_table
    await ensure_table(db, user.id)

    return RegisterResponse(
        message="User registered successfully",
        user=UserResponse(
            id=user.id,
            username=user.username,
            is_admin=user.is_admin,
            created_at=(
                user.created_at.isoformat() if user.created_at else None
            ),
        ),
    )


@router.post("/login", response_model=TokenResponse)
async def login(
    req: LoginRequest,
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(User).where(User.username == req.username)
    )
    user = result.scalar_one_or_none()
    if not user or not verify_password(req.password, user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid username or password",
        )

    # Token rotation: remove all existing tokens for this user
    await remove_user_tokens(db, user.id)

    # Create new token
    expire_minutes = settings.access_token_expire_minutes
    expire_time = datetime.now(timezone.utc) + timedelta(minutes=expire_minutes)
    
    token = create_access_token({
        "sub": str(user.id),
        "username": user.username,
        "is_admin": user.is_admin,
    })

    # Store the new token
    await store_token(db, token, user.id, expire_time)
    await db.commit()

    return TokenResponse(
        access_token=token,
        user_id=user.id,
        username=user.username,
        is_admin=user.is_admin,
    )


@router.post("/logout")
async def logout(
    user: User = Depends(get_current_user),
    credentials: HTTPAuthorizationCredentials = Depends(bearer_scheme),
    db: AsyncSession = Depends(get_db),
):
    # Remove the current token
    await remove_token(db, credentials.credentials)
    await db.commit()
    return {"success": True, "message": "Logged out successfully"}


@router.post("/change-password")
async def change_password(
    req: ChangePasswordRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    if not verify_password(req.old_password, user.password_hash):
        raise HTTPException(status_code=400, detail="原密码错误")
    user.password_hash = hash_password(req.new_password)
    
    # Token rotation: remove all tokens after password change
    await remove_user_tokens(db, user.id)
    await db.commit()
    
    return {"success": True, "message": "密码已修改"}


@router.post("/change-username")
async def change_username(
    req: ChangeUsernameRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    if user.is_admin:
        raise HTTPException(status_code=403, detail="管理员不可修改用户名")
    # Check duplicate
    result = await db.execute(
        select(User).where(User.username == req.new_username)
    )
    if result.scalar_one_or_none():
        raise HTTPException(status_code=409, detail="用户名已被使用")
    user.username = req.new_username
    return {"success": True, "message": "用户名已修改"}
