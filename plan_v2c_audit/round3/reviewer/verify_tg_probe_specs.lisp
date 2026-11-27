;;;; Test tg-probe on the ACTUAL kernel :spec rows and test inversion / composability gaps
(load "/home/tlh24/lisploop/plan_v2c_audit/proto/tg-probe.lisp")
(in-package :tg)

;; Add extra unary/binary code operators needed to represent the kernel's :spec code args
;; Kernel's :filter uses pos-pred (< 0 x) and even-pred (= (* (div x 2) 2) x);
;; Kernel's :map uses id and inc; :foldl / :map-adjacent / :scan use (- a b) and (+ a b).
(push (make-op :name 'posp :args '(:int) :res :bool :arity 1 :fn (lambda (x) (bool (< 0 x)))) *all-ops*)
(push (make-op :name 'evenp-op :args '(:int) :res :bool :arity 1 :fn (lambda (x) (bool (evenp x)))) *all-ops*)
(push (make-op :name 'call1b :args '(:code :int) :res :bool :arity 2
               :fn (lambda (f x) (funcall (op-fn (find f *all-ops* :key #'op-name)) x)))
      *all-ops*)

(format t "~&=== 1. TESTING TG-PROBE ON ACTUAL KERNEL :SPEC ROWS ===~%")
;; Each entry: (name task-struct actual-spec-examples)
;; where actual-spec-examples are copied verbatim from bootstrap/build-batteries.lisp!
(let ((spec-tests
        (list
         ;; 6 seed functions (build-batteries.lisp:563-568)
         (list "copy (:spec, 4 rows)"
               (tk "copy" '((xs :seq)) #'identity)
               '((((xs . ())) . ()) (((xs . (3))) . (3)) (((xs . (1 3))) . (1 3)) (((xs . (4 1 3))) . (4 1 3))))
         (list "inc-all (:spec, 4 rows)"
               (tk "inc-all" '((xs :seq)) (lambda (xs) (mapcar #'1+ xs)))
               '((((xs . ())) . ()) (((xs . (3))) . (4)) (((xs . (1 3))) . (2 4)) (((xs . (4 1 3))) . (5 2 4))))
         (list "dbl-all (:spec, 4 rows)"
               (tk "dbl-all" '((xs :seq)) (lambda (xs) (mapcar (lambda (x) (* 2 x)) xs)))
               '((((xs . ())) . ()) (((xs . (3))) . (6)) (((xs . (1 3))) . (2 6)) (((xs . (4 1 3))) . (8 2 6))))
         ;; positions (build-batteries.lisp:665-667)
         (list "positions (:spec, 11 rows)"
               (tk "positions" '((xs :seq) (k :int 0 4))
                   (lambda (xs k) (loop for i below (length xs) collect (+ k i))))
               (mapcar (lambda (r) (cons (list (cons 'xs (caar r)) (cons 'k (cadar r))) (second r)))
                       '(((() 0) ()) ((() 1) ()) ((() 2) ()) ((() 3) ()) ((() 4) ())
                         (((7) 2) (2)) (((4) 3) (3)) (((7) 0) (0))
                         (((6 7) 1) (1 2)) (((9 4) 2) (2 3)) (((5 6 7) 0) (0 1 2)))))
         ;; map-adjacent (build-batteries.lisp:645-652)
         ;; NOTE: In kernel :spec/map-adjacent, sub-step = (- arg0 arg1) applied to ((4 9)) -> (5),
         ;; which means f(xs[i+1], xs[i])? Wait: (- 4 9) = -5, (- 9 4) = 5! Let's check exact spec!
         (list "map-adjacent (:spec, 8 rows)"
               (tk "map-adjacent" '((xs :seq) (f :code))
                   (lambda (xs f) (loop for (a b) on xs while b collect (funcall f b a))))
               (mapcar (lambda (r) (cons (list (cons 'xs (first r)) (cons 'f (second r))) (third r)))
                       '((() - ()) ((9) - ()) ((4 9) - (5)) ((1 4 9) - (3 5))
                         (() + ()) ((5) + ()) ((2 5) + (7)) ((1 2 5) + (3 7)))))
         ;; scan (build-batteries.lisp:789-797)
         (list "scan (:spec, 9 rows)"
               (tk "scan" '((xs :seq) (a :int -5 9) (f :code))
                   (lambda (xs a f) (loop for x in xs collect (setf a (funcall f a x)))))
               (mapcar (lambda (r) (cons (list (cons 'xs (first r)) (cons 'a (second r)) (cons 'f (third r)))
                                         (fourth r)))
                       '((() 4 + ()) (() 5 + ()) (() 2 + ())
                         ((3) 2 + (5)) ((-1 3) 3 + (2 5)) ((2 -1 3) 1 + (3 2 5))
                         (() 6 - ()) ((4) 10 - (6)) ((1 4) 11 - (10 6)))))
         ;; shift-seq (build-batteries.lisp:837-842)
         (list "shift-seq (:spec, 13 rows)"
               (tk "shift-seq" '((xs :seq) (k :int 0 3))
                   (lambda (xs k) (loop for i below (length xs) collect (or (nth (+ i k) xs) 0))))
               (mapcar (lambda (r) (cons (list (cons 'xs (caar r)) (cons 'k (cadar r))) (second r)))
                       '(((() 0) ()) ((() 1) ()) ((() 2) ())
                         (((5) 0) (5)) (((1 5) 0) (1 5)) (((4 1 5) 0) (4 1 5))
                         (((5) 1) (0)) (((1 5) 1) (5 0)) (((4 1 5) 1) (1 5 0))
                         (((1 5) 2) (0 0)) (((4 1 5) 2) (5 0 0))
                         (((3 1 4 1 5) 0) (3 1 4 1 5))
                         (((3 1 4 1 5) 2) (4 1 5 0 0)))))
         ;; filter (build-batteries.lisp:629-635) using call1b
         (list "filter (:spec, 7 rows)"
               (tk "filter" '((xs :seq) (p :code))
                   (lambda (xs p)
                     (let ((fn (op-fn (find p *all-ops* :key #'op-name))))
                       (loop for x in xs when (eq :t (funcall fn x)) collect x))))
               (mapcar (lambda (r) (cons (list (cons 'xs (first r)) (cons 'p (second r))) (third r)))
                       '((() posp ()) ((3) posp (3)) ((-2 3) posp (3)) ((4 -2 3) posp (4 3))
                         (() evenp-op ()) ((3) evenp-op ()) ((4 3) evenp-op (4))))))))
  (let ((*d-ops* (append *d-ops* (ops 'call1b))))
    (dolist (entry spec-tests)
      (destructuring-bind (label task exs) entry
        (destructuring-bind (prog cand cells ms notes scan)
            (timed (lambda () (solve-task task exs 10 15000000)))
          (declare (ignore cells scan))
          (let ((ho (if prog
                        (if (string= (task-name task) "filter")
                            ;; custom held-out for unary predicate code
                            (let ((rs (sb-ext:seed-random-state 999)))
                              (count-if (lambda (dummy)
                                          (declare (ignore dummy))
                                          (let* ((xs (loop repeat (rnd rs 0 12) collect (rnd rs -5 9)))
                                                 (p (if (zerop (random 2 rs)) 'posp 'evenp-op))
                                                 (env (list (cons 'xs xs) (cons 'p p))))
                                            (equal (funcall (task-ref task) xs p) (ev prog env))))
                                        (make-list 200)))
                            (verify task prog))
                        0)))
            (format t "  ~28a -> cand=~9d ms=~5d held-out=~3d/200  prog=~s~%    notes=~a~%"
                    label cand ms ho prog notes)))))))

(format t "~&=== 2. SCALAR SPEC ROWS: SUM-ALL, LEN-ALL, PRD-ALL, LAST-OR, SEQ-CORR, FOLDL ===~%")
(let ((scalar-tests
        (list
         (list "sum-all (:spec, 4 rows)"
               (tk "sum-all" '((xs :seq)) (lambda (xs) (reduce #'+ xs)) :int)
               '((((xs . ())) . 0) (((xs . (3))) . 3) (((xs . (2 3))) . 5) (((xs . (4 2 3))) . 9)))
         (list "len-all (:spec, 4 rows)"
               (tk "len-all" '((xs :seq)) #'length :int)
               '((((xs . ())) . 0) (((xs . (3))) . 1) (((xs . (2 3))) . 2) (((xs . (4 2 3))) . 3)))
         (list "prd-all (:spec, 4 rows)"
               (tk "prd-all" '((xs :seq)) (lambda (xs) (reduce #'* xs :initial-value 1)) :int)
               '((((xs . ())) . 1) (((xs . (3))) . 3) (((xs . (2 3))) . 6) (((xs . (4 2 3))) . 24)))
         (list "last-or (:spec, 7 rows)"
               (tk "last-or" '((xs :seq) (d :int -5 9)) (lambda (xs d) (if xs (car (last xs)) d)) :int)
               (mapcar (lambda (r) (cons (list (cons 'xs (caar r)) (cons 'd (cadar r))) (second r)))
                       '(((() 7) 7) ((() 9) 9) (((4) 7) 4) (((1 4) 7) 4)
                         (((3 1 4) 7) 4) (((8) 2) 8) (((5 8) 2) 8))))
         (list "seq-corr (:spec, 7 rows)"
               (tk "seq-corr" '((xs :seq) (ys :seq))
                   (lambda (xs ys) (loop for x in xs for y in ys sum (* x y))) :int)
               (mapcar (lambda (r) (cons (list (cons 'xs (caar r)) (cons 'ys (cadar r))) (second r)))
                       '(((() ()) 0) ((() (5)) 0) (((3) ()) 0)
                         (((3) (5)) 15) (((2 3) (4 5)) 23) (((1 2 3) (2 4 5)) 25)
                         (((2 3) (5)) 10))))
         (list "foldl (:spec, 9 rows)"
               (tk "foldl" '((xs :seq) (a :int -5 9) (f :code))
                   (lambda (xs a f) (dolist (x xs a) (setf a (funcall f a x)))) :int)
               (mapcar (lambda (r) (cons (list (cons 'xs (first r)) (cons 'a (second r)) (cons 'f (third r)))
                                         (fourth r)))
                       '((() 7 - 7) (() 9 - 9) (() 6 - 6)
                         ((3) 9 - 6) ((2 3) 11 - 6) ((1 2 3) 12 - 6)
                         (() 10 - 10) ((4) 10 - 6) ((1 4) 11 - 6)))))))
  (dolist (entry scalar-tests)
    (destructuring-bind (label task exs) entry
      (let* ((base (make-base :n (length exs)))
             (leaves (input-cols task exs))
             (ys (map 'simple-vector #'cdr exs))
             (sc (solve-scalar base leaves ys 9 500000))
             (fl (solve-fold task exs 500000)))
        (format t "  ~26a scalar=~s (ho ~a) | fold=~s (ho ~a)~%"
                label
                sc (and sc (format nil "~d/200" (verify task sc)))
                fl (and fl (format nil "~d/200" (verify task fl))))))))

(format t "~&=== 3. INVERSE COMPLETENESS: ROUND-TRIP EXISTENCE GUARD FOR * AND DIV ===~%")
;; For *: fd-probe finds uniqueness guard G_u = (not (= b 0)) and witness W = (div c b).
;; Check on ALL (b, c) in [-20..20]^2 whether full guard G_full = (and G_u (= (* W b) c))
;; is 100% exact for "exists unique a in Z such that a * b = c, and W = a"!
(let ((errors 0) (checked 0))
  (loop for b from -20 to 20 do
    (loop for c from -20 to 20 do
      (incf checked)
      (let* ((true-sols (loop for a from -400 to 400 when (= (* a b) c) collect a))
             (true-unique (= 1 (length true-sols)))
             (g-uniq (not (= b 0)))
             (w (and g-uniq (floor c b)))
             (g-full (and g-uniq (= (* w b) c))))
        (unless (and (eq true-unique g-full)
                     (or (not true-unique) (= w (first true-sols))))
          (incf errors)))))
  (format t "  * full guard (and (not (= b 0)) (= (* (div c b) b) c)) over ~d pairs: ~d errors!~%"
          checked errors))

;; Check floor-div vs trunc-div for c = div(a, b) solving for b!
;; When is b = div(a, c) a valid SECTION vs UNIQUE inverse?
(let ((sec-hits 0) (nonempty 0))
  (loop for a from -12 to 12 do
    (loop for c from -12 to 12 do
      (let ((sols (loop for b from -30 to 30
                        when (and (/= b 0) (= (floor a b) c))
                        collect b)))
        (when sols
          (incf nonempty)
          (let ((cand (and (/= c 0) (floor a c))))
            (when (and cand (/= cand 0) (= (floor a cand) c))
              (incf sec-hits)))))))
  (format t "  floor-div b=div(a,c) hits a valid fiber element on ~d / ~d non-empty fibers (~,1f%)~%"
          sec-hits nonempty (* 100.0 (/ sec-hits nonempty))))
