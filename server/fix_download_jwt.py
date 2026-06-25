"""Add JWT query param support to download endpoint."""
with open('/mnt/datadisk/home/yuan/mygithub/share_timeline/server/app/routers/files.py', 'r') as f:
    lines = f.readlines()

# Find the download function and add JWT decode after docstring
for i, line in enumerate(lines):
    if 'async def download_file(' in line:
        # Find the docstring closing
        for j in range(i, min(i+10, len(lines))):
            if lines[j].strip().endswith('"""'):
                # Insert JWT decode after docstring
                indent = '    '
                jwt_code = [
                    indent + '# Support JWT via query parameter (for external apps/browsers)\n',
                    indent + 'if token and not user:\n',
                    indent + '    from app.services.auth_service import decode_access_token\n',
                    indent + '    p = decode_access_token(token)\n',
                    indent + '    if p:\n',
                    indent + '        uid = int(p.get("sub", 0))\n',
                    indent + '        r = await db.execute(select(User).where(User.id == uid))\n',
                    indent + '        user = r.scalar_one_or_none()\n',
                    '\n',
                ]
                lines[j+1:j+1] = jwt_code
                break
        break

# Also add select import if needed
for i, line in enumerate(lines):
    if 'from sqlalchemy import' in line and 'select' not in line:
        lines[i] = line.rstrip() + ', select\n'
        break

with open('/mnt/datadisk/home/yuan/mygithub/share_timeline/server/app/routers/files.py', 'w') as f:
    f.writelines(lines)

# Also add admin bypass to auth check
with open('/mnt/datadisk/home/yuan/mygithub/share_timeline/server/app/routers/files.py', 'r') as f:
    content = f.read()

old = '''    # Auth check
    is_authorized = False
    if user and any(r["id"] == file_id for r in (await file_service.get_user_files(db, user.id))):
        is_authorized = True
    elif request.session.get("admin_user_id"):
        is_authorized = True'''

new = '''    # Auth check
    is_authorized = False
    if user and any(r["id"] == file_id for r in (await file_service.get_user_files(db, user.id))):
        is_authorized = True
    elif user and user.is_admin:
        is_authorized = True
    elif request.session.get("admin_user_id"):
        is_authorized = True'''

content = content.replace(old, new)

with open('/mnt/datadisk/home/yuan/mygithub/share_timeline/server/app/routers/files.py', 'w') as f:
    f.write(content)

import ast
ast.parse(content)
print('OK')
