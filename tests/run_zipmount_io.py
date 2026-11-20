"""Run the preserved native ZIP reader fixture with generated, non-game data."""
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import zipfile

with tempfile.TemporaryDirectory(prefix='ut3-zip-') as temp:
    root = Path(temp)
    archive, index = root/'stored.zip', root/'stored.zmi'
    values = [('Data/Big.bin',bytes(i%251 for i in range(300000)),0),
              ('data/small.txt',b'hello',0),('data/nested/test',b'nested',0),('packed.txt',b'compressed',8)]
    with zipfile.ZipFile(archive,'w') as z:
        for name,data,compression in values:z.writestr(name,data,compress_type=compression)
    raw = archive.read_bytes()
    records = []
    with zipfile.ZipFile(archive) as z:
        for row in z.infolist():
            name=row.filename.encode()
            name_size,extra_size=struct.unpack_from('<HH',raw,row.header_offset+26)
            offset=row.header_offset+30+name_size+extra_size
            records.append(struct.pack('<QQIIQH',offset,row.file_size,row.CRC,int(bool(row.compress_type)),0,len(name))+name)
    index.write_bytes(b'ZMI1'+struct.pack('<IQ',4,len(raw))+bytes(32)+b''.join(records))
    subprocess.run([str(Path(sys.argv[1]).resolve()),str(archive),str(index)],cwd=root,check=True)
