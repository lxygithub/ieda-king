"""Add multipart upload endpoints for resumable uploads."""
import ast

with open('/mnt/datadisk/home/yuan/mygithub/share_timeline/server/app/routers/files.py', 'r') as f:
    content = f.read()

multipart_code = '''

import time

# In-memory store for multipart uploads
_multipart_uploads: dict[str, dict] = {}

@router.post("/upload/init")
async def init_multipart_upload(
    file_id: str = Form(...),
    name: str = Form(...),
    file_type: str = Form(alias="type"),
    mime_type: str | None = Form(None, alias="mimeType"),
    file_size: int = Form(...),
    user: User = Depends(get_current_user),
):
    from app.services.s3_service import _get_client
    from app.config import settings
    s3_key = s3_service.generate_s3_key(name, user_id=user.id)
    client = _get_client()
    minio_uid = client._create_multipart_upload(settings.s3_bucket, s3_key, {})
    upload_id = str(uuid.uuid4())
    _multipart_uploads[upload_id] = {
        "user_id": user.id,
        "file_id": file_id,
        "name": name,
        "type": file_type,
        "mime_type": mime_type,
        "file_size": file_size,
        "s3_key": s3_key,
        "minio_uid": minio_uid,
        "parts": [],
    }
    return {"upload_id": upload_id, "s3_key": s3_key, "part_size": 5 * 1024 * 1024}


@router.post("/upload/{upload_id}/part")
async def upload_part(
    upload_id: str,
    part_number: int = Form(...),
    file: UploadFile = File(...),
    user: User = Depends(get_current_user),
):
    meta = _multipart_uploads.get(upload_id)
    if not meta:
        raise HTTPException(status_code=404, detail="Upload not found")
    if meta["user_id"] != user.id:
        raise HTTPException(status_code=403, detail="Not your upload")

    from app.services.s3_service import _get_client
    from app.config import settings

    content = await file.read()
    client = _get_client()
    try:
        etag = client._upload_part(
            settings.s3_bucket, meta["s3_key"], content, {}, meta["minio_uid"], part_number,
        )
        from minio.datatypes import Part
        meta["parts"].append(Part(part_number, etag))
        return {"part_number": part_number, "etag": etag, "success": True}
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"Part failed: {e}")


@router.post("/upload/{upload_id}/complete")
async def complete_multipart_upload(
    upload_id: str,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    meta = _multipart_uploads.get(upload_id)
    if not meta:
        raise HTTPException(status_code=404, detail="Upload not found")
    if meta["user_id"] != user.id:
        raise HTTPException(status_code=403, detail="Not your upload")

    from app.services.s3_service import _get_client
    from app.config import settings

    client = _get_client()
    sorted_parts = sorted(meta["parts"], key=lambda p: p.part_number)
    try:
        client._complete_multipart_upload(
            settings.s3_bucket, meta["s3_key"], meta["minio_uid"], sorted_parts,
        )
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"Complete failed: {e}")

    s3_key = meta["s3_key"]
    file_id = meta["file_id"]
    await file_service.update_file_s3(
        db, user.id, file_id, s3_key, meta["file_size"], meta["mime_type"],
    )
    del _multipart_uploads[upload_id]
    return {"success": True, "id": file_id, "s3Key": s3_key, "fileSize": meta["file_size"]}


@router.get("/upload/{upload_id}/parts")
async def list_upload_parts(
    upload_id: str,
    user: User = Depends(get_current_user),
):
    meta = _multipart_uploads.get(upload_id)
    if not meta:
        raise HTTPException(status_code=404, detail="Upload not found")
    if meta["user_id"] != user.id:
        raise HTTPException(status_code=403, detail="Not your upload")
    return {"parts": [{"part_number": p.part_number, "etag": p.etag} for p in meta["parts"]]}
'''

# Insert before @router.post("/upload")
marker = '@router.post("/upload")'
content = content.replace(marker, multipart_code + '\n' + marker)

with open('/mnt/datadisk/home/yuan/mygithub/share_timeline/server/app/routers/files.py', 'w') as f:
    f.write(content)

ast.parse(content)
print('OK')
