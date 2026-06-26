"""Fix MMKV API calls across all Dart files."""
import re, os, sys

files = [
    r'D:\mygithub\share_timeline\lib\providers\auth_provider.dart',
    r'D:\mygithub\share_timeline\lib\providers\timeline_provider.dart',
    r'D:\mygithub\share_timeline\lib\screens\login_screen.dart',
    r'D:\mygithub\share_timeline\lib\screens\timeline_screen.dart',
]

replacements = [
    (r'mmkv\.getString\(', 'mmkv.decodeString('),
    (r'mmkv\.getInt\(', 'mmkv.decodeInt('),
    (r'mmkv\.getBool\(', 'mmkv.decodeBool('),
    (r'mmkv\.setString\(', 'mmkv.encodeString('),
    (r'mmkv\.setInt\(', 'mmkv.encodeInt('),
    (r'mmkv\.setBool\(', 'mmkv.encodeBool('),
    (r'mmkv\.remove\(', 'mmkv.removeValue('),
]

for fp in files:
    with open(fp, 'r', encoding='utf-8') as f:
        content = f.read()
    for old, new in replacements:
        content = re.sub(old, new, content)
    with open(fp, 'w', encoding='utf-8') as f:
        f.write(content)
    print(f'Fixed: {os.path.basename(fp)}')
