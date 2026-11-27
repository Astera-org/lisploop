#!/usr/bin/env python3
"""Condense the per-task rows of an L1 log (E1, E4, E5b, ...) into one line per task:
   plain / first / probe candidates, gains, classes held (cls<=dn + cls>dn), CPU ms, look-ups per tested
   candidate, held-out, and whether the program is unchanged.
   Usage: python3 tabulate.py logs/e1.log [section-substring]"""
import re, sys

ROW = re.compile(r'^(.{24}) (\S+)\s+(\d+) \|\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+) \|\s+(\d+)\s+(\d+)\s+(\d+)\s+(\S+)\s+(\d+)\s+(\d+)\s+(\d+) \|\s+([\d.]+)\s+(\S+)\s*(\S*)')

def parse(path, section=None):
    out, cur, on = [], None, section is None
    for line in open(path):
        if line.startswith('--- '):
            on = section is None or section in line
            if on: out.append(('SECTION', line.strip()))
            continue
        if not on: continue
        m = ROW.match(line)
        if m:
            g = m.groups()
            out.append((g[0].strip(), g[1], dict(cand=int(g[2]), done=int(g[3]), cls=int(g[6]) + int(g[7]),
                                                 look=int(g[10]), lkg=g[11], work=int(g[14]), ms=float(g[15]),
                                                 ho=g[16], same=g[17])))
    return out

def main():
    path = sys.argv[1]; section = sys.argv[2] if len(sys.argv) > 2 else None
    rows = parse(path, section)
    tasks = {}
    order = []
    sec = 0
    for r in rows:
        if r[0] == 'SECTION':
            order.append(r); sec += 1; continue
        name, mode, d = r
        key = (sec, name)
        if key not in tasks: tasks[key] = {}; order.append(key)
        tasks[key][mode] = d
    hdr = f"{'task':24} {'plain':>9} {'first':>9} {'gain':>6} {'probe':>9} | {'cls-pl':>8} {'cls-fi':>8} | {'ms-pl':>8} {'ms-fi':>8} {'t-gain':>6} {'ms-pr':>8} {'t-gain':>6} | {'lk/cand':>7} | {'held-out':>8} same"
    for o in order:
        if o[0] == 'SECTION':
            print('\n' + o[1]); print(hdr); continue
        t = tasks[o]; p = t.get('plain'); f = t.get('first'); pr = t.get('probe')
        if not (p and f): continue
        def g(a, b): return f"{a / max(b, 1e-9):5.2f}x"
        print(f"{o[1]:24} {p['cand']:9d} {f['cand']:9d} {g(p['cand'], f['cand']):>6} {pr['cand'] if pr else 0:9d} | "
              f"{p['cls']:8d} {f['cls']:8d} | {p['ms']:8.2f} {f['ms']:8.2f} {g(p['ms'], f['ms']):>6} "
              f"{pr['ms'] if pr else 0:8.2f} {g(p['ms'], pr['ms']) if pr else '-':>6} | {f['lkg']:>7} | "
              f"{f['ho']:>8} {f['same']}{'' if not pr else ('' if pr['same'] == 'yes' else ' probe:' + pr['same'])}")

main()
