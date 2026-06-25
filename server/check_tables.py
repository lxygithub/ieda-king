import asyncio
import sys
sys.path.insert(0, '/mnt/datadisk/home/yuan/mygithub/share_timeline/server')

from app.database import SessionLocal
from sqlalchemy import text

async def run():
    async with SessionLocal() as db:
        r = await db.execute(text("SHOW TABLES LIKE 'files_%'"))
        tables = [row[0] for row in r.fetchall()]
        print('Tables:', tables)

        for tbl in tables:
            try:
                r2 = await db.execute(text(f"SELECT id, thumbS3Key FROM {tbl} WHERE id = 'thumb_final'"))
                row = r2.mappings().one_or_none()
                if row:
                    print(f'FOUND in {tbl}:', dict(row))
            except Exception as e:
                print(f'{tbl}: {e}')

asyncio.run(run())
