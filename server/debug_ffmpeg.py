"""Debug ffmpeg video thumbnail extraction."""
import asyncio, os, sys, tempfile, subprocess
sys.path.insert(0, '/mnt/datadisk/home/yuan/mygithub/share_timeline/server')
from app.services.s3_service import _get_client
from app.config import settings

async def run():
    client = _get_client()
    s3_key = 'files/1000/2026/06/23/17_12_08_VID_20260621_142952.mp4'
    resp = client.get_object(settings.s3_bucket, s3_key)
    data = resp.read()
    print(f'Downloaded: {len(data)} bytes')

    with tempfile.NamedTemporaryFile(suffix='.mp4', delete=False) as f:
        f.write(data)
        in_path = f.name

    out_path = in_path + '.jpg'
    result = subprocess.run(
        ['ffmpeg', '-y', '-ss', '00:00:01', '-i', in_path,
         '-vframes', '1', '-vf', 'scale=300:300:force_original_aspect_ratio=decrease',
         '-q:v', '2', out_path],
        capture_output=True, timeout=60,
    )

    print(f'ffmpeg returncode: {result.returncode}')
    if result.returncode != 0:
        print(f'stderr: {result.stderr.decode()[:500]}')

    print(f'Output exists: {os.path.exists(out_path)}')
    if os.path.exists(out_path):
        print(f'Output size: {os.path.getsize(out_path)}')

    for p in [in_path, out_path]:
        try: os.unlink(p)
        except: pass

asyncio.run(run())
