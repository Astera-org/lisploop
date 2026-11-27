;;;; r1-spec.lisp -- verify-review R1: run tg-probe on the kernel's ACTUAL :spec rows.
;;;; Loaded AFTER tg-probe-r1.lisp (the probe copy with 3 marked modifications).
;;;; Everything in this file is an ADDITION (driver + data + hidden references);
;;;; it redefines nothing in the probe.
(in-package :tg)

;;; -------------------------------------------------------------------
;;; Hidden references: line-by-line transliterations of the kernel's library
;;; :EXPRESSION for each function (v2/library/{sequences,scans,sequence-shift}.sexp).
;;; A :code argument is an operator NAME (+ - *), applied with FUNCALL, exactly as
;;; the probe's own tasks do; a :pred argument is one of the names POS EVEN NEG.
;;; copy / inc-all / dbl-all / sum-all / len-all / prd-all are NOT stored in the
;;; library (they are the bootstrap's seed corpus, build-batteries.lisp:563-568);
;;; their references are the functions their names and four rows denote.
;;; -------------------------------------------------------------------
(defun r-copy (xs) (if (null xs) nil (cons (car xs) (r-copy (cdr xs)))))
(defun r-inc-all (xs) (if (null xs) nil (cons (+ (car xs) 1) (r-inc-all (cdr xs)))))
(defun r-dbl-all (xs) (if (null xs) nil (cons (* (car xs) 2) (r-dbl-all (cdr xs)))))
(defun r-sum-all (xs) (if (null xs) 0 (+ (car xs) (r-sum-all (cdr xs)))))
(defun r-len-all (xs) (if (null xs) 0 (+ 1 (r-len-all (cdr xs)))))
(defun r-prd-all (xs) (if (null xs) 1 (* (car xs) (r-prd-all (cdr xs)))))
;; :positions  (if (= xs ()) xs (cons k (positions (tail xs) (+ k 1))))
(defun r-positions (xs k) (if (null xs) xs (cons k (r-positions (cdr xs) (+ k 1)))))
;; :scan  (if (= xs ()) () (cons (f a xs0) (scan (tail xs) (f a xs0) f)))
(defun r-scan (xs a f)
  (if (null xs) nil (cons (funcall f a (car xs)) (r-scan (cdr xs) (funcall f a (car xs)) f))))
;; :shift-seq  (if (= xs ()) () (if (< 0 k) (concat (cons (shift-seq (tail xs) (- k 1)) ((0)))) xs))
(defun r-shift-seq (xs k)
  (cond ((null xs) nil) ((< 0 k) (append (r-shift-seq (cdr xs) (- k 1)) (list 0))) (t xs)))
;; :filter  (if (= xs ()) xs (if (p xs0) (cons xs0 (filter (tail xs) p)) (filter (tail xs) p)))
(defun pred-fn (p) (ecase p (pos (lambda (x) (< 0 x))) (even #'evenp) (neg (lambda (x) (< x 0)))))
(defun r-filter (xs p)
  (cond ((null xs) xs)
        ((funcall (pred-fn p) (car xs)) (cons (car xs) (r-filter (cdr xs) p)))
        (t (r-filter (cdr xs) p))))
;; :map-adjacent (if (= xs ()) () (if (= (tail xs) ()) () (cons (f xs1 xs0) (map-adjacent (tail xs) f))))
(defun r-map-adjacent (xs f)
  (cond ((null xs) nil) ((null (cdr xs)) nil)
        (t (cons (funcall f (cadr xs) (car xs)) (r-map-adjacent (cdr xs) f)))))
;; :foldl  (if (= xs ()) a (foldl (tail xs) (f a xs0) f))
(defun r-foldl (xs a f) (if (null xs) a (r-foldl (cdr xs) (funcall f a (car xs)) f)))
;; :seq-corr (if (= xs ()) 0 (if (= ys ()) 0 (+ (* xs0 ys0) (seq-corr (tail xs) (tail ys)))))
(defun r-seq-corr (xs ys)
  (cond ((null xs) 0) ((null ys) 0) (t (+ (* (car xs) (car ys)) (r-seq-corr (cdr xs) (cdr ys))))))
;; :best-shift (if (= xs ()) (tuple 0 k)
;;               ((lambda (c rest k) (if (< c (at rest 0)) rest (tuple c k)))
;;                (seq-corr xs ys) (best-shift (tail xs) ys (+ k 1)) k))
(defun r-best-shift (xs ys k)
  (if (null xs) (list 0 k)
      (let ((c (r-seq-corr xs ys)) (rest (r-best-shift (cdr xs) ys (+ k 1))))
        (if (< c (first rest)) rest (list c k)))))
;; :argmax-corr (at (best-shift xs ys 0) 1)
(defun r-argmax-corr (xs ys) (second (r-best-shift xs ys 0)))
;; :last-or (if (= xs ()) d (if (= (tail xs) ()) xs0 (last-or (tail xs) d)))
(defun r-last-or (xs d) (cond ((null xs) d) ((null (cdr xs)) (car xs)) (t (r-last-or (cdr xs) d))))

;;; -------------------------------------------------------------------
;;; The kernel's :spec rows, copied from bootstrap/build-batteries.lisp
;;; (line numbers given).  sub-step (- x0 x1) -> the name -, add-step (+ x0 x1) -> +,
;;; pos-pred (< 0 x0) -> POS, even-pred (= (* (/ x0 2) 2) x0) -> EVEN.
;;; Entry: (task . rows); a row is ((input ...) output) in the kernel's argument order.
;;; Integer ranges in INS are used ONLY by the held-out generator (my choice, stated in the report).
;;; -------------------------------------------------------------------
(defparameter *spec*
  (list
   ;; --- build-batteries.lisp:563-568 (seed corpus, 4 rows each)
   (cons (tk "copy" '((xs :seq)) #'r-copy)
         '(((()) ()) (((3)) (3)) (((1 3)) (1 3)) (((4 1 3)) (4 1 3))))
   (cons (tk "inc-all" '((xs :seq)) #'r-inc-all)
         '(((()) ()) (((3)) (4)) (((1 3)) (2 4)) (((4 1 3)) (5 2 4))))
   (cons (tk "dbl-all" '((xs :seq)) #'r-dbl-all)
         '(((()) ()) (((3)) (6)) (((1 3)) (2 6)) (((4 1 3)) (8 2 6))))
   (cons (tk "sum-all" '((xs :seq)) #'r-sum-all :int)
         '(((()) 0) (((3)) 3) (((2 3)) 5) (((4 2 3)) 9)))
   (cons (tk "len-all" '((xs :seq)) #'r-len-all :int)
         '(((()) 0) (((3)) 1) (((2 3)) 2) (((4 2 3)) 3)))
   (cons (tk "prd-all" '((xs :seq)) #'r-prd-all :int)
         '(((()) 1) (((3)) 3) (((2 3)) 6) (((4 2 3)) 24)))
   ;; --- :spec/positions, build-batteries.lisp:664-667 (11 rows)
   (cons (tk "positions" '((xs :seq) (k :int 0 4)) #'r-positions)
         '(((() 0) ()) ((() 1) ()) ((() 2) ()) ((() 3) ()) ((() 4) ())
           (((7) 2) (2)) (((4) 3) (3)) (((7) 0) (0))
           (((6 7) 1) (1 2)) (((9 4) 2) (2 3)) (((5 6 7) 0) (0 1 2))))
   ;; --- :spec/scan, build-batteries.lisp:788-797 (9 rows)
   (cons (tk "scan" '((xs :seq) (a :int -5 9) (f :code)) #'r-scan)
         '(((() 4 +) ()) ((() 5 +) ()) ((() 2 +) ()) (((3) 2 +) (5)) (((-1 3) 3 +) (2 5))
           (((2 -1 3) 1 +) (3 2 5)) ((() 6 -) ()) (((4) 10 -) (6)) (((1 4) 11 -) (10 6))))
   ;; --- :spec/shift-seq, build-batteries.lisp:836-842 (13 rows)
   (cons (tk "shift-seq" '((xs :seq) (k :int 0 3)) #'r-shift-seq)
         '(((() 0) ()) ((() 1) ()) ((() 2) ())
           (((5) 0) (5)) (((1 5) 0) (1 5)) (((4 1 5) 0) (4 1 5))
           (((5) 1) (0)) (((1 5) 1) (5 0)) (((4 1 5) 1) (1 5 0))
           (((1 5) 2) (0 0)) (((4 1 5) 2) (5 0 0))
           (((3 1 4 1 5) 0) (3 1 4 1 5))
           (((3 1 4 1 5) 2) (4 1 5 0 0))))
   ;; --- :spec/filter, build-batteries.lisp:628-635 (7 rows)
   (cons (tk "filter" '((xs :seq) (p :pred)) #'r-filter)
         '(((() pos) ()) (((3) pos) (3)) (((-2 3) pos) (3)) (((4 -2 3) pos) (4 3))
           ((() even) ()) (((3) even) ()) (((4 3) even) (4))))
   ;; --- :spec/map-adjacent, build-batteries.lisp:644-652 (8 rows)
   (cons (tk "map-adjacent" '((xs :seq) (f :code)) #'r-map-adjacent)
         '(((() -) ()) (((9) -) ()) (((4 9) -) (5)) (((1 4 9) -) (3 5))
           ((() +) ()) (((5) +) ()) (((2 5) +) (7)) (((1 2 5) +) (3 7))))
   ;; --- :spec/foldl, build-batteries.lisp:611-620 (9 rows)
   (cons (tk "foldl" '((xs :seq) (a :int -5 9) (f :code)) #'r-foldl :int)
         '(((() 7 -) 7) ((() 9 -) 9) ((() 6 -) 6) (((3) 9 -) 6) (((2 3) 11 -) 6)
           (((1 2 3) 12 -) 6) ((() 10 -) 10) (((4) 10 -) 6) (((1 4) 11 -) 6)))
   ;; --- :spec/last-or, build-batteries.lisp:893-895 (7 rows)
   (cons (tk "last-or" '((xs :seq) (d :int -5 9)) #'r-last-or :int)
         '(((() 7) 7) ((() 9) 9) (((4) 7) 4) (((1 4) 7) 4)
           (((3 1 4) 7) 4) (((8) 2) 8) (((5 8) 2) 8)))
   ;; --- :spec/seq-corr, build-batteries.lisp:853-856 (7 rows)
   (cons (tk "seq-corr" '((xs :seq) (ys :seq)) #'r-seq-corr :int)
         '(((() ()) 0) ((() (5)) 0) (((3) ()) 0)
           (((3) (5)) 15) (((2 3) (4 5)) 23) (((1 2 3) (2 4 5)) 25)
           (((2 3) (5)) 10)))
   ;; --- :spec/best-shift, build-batteries.lisp:867-870 (9 rows; output is a 2-tuple)
   (cons (tk "best-shift" '((xs :seq) (ys :seq) (k :int 0 3)) #'r-best-shift :tuple)
         '(((() (4 1) 3) (0 3)) ((() (4 1) 2) (0 2)) ((() (4 1) 1) (0 1))
           (((1) (4 1) 2) (4 2)) (((4 1) (4 1) 1) (17 1)) (((3 4 1) (4 1) 0) (17 1))
           ((() (5 0) 2) (0 2)) (((2) (5 0) 1) (10 1)) (((5 2) (5 0) 0) (25 0))))
   ;; --- :spec/argmax-corr, build-batteries.lisp:881-884 (3 rows)
   (cons (tk "argmax-corr" '((xs :seq) (ys :seq)) #'r-argmax-corr :int)
         '((((3 4 1) (4 1)) 1) (((5 2) (5 0)) 0) (((3 1 4 1 5) (4 1 5 0 0)) 2)))))

(defun spec-task (name) (car (assoc name *spec* :key #'task-name :test #'string=)))
(defun spec-exs (name)
  "The spec rows of task NAME as probe examples: ((input-name . value) ...) . output."
  (let* ((e (assoc name *spec* :key #'task-name :test #'string=))
         (names (mapcar #'first (task-ins (car e)))))
    (mapcar (lambda (row) (cons (mapcar #'cons names (first row)) (second row))) (cdr e))))

(defun check-refs ()
  "Every hidden reference must reproduce every one of its spec rows."
  (dolist (e *spec*)
    (let* ((task (car e)) (bad 0))
      (dolist (ex (spec-exs (task-name task)))
        (unless (equal (cdr ex) (apply (task-ref task) (mapcar #'cdr (car ex)))) (incf bad)))
      (format t "ref-check ~14a ~2d rows, ~d mismatches~%" (task-name task) (length (cdr e)) bad)
      (assert (zerop bad)))))

(defun held-out (task prog &key (n 200) (seed 999) (maxlen 12))
  "The probe's own VERIFY, guarded: returns the count, or (:error msg) if PROG signals."
  (handler-case (verify task prog :n n :seed seed :maxlen maxlen)
    (error (c) (list :error (princ-to-string c)))))

(defun elem-of (prog)
  "The element/predicate/step term inside the granted container form."
  (case (and (consp prog) (first prog))
    (tabulate (third (third prog)))
    ((select where) (third (third prog)))
    ((fold foldr) (third (third prog)))
    (fold-space (third (fourth prog)))    ; used by r2-reduce.lisp only
    (t prog)))

(defun report (label task exs thunk)
  (destructuring-bind (prog cand cells ms notes scan)
      (handler-case (timed thunk)
        (error (c) (list (list :error (princ-to-string c)) *cand* *cells* -1 (reverse *note*) *scan*)))
    (declare (ignore cells))
    (let ((err (and (consp prog) (eq (first prog) :error))))
      (format t "~14a ~22a rows ~2d  cand ~9d  ms ~6d  held-out ~8a  size(elem) ~a~%   program: ~s~%   [~{~a~^; ~}; split-scan cells ~d]~%"
              (task-name task) label (length exs) cand ms
              (cond (err "ERROR") (prog (let ((h (held-out task prog))) (if (integerp h) (format nil "~d/200" h) h)))
                    (t "-"))
              (if (and prog (not err)) (tsize (elem-of prog)) "-")
              prog notes scan)
      (finish-output)
      prog)))

(defun run-seq (name &key (max-size 10) (limit 30000000) (label "default"))
  "A sequence-output spec through the probe's own SOLVE-TASK (tabulate, else select/where),
   with the probe's EXP-D defaults: max size 10, budget 30M candidates."
  (let ((task (spec-task name)) (exs (spec-exs name)))
    (report label task exs (lambda () (solve-task task exs max-size limit)))))

(defun run-scalar (name)
  "A scalar-output spec through the two paths the probe's EXP-D uses for its fold
   negatives, with the same budgets: SOLVE-SCALAR (size<=9, 3M) and SOLVE-FOLD (3M)."
  (let* ((task (spec-task name)) (exs (spec-exs name))
         (base (make-base :n (length exs))) (leaves (input-cols task exs))
         (ys (map 'simple-vector #'cdr exs)))
    (list (report "scalar (unlifted)" task exs (lambda () (solve-scalar base leaves ys 9 3000000)))
          (report "fold form" task exs (lambda () (solve-fold task exs 3000000))))))

(defun breakdown (name prog)
  "Held-out hits of PROG split by the value of the function/predicate argument, and by output length."
  (let* ((task (spec-task name)) (tab (make-hash-table :test 'equal)))
    (dolist (ex (gen-examples task 999 200 12))
      (let* ((fa (or (cdr (assoc 'f (car ex))) (cdr (assoc 'p (car ex))) '-))
             (triv (if (listp (cdr ex)) (if (null (cdr ex)) :empty-output :nonempty-output) :scalar))
             (key (list fa triv)) (cell (or (gethash key tab) (setf (gethash key tab) (list 0 0)))))
        (incf (second cell))
        (when (equal (cdr ex) (ev prog (car ex))) (incf (first cell)))))
    (format t "   held-out breakdown (arg, output): ~{~a~^  ~}~%"
            (sort (loop for k being the hash-keys of tab using (hash-value v)
                        collect (format nil "~a/~a ~d/~d" (first k) (second k) (first v) (second v)))
                  #'string<))))

(defun r1 ()
  (let ((*package* (find-package :tg)) (*print-pretty* nil) (*print-case* :downcase))
    (format t "=== R1: tg-probe on the kernel's :spec rows; held-out = probe VERIFY (200 examples, seed 999, maxlen 12) ===~%")
    (format t "d-ops ~a~%" (mapcar #'op-name *d-ops*))
    (check-refs)
    (format t "~%--- (a) copy inc-all dbl-all positions ; (b) scan shift-seq : SOLVE-TASK default policy ---~%")
    (dolist (n '("copy" "inc-all" "dbl-all" "positions" "scan" "shift-seq")) (run-seq n))
    (format t "~%--- (c) filter: grammar WITHOUT call1b (probe as it stands), then WITH call1b ---~%")
    (run-seq "filter" :label "no call1b")
    (let ((*d-ops* (append *d-ops* (ops 'call1b))))
      (let ((p (run-seq "filter" :label "+call1b"))) (when p (breakdown "filter" p))))
    (format t "~%--- (d) sum-all len-all prd-all last-or: unlifted scalar path, then fold path ---~%")
    (dolist (n '("sum-all" "len-all" "prd-all" "last-or")) (run-scalar n))
    (format t "~%--- (e) map-adjacent on its 8 spec rows: default policy, then *occam* = t ---~%")
    (let ((p (run-seq "map-adjacent"))) (when p (breakdown "map-adjacent" p)))
    (let ((*occam* t))
      (let ((p (run-seq "map-adjacent" :label "occam"))) (when p (breakdown "map-adjacent" p))))
    (format t "~%--- (f) foldl on its 9 spec rows: unlifted scalar path, then fold path ---~%")
    (dolist (p (run-scalar "foldl")) (when (and p (not (eq (first p) :error))) (breakdown "foldl" p)))
    (format t "~%--- (g) seq-corr, argmax-corr: scalar + fold paths; best-shift: SOLVE-TASK on the 2-tuple as a sequence ---~%")
    (run-scalar "seq-corr")
    (run-scalar "argmax-corr")
    (run-seq "best-shift")
    (finish-output)))
