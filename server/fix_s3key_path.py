"""Fix s3Key for the epub file - point to correct S3 path."""
import asyncio, sys
sys.path.insert(0, '/mnt/datadisk/home/yuan/mygithub/share_timeline/server')
from app.database import SessionLocal
from sqlalchemy import text

async def run():
    async with SessionLocal() as db:
        # Set the correct s3Key from what the user found in S3
        correct_key = "files/1006/2026/06/25/23_05_43_____(______)_(z-library.sk,_1lib.sk,_z-lib.sk).epub"
        await db.execute(
            text("UPDATE files_1006 SET s3Key = :key WHERE id = '019eff50-3b1a-7dd4-988d-833135a85df8'"),
            {"key": correct_key}
        )
        await db.commit()

        # Verify
        r = await db.execute(text("SELECT s3Key, fileSize FROM files_1006 WHERE id = '019eff50-3b1a-7dd4-988d-833135a85df8'"))
        row = r.mappings().one()
        print('s3Key:', row['s3Key'][:40] + '...')
        print('fileSize:', row['fileSize'])

asyncio.run(run())
