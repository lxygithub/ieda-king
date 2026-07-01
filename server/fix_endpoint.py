import re

with open("/mnt/datadisk/home/yuan/mygithub/share_timeline/server/app/routers/files.py", "r") as f:
    content = f.read()

# Find and replace the broken update-metadata endpoint
old_endpoint = '''@router.post("/update-metadata")
async def update_file_metadata(
    file_id: str = Form(...),
    tags: str | None = Form(None),
    title: str | None = Form(None),
    description: str | None = Form(None),
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Update file tags and description."""
    await file_service.ensure_table(db, user.id)
    table = file_service._table_name(user.id)

    updates = []
    params = {"id": file_id}

    if tags is not None:
        updates.append("tags = :tags")
        params["tags"] = tags

    if description is not None:
if title is not None:        updates.append("title = :title")        params["title"] = title
        updates.append("description = :description")
if title is not None:        updates.append("title = :title")        params["title"] = title
        params["description"] = description
if title is not None:        updates.append("title = :title")        params["title"] = title

    if not updates:
        return {"success": True, "message": "No updates"}

    sql = f"UPDATE {table} SET {", ".join(updates)} WHERE id = :id"
    result = await db.execute(text(sql), params)

    return {"success": True, "updated": result.rowcount > 0 if result.rowcount else False}'''

new_endpoint = '''@router.post("/update-metadata")
async def update_file_metadata(
    file_id: str = Form(...),
    tags: str | None = Form(None),
    title: str | None = Form(None),
    description: str | None = Form(None),
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Update file tags, title, and description."""
    await file_service.ensure_table(db, user.id)
    table = file_service._table_name(user.id)

    updates = []
    params = {"id": file_id}

    if tags is not None:
        updates.append("tags = :tags")
        params["tags"] = tags

    if title is not None:
        updates.append("title = :title")
        params["title"] = title

    if description is not None:
        updates.append("description = :description")
        params["description"] = description

    if not updates:
        return {"success": True, "message": "No updates"}

    sql = f"UPDATE {table} SET {", ".join(updates)} WHERE id = :id"
    result = await db.execute(text(sql), params)

    return {"success": True, "updated": result.rowcount > 0 if result.rowcount else False}'''

content = content.replace(old_endpoint, new_endpoint)

with open("/mnt/datadisk/home/yuan/mygithub/share_timeline/server/app/routers/files.py", "w") as f:
    f.write(content)

print("Fixed")
