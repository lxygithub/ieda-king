"""One-time migration: generate thumbnails for all existing files with s3Key."""
import asyncio
import sys
sys.path.insert(0, '/mnt/datadisk/home/yuan/mygithub/share_timeline/server')

from app.database import SessionLocal
from app.models.user import User
from sqlalchemy import select, text
from app.services.file_service import _table_name
from app.services.thumbnail_service import generate_and_upload_thumbnail

async def run():
    async with SessionLocal() as db:
        r = await db.execute(select(User))
        users = r.scalars().all()

        for u in users:
            tbl = _table_name(u.id)
            try:
                rows = await db.execute(
                    text(f"SELECT id, s3Key, type, mimeType FROM {tbl} WHERE s3Key IS NOT NULL AND (thumbS3Key IS NULL OR thumbS3Key = '')")
                )
                for row in rows.mappings():
                    d = dict(row)
                    fid = d['id']
                    s3k = d['s3Key']
                    ftype = d.get('type', '')
                    mtype = d.get('mimeType', '')
                    print(f'  {fid[:16]} type={ftype} s3Key={bool(s3k)}')

                    if ftype in ('image', 'video') or (mtype and (mtype.startswith('image/') or mtype.startswith('video/'))):
                        sid = u.id  # storage_id = user_id after migration
                        try:
                            tk = await generate_and_upload_thumbnail(s3k, sid, fid, ftype, mtype)
                            if tk:
                                await db.execute(
                                    text(f"UPDATE {tbl} SET thumbS3Key = :tk WHERE id = :id"),
                                    {"tk": tk, "id": fid}
                                )
                                print(f'    => thumb: {tk}')
                        except Exception as ex:
                            print(f'    => ERROR: {ex}')

                await db.commit()
            except Exception as e:
                print(f'  {tbl}: {e}')

asyncio.run(run())
