#!/usr/bin/env python3
# Parse e4_x1000_*.log rung lines: per searching node, (completed body bits, node work, syntax count);
# least-squares fit of ln(work) and ln(syntax) against completed body bits -> growth factor per bit.
import re, sys, math, glob, os
E='/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/empirical/logs/'
def fit(xs, ys):
    n=len(xs); mx=sum(xs)/n; my=sum(ys)/n
    sxx=sum((x-mx)**2 for x in xs); sxy=sum((x-mx)*(y-my) for x,y in zip(xs,ys))
    b=sxy/sxx; a=my-b*mx; return a,b
for spec in ['map-adjacent','scan','shift-seq','best-shift','argmax-corr']:
    f=E+'e4_x1000_%s.log'%spec
    if not os.path.exists(f): continue
    nodes={}; tot=[]
    for line in open(f):
        if not line.startswith('  rung'): continue
        m=re.search(r'cap=\s*(\d+) work=\s*(\d+) claim=(\S+)\s+cpu_s=\s*([\d.]+) wall_s=\s*([\d.]+) gc_s=\s*(-?[\d.]+) live_MiB=\s*([\d.]+)',line)
        cap,work,claim,cpu,wall,gc,live=m.groups(); tot.append((int(work),float(cpu),float(gc),float(live)))
        for nm in re.finditer(r'\((\d+) (\S+) :BOUND (\d+) :DONE-BITS (\d+) :HDR (\d+) :BODY-SIZE (\d+) :OPS (\d+) :INPUTS (\d+) :SYNTAX (\d+) :WORK (\d+) :REJECTED (\d+)\)',line):
            nid,prop,bound,done,hdr,body,ops,inp,syn,w,rej=nm.groups()
            nodes.setdefault(int(nid),[]).append(dict(prop=prop,bound=int(bound),hdr=int(hdr),done=int(done)-int(hdr),ops=int(ops),inp=int(inp),syn=int(syn),work=int(w),tot=int(work)))
    print('=====',spec)
    w,c,g,l=tot[-1]
    print('  final: work=%d cpu_s=%.2f gc_s=%.2f (%.0f%%) live_MiB=%.0f  => %.2fM work/s, %.1f bytes live per work unit'%(w,c,g,100*g/c,l,w/c/1e6,l*1048576/w))
    for (w,c,g,l) in tot:
        if w in (350000,3500000,35000000,100000000,350000000): print('    work=%11d cpu_s=%7.2f gc_s=%6.2f live_MiB=%7.1f rate=%.2fM/s'%(w,c,g,l,w/max(c,1e-9)/1e6))
    for nid,rs in sorted(nodes.items()):
        if len(rs)<4: 
            print('  node',nid,rs[-1]['prop'],'(only %d rungs in :search)'%len(rs)); continue
        # use the last rung at which each completed-bits value is first seen -> (bits, work when that many bits were complete is <= work)
        pts=[(r['done'],r['work'],r['syn']) for r in rs if r['work']>=300000]
        a,b=fit([p[0] for p in pts],[math.log(p[1]) for p in pts])
        a2,b2=fit([p[0] for p in pts],[math.log(p[2]) for p in pts])
        last=rs[-1]; cap_body=last['bound']-last['hdr']
        print('  node %d %-24s inputs=%d ops=%d hdr=%d  body-bit cap=%d ; completed body bits %d @350k-total -> %d @final ; node work %d ; syntax %d ; work/syntax=%.1f'%(
            nid,last['prop'],last['inp'],last['ops'],last['hdr'],cap_body,rs[0]['done'],last['done'],last['work'],last['syn'],last['work']/last['syn']))
        print('      growth per body bit: work x%.3f, syntax x%.3f  (fit over %d rungs, completed bits %d..%d)'%(math.exp(b),math.exp(b2),len(pts),pts[0][0],pts[-1][0]))
        # extrapolate: work needed (for this node alone) to exhaust its bound, and bits reachable in 1h/10h at node's share
        need=last['work']*math.exp(b*(cap_body-last['done']))
        print('      to exhaust the %d-bit body cap this node alone needs ~%.2e work (x%.1e its current work)'%(cap_body,need,need/last['work']))
        for hours in (1,10):
            rate=w/c; share=last['work']/last['tot']; budget=hours*3600*rate*share
            bits=last['done']+math.log(budget/last['work'])/b
            print('      %2dh single-thread at %.2fM work/s (node share %.0f%%): completed body bits ~%.1f'%(hours,rate/1e6,100*share,bits))
