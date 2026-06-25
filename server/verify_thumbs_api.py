"""Verify get_user_files returns thumbS3Key for user 1006."""
import asyncio, sys
sys.path.insert(0, '/mnt/datadisk/home/yuan/mygithub/share_timeline/server')
from app.database import SessionLocal
from app.services.file_service import get_user_files

async def run():
    async with SessionLocal() as db:
        files = await get_user_files(db, 1006)
        for f in files:
            if '019efca2' in f['id']:
                print(f"id={f['id'][:20]} thumbS3Key={f.get('thumbS3Key')}")
                return
        print('File not found for user 1006')

asyncio.run(run())
