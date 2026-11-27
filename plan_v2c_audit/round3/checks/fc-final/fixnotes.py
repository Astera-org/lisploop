#!/usr/bin/env python3
"""Bring the revision notes (notes/10-part1.md, notes/length-paragraph.md) into line with the
corrections of the final check, so that the notes and the plan say the same thing."""
R = '/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/round3/'
fails = 0

def patch(path, old, new):
    global fails
    s = open(path).read()
    if s.count(old) != 1:
        fails += 1
        print('NOT APPLIED', s.count(old), old[:70])
        return
    open(path, 'w').write(s.replace(old, new))

P = R + 'notes/10-part1.md'
patch(P, "With a size bound raised round by round the loss did not occur: in Python, both branches of all 120 conditionals built for the test were kept one or two rounds later, at no extra cost. The added step",
         "With a size bound raised round by round, in Python, both branches of all 120 conditionals built for the test were kept one or two rounds later, at no extra cost. That test did not ask whether the guard was kept as well. The added step")
patch(P, "The second is the look-ahead once a held answer gives a firm bound: the classes held were ten times fewer or more on lifted tasks, in the store prototype.",
         "The second is the look-ahead once there is a firm bound on the size of the whole answer. In the store prototype the classes stored were 34 times fewer on the seven guarded runs, where a held answer gave the bound, and ten times fewer or more on three lifted tasks, where the answer's size was handed over.")

L = R + 'notes/length-paragraph.md'
patch(L, "It found about forty places where it had, and those were corrected (`reports/factcheck3-C.md`).",
         "It found about forty places where it had, and those were corrected (`reports/factcheck3-C.md`). A last check compared the finished plan with the full record of the vocabulary measurements. It found no figure that differed. It found twenty-five places where a figure was attached to the wrong arrangement, a qualifier had been dropped, two sections disagreed, or a pointer led to something that had moved, and those were corrected as well (`reports/factcheck3-final.md`, `reports/apply-final.md`).")
patch(L, "The plan keeps an account of about 3,300 words where that record has 6,900.",
         "The plan keeps an account of about 3,500 words where that record has 7,000.")
print('failures:', fails)
