import sys, warnings
warnings.filterwarnings("ignore")
import pymupdf
doc = pymupdf.open(sys.argv[1])
n = 0
for pno in range(len(doc)):
    page = doc[pno]
    words = page.get_text("words")
    for a in page.annots() or []:
        n += 1
        info = a.info
        t = a.type
        rect = a.rect
        print(f"--- #{n} page {pno+1} type={t[1]} rect=({rect.x0:.1f},{rect.y0:.1f},{rect.x1:.1f},{rect.y1:.1f}) created={info.get('creationDate')} mod={info.get('modDate')} author={info.get('title')}")
        print(f"    contents: {info.get('content')!r}")
        # text under highlight quads
        if t[1] in ("Highlight","Underline","Squiggly","StrikeOut"):
            v = a.vertices
            txt = []
            if v:
                for i in range(0, len(v), 4):
                    q = pymupdf.Quad(v[i:i+4]).rect
                    q = pymupdf.Rect(q.x0, q.y0+2, q.x1, q.y1-2)
                    ws = [w for w in words if pymupdf.Rect(w[:4]).intersects(q) and (min(w[3],q.y1)-max(w[1],q.y0)) > 0.5*(w[3]-w[1])]
                    txt.append(" ".join(w[4] for w in ws))
            print(f"    highlighted text: {' / '.join(txt)!r}")
        else:
            # nearby text: lines whose vertical range overlaps the annot rect, expanded
            r = pymupdf.Rect(0, rect.y0-4, page.rect.width, rect.y1+4)
            ws = [w for w in words if pymupdf.Rect(w[:4]).intersects(r)]
            ws.sort(key=lambda w:(round(w[1]),w[0]))
            print(f"    text on adjacent lines (y {rect.y0:.0f}-{rect.y1:.0f}): {' '.join(w[4] for w in ws)[:900]!r}")
print("TOTAL", n)
