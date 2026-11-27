import re
D='/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/round3/v5-for-check.md'
L=open(D).read().split('\n')
i=0
while i<len(L):
    if L[i].startswith('|') and i+1<len(L) and re.match(r'^\|[:\- |]+\|$',L[i+1]):
        hdr=L[i].count('|')-L[i].count('\\|')
        j=i+2
        while j<len(L) and L[j].startswith('|'):
            c=L[j].count('|')-L[j].count('\\|')
            if c!=hdr: print(f"table@{i+1} hdr={hdr-1} row@{j+1} cells={c-1}: {L[j][:110]}")
            if not L[j].rstrip().endswith('|'): print(f"row@{j+1} no trailing pipe")
            j+=1
        i=j
    else: i+=1
print('done')
# numbered-list count claims
pat=re.compile(r'\b(Two|Three|Four|Five|Six|Seven|Eight|Nine|Ten|two|three|four|five|six)\b[^.]{0,60}(follow|apply|rules|steps|findings|limits|purposes|uses|changes|qualifications|consequences|situations|arms|results|proposals|remarks|ways|things|signals|observations)\b')
for n,l in enumerate(L,1):
    for m in pat.finditer(l):
        print(n, l[max(0,m.start()-10):m.end()+30])
