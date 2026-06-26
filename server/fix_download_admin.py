"""Add admin all-table search to download endpoint."""
with open('/mnt/datadisk/home/yuan/mygithub/share_timeline/server/app/routers/files.py', 'r') as f:
    content = f.read()

old = '''    if not record and request.session.get("admin_user_id"):
        admin_id = request.session["admin_user_id"]
        admin_records = await file_service.get_user_files(db, admin_id)
        for r in admin_records:
            if r["id"] == file_id:
                record = r
                break'''

new = '''    # Admin: search all user tables
    if not record and user and user.is_admin:
        from app.services.file_service import _table_name as _tn
        r = await db.execute(select(User))
        for u in r.scalars().all():
            try:
                tbl = _tn(u.id)
                r2 = await db.execute(text(f"SELECT * FROM {tbl} WHERE id = :id"), {"id": file_id})
                row = r2.mappings().one_or_none()
                if row:
                    record = dict(row)
                    break
            except Exception:
                continue

    if not record and request.session.get("admin_user_id"):
        admin_id = request.session["admin_user_id"]
        admin_records = await file_service.get_user_files(db, admin_id)
        for r in admin_records:
            if r["id"] == file_id:
                record = r
                break'''

content = content.replace(old, new)

with open('/mnt/datadisk/home/yuan/mygithub/share_timeline/server/app/routers/files.py', 'w') as f:
    f.write(content)

import ast
ast.parse(content)
print('OK')
