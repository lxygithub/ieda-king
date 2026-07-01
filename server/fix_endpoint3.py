#!/usr/bin/env python3
import sys

filepath = "/mnt/datadisk/home/yuan/mygithub/share_timeline/server/app/routers/files.py"

with open(filepath, "r") as f:
    content = f.read()

# Fix the f-string syntax issue - replace the broken line
old_line = '''    sql = f"UPDATE {table} SET {", ".join(updates)} WHERE id = :id"'''
new_line = '''    sql = f"UPDATE {table} SET {', '.join(updates)} WHERE id = :id"'''

content = content.replace(old_line, new_line)

with open(filepath, "w") as f:
    f.write(content)

print("Fixed f-string syntax")
