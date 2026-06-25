"""Debug video thumbnail generation."""
import asyncio
import traceback
import sys
sys.path.insert(0, '/mnt/datadisk/home/yuan/mygithub/share_timeline/server')
from app.database import SessionLocal
from sqlalchemy import text

async def run():
    async with SessionLocal() as db:
        # Get a video file's s3Key from DB
        r = await db.execute(text("SELECT id, s3Key FROM files_1000 WHERE s3Key LIKE '%.mp4' LIMIT 1"))
        row = r.mappings().one_or_none()
        if not row:
            print('No video file found')
            return
        d = dict(row)
        fid = d['id']
        s3k = d['s3Key']
        print(f'Processing video: id={fid} s3Key={s3k}')

        from app.services.thumbnail_service import generate_and_upload_thumbnail
        try:
            result = await generate_and_upload_thumbnail(
                s3k, 1000, fid, 'video', 'video/mp4'
            )
            print(f'Result: {result}')
        except Exception:
            traceback.print_exc()

asyncio.run(run())
