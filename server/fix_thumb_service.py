"""Fix thumbnail service for RGBA images and video extraction."""
import sys
sys.path.insert(0, '/mnt/datadisk/home/yuan/mygithub/share_timeline/server')

with open('app/services/thumbnail_service.py', 'r') as f:
    content = f.read()

# Fix: convert RGBA to RGB before JPEG save
old = '''    # Resize
    img = Image.open(BytesIO(img_data))
    img.thumbnail((THUMB_MAX_WIDTH, THUMB_MAX_HEIGHT), Image.LANCZOS)

    # Save to bytes
    buf = BytesIO()
    img.save(buf, format="JPEG", quality=THUMB_QUALITY)'''

new = '''    # Resize
    img = Image.open(BytesIO(img_data))
    if img.mode in ("RGBA", "P", "LA"):
        img = img.convert("RGB")
    img.thumbnail((THUMB_MAX_WIDTH, THUMB_MAX_HEIGHT), Image.LANCZOS)

    # Save to bytes
    buf = BytesIO()
    img.save(buf, format="JPEG", quality=THUMB_QUALITY)'''

content = content.replace(old, new)

# Fix video: client.get_object returns bytes, use BytesIO
old_vid = '''    # Download original to temp file
    resp = client.get_object(settings.s3_bucket, s3_key)
    with tempfile.NamedTemporaryFile(suffix=\".video\", delete=False) as tmp_in:
        tmp_in.write(resp.read())
        tmp_in_path = tmp_in.name'''

new_vid = '''    # Download original to temp file
    resp = client.get_object(settings.s3_bucket, s3_key)
    data = resp.read() if hasattr(resp, \"read\") else resp
    with tempfile.NamedTemporaryFile(suffix=\".video\", delete=False) as tmp_in:
        if isinstance(data, bytes):
            tmp_in.write(data)
        else:
            tmp_in.write(data.read() if hasattr(data, \"read\") else data)
        tmp_in_path = tmp_in.name'''

content = content.replace(old_vid, new_vid)

with open('app/services/thumbnail_service.py', 'w') as f:
    f.write(content)

import ast
ast.parse(content)
print('thumbnail_service fixed')
