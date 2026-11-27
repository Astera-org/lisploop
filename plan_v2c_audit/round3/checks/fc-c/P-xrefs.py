import re,sys
p='/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/round3/v3-for-check.md'
L=open(p).read().split('\n')
scope=[(120,626),(815,839),(897,909),(1285,1335),(1430,1509)]
pat=re.compile(r'(§\s?\d+(?:\.\d+)?(?:\s?(?:to|–|-|and)\s?§?\d+(?:\.\d+)?)?|Section \d+(?:\.\d+)?|Sections \d+ to \d+|Appendix [A-G]|Stage [A-D0-9]\b|\bX\d\b|experiment X\d)')
for a,b in scope:
    for i in range(a,b+1):
        s=L[i-1]
        for m in pat.finditer(s):
            t=m.group(1)
            # only out-of-own-section pointers of interest: 6,7,8,10,11, appendix, stage, X
            if re.match(r'(§\s?(6|7|8|10|11)\b|Section (6|7|8|10|11)|Appendix|Stage|X\d|experiment)',t) or True:
                c=s[max(0,m.start()-110):m.end()+40].replace('\n',' ')
                print(f'{i}\t{t}\t...{c}...')
