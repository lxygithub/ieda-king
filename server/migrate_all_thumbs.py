"""Regenerate all thumbnails and ensure they're committed."""
import asyncio, os, sys, tempfile, subprocess
sys.path.insert(0, '/mnt/datadisk/home/yuan/mygithub/share_timeline/server')
from app.database import SessionLocal
from app.models.user import User
from sqlalchemy import select, text
from app.services.file_service import _table_name
from app.services.s3_service import _get_client
from app.config import settings
from PIL import Image
from io import BytesIO

async def run():
    client = _get_client()
    async with SessionLocal() as db:
        r = await db.execute(select(User))
        for u in r.scalars():
            tbl = _table_name(u.id)
            uid = u.id
            # Get files with s3Key but no thumb
            rows = await db.execute(
                text(f"SELECT id, s3Key, type, mimeType FROM {tbl} WHERE s3Key IS NOT NULL AND (thumbS3Key IS NULL OR thumbS3Key = '')")
            )
            for row in rows.mappings():
                d = dict(row)
                fid = d['id']
                s3k = d['s3Key']
                ftype = d.get('type', '')
                mtype = d.get('mimeType', '')
                is_img = (ftype == 'image' or mtype.startswith('image/'))
                is_vid = (ftype == 'video' or mtype.startswith('video/'))
                if not is_img and not is_vid:
                    continue
                thumb_key = f'thumbnails/{uid}/{fid}.jpg'
                print(f'{fid[:16]} ({ftype})', end=' ', flush=True)

                try:
                    resp = client.get_object(settings.s3_bucket, s3k)
                    raw_data = resp.read() if hasattr(resp, 'read') else resp
                    if not isinstance(raw_data, bytes):
                        raw_data = bytes(raw_data)

                    if is_img:
                        img = Image.open(BytesIO(raw_data))
                        if img.mode in ('RGBA', 'P', 'LA'):
                            img = img.convert('RGB')
                        img.thumbnail((300, 300), Image.LANCZOS)
                        buf = BytesIO()
                        img.save(buf, format='JPEG', quality=75)
                        buf.seek(0)
                        client.put_object(settings.s3_bucket, thumb_key, buf,
                            length=buf.getbuffer().nbytes, content_type='image/jpeg')
                    elif is_vid:
                        with tempfile.NamedTemporaryFile(suffix='.mp4', delete=False) as f:
                            f.write(raw_data)
                            tmp_in = f.name
                        tmp_out = tmp_in + '.jpg'
                        subprocess.run(
                            ['ffmpeg', '-y', '-ss', '00:00:01', '-i', tmp_in,
                             '-vframes', '1', '-vf', 'scale=300:300:force_original_aspect_ratio=decrease',
                             '-q:v', '2', tmp_out],
                            capture_output=True, timeout=60)
                        if os.path.exists(tmp_out):
                            with open(tmp_out, 'rb') as f:
                                client.put_object(settings.s3_bucket, thumb_key, f,
                                    length=os.path.getsize(tmp_out), content_type='image/jpeg')
                        for p in [tmp_in, tmp_out]:
                            if p and os.path.exists(p):
                                try: os.unlink(p)
                                except: pass

                    # Update DB
                    await db.execute(
                        text(f"UPDATE {tbl} SET thumbS3Key = :tk WHERE id = :id"),
                        {'tk': thumb_key, 'id': fid}
                    )
                    print(f'OK -> {thumb_key}')
                except Exception as ex:
                    print(f'FAIL: {ex}')

            await db.commit()
            print(f'  Committed for user {uid}')

    print('DONE')

asyncio.run(run())
