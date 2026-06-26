"""Clear corrupted s3Key for files that had their key overwritten."""
import asyncio, sys
sys.path.insert(0, '/mnt/datadisk/home/yuan/mygithub/share_timeline/server')
from app.database import SessionLocal
from sqlalchemy import text

async def run():
    async with SessionLocal() as db:
        await db.execute(
            text("UPDATE files_1006 SET s3Key = NULL WHERE id = '019eff50-3b1a-7dd4-988d-833135a85df8'")
        )
        await db.commit()
        print('Cleared')

        # Verify
        r = await db.execute(text("SELECT s3Key FROM files_1006 WHERE id = '019eff50-3b1a-7dd4-988d-833135a85df8'"))
        row = r.one_or_none()
        print('s3Key after:', row[0] if row else 'not found')

asyncio.run(run())
