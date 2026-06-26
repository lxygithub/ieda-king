"""Fix type filter to support multiple comma-separated types."""
with open('/mnt/datadisk/home/yuan/mygithub/share_timeline/server/app/services/file_service.py', 'r') as f:
    content = f.read()

# Replace single type filter with multi-type
old = '            sql += f" AND type = \'{file_type}\'"'
new = '''            types_list = [f"\'{t.strip()}\'" for t in file_type.split(",") if t.strip()]
            sql += f" AND type IN ({','.join(types_list)})"'''

content = content.replace(old, new)

with open('/mnt/datadisk/home/yuan/mygithub/share_timeline/server/app/services/file_service.py', 'w') as f:
    f.write(content)

import ast
ast.parse(content)
print('OK')
