"""Debug video thumbnail - check what get_object returns."""
import asyncio
import sys
sys.path.insert(0, '/mnt/datadisk/home/yuan/mygithub/share_timeline/server')
from app.services.s3_service import _get_client
from app.config import settings

async def run():
    client = _get_client()
    s3_key = 'files/2005/2026/06/25/10_50_03_mmexport1782348047148.mp4'
    print(f'Fetching: {s3_key}')
    try:
        resp = client.get_object(settings.s3_bucket, s3_key)
        print(f'type(resp)={type(resp)}')
        print(f'hasattr(read)={hasattr(resp, "read")}')
        print(f'isinstance(bytes)={isinstance(resp, bytes)}')
        if hasattr(resp, 'read'):
            data = resp.read()
            print(f'read() -> {type(data)} len={len(data)}')
        else:
            print(f'resp is bytes? {isinstance(resp, bytes)}, len={len(resp)}')
    except Exception as e:
        print(f'Error: {e}')

asyncio.run(run())
