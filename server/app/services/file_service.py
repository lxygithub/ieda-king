from datetime import datetime

from sqlalchemy import delete, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.file_record import FileRecord


async def get_user_files(
    db: AsyncSession, user_id: int
) -> list[FileRecord]:
    result = await db.execute(
        select(FileRecord)
        .where(FileRecord.user_id == user_id)
        .order_by(FileRecord.receivedAt.desc())
    )
    return list(result.scalars().all())


async def get_all_files(
    db: AsyncSession, user_id: int | None = None
) -> list[FileRecord]:
    query = select(FileRecord).order_by(FileRecord.receivedAt.desc())
    if user_id is not None:
        query = query.where(FileRecord.user_id == user_id)
    result = await db.execute(query)
    return list(result.scalars().all())


async def create_file(
    db: AsyncSession, user_id: int, data: dict
) -> FileRecord:
    # Parse receivedAt from ISO string if present
    if "receivedAt" in data and isinstance(data["receivedAt"], str):
        try:
            data["receivedAt"] = datetime.fromisoformat(data["receivedAt"])
        except ValueError:
            del data["receivedAt"]

    record = FileRecord(user_id=user_id, **data)
    db.add(record)
    await db.flush()
    await db.refresh(record)
    return record


async def delete_user_file(
    db: AsyncSession, file_id: str, user_id: int
) -> FileRecord | None:
    result = await db.execute(
        select(FileRecord).where(
            FileRecord.id == file_id, FileRecord.user_id == user_id
        )
    )
    record = result.scalar_one_or_none()
    if record:
        await db.delete(record)
    return record


async def delete_file_as_admin(
    db: AsyncSession, file_id: str
) -> FileRecord | None:
    result = await db.execute(
        select(FileRecord).where(FileRecord.id == file_id)
    )
    record = result.scalar_one_or_none()
    if record:
        await db.delete(record)
    return record


async def clear_user_files(
    db: AsyncSession, user_id: int
) -> int:
    result = await db.execute(
        delete(FileRecord).where(FileRecord.user_id == user_id)
    )
    return result.rowcount


async def count_user_files(
    db: AsyncSession, user_id: int
) -> int:
    result = await db.execute(
        select(func.count())
        .select_from(FileRecord)
        .where(FileRecord.user_id == user_id)
    )
    return result.scalar_one()
