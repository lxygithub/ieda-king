import asyncio
import sys
sys.path.insert(0, '/mnt/datadisk/home/yuan/mygithub/share_timeline/server')
from app.database import SessionLocal
from sqlalchemy import text

async def run():
    async with SessionLocal() as db:
        r = await db.execute(text("SELECT id, thumbS3Key FROM files_1000 WHERE id = 'thumb_final'"))
        row = r.mappings().one_or_none()
        if row:
            print('FOUND:', row.get('thumbS3Key'))
        else:
            print('NOT FOUND in files_1000')
            r2 = await db.execute(text("SELECT id FROM files_1000 ORDER BY receivedAt DESC LIMIT 5"))
            for rw in r2.mappings():
                print('  file:', rw.get('id'))

asyncio.run(run())
