"""Add pagination params to get_user_files."""
with open('/mnt/datadisk/home/yuan/mygithub/share_timeline/server/app/services/file_service.py', 'r') as f:
    content = f.read()

old_func = '''async def get_user_files(
    db: AsyncSession, user_id: int
) -> list[dict]:
    """Fetch files from per-user table."""
    await ensure_table(db, user_id)
    table = _table_name(user_id)
    try:
        result = await db.execute(
            text(f"SELECT {_COLS_STR} FROM {table} ORDER BY receivedAt DESC")
        )
        return [row_to_dict(r) for r in result.mappings().all()]
    except Exception:
        return []'''

new_func = '''async def get_user_files(
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

content = content.replace(old_func, new_func)

with open('/mnt/datadisk/home/yuan/mygithub/share_timeline/server/app/services/file_service.py', 'w') as f:
    f.write(content)

import ast
ast.parse(content)
print('OK')
