import asyncio, sys
sys.path.insert(0, '/mnt/datadisk/home/yuan/mygithub/share_timeline/server')
from app.database import SessionLocal
from sqlalchemy import text

async def run():
    async with SessionLocal() as db:
        sql = "SELECT COUNT(*) FROM files_1000 WHERE receivedAt >= '2026-06-23T00:00:00' AND receivedAt <= '2026-06-23T23:59:59'"
        r = await db.execute(text(sql))
        print('Count Jun 23:', r.scalar())

asyncio.run(run())
