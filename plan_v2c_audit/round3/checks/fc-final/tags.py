import re
D='/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/round3/v5-for-check.md'
L=open(D).read().split('\n')
for n in range(639,1027):
    s=L[n-1]
    for m in re.finditer(r'\*\*\[M\]\*\*|\[M\]',s):
        st=max(0,m.start()-260)
        print(n, '...'+s[st:m.end()+60].replace('\n',' '))
        print()
