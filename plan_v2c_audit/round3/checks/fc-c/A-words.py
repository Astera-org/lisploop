import re
base='/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/round3/'
lines=open(base+'v3-for-check.md').read().split('\n')
pat=re.compile(r'\b(stages?|nodes?|class(?:es)?|fold\w*|witness\w*|quotient\w*|signatures?|probes?|index\w*|indices)\b', re.I)
for i in range(119,219):
    for m in pat.finditer(lines[i]):
        s=max(0,m.start()-70); e=min(len(lines[i]), m.end()+50)
        print(i+1, '|', lines[i][s:e].replace('\n',' '))
