"""Add date range filter to get_user_files and list_files endpoint."""
import ast

# === 1. Fix get_user_files in file_service.py ===
with open('/mnt/datadisk/home/yuan/mygithub/share_timeline/server/app/services/file_service.py', 'r') as f:
    content = f.read()

old_func = '''async def get_user_files(
    db: AsyncSession, user_id: int, page: int = 0, size: int = 0
) -> list[dict]:
    """Fetch files from per-user table, with optional pagination."""
    await ensure_table(db, user_id)
    table = _table_name(user_id)
    try:
        sql = f"SELECT {_COLS_STR} FROM {table} ORDER BY receivedAt DESC"
        if size > 0:
            sql += f" LIMIT {size} OFFSET {page * size}"
        result = await db.execute(text(sql))
        return [row_to_dict(r) for r in result.mappings().all()]
    except Exception:
        return []'''

new_func = '''async def get_user_files(
    db: AsyncSession, user_id: int, page: int = 0, size: int = 0,
    start_date: str | None = None, end_date: str | None = None,
) -> list[dict]:
    """Fetch files from per-user table, with optional pagination and date filter."""
    await ensure_table(db, user_id)
    table = _table_name(user_id)
    try:
        sql = f"SELECT {_COLS_STR} FROM {table} WHERE 1=1"
        if start_date:
            sql += f" AND receivedAt >= '{start_date}'"
        if end_date:
            sql += f" AND receivedAt <= '{end_date}'"
        sql += " ORDER BY receivedAt DESC"
        if size > 0:
            sql += f" LIMIT {size} OFFSET {page * size}"
        result = await db.execute(text(sql))
        return [row_to_dict(r) for r in result.mappings().all()]
    except Exception:
        return []'''

content = content.replace(old_func, new_func)

# Also update count_user_files to support date filter
old_cnt = '''async def count_user_files(db: AsyncSession, user_id: int) -> int:
    table = _table_name(user_id)
    try:
        result = await db.execute(text(f"SELECT COUNT(*) AS cnt FROM {table}"))
        row = result.one()
        return row[0] if row else 0
    except Exception:
        return 0'''

new_cnt = '''async def count_user_files(db: AsyncSession, user_id: int, start_date: str | None = None, end_date: str | None = None) -> int:
    table = _table_name(user_id)
    try:
        sql = f"SELECT COUNT(*) AS cnt FROM {table} WHERE 1=1"
        if start_date:
            sql += f" AND receivedAt >= '{start_date}'"
        if end_date:
            sql += f" AND receivedAt <= '{end_date}'"
        result = await db.execute(text(sql))
        row = result.one()
        return row[0] if row else 0
    except Exception:
        return 0'''

content = content.replace(old_cnt, new_cnt)

with open('/mnt/datadisk/home/yuan/mygithub/share_timeline/server/app/services/file_service.py', 'w') as f:
    f.write(content)
ast.parse(content)
print('file_service OK')

# === 2. Fix list_files endpoint ===
with open('/mnt/datadisk/home/yuan/mygithub/share_timeline/server/app/routers/files.py', 'r') as f:
    content = f.read()

old_list = '''async def list_files(
    page: int = 0,
    size: int = 20,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    records = await file_service.get_user_files(db, user.id, page=page, size=size)
    total = await file_service.count_user_files(db, user.id)
    return {"files": records, "total": total}'''

new_list = '''async def list_files(
    page: int = 0,
    size: int = 20,
    start_date: str | None = None,
    end_date: str | None = None,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    records = await file_service.get_user_files(db, user.id, page=page, size=size, start_date=start_date, end_date=end_date)
    total = await file_service.count_user_files(db, user.id, start_date=start_date, end_date=end_date)
    return {"files": records, "total": total}'''

content = content.replace(old_list, new_list)

with open('/mnt/datadisk/home/yuan/mygithub/share_timeline/server/app/routers/files.py', 'w') as f:
    f.write(content)
ast.parse(content)
print('router OK')
