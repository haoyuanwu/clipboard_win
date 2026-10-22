from urllib.request import urlopen
from pathlib import Path
url='https://github.com/alexmercerind/flutter-windows-ANGLE-OpenGL-ES/releases/download/v1.0.1/ANGLE.7z'
p=Path('build/windows/x64/ANGLE.7z')
with urlopen(url, timeout=25) as response:
    data=response.read()
p.write_bytes(data)
import hashlib
print(len(data), hashlib.md5(data).hexdigest())
