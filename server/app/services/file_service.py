from datetime import datetime
from typing import Any

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession


def _storage_id(user_id: int) -> int:
    return user_id + 999


def _table_name(user_id: int) -> str:
    return f"files_{_storage_id(user_id)}"


# Shared table for legacy/backward-compat reads
_SHARED_TABLE = "files"

# Columns shared between per-user tables and the shared table
_COLS = (
    "id", "name", "type", "localPath", "textContent", "sourceUri",
    "receivedAt", "mimeType", "fileSize", "s3Key", "uploadProgress",
    "uploadError", "uploadId", "uploadedParts", "tags", "description"
)
_COLS_STR = ", ".join(_COLS)
_PLACEHOLDERS = ", ".join(f":{c}" for c in _COLS)

# ===== Schema =====

_CREATE_SQL = """CREATE TABLE IF NOT EXISTS {table} (
  id VARCHAR(64) PRIMARY KEY,
  name TEXT NOT NULL,
  type VARCHAR(50) NOT NULL,
  localPath TEXT,
  textContent LONGTEXT,
  sourceUri VARCHAR(2000),
  receivedAt VARCHAR(32),
  mimeType VARCHAR(100),
  fileSize BIGINT DEFAULT 0,
  s3Key VARCHAR(500),
  uploadProgress DOUBLE,
  uploadError TEXT,
  uploadId VARCHAR(255),
  uploadedParts TEXT,
  tags TEXT,
  description TEXT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4"""


async def ensure_table(db: AsyncSession, user_id: int):
    """Create per-user table if it doesn't exist."""
    await db.execute(text(_CREATE_SQL.format(table=_table_name(user_id))))


# ===== To dict helper =====

def row_to_dict(row) -> dict[str, Any]:
    """Convert a raw DB row (RowMapping) to the API response format."""
    d = dict(row)
    # receivedAt might be datetime or string from shared table
    if d.get("receivedAt"):
        if hasattr(d["receivedAt"], "isoformat"):
            d["receivedAt"] = d["receivedAt"].isoformat()
    return d


# ===== CRUD =====

async def get_user_files(
    db: AsyncSession, user_id: int
) -> list[dict]:
    """Fetch files from per-user table first, then shared table."""
    table = _table_name(user_id)
    rows = []
    # Per-user table
    try:
        result = await db.execute(
            text(f"SELECT {_COLS_STR} FROM {table} ORDER BY receivedAt DESC")
        )
        rows = [row_to_dict(r) for r in result.mappings().all()]
    except Exception:
        pass  # table may not exist yet
    # Also fetch from shared table for legacy data
    try:
        result = await db.execute(
            text(f"SELECT {_COLS_STR} FROM {_SHARED_TABLE} WHERE user_id = :uid ORDER BY receivedAt DESC"),
            {"uid": user_id},
        )
        shared_rows = [row_to_dict(r) for r in result.mappings().all()]
        # Merge: per-user takes priority, dedup by id
        seen = {r["id"] for r in rows}
        for r in shared_rows:
            if r["id"] not in seen:
                rows.append(r)
    except Exception:
        pass
    return rows


async def get_all_files(
    db: AsyncSession, user_id: int | None = None
) -> list[dict]:
    """Admin: fetch from all tables. Slow for large datasets."""
    rows = []
    # Shared table
    try:
        if user_id:
            result = await db.execute(
                text(f"SELECT {_COLS_STR}, user_id FROM {_SHARED_TABLE} WHERE user_id = :uid ORDER BY receivedAt DESC"),
                {"uid": user_id},
            )
        else:
            result = await db.execute(
                text(f"SELECT {_COLS_STR}, user_id FROM {_SHARED_TABLE} ORDER BY receivedAt DESC LIMIT 200")
            )
        rows = [row_to_dict(r) for r in result.mappings().all()]
    except Exception:
        pass
    return rows


async def create_file(
    db: AsyncSession, user_id: int, data: dict
) -> dict:
    """Insert file into per-user table."""
    table = _table_name(user_id)
    await ensure_table(db, user_id)

    # Parse receivedAt
    if "receivedAt" in data and isinstance(data["receivedAt"], str):
        data["receivedAt"] = data["receivedAt"]  # keep as string for VARCHAR

    cols = ", ".join(data.keys())
    vals = ", ".join(f":{k}" for k in data.keys())
    await db.execute(
        text(f"INSERT INTO {table} ({cols}) VALUES ({vals})"),
        data,
    )
    return data


async def update_file_s3(
    db: AsyncSession, user_id: int, file_id: str, s3_key: str, file_size: int, mime_type: str | None
):
    """Update s3Key + fileSize on an existing file."""
    await ensure_table(db, user_id)
    table = _table_name(user_id)
    await db.execute(
        text(f"UPDATE {table} SET s3Key = :k, fileSize = :sz, mimeType = :mt WHERE id = :id"),
        {"k": s3_key, "sz": file_size, "mt": mime_type, "id": file_id},
    )


async def delete_user_file(
    db: AsyncSession, file_id: str, user_id: int
) -> bool:
    """Delete from per-user table. Returns True if deleted."""
    table = _table_name(user_id)
    result = await db.execute(
        text(f"DELETE FROM {table} WHERE id = :id"),
        {"id": file_id},
    )
    if result.rowcount > 0:
        return True
    # Also try shared table (legacy)
    result = await db.execute(
        text(f"DELETE FROM {_SHARED_TABLE} WHERE id = :id AND user_id = :uid"),
        {"id": file_id, "uid": user_id},
    )
    return result.rowcount > 0


async def delete_file_as_admin(
    db: AsyncSession, file_id: str
) -> bool:
    """Delete from any table. Try shared, then any per-user table."""
    # Try shared table
    result = await db.execute(
        text(f"DELETE FROM {_SHARED_TABLE} WHERE id = :id"),
        {"id": file_id},
    )
    if result.rowcount > 0:
        return True
    # For per-user tables, we need to search. Try common ones.
    # This is a limitation — admin delete on per-user tables requires knowing the user.
    return False


async def clear_user_files(
    db: AsyncSession, user_id: int
) -> int:
    table = _table_name(user_id)
    result = await db.execute(text(f"DELETE FROM {table} WHERE 1=1"))
    count = result.rowcount or 0
    # Also clear shared table
    result = await db.execute(
        text(f"DELETE FROM {_SHARED_TABLE} WHERE user_id = :uid"),
        {"uid": user_id},
    )
    return count + (result.rowcount or 0)


async def count_user_files(
    db: AsyncSession, user_id: int
) -> int:
    table = _table_name(user_id)
    try:
        result = await db.execute(text(f"SELECT COUNT(*) AS cnt FROM {table}"))
        row = result.one()
        return row[0] if row else 0
    except Exception:
        return 0
