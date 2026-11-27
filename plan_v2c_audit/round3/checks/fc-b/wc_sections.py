# Word counts per section (## and ### headings) for the previous and the frozen version.
import re, sys
def sections(path):
    out = []  # (heading, words)
    cur = 'FRONT'; n = 0
    for line in open(path, encoding='utf-8'):
        m = re.match(r'^(##|###) (.*)', line)
        if m:
            out.append((cur, n)); cur = m.group(2).strip(); n = 0
        n += len(line.split())
    out.append((cur, n))
    return out
for p in sys.argv[1:]:
    print('=====', p)
    tot = 0
    for h, n in sections(p):
        tot += n
        print('%6d  %s' % (n, h[:80]))
    print('%6d  TOTAL' % tot)
