"""Update old s3Key paths (files/1999/, files/2005/, etc.) to new format (files/1000/, files/1006/)."""
import asyncio
import sys
sys.path.insert(0, '/mnt/datadisk/home/yuan/mygithub/share_timeline/server')
from app.database import SessionLocal
from app.models.user import User
from sqlalchemy import select, text
from app.services.file_service import _table_name, _storage_id

async def run():
    async with SessionLocal() as db:
        r = await db.execute(select(User))
        users = r.scalars().all()

        for u in users:
            tbl = _table_name(u.id)
            new_prefix = f'files/{u.id}/'
            old_prefix = f'files/{u.id + 999}/'  # old storage_id had +999

            # Check if any records need updating
            cnt = 0
            rows = await db.execute(
                text(f"SELECT id, s3Key, thumbS3Key FROM {tbl} WHERE s3Key LIKE :old OR thumbS3Key LIKE :old"),
                {'old': f'{old_prefix}%'}
            )
            for row in rows.mappings():
                d = dict(row)
                new_s3 = d['s3Key'].replace(old_prefix, new_prefix) if d.get('s3Key') else None
                new_thumb = d['thumbS3Key'].replace(old_prefix, new_prefix) if d.get('thumbS3Key') else None
                await db.execute(
                    text(f"UPDATE {tbl} SET s3Key = :s3, thumbS3Key = :tk WHERE id = :id"),
                    {'s3': new_s3, 'tk': new_thumb, 'id': d['id']}
                )
                cnt += 1

            if cnt:
                print(f'  {tbl}: migrated {cnt} s3Keys ({old_prefix} -> {new_prefix})')

        await db.commit()
        print('done')

asyncio.run(run())
