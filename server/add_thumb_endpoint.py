"""Add thumbnail download endpoint to files.py."""
with open('/mnt/datadisk/home/yuan/mygithub/share_timeline/server/app/routers/files.py', 'r') as f:
    content = f.read()

thumb_ep = '''

@router.get("/{file_id}/thumbnail")
async def download_thumbnail(
    file_id: str,
    token: str | None = None,
    user: User | None = Depends(get_current_user_optional),
    db: AsyncSession = Depends(get_db),
):
    """Return thumbnail for a file. Uses thumbS3Key from DB."""
    from app.services.file_service import _table_name as _tn
    from app.services.s3_service import _get_client
    from app.config import settings

    # Support JWT via query param
    if token and not user:
        from app.services.auth_service import decode_access_token
        p = decode_access_token(token)
        if p:
            uid = int(p.get("sub", 0))
            r = await db.execute(select(User).where(User.id == uid))
            user = r.scalar_one_or_none()

    # Search all user tables for the file
    records = []
    users_to_check = [user] if user and not getattr(user, "is_admin", False) else []
    if not users_to_check:
        r = await db.execute(select(User))
        users_to_check = list(r.scalars().all())

    for u in users_to_check:
        try:
            tbl = _tn(u.id)
            r = await db.execute(text(f"SELECT id, thumbS3Key, s3Key FROM {tbl} WHERE id = :id"), {"id": file_id})
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
    try:
        resp = client.get_object(settings.s3_bucket, target)
        raw = resp.read() if hasattr(resp, 'read') else resp
        if not isinstance(raw, bytes):
            raw = raw.read() if hasattr(raw, 'read') else bytes(raw)
        from fastapi.responses import Response
        return Response(content=raw, media_type="image/jpeg",
                        headers={"Content-Disposition": "inline; filename=thumb.jpg"})
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"Thumb fail: {e}")
'''

# Insert before @router.post("/upload")
marker = '@router.post("/upload")'
content = content.replace(marker, thumb_ep + '\n' + marker)

with open('/mnt/datadisk/home/yuan/mygithub/share_timeline/server/app/routers/files.py', 'w') as f:
    f.write(content)

import ast
ast.parse(content)
print('OK')
