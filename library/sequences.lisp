;;; Higher-order combinators over sequences.
;;; Battery source: read by `load-battery`, never evaluated. See batteries.lisp.
;;;
;;; Each is stated at one element type, ?a. The kernel retypes a combinator to the element
;;; and result types a frame needs (`retype-function-definition`), so one statement serves.

(:battery :sequences
  :parameters ((?a :int)))

;; The code applied to each element.
(:function :map ((xs (:seq ?a)) (f (:code ((0 . ?a)) ?a))) (:seq ?a)
  (if (= xs ()) ()
      (cons (code-eval f (at xs 0)) (:map (tail xs) f)))
  :examples ((('() (code ((x ?a)) ?a x)) => '())
             (('(1 2 3) (code ((x ?a)) ?a (+ x 1))) => '(2 3 4))))

;; The step folded over the sequence from the right: step(x0, step(x1, ... base)).
(:function :foldr ((xs (:seq ?a)) (base ?a) (step (:code ((0 . ?a) (1 . ?a)) ?a))) ?a
  (if (= xs ()) base
      (code-eval step (at xs 0) (:foldr (tail xs) base step)))
  :examples ((('() 7 (code ((x ?a) (rest ?a)) ?a (- x rest))) => 7)
             (('(1 2 3) 10 (code ((x ?a) (rest ?a)) ?a (- x rest))) => -8)))

;; The step folded over the sequence from the left: step(... step(step(base, x0), x1) ...).
(:function :foldl ((xs (:seq ?a)) (base ?a) (step (:code ((0 . ?a) (1 . ?a)) ?a))) ?a
  (if (= xs ()) base
      (:foldl (tail xs) (code-eval step base (at xs 0)) step))
  :examples ((('() 7 (code ((sofar ?a) (x ?a)) ?a (- sofar x))) => 7)
             (('(1 2 3) 10 (code ((sofar ?a) (x ?a)) ?a (- sofar x))) => 4)))

;; The elements the predicate holds of, in order.
(:function :filter ((xs (:seq ?a)) (keep (:code ((0 . ?a)) :bool))) (:seq ?a)
  (if (= xs ()) ()
      (if (code-eval keep (at xs 0))
          (cons (at xs 0) (:filter (tail xs) keep))
          (:filter (tail xs) keep)))
  :examples ((('() (code ((x ?a)) :bool (< 0 x))) => '())
             (('(3 -1 4 0) (code ((x ?a)) :bool (< 0 x))) => '(3 4))))

;; The code applied to each element and the one before it: one output fewer than inputs.
(:function :map-adjacent ((xs (:seq ?a)) (f (:code ((0 . ?a) (1 . ?a)) ?a))) (:seq ?a)
  (if (= xs ()) ()
      (if (= (tail xs) ()) ()
          (cons (code-eval f (at (tail xs) 0) (at xs 0))
                (:map-adjacent (tail xs) f))))
  :examples ((('(5) (code ((next ?a) (here ?a)) ?a (- next here))) => '())
             (('(1 4 9) (code ((next ?a) (here ?a)) ?a (- next here))) => '(3 5))))
