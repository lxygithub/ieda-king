import asyncio, sys
sys.path.insert(0, '/mnt/datadisk/home/yuan/mygithub/share_timeline/server')
from app.database import SessionLocal
from sqlalchemy import text

async def run():
    async with SessionLocal() as db:
        r = await db.execute(text("SELECT receivedAt FROM files_1000 ORDER BY receivedAt DESC LIMIT 5"))
        print('Sample dates:', [row[0] for row in r.fetchall()])
        r2 = await db.execute(text("SELECT COUNT(*) FROM files_1000 WHERE receivedAt >= '2026-06-23 00:00:00' AND receivedAt <= '2026-06-23 23:59:59'"))
        print('Count Jun 23:', r2.scalar())

asyncio.run(run())
