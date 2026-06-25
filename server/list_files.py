import asyncio
import sys
sys.path.insert(0, '/mnt/datadisk/home/yuan/mygithub/share_timeline/server')
from app.database import SessionLocal
from sqlalchemy import text

async def run():
    async with SessionLocal() as db:
        r = await db.execute(text("SELECT id, s3Key, thumbS3Key FROM files_1000 ORDER BY receivedAt DESC LIMIT 10"))
        for row in r.mappings():
            d = dict(row)
            print(f"{d['id'][:20]} s3Key={bool(d.get('s3Key'))} thumbS3Key={d.get('thumbS3Key')}")

asyncio.run(run())
