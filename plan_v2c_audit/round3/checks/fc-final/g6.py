import re,sys
D='/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/round3/v5-for-check.md'
L=open(D).read().split('\n')
# section ranges of item 1
heads=[(i+1,l) for i,l in enumerate(L) if l.startswith('#')]
def rng(prefix):
    for k,(n,l) in enumerate(heads):
        if l.lstrip('#').strip().startswith(prefix):
            end=heads[k+1][0]-1 if k+1<len(heads) else len(L)
            return (n,end)
want=['1.3','1.4','1.6','5.9','6. Geometry','6.1','6.2','6.3','6.4','6.5','6.6','6.7','6.8','7.2','7.4','7.5','7.6','8.7','8.8','10.','11.1','11.2','11.3']
pat=re.compile(r'§(2|3|4|5\.[1-8]|7\.1|7\.3|8\.[1-4]|9)(\.\d+)?(?![\d])')
for w in want:
    a,b=rng(w)
    for n in range(a,b+1):
        s=L[n-1]
        for m in pat.finditer(s):
            st=max(0,m.start()-230); en=min(len(s),m.end()+40)
            print(f"{n} [{w}] ...{s[st:en]}...")
            print()
