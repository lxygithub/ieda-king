#!/usr/bin/env python3
import sys

filepath = "/mnt/datadisk/home/yuan/mygithub/share_timeline/server/app/routers/files.py"

with open(filepath, "r") as f:
    content = f.read()

# Find the end of update-metadata endpoint
marker = '''    return {"success": True, "updated": result.rowcount > 0 if result.rowcount else False}'''

new_endpoint = '''    return {"success": True, "updated": result.rowcount > 0 if result.rowcount else False}


@router.post("/update-text")
async def update_file_text(
    file_id: str = Form(...),
    content: str = Form(...),
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Update file text content."""
    await file_service.ensure_table(db, user.id)
    table = file_service._table_name(user.id)

    sql = f"UPDATE {table} SET textContent = :content WHERE id = :id"
    result = await db.execute(text(sql), {"content": content, "id": file_id})

    return {"success": True, "updated": result.rowcount > 0 if result.rowcount else False}'''

content = content.replace(marker, new_endpoint)

with open(filepath, "w") as f:
    f.write(content)

print("Added update-text endpoint")
