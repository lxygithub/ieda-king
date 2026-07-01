#!/usr/bin/env python3
import sys

filepath = "/mnt/datadisk/home/yuan/mygithub/share_timeline/server/app/routers/files.py"

with open(filepath, "r") as f:
    lines = f.readlines()

# Find the update-metadata endpoint
start_idx = None
for i, line in enumerate(lines):
    if '@router.post("/update-metadata")' in line:
        start_idx = i
        break

if start_idx is None:
    print("Endpoint not found")
    sys.exit(1)

# Find the end of the endpoint (next @router or end of file)
end_idx = len(lines)
for i in range(start_idx + 1, len(lines)):
    if lines[i].strip().startswith("@router.") or lines[i].strip().startswith("async def ") and i > start_idx + 1:
        # Check if this is a new route decorator
        if "@router." in lines[i]:
            end_idx = i
            break

# Replace the endpoint
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

    return {"success": True, "updated": result.rowcount > 0 if result.rowcount else False}

'''

lines = lines[:start_idx] + [new_endpoint] + lines[end_idx:]

with open(filepath, "w") as f:
    f.writelines(lines)

print(f"Fixed endpoint at line {start_idx + 1}")
