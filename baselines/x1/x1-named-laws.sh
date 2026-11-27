#!/bin/bash
# Which textbook laws are among the 187, and in which job. Reads x1-equations-by-job.txt.
W="$(cd "$(dirname "$0")" && pwd)"
F="$W/x1-equations-by-job.txt"
look() {
  printf '%-34s %-46s ' "$1" "$2"
  hits=$(grep -F -- "	$2" "$F" | cut -f1 | tr '\n' ' ')
  if [ -n "$hits" ]; then echo "yes: $hits"; else echo "no"; fi
}
look "commutativity of +"            "(= (+ x1 x0) (+ x0 x1))"
look "commutativity of + (x0,x2)"    "(= (+ x2 x0) (+ x0 x2))"
look "commutativity of + (x1,x2)"    "(= (+ x2 x1) (+ x1 x2))"
look "commutativity of *"            "(= (* x1 x0) (* x0 x1))"
look "commutativity of * (x0,x2)"    "(= (* x2 x0) (* x0 x2))"
look "commutativity of * (x1,x2)"    "(= (* x2 x1) (* x1 x2))"
look "associativity of +"            "(= (+ (+ x0 x1) x2) (+ x0 (+ x1 x2)))"
look "associativity of *"            "(= (* (* x0 x1) x2) (* x0 (* x1 x2)))"
look "right identity of +"           "(= (+ x0 0) x0)"
look "left identity of +"            "(= (+ 0 x0) x0)"
look "right identity of *"           "(= (* x0 1) x0)"
look "left identity of *"            "(= (* 1 x0) x0)"
look "right zero of *"               "(= (* x0 0) 0)"
look "left zero of *"                "(= (* 0 x0) 0)"
look "distributivity"                "(= (+ (* x0 x1) (* x0 x2)) (* x0 (+ x1 x2)))"
look "distributivity instance, x*(x+1)" "(= (* x0 (+ x0 1)) (+ x0 (* x0 x0)))"
look "GF(3) only: x*x*x = x"         "(= (* x0 (* x0 x0)) x0)"
look "GF(3) only: x+x+x = 0"         "(= (+ x0 (+ x0 x0)) 0)"
echo
echo "operators that occur anywhere in the 187 equations:"
cut -f2 "$F" | grep -o '([^ ()]*' | sort | uniq -c
echo "literals that occur as whole arguments:"
cut -f2 "$F" | grep -o ' [0-9]\+' | sort | uniq -c
echo
echo "equations per job, and lines that occur in more than one job:"
cut -f1 "$F" | sort | uniq -c
cut -f2 "$F" | sort | uniq -d | wc -l | sed 's/$/ distinct equations occur more than once/'
cut -f2 "$F" | sort | uniq -c | awk '$1>1{n+=$1-1} END{print n " surplus lines (187 minus distinct)"}'
echo "distributivity in the 3-variable two-operator run at 34 body bits:"
grep -n -F -- "(= (+ (* x0 x1) (* x0 x2)) (* x0 (+ x1 x2)))" "$W/x1-dist34.equations.txt"
