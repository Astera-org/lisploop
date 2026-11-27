import re,sys,glob,os
# crude s-expression reader
def tokenize(s):
    tokens=[];i=0;n=len(s)
    while i<n:
        c=s[i]
        if c.isspace(): i+=1
        elif c in '()': tokens.append(c); i+=1
        elif c=='"':
            j=i+1
            while s[j]!='"':
                if s[j]=='\\': j+=1
                j+=1
            tokens.append(s[i:j+1]); i=j+1
        elif c==';':
            while i<n and s[i]!='\n': i+=1
        else:
            j=i
            while j<n and not s[j].isspace() and s[j] not in '()': j+=1
            tokens.append(s[i:j]); i=j
    return tokens
def parse(tokens):
    pos=0
    def rd():
        nonlocal pos
        t=tokens[pos]; pos+=1
        if t=='(':
            l=[]
            while tokens[pos]!=')': l.append(rd())
            pos+=1
            return l
        return t
    return rd()
def getf(pl,k,default=None):
    if not isinstance(pl,list): return default
    for i in range(0,len(pl)-1,2):
        if pl[i]==k: return pl[i+1]
    return default
def show(x):
    if isinstance(x,list):
        if len(x)>=2 and x[0]==':APP': 
            return '('+' '.join(show(y) for y in x[1:])+')'
        if len(x)>=2 and x[0]==':OP': return x[1].lower().lstrip(':')
        if len(x)>=2 and x[0]==':VAR': return 'x'+x[1]
        if len(x)>=3 and x[0]==':LIT': return "'"+show(x[2])
        if len(x)>=2 and x[0]==':HOLE': return '?'+x[1]
        return '('+' '.join(show(y) for y in x)+')'
    return x
for f in sorted(glob.glob('/home/tlh24/lisploop/v2/library/*.sexp')):
    s=open(f).read()
    t=parse(tokenize(s))
    print('=====',os.path.basename(f), 'top keys:', [x for x in t[1::2] if isinstance(x,str)])
    print('  METADATA', show(getf(t[1:],':METADATA')))
    ents=getf(t[1:],':ENTRIES')
    for e in ents:
        cert=getf(e,':CERTIFICATE')
        method=None; obl=None
        if isinstance(cert,list):
            d=getf(cert,':DATA',cert)
            method=getf(d,':METHOD',getf(d,':KIND')); obl=getf(d,':OBLIGATIONS')
        meta=getf(e,':METADATA')
        metakeys=[]
        if isinstance(meta,list):
            metakeys=[(meta[i], (show(meta[i+1]) if len(show(meta[i+1]))<60 else show(meta[i+1])[:57]+'...')) for i in range(0,len(meta)-1,2)]
        ex=show(getf(e,':EXPRESSION'))
        gd=show(getf(e,':GUARD'))
        print('-',getf(e,':ID'),getf(e,':KIND'),'dom=',show(getf(e,':DOMAIN')),'status=',getf(e,':STATUS'),'method=',method,'obl=',show(obl) if obl else None,'bits=',getf(e,':BITS'),'work=',getf(e,':WORK'))
        print('    inputs=',show(getf(e,':INPUTS')),'target=',show(getf(e,':TARGET')))
        print('    expr=',ex[:400])
        if gd!="'T": print('    guard=',gd[:300])
        for k in (':TRIGGER',':RESIDUAL',':AUXILIARY-CODE'):
            v=getf(e,k)
            if v and v!='NIL': print('   ',k,show(v)[:300])
        print('    edges=',show(getf(e,':EDGES'))[:300])
        print('    meta=',metakeys)
