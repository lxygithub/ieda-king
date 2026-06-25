"""Generate video thumbnails - using proven ffmpeg parameters."""
import asyncio, os, sys, tempfile, subprocess
sys.path.insert(0, '/mnt/datadisk/home/yuan/mygithub/share_timeline/server')
from app.database import SessionLocal
from app.models.user import User
from sqlalchemy import select, text
from app.services.file_service import _table_name
from app.services.s3_service import _get_client
from app.config import settings

async def run():
    client = _get_client()
    async with SessionLocal() as db:
        r = await db.execute(select(User))
        for u in r.scalars():
            tbl = _table_name(u.id)
            rows = await db.execute(
                text(f"SELECT id, s3Key FROM {tbl} WHERE s3Key LIKE '%.mp4' AND (thumbS3Key IS NULL OR thumbS3Key = '')")
            )
            for row in rows.mappings():
                d = dict(row)
                fid = d['id']
                s3k = d['s3Key']
                thumb_key = f'thumbnails/{u.id}/{fid}.jpg'
                print(f'Video: {fid[:16]} s3={s3k}', flush=True)

                tmp_in = None
                tmp_out = None
                try:
                    resp = client.get_object(settings.s3_bucket, s3k)
                    raw = resp.read()
                    with tempfile.NamedTemporaryFile(suffix='.mp4', delete=False) as f:
                        f.write(raw)
                        tmp_in = f.name

                    tmp_out = tmp_in + '.jpg'
                    result = subprocess.run(
                        ['ffmpeg', '-y', '-ss', '00:00:01', '-i', tmp_in,
                         '-vframes', '1', '-vf', 'scale=300:300:force_original_aspect_ratio=decrease',
                         '-q:v', '2', tmp_out],
                        capture_output=True, timeout=60,
                    )
                    if result.returncode != 0:
                        print(f'  ffmpeg error: {result.stderr.decode()[:200]}')
                        continue

                    if not os.path.exists(tmp_out):
                        print(f'  ffmpeg produced no output file')
                        continue

                    with open(tmp_out, 'rb') as fh:
                        client.put_object(settings.s3_bucket, thumb_key, fh,
                            length=os.path.getsize(tmp_out), content_type='image/jpeg')

                    await db.execute(
                        text(f"UPDATE {tbl} SET thumbS3Key = :tk WHERE id = :id"),
                        {'tk': thumb_key, 'id': fid}
                    )
                    print(f'  => {thumb_key}', flush=True)
                except Exception as ex:
                    print(f'  ERROR: {ex}', flush=True)
                finally:
                    for p in [tmp_in, tmp_out]:
                        if p and os.path.exists(p):
                            try: os.unlink(p)
                            except: pass
            await db.commit()
    print('DONE')

asyncio.run(run())
