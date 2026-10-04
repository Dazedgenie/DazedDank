# Read/write Project Zomboid PZPK v1 texture packs: pages of PNG atlases with named, trimmed sprite entries.
import struct, io
from PIL import Image
def rd(b):
    p=0
    def i32():
        nonlocal p; v=struct.unpack_from('<i',b,p)[0]; p+=4; return v
    def s():
        nonlocal p; n=i32(); v=b[p:p+n].decode('latin1'); p+=n; return v
    assert b[:4]==b'PZPK'; p=4; ver=i32(); pages=[]
    for _ in range(i32()):
        name=s(); n=i32(); mask=i32()
        ents=[(s(),*[i32() for _ in range(8)]) for _ in range(n)]
        ln=i32(); png=b[p:p+ln]; p+=ln
        pages.append(dict(name=name,mask=mask,ents=ents,png=png))
    assert p==len(b),(p,len(b))
    return ver,pages
def wr(ver,pages):
    def st(x): x=x.encode('latin1'); return struct.pack('<i',len(x))+x
    o=bytearray(b'PZPK')+struct.pack('<ii',ver,len(pages))
    for pg in pages:
        o+=st(pg['name'])+struct.pack('<ii',len(pg['ents']),pg['mask'])
        for e in pg['ents']: o+=st(e[0])+struct.pack('<8i',*e[1:])
        o+=struct.pack('<i',len(pg['png']))+pg['png']
    return bytes(o)
def frames(pages):
    """Every sprite as a full-frame RGBA image, by name."""
    out={}
    for pg in pages:
        img=Image.open(io.BytesIO(pg['png'])).convert('RGBA')
        for (n,x,y,w,h,ox,oy,fw,fh) in pg['ents']:
            f=Image.new('RGBA',(fw,fh)); f.paste(img.crop((x,y,x+w,y+h)),(ox,oy)); out[n]=f
    return out
def pack_pages(prefix, start_index, named_frames, size=1024, pad=1):
    """Shelf-pack trimmed frames into new pages named prefix+index. Returns page dicts."""
    items=[]
    for n,f in named_frames:
        bb=f.getbbox() or (0,0,1,1)
        items.append((n,f.crop(bb),bb[0],bb[1],f.size[0],f.size[1]))
    items.sort(key=lambda t:-t[1].size[1])
    pages=[]; cur=None
    def newpage():
        return dict(img=Image.new('RGBA',(size,size)),ents=[],x=0,y=0,row=0)
    cur=newpage()
    for n,im,ox,oy,fw,fh in items:
        w,h=im.size
        if cur['x']+w>size: cur['x']=0; cur['y']+=cur['row']+pad; cur['row']=0
        if cur['y']+h>size:
            pages.append(cur); cur=newpage()
        cur['img'].paste(im,(cur['x'],cur['y']))
        cur['ents'].append((n,cur['x'],cur['y'],w,h,ox,oy,fw,fh))
        cur['x']+=w+pad; cur['row']=max(cur['row'],h)
    pages.append(cur)
    out=[]
    for i,pg in enumerate(pages):
        bio=io.BytesIO(); pg['img'].save(bio,'PNG',optimize=True)
        out.append(dict(name=f"{prefix}{start_index+i}",mask=1,ents=pg['ents'],png=bio.getvalue()))
    return out
