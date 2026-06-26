"""Add type and search params to API endpoints."""
# 1. Update list_files endpoint
with open('/mnt/datadisk/home/yuan/mygithub/share_timeline/server/app/routers/files.py', 'r') as f:
    content = f.read()

old_list = '''async def list_files(
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

new_list = '''async def list_files(
    page: int = 0,
    size: int = 20,
    start_date: str | None = None,
    end_date: str | None = None,
    from fastapi import Query
    file_type: str | None = Query(None, alias="type"),
    search: str | None = None,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    records = await file_service.get_user_files(
        db, user.id, page=page, size=size,
        start_date=start_date, end_date=end_date,
        file_type=file_type, search=search,
    )
    total = await file_service.count_user_files(
        db, user.id, start_date=start_date, end_date=end_date,
        file_type=file_type, search=search,
    )
    return {"files": records, "total": total}'''

content = content.replace(old_list, new_list)

with open('/mnt/datadisk/home/yuan/mygithub/share_timeline/server/app/routers/files.py', 'w') as f:
    f.write(content)

print('router OK')

# 2. Update get_user_files and count_user_files
with open('/mnt/datadisk/home/yuan/mygithub/share_timeline/server/app/services/file_service.py', 'r') as f:
    content = f.read()

old_get = '''async def get_user_files(
    db: AsyncSession, user_id: int, page: int = 0, size: int = 0,
    start_date: str | None = None, end_date: str | None = None,
) -> list[dict]:
    """Fetch files from per-user table, with optional pagination and date filter."""
    await ensure_table(db, user_id)
    table = _table_name(user_id)
    try:
        sql = f"SELECT {_COLS_STR} FROM {table} WHERE 1=1"
        if start_date:
            sql += f" AND receivedAt >= '{start_date}T00:00:00'"
        if end_date:
            sql += f" AND receivedAt <= '{end_date}T23:59:59'"
        sql += " ORDER BY receivedAt DESC"
        if size > 0:
            sql += f" LIMIT {size} OFFSET {page * size}"
        result = await db.execute(text(sql))
        return [row_to_dict(r) for r in result.mappings().all()]
    except Exception:
        return []'''

new_get = '''async def get_user_files(
    db: AsyncSession, user_id: int, page: int = 0, size: int = 0,
    start_date: str | None = None, end_date: str | None = None,
    file_type: str | None = None, search: str | None = None,
) -> list[dict]:
    """Fetch files from per-user table, with optional pagination and filters."""
    await ensure_table(db, user_id)
    table = _table_name(user_id)
    try:
        sql = f"SELECT {_COLS_STR} FROM {table} WHERE 1=1"
        if start_date:
            sql += f" AND receivedAt >= '{start_date}T00:00:00'"
        if end_date:
            sql += f" AND receivedAt <= '{end_date}T23:59:59'"
        if file_type:
            sql += f" AND type = '{file_type}'"
        if search:
            sql += f" AND name LIKE '%{search}%'"
        sql += " ORDER BY receivedAt DESC"
        if size > 0:
            sql += f" LIMIT {size} OFFSET {page * size}"
        result = await db.execute(text(sql))
        return [row_to_dict(r) for r in result.mappings().all()]
    except Exception:
        return []'''

content = content.replace(old_get, new_get)

old_cnt = '''async def count_user_files(
    db: AsyncSession, user_id: int, start_date: str | None = None, end_date: str | None = None
) -> int:
    table = _table_name(user_id)
    try:
        sql = f"SELECT COUNT(*) AS cnt FROM {table} WHERE 1=1"
        if start_date:
            sql += f" AND receivedAt >= '{start_date}T00:00:00'"
        if end_date:
            sql += f" AND receivedAt <= '{end_date}T23:59:59'"
        result = await db.execute(text(sql))
        row = result.one()
        return row[0] if row else 0
    except Exception:
        return 0'''

new_cnt = '''async def count_user_files(
    db: AsyncSession, user_id: int, start_date: str | None = None, end_date: str | None = None,
    file_type: str | None = None, search: str | None = None,
) -> int:
    table = _table_name(user_id)
    try:
        sql = f"SELECT COUNT(*) AS cnt FROM {table} WHERE 1=1"
        if start_date:
            sql += f" AND receivedAt >= '{start_date}T00:00:00'"
        if end_date:
            sql += f" AND receivedAt <= '{end_date}T23:59:59'"
        if file_type:
            sql += f" AND type = '{file_type}'"
        if search:
            sql += f" AND name LIKE '%{search}%'"
        result = await db.execute(text(sql))
        row = result.one()
        return row[0] if row else 0
    except Exception:
        return 0'''

content = content.replace(old_cnt, new_cnt)

with open('/mnt/datadisk/home/yuan/mygithub/share_timeline/server/app/services/file_service.py', 'w') as f:
    f.write(content)

import ast
ast.parse(content)
print('file_service OK')
