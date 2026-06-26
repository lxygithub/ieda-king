"""Add abort multipart upload endpoint."""
with open('/mnt/datadisk/home/yuan/mygithub/share_timeline/server/app/routers/files.py', 'r') as f:
    lines = f.readlines()

abort_code = '''
@router.post("/upload/{upload_id}/abort")
async def abort_multipart_upload(
    upload_id: str,
    user: User = Depends(get_current_user),
):
    meta = _multipart_uploads.get(upload_id)
    if not meta:
        raise HTTPException(status_code=404, detail="Upload not found")
    if meta["user_id"] != user.id:
        raise HTTPException(status_code=403, detail="Not your upload")
    from app.services.s3_service import _get_client
    from app.config import settings
    client = _get_client()
    try:
        client._abort_multipart_upload(settings.s3_bucket, meta["s3_key"], meta["minio_uid"])
    except Exception:
        pass
    del _multipart_uploads[upload_id]
    return {"success": True}

'''

for i, line in enumerate(lines):
    if '@router.get("/upload/{upload_id}/parts")' in line:
        lines.insert(i, abort_code)
        break

with open('/mnt/datadisk/home/yuan/mygithub/share_timeline/server/app/routers/files.py', 'w') as f:
    f.writelines(lines)

import ast
ast.parse(open('/mnt/datadisk/home/yuan/mygithub/share_timeline/server/app/routers/files.py').read())
print('OK')
