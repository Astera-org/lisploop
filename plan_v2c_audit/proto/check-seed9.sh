#!/bin/sh
# Prints the 12 training examples of "map-adjacent f" for seed 9 (the example set
# on which the default policy returned an impostor), to see which operators occur.
cd "$(dirname "$0")" || exit 1
sbcl --noinform --non-interactive --load tg-probe.lisp --eval '
(let ((*package* (find-package :tg)) (*print-case* :downcase)
      (task (find "map-adjacent f (spec)" tg::*tasks* :key (function tg::task-name) :test (function string=))))
  (dolist (seed (list 9 1))
    (format t "seed ~d~%" seed)
    (dolist (ex (tg::gen-examples task seed 12 7))
      (format t "  f=~a  xs=~a  ->  ~a~%" (cdr (assoc (quote tg::f) (car ex))) (cdr (assoc (quote tg::xs) (car ex))) (cdr ex)))))' > logs/check-seed9.log 2>&1
echo "exit $? -> logs/check-seed9.log"
