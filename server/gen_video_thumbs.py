"""Generate thumbnails for video files that don't have one yet."""
import asyncio, os, sys, tempfile, subprocess
sys.path.insert(0, '/mnt/datadisk/home/yuan/mygithub/share_timeline/server')
from app.database import SessionLocal
from app.models.user import User
from sqlalchemy import select, text
from app.services.file_service import _table_name
from app.services.s3_service import _get_client
from app.config import settings

THUMB_MAX_WIDTH = 300
THUMB_MAX_HEIGHT = 300

async def run():
    client = _get_client()
    async with SessionLocal() as db:
        r = await db.execute(select(User))
        for u in r.scalars():
            tbl = _table_name(u.id)
            rows = await db.execute(text(f"SELECT id, s3Key FROM {tbl} WHERE s3Key LIKE '%.mp4' AND (thumbS3Key IS NULL OR thumbS3Key = '')"))
            for row in rows.mappings():
                d = dict(row)
                fid = d['id']
                s3k = d['s3Key']
                thumb_key = f'thumbnails/{u.id}/{fid}.jpg'
                print(f'Processing: {fid[:16]} s3Key={s3k}', flush=True)

                tmp_in = tempfile.NamedTemporaryFile(suffix='.mp4', delete=False)
                tmp_out = tmp_in.name + '.jpg'
                try:
                    resp = client.get_object(settings.s3_bucket, s3k)
                    data = resp.read()
                    tmp_in.write(data)
                    tmp_in.close()

                    subprocess.run(
                        ['ffmpeg', '-y', '-ss', '00:00:01', '-i', tmp_in.name,
                         '-vframes', '1', '-vf', f'scale=min({THUMB_MAX_WIDTH},iw):min({THUMB_MAX_HEIGHT},ih):force_original_aspect_ratio=decrease',
                         '-q:v', '2', tmp_out],
                        capture_output=True, timeout=60,
                    )

                    if not os.path.exists(tmp_out):
                        print(f'  ffmpeg failed - no output')
                        continue

                    with open(tmp_out, 'rb') as f:
                        client.put_object(settings.s3_bucket, thumb_key, f,
                            length=os.path.getsize(tmp_out), content_type='image/jpeg')

                    await db.execute(text(f"UPDATE {tbl} SET thumbS3Key = :tk WHERE id = :id"),
                                     {'tk': thumb_key, 'id': fid})
                    print(f'  => {thumb_key}', flush=True)
                except Exception as ex:
                    print(f'  ERROR: {ex}', flush=True)
                finally:
                    for p in [tmp_in.name, tmp_out]:
                        try: os.unlink(p)
                        except: pass

            await db.commit()
    print('DONE')

asyncio.run(run())
