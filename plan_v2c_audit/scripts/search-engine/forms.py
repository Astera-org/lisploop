#!/usr/bin/env python3
"""List top-level forms (name, start line, line count) for the given Lisp files."""
import re, sys
for path in sys.argv[1:]:
    lines = open(path).read().split('\n')
    starts = [i for i, l in enumerate(lines) if l.startswith('(')]
    print(f"== {path} ({len(lines)} lines)")
    for k, s in enumerate(starts):
        e = starts[k + 1] if k + 1 < len(starts) else len(lines)
        # trim trailing blank/comment lines from the span
        span = lines[s:e]
        while span and (span[-1].strip() == '' or span[-1].lstrip().startswith(';')):
            span.pop()
        m = re.match(r'\((\S+)\s+\(?([^\s()]+)', lines[s])
        kind, name = (m.group(1), m.group(2)) if m else ('?', lines[s][:40])
        print(f"{s+1:5d} {len(span):4d} {kind} {name}")
