#!/usr/bin/env python3
"""Correct the line numbers cited in part-B.md after re-checking them with grep.
Each replacement must match exactly the stated number of times, or the script stops."""
P = "/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/round3/fc-c/part-B.md"
s = open(P, encoding="utf-8").read()

reps = [
    # finding 3
    ("`laws-library.md:28` (finding 8)", "`laws-library.md:29` (finding 8)", 1),
    ("(`laws-library.md:185-200`)", "(`laws-library.md:186-194`)", 1),
    # finding 4
    ("and its summary (line 77) says", "and its summary (line 84) says", 1),
    # finding 5
    ("(`bootstrap-reflection.md:118-119`)", "(`bootstrap-reflection.md:121-122`)", 1),
    # finding 6
    ("(`bootstrap-reflection.md:155-157`, `:118`, `:401-402`, `:256-257`)",
     "(`bootstrap-reflection.md:158`, `:121`, `:401-402`, `:266-267`)", 1),
    ("`resume-synthesis` (`bootstrap-reflection.md:118`)", "`resume-synthesis` (`bootstrap-reflection.md:121`)", 1),
    ("(`bootstrap-reflection.md:113`, `:210`:", "(`bootstrap-reflection.md:114`, `:210`:", 1),
    ("\"operational\" (`bootstrap-reflection.md:155`)", "\"operational\" (`bootstrap-reflection.md:158`)", 1),
    ("(`bootstrap-reflection.md:240-246`; `laws-library.md:259`)", "(`bootstrap-reflection.md:243-248`; `laws-library.md:259`)", 1),
    ("(`bootstrap-reflection.md:313-317`)", "(`bootstrap-reflection.md:315-319`)", 1),
    ("(`bootstrap-reflection.md:354-355`)", "(`bootstrap-reflection.md:358-359`)", 1),
    # finding 7
    ("(`deprecated/plan.md:241-244` and `:1021-1022`;", "(`deprecated/plan.md:241-244` and `:1023-1024`;", 1),
    # finding 9
    ("`core-repr.md:489-494` lists", "`core-repr.md:493-498` lists", 1),
    # finding 10
    ("Source: `laws-library.md:27`: \"A `:solver` is literally", "Source: `laws-library.md:28`: \"A `:solver` is literally", 1),
    ("(`consolidate.lisp:556-563`: \"The witness law says that, under GUARD, OPERATOR applied to WITNESS gives the target\")",
     "(`consolidate.lisp:556-563`: \"The witness law says that, under GUARD, OPERATOR applied to WITNESS gives the target\"; `milestones/algebra-discovery.lisp:34-39`, `solve-witness-law`, substitutes the witness for the unknown at a position of the operator)", 1),
    # finding 12
    ("(`laws.lisp:888-889`)", "(`laws.lisp:889-890`)", 1),
    # finding 13
    ("(`bootstrap-reflection.md:176`, `:221-229`)", "(`bootstrap-reflection.md:182`, `:222-229`)", 1),
    # table
    ("`laws-library.md:41-52`, `:65`;", "`laws-library.md:41-52`, `:63`;", 1),
    ("`consolidate.lisp:693-696`, `:803-831`, `:833-915`", "`consolidate.lisp:693-696`, `:799-831`, `:833-915`", 1),
    ("`bootstrap-reflection.md:155-157`, `:118`, `:256-257`, `:401-402`", "`bootstrap-reflection.md:158`, `:121`, `:266-267`, `:401-402`", 1),
    ("`bootstrap-reflection.md:417-420`, `:367-368`", "`bootstrap-reflection.md:417-431`, `:366`", 1),
    ("`bootstrap-reflection.md:249-250`, `:755-756`;", "`bootstrap-reflection.md:256-257`, `:753-755`;", 1),
    ("`frame.lisp:508-545` (docstring and four `cond` clauses)", "`frame.lisp:508-542` (docstring and four `cond` clauses)", 1),
    ("`core-repr.md:497-502`; `frame.lisp", "`core-repr.md:501-505`; `frame.lisp", 1),
    ("gap log; `core-repr.md:52-54`", "gap log; `core-repr.md:53-55`", 1),
    # checked list
    ("(`laws-library.md:140-155`)", "(`laws-library.md:148-161`)", 1),
    ("(`bootstrap-reflection.md:159-167`)", "(`bootstrap-reflection.md:158-169`)", 1),
    ("(`bootstrap-reflection.md:32-37`, `:210-218`, `:398-402`)", "(`bootstrap-reflection.md:37-41`, `:210-218`, `:398-402`)", 1),
    ("(`:39-43`, `:417-431`)", "(`:43-47`, `:417-431`)", 1),
    ("(393,075 / 165,602, `:787-789`)", "(393,075 / 165,602, `:796-797`)", 1),
    ("(`:755-756`); 8 tasks", "(`:753-755`); 8 tasks", 1),
]
for old, new, n in reps:
    c = s.count(old)
    if c != n:
        raise SystemExit(f"expected {n} match(es), found {c}: {old!r}")
    s = s.replace(old, new)

tail_old = "- Whether \"four times\" in the docs-origins report means one occasion per plan (finding 7): the report does not say.\n"
tail_new = tail_old + (
    "- Checks made after 19:01, when the root kernel files were moved to `/home/tlh24/lisploop/v1/`: only two. "
    "The line numbers of the function definitions cited above (`consolidate.lisp`, `proposals.lisp`, `frame.lisp`, "
    "`synthesize.lisp`, `laws.lisp`) were re-confirmed by grep against `v1/`, and `milestones/algebra-discovery.lisp:30-48` "
    "(used in finding 10) was read at `v1/milestones/algebra-discovery.lisp`. Every other read of a root file, including all "
    "of `deprecated/`, `plan7/`, `plan8.md`, `plan9-audit.md`, `tests/topology.lisp` and the kernel sources, was made at the "
    "root path before the move. No citation is reported as broken because of the move.\n"
)
if s.count(tail_old) != 1:
    raise SystemExit("tail line not found exactly once")
s = s.replace(tail_old, tail_new)
open(P, "w", encoding="utf-8").write(s)
print("applied", len(reps) + 1, "replacements")
