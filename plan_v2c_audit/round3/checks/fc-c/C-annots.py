# print the /Contents strings of annotations in a decompressed PDF
import re,sys
for fn in sys.argv[1:]:
    data=open(fn,'rb').read()
    print('=====',fn)
    # literal strings
    for m in re.finditer(rb'/Contents\s*\(((?:\\.|[^\\()]|\((?:\\.|[^\\()])*\))*)\)', data):
        s=m.group(1)
        s=s.replace(b'\\r',b'\n').replace(b'\\n',b'\n').replace(b'\\(',b'(').replace(b'\\)',b')')
        try:
            if s.startswith(b'\xfe\xff'): t=s[2:].decode('utf-16-be','replace')
            else: t=s.decode('latin-1')
        except Exception as e: t=repr(s)
        if len(t.strip())>2: print('-',t.strip()[:900])
    for m in re.finditer(rb'/Contents\s*<([0-9A-Fa-f\s]+)>', data):
        h=re.sub(rb'\s',b'',m.group(1))
        b=bytes.fromhex(h.decode())
        t=b[2:].decode('utf-16-be','replace') if b.startswith(b'\xfe\xff') else b.decode('latin-1')
        if len(t.strip())>2: print('-',t.strip()[:900])
