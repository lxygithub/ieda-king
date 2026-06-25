import ast, re

with open('/mnt/datadisk/home/yuan/mygithub/share_timeline/server/app/routers/files.py', 'r') as f:
    content = f.read()

# 1. Add thumbnail_service import
content = content.replace(
    'from app.services import file_service, s3_service',
    'from app.services import file_service, s3_service, thumbnail_service'
)

# 2. Add thumbnail generation in upload endpoint
old_ret = '''
    await file_service.update_file_s3(db, user.id, file_id, s3_key, file_size, mime_type)

    return {
        "success": True,
        "id": file_id,
        "s3Key": s3_key,
        "fileSize": file_size,
    }'''

new_ret = '''
    await file_service.update_file_s3(db, user.id, file_id, s3_key, file_size, mime_type)

    # Generate thumbnail for images/videos
    thumb_s3_key = None
    img_types = {"image", "video"}
    if file_type in img_types or (mime_type and (mime_type.startswith("image/") or mime_type.startswith("video/"))):
        storage_id = file_service._storage_id(user.id)
        try:
            import app.services.thumbnail_service as _ts
            thumb_s3_key = await _ts.generate_and_upload_thumbnail(
                s3_key, storage_id, file_id, file_type, mime_type,
            )
            if thumb_s3_key:
                await file_service.update_file_s3(db, user.id, file_id, s3_key, file_size, mime_type, thumb_s3_key=thumb_s3_key)
        except Exception as e:
            print(f"[upload] thumb gen failed: {e}")

    return {
        "success": True,
        "id": file_id,
        "s3Key": s3_key,
        "fileSize": file_size,
        "thumbS3Key": thumb_s3_key,
    }'''

content = content.replace(old_ret, new_ret)

# 3. Add thumbnail download endpoint before upload
thumb_ep = '''

@router.get("/{file_id}/thumbnail")
async def download_thumbnail(
    file_id: str,
    token: str | None = None,
    user: User | None = Depends(get_current_user_optional),
    db: AsyncSession = Depends(get_db),
):
    import tempfile
    from app.services.file_service import _table_name as _tn
    from app.services.s3_service import _get_client
    from app.config import settings

    records = []
    check = [user] if user else []
    if not check:
        r = await db.execute(select(User))
        check = list(r.scalars().all())

    for u in check:
        try:
            tbl = _tn(u.id)
            r = await db.execute(
                text("SELECT id, thumbS3Key, s3Key FROM " + tbl + " WHERE id = :id"),
                {"id": file_id},
            )
            row = r.mappings().one_or_none()
            if row:
                d = dict(row)
                records.append(d)
                break
        except Exception:
            continue

    if not records:
        raise HTTPException(status_code=404, detail="Not found")
    target = records[0].get("thumbS3Key") or records[0].get("s3Key")
    if not target:
        raise HTTPException(status_code=404, detail="No thumb avail")

    client = _get_client()
    tmp = tempfile.NamedTemporaryFile(suffix=".jpg", delete=False)
    try:
        client.fget_object(settings.s3_bucket, target, tmp.name)
        tmp.close()
        return FileResponse(
            tmp.name,
            media_type="image/jpeg",
            headers={"Content-Disposition": "inline"},
        )
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"Thumb fail: {e}")
'''

content = content.replace('@router.post("/upload")', thumb_ep + '\n' + '@router.post("/upload")')

with open('/mnt/datadisk/home/yuan/mygithub/share_timeline/server/app/routers/files.py', 'w') as f:
    f.write(content)

ast.parse(content)
print('PATCH OK')
