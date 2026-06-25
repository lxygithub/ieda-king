import asyncio
import sys
sys.path.insert(0, '/mnt/datadisk/home/yuan/mygithub/share_timeline/server')
from app.database import SessionLocal
from sqlalchemy import text

async def run():
    async with SessionLocal() as db:
        for tbl in ['files_1000', 'files_1006', 'files_1007']:
            r = await db.execute(
                text(f"SELECT id, s3Key, type, name FROM {tbl} WHERE type = 'video' AND s3Key IS NOT NULL LIMIT 1")
            )
            row = r.mappings().one_or_none()
            if row:
                d = dict(row)
                sid = d['id'][:20]
                sk = d['s3Key']
                nm = d['name']
                print(f'{tbl}: id={sid} s3Key={sk} name={nm}')

asyncio.run(run())
