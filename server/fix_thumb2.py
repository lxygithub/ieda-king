"""Fix both image and video thumbnail extraction."""
with open('/mnt/datadisk/home/yuan/mygithub/share_timeline/server/app/services/thumbnail_service.py', 'r') as f:
    content = f.read()

# Fix image: handle bytes or response object
old_img = '''    # Download original
    resp = client.get_object(settings.s3_bucket, s3_key)
    img_data = resp.read()'''

new_img = '''    # Download original
    resp = client.get_object(settings.s3_bucket, s3_key)
    img_data = resp.read() if hasattr(resp, 'read') else resp'''

content = content.replace(old_img, new_img)

# Fix video: simpler approach
old_vid = '''    # Download original to temp file
    resp = client.get_object(settings.s3_bucket, s3_key)
    data = resp.read() if hasattr(resp, \"read\") else resp
    with tempfile.NamedTemporaryFile(suffix=\".video\", delete=False) as tmp_in:
        if isinstance(data, bytes):
            tmp_in.write(data)
        else:
            tmp_in.write(data.read() if hasattr(data, \"read\") else data)
        tmp_in_path = tmp_in.name'''

new_vid = '''    # Download original to temp file
    resp = client.get_object(settings.s3_bucket, s3_key)
    raw = resp.read() if hasattr(resp, 'read') else resp
    if not isinstance(raw, bytes):
        raw = raw.read() if hasattr(raw, 'read') else bytes(raw)
    with tempfile.NamedTemporaryFile(suffix=\".video\", delete=False) as tmp_in:
        tmp_in.write(raw)
        tmp_in_path = tmp_in.name'''

content = content.replace(old_vid, new_vid)

with open('/mnt/datadisk/home/yuan/mygithub/share_timeline/server/app/services/thumbnail_service.py', 'w') as f:
    f.write(content)

import ast
ast.parse(content)
print('fixed')
