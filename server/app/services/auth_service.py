from datetime import datetime, timedelta, timezone

from jose import JWTError, jwt
from passlib.context import CryptContext

from app.config import settings

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")


def hash_password(password: str) -> str:
    return pwd_context.hash(password)


def verify_password(plain: str, hashed: str) -> bool:
    return pwd_context.verify(plain, hashed)


def create_access_token(data: dict) -> str:
    to_encode = data.copy()
    expire = datetime.now(timezone.utc) + timedelta(
        minutes=settings.access_token_expire_minutes
    )
    to_encode.update({"exp": expire})
    return jwt.encode(
        to_encode, settings.secret_key, algorithm=settings.algorithm
    )


def decode_access_token(token: str) -> dict | None:
    try:
        return jwt.decode(
            token, settings.secret_key, algorithms=[settings.algorithm]
        )
    except JWTError:
        return None

async def store_token(db, token: str, user_id: int, expires_at) -> None:
    """Store a valid token in the database."""
    from app.models.token import Token
    token_record = Token(
        token=token,
        user_id=user_id,
        expires_at=expires_at,
    )
    db.add(token_record)
    await db.flush()


async def remove_user_tokens(db, user_id: int) -> None:
    """Remove all active tokens for a user (token rotation)."""
    from app.models.token import Token
    from sqlalchemy import delete
    await db.execute(delete(Token).where(Token.user_id == user_id))
    await db.flush()


async def is_token_valid(db, token: str) -> bool:
    """Check if a token exists in the active token list."""
    from app.models.token import Token
    from sqlalchemy import select
    from datetime import datetime, timezone
    
    result = await db.execute(
        select(Token).where(
            Token.token == token,
            Token.expires_at > datetime.now(timezone.utc)
        )
    )
    return result.scalar_one_or_none() is not None


async def remove_token(db, token: str) -> None:
    """Remove a specific token."""
    from app.models.token import Token
    from sqlalchemy import delete
    await db.execute(delete(Token).where(Token.token == token))
    await db.flush()
