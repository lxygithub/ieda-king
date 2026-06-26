"""Test Content-Disposition header generation."""
import sys
sys.path.insert(0, '/mnt/datadisk/home/yuan/mygithub/share_timeline/server')

nm = "应用宝.apk"
nm_ascii = nm.encode("ascii", errors="replace").decode("ascii")
disp = "attachment"

# Current code
from urllib.parse import quote
hdr = {"Content-Disposition": disp + "; filename=\"" + nm_ascii + "\"; filename*=UTF-8''" + quote(nm)}
print("Result:", hdr)
