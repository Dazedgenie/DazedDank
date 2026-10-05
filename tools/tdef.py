# Read/write Project Zomboid .tiles (tdef v1) files: one sheet, newline-terminated strings, LE ints.
import struct
def rd(b):
    p=0
    def i32():
        nonlocal p; v=struct.unpack_from('<i',b,p)[0]; p+=4; return v
    def s():
        nonlocal p; e=b.index(b'\n',p); v=b[p:e].decode('latin1'); p=e+1; return v
    assert b[:4]==b'tdef'; p=4
    ver=i32(); nsheets=i32(); sheets=[]
    for _ in range(nsheets):
        name=s(); img=s(); w=i32(); h=i32(); sid=i32(); n=i32(); tiles=[]
        for _ in range(n):
            k=i32(); props=[(s(),s()) for _ in range(k)]; tiles.append(props)
        sheets.append(dict(name=name,img=img,w=w,h=h,id=sid,tiles=tiles))
    assert p==len(b),(p,len(b))
    return ver,sheets
def wr(ver,sheets):
    o=bytearray(b'tdef')+struct.pack('<ii',ver,len(sheets))
    for sh in sheets:
        o+=sh['name'].encode('latin1')+b'\n'+sh['img'].encode('latin1')+b'\n'
        o+=struct.pack('<iiii',sh['w'],sh['h'],sh['id'],len(sh['tiles']))
        for props in sh['tiles']:
            o+=struct.pack('<i',len(props))
            for k,v in props: o+=k.encode('latin1')+b'\n'+v.encode('latin1')+b'\n'
    return bytes(o)
