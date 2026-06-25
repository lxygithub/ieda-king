"""Set thumbS3Key for the user's file and commit."""
import asyncio, sys
sys.path.insert(0, '/mnt/datadisk/home/yuan/mygithub/share_timeline/server')
from app.database import SessionLocal
from sqlalchemy import text

async def run():
    async with SessionLocal() as db:
        # Check current value
        r = await db.execute(text("SELECT thumbS3Key FROM files_1006 WHERE id = '019efca2-38a6-7b32-b885-0f7651a0c153'"))
        row = r.mappings().one_or_none()
        print('Before:', dict(row) if row else 'None')

        # Update
        await db.execute(
            text("UPDATE files_1006 SET thumbS3Key = 'thumbnails/1006/019efca2-38a6-7b32-b885-0f7651a0c153.jpg' WHERE id = '019efca2-38a6-7b32-b885-0f7651a0c153'")
        )
        await db.commit()

        # Verify
        r2 = await db.execute(text("SELECT thumbS3Key FROM files_1006 WHERE id = '019efca2-38a6-7b32-b885-0f7651a0c153'"))
        row2 = r2.mappings().one_or_none()
        print('After:', dict(row2) if row2 else 'None')

asyncio.run(run())
