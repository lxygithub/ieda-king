"""Check if thumbS3Key is set in DB for a specific file."""
import asyncio, sys
sys.path.insert(0, '/mnt/datadisk/home/yuan/mygithub/share_timeline/server')
from app.database import SessionLocal
from sqlalchemy import text

async def run():
    async with SessionLocal() as db:
        for tbl in ['files_1000', 'files_1006', 'files_1007']:
            r = await db.execute(text(f"SELECT id, thumbS3Key FROM {tbl} WHERE id LIKE '019efca2%'"))
            row = r.mappings().one_or_none()
            if row:
                d = dict(row)
                print(f'{tbl}: thumbS3Key={d.get("thumbS3Key")}')
                return
        print('File not found in any table')

asyncio.run(run())
