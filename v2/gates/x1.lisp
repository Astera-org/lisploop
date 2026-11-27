;;; Gate X1 (plan_v2c.md section 11.2): classes, and law discovery on the store.
;;;
;;;   sbcl --dynamic-space-size 8000 --script gates/x1.lisp
;;;
;;; The baseline is recorded in ../baselines/x1/. The present kernel's bucket engine proposes 187
;;; equations on GF(3) in four separate jobs. Each equation sets a syntactic term equal to the
;;; first term of its behaviour class, and the terms range over every tree within a bound, so
;;; the 187 include equations whose sub-terms are not themselves the first of their class.
;;;
;;; This store builds terms only from the smallest term of each class. So it states fewer
;;; equations, one for each collision, and the comparison is made in the way the baseline's
;;; report prescribes for an engine of this kind:
;;;
;;;   same classes     both sides of every baseline equation fall in one class of the store, and
;;;                    two terms that the baseline puts in different classes fall in different ones
;;;   implied          both sides of every baseline equation reach one normal form using only the
;;;                    store's own collision equations and replacement of equals inside a term
;;;
;;; "At least 10 times less work at the same bound" has three readings, because the present
;;; kernel's ledger unit is not one operator applied on one row. All three are reported.

(load (merge-pathnames "common.lisp" (make-pathname :name nil :type nil :defaults *load-truename*)))
(in-package #:lisploop2)

(defparameter *gf3* (gf 3))
(defparameter *env* `((x0 . ,*gf3*) (x1 . ,*gf3*) (x2 . ,*gf3*)))

(defun gf3-term (sexp) (parse-term sexp *env* *gf3*))

(defun field-bank (variable-count op-names literals)
  "A bank on every assignment of the variables x0 ... over GF(3)."
  (let ((variables (loop for k below variable-count
                         collect (var (intern (format nil "X~d" k) '#:lisploop2) *gf3*))))
    (multiple-value-bind (space leaves) (exhaustive-space variables)
      (let ((bank (make-bank space op-names)))
        (loop for v in variables for (nil . column) in leaves do (add-leaf bank v column))
        (dolist (c literals) (add-constant bank c *gf3*))
        bank))))

(defun read-lines (name)
  (with-open-file (s (baseline-path (concatenate 'string "x1/" name)))
    (loop for line = (read-line s nil) while line
          unless (or (zerop (length line)) (char= #\# (char line 0))) collect line)))

(defun split-tabs (line)
  (loop with start = 0
        for tab = (position #\Tab line :start start)
        collect (subseq line start tab)
        while tab do (setf start (1+ tab))))

(defun read-sexp (text)
  (let ((*package* (find-package '#:lisploop2))) (read-from-string text)))

(defun term-leaves (sexp) (if (consp sexp) (reduce #'+ (mapcar #'term-leaves (rest sexp))) 1))

(defstruct run bank book ledger seconds)

(defun enumerate-run (variable-count op-names literals max-size &key skip)
  "Enumerate the bank to MAX-SIZE nodes, keeping every collision. SKIP, when given, is a function
of the law book that returns the bank's candidate-skipping hook."
  (let* ((bank (field-bank variable-count op-names literals))
         (book (collect-laws bank :grade :certified :every t))
         (ledger (make-ledger)) (t0 (get-internal-real-time)))
    (when skip (setf (bank-skip-candidate bank) (funcall skip book)))
    (enumerate bank max-size ledger most-positive-fixnum)
    (make-run :bank bank :book book :ledger ledger :seconds (seconds-since t0))))

(defun check-equations (run equations)
  "For each (lhs rhs) of EQUATIONS: do both sides fall in one class of the store, and do the
store's collision equations alone give them one normal form? Returns the two counts."
  (let ((same 0) (implied 0) (table (law-book-table (run-book run))))
    (loop for (l r) in equations
          do (let ((lhs (gf3-term l)) (rhs (gf3-term r)))
               (let ((a (term-class (run-bank run) lhs)) (b (term-class (run-bank run) rhs)))
                 (when (and a (eq a b)) (incf same)))
               (when (eq (normal-form lhs table) (normal-form rhs table)) (incf implied))))
    (values same implied)))

(defun check-partition (run class-lines)
  "CLASS-LINES give, for each baseline class, its members. Returns the number of baseline classes
whose members all fall in one class of the store, and whether distinct baseline classes fall in
distinct classes of the store."
  (let ((whole 0) (seen '()) (distinct t))
    (dolist (members class-lines)
      (let ((classes (remove-duplicates (mapcar (lambda (m) (term-class (run-bank run) (gf3-term m))) members))))
        (when (and (= 1 (length classes)) (first classes))
          (incf whole)
          (when (member (first classes) seen) (setf distinct nil))
          (push (first classes) seen))))
    (values whole distinct)))

(defun class-members (line) ; the last field of a line of x1-classes.txt: the members, as one list
  (read-sexp (format nil "(~a)" (car (last (split-tabs line))))))

;;; ---------------------------------------------------------------------------------------------

(format t "Gate X1: classes, and laws from collisions, on GF(3)~%")

;;; 1. The 187 equations of the four jobs.
(format t "~%=== 1. The 187 equations ===~%")
(let* ((by-job (mapcar #'split-tabs (read-lines "x1-equations-by-job.txt")))
       (classes (mapcar #'split-tabs (read-lines "x1-classes.txt")))
       (jobs '(("obs1" 1 (+ *) (0 1)) ("obs2" 2 (+ *) ()) ("obs3+" 3 (+) ()) ("obs3*" 3 (*) ())))
       (total 0) (total-same 0) (total-implied 0) (all-partitions t))
  (format t "~7a ~9a ~10a ~10a ~9a ~18a ~9a ~11a ~10a~%" "job" "baseline" "one class" "implied" "classes"
          "baseline classes" "bound" "collisions" "cells")
  (loop for (job variable-count op-names literals) in jobs
        do (let* ((equations (loop for (name text) in by-job when (string= name job)
                                   collect (rest (read-sexp text))))
                  ;; the node bound that covers every term of the job: 2 * leaves - 1
                  (leaves (reduce #'max (mapcar (lambda (e) (max (term-leaves (first e)) (term-leaves (second e))))
                                                equations)))
                  (bound (1- (* 2 leaves)))
                  (run (enumerate-run variable-count op-names literals bound))
                  (job-classes (loop for fields in classes when (string= (first fields) job)
                                     collect (read-sexp (format nil "(~a)" (car (last fields)))))))
             (multiple-value-bind (same implied) (check-equations run equations)
               (multiple-value-bind (whole distinct) (check-partition run job-classes)
                 (incf total (length equations)) (incf total-same same) (incf total-implied implied)
                 (unless (and distinct (= whole (length job-classes))) (setf all-partitions nil))
                 (format t "~7a ~9d ~10d ~10d ~9d ~18a ~9d ~11d ~10:d~%" job (length equations) same implied
                         (bank-size (run-bank run))
                         (format nil "~d of ~d kept whole" whole (length job-classes))
                         bound (law-book-collisions (run-book run)) (ledger-total (run-ledger run)))))))
  (format t "~%of the ~d baseline equations: ~d have both sides in one class of the store; ~d follow from the store's own collision equations~%"
          total total-same total-implied)
  (format t "baseline classes kept whole and apart: ~a~%" (if all-partitions "all" "NOT ALL"))
  (defparameter *part-1* (and (= total 187) (= total-same 187) (= total-implied 187) all-partitions)))

;;; 2. Distributivity: three variables with both operators.
(format t "~%=== 2. Distributivity (x0 x1 x2 with + and *, no literals, four leaves) ===~%")
(let* ((run (enumerate-run 3 '(+ *) '() 7))
       (lhs (gf3-term '(+ (* x0 x1) (* x0 x2)))) (rhs (gf3-term '(* x0 (+ x1 x2))))
       (table (law-book-table (run-book run)))
       (equations (mapcar (lambda (line) (rest (read-sexp line))) (read-lines "x1-dist34.equations.txt")))
       (stated (gethash lhs table)))
  (multiple-value-bind (same implied) (check-equations run equations)
    (format t "the store: ~d classes, ~d collisions, ~:d cells, ~,3f s (baseline: 274 classes, 3,203 equations, 6,831,983 ledger units, 0.075 s)~%"
            (bank-size (run-bank run)) (law-book-collisions (run-book run))
            (ledger-total (run-ledger run)) (run-seconds run))
    (format t "the baseline's ~d equations at this bound: ~d have both sides in one class; ~d follow from the store's collisions~%"
            (length equations) same implied)
    (format t "distributivity: one class ~a; stated by the store as a collision: ~a; certified on all 27 assignments: ~a~%"
            (let ((a (term-class (run-bank run) lhs))) (and a (eq a (term-class (run-bank run) rhs)) t))
            (if stated (format nil "~a = ~a" lhs stated) "no")
            (certify-equation lhs rhs))
    (format t "laws kept after dropping instances of earlier laws: ~d of ~d collisions~%"
            (length (law-book-laws (run-book run))) (law-book-collisions (run-book run)))
    (defparameter *part-2* (and (= same (length equations)) (= implied (length equations))
                                (eq :certified (certify-equation lhs rhs))
                                (= 274 (bank-size (run-bank run)))))))

;;; 3. Work at the same bound. The baseline's three columns are from ../baselines/x1/REPORT.md, section 4.5.
(format t "~%=== 3. Work at the same bound ===~%")
(format t "A cell is one operator applied on one row. The present kernel's ledger charges 22 to 33 units for each.~%")
(format t "~28a ~13a ~13a ~13a ~10a ~10a | ~9a ~9a ~9a~%" "grammar and bound" "v1 ledger" "v1 op x rows"
        "v1 trees x r" "store cand" "store cells" "ledger" "op x rows" "trees")
(defparameter *work-rows* '())
(loop for (label variable-count op-names literals bound ledger applications trees)
        in '(("x0 x1 x2, +, 3 leaves" 3 (+) () 5 102113 3159 1701)
             ("x0 x1 x2, +, 4 leaves" 3 (+) () 7 909310 35964 12636)
             ("x0 x1 x2, +, 5 leaves" 3 (+) () 9 8947503 403380 104490)
             ("x0 x1 x2, *, 5 leaves" 3 (*) () 9 8947503 403380 104490)
             ("x0 x1 x2, + *, 3 leaves" 3 (+ *) () 5 376299 12150 6318)
             ("x0 x1 x2, + *, 4 leaves" 3 (+ *) () 7 6831983 274590 93798)
             ("x0 x1 x2, + *, 5 leaves" 3 (+ *) () 9 135437377 6153246 1563462))
      do (let* ((run (enumerate-run variable-count op-names literals bound))
                (cells (ledger-total (run-ledger run))))
           (push (list label ledger applications trees cells) *work-rows*)
           (format t "~28a ~13:d ~13:d ~13:d ~10:d ~10:d | ~8,1fx ~8,1fx ~8,1fx~%" label ledger applications trees
                   (bank-candidates (run-bank run)) cells
                   (/ ledger cells) (/ applications cells) (/ trees cells))))
(format t "~%Reading 1 (the kernel's own ledger): passed everywhere, by the change of unit alone.~%")
(format t "Reading 2 (operator applications on rows, like for like): what classes and shared sub-terms save.~%")
(format t "Reading 3 (one column for each tree): what classes alone save over an enumerator that already evaluates by column.~%")

;;; 4. Memory.
(format t "~%=== 4. What is kept ===~%")
(dolist (bound '(7 9))
  (sb-ext:gc :full t)
  (let* ((before (sb-kernel:dynamic-usage))
         (terms-before *term-count*)
         (bank (field-bank 3 '(+ *) '()))
         (ledger (make-ledger)))
    (enumerate bank bound ledger most-positive-fixnum)
    (sb-ext:gc :full t)
    (let ((bytes (- (sb-kernel:dynamic-usage) before)))
      (declare (ignorable terms-before))
      (format t "x0 x1 x2, + *, ~d leaves: ~:d candidates evaluated; ~:d classes kept, each with one column and one term; ~:d bytes, ~d for each class. Baseline: ~a~%"
              (/ (1+ bound) 2) (bank-candidates bank) (bank-size bank)
              bytes (round bytes (bank-size bank))
              (if (= bound 7) "3,477 trees kept, 2.85 MB" "57,909 trees kept, 47.9 MB"))
      (setf bank nil))))

;;; 5. Pruning by laws already found, on top of classes.
(format t "~%=== 5. What pruning by laws already found adds on top of classes ===~%")
(format t "A candidate is skipped, before it is evaluated, when a law already kept rewrites it at the root.~%")
(format t "Times are the best of five runs. The baseline's operator applications on rows are given where it was run.~%")
(defparameter *pruned-rows* '())
(flet ((best-of (thunk)
         (let ((best nil) (result nil))
           (dotimes (k 5 (values result best))
             (let ((run (funcall thunk)))
               (when (or (null best) (< (run-seconds run) best))
                 (setf best (run-seconds run) result run)))))))
  (loop for (bound applications) in '((7 274590) (9 6153246) (11 nil))
        do (multiple-value-bind (plain plain-seconds)
               (best-of (lambda () (enumerate-run 3 '(+ *) '() bound)))
             (multiple-value-bind (pruned pruned-seconds)
                 (best-of (lambda ()
                            (enumerate-run 3 '(+ *) '() bound
                                           :skip (lambda (book)
                                                   (lambda (op args)
                                                     (rewrite-at-root (app-op op (mapcar #'cls-term args))
                                                                      (law-book-rules book)))))))
               (let ((same-classes (and (= (bank-size (run-bank plain)) (bank-size (run-bank pruned)))
                                        (every (lambda (c) (lookup (run-bank pruned) (cls-col c)))
                                               (bank-all (run-bank plain))))))
                 (push (list bound applications (ledger-total (run-ledger plain))
                             (ledger-total (run-ledger pruned)) same-classes)
                       *pruned-rows*)
                 (format t "~d leaves: classes alone ~:d candidates, ~:d cells, ~,4f s. With pruning ~:d evaluated and ~:d skipped, ~:d cells, ~,4f s, ~d laws kept. Same classes: ~a. Cells ~,1fx fewer; time ~,2fx.~@[ Against the baseline, like for like: ~,1fx.~]~%"
                         (/ (1+ bound) 2) (bank-candidates (run-bank plain)) (ledger-total (run-ledger plain))
                         plain-seconds
                         (bank-candidates (run-bank pruned)) (bank-pruned (run-bank pruned))
                         (ledger-total (run-ledger pruned)) pruned-seconds
                         (length (law-book-laws (run-book pruned)))
                         (if same-classes "yes" "NO")
                         (/ (ledger-total (run-ledger plain)) (max 1 (ledger-total (run-ledger pruned))))
                         (/ plain-seconds (max 1e-6 pruned-seconds))
                         (and applications (/ applications (max 1 (ledger-total (run-ledger pruned)))))))))))

(format t "~%GATE X1~%")
(format t "  the 187 equations: ~:[NOT all~;all~] in the store's classes and implied by its collision equations~%" *part-1*)
(format t "  distributivity: ~:[NOT found~;found and certified, with the baseline's 274 classes at that bound~]~%" *part-2*)
(format t "  10x less work at the same bound:~%")
(dolist (row (reverse *work-rows*))
  (destructuring-bind (label ledger applications trees cells) row
    (format t "     ~28a ~7,1fx by the ledger, ~6,1fx like for like, ~5,1fx against one column for each tree~%"
            label (/ ledger cells) (/ applications cells) (/ trees cells))))
(format t "  memory: one column and one term for each class; candidates that collide are not kept~%")
(format t "  pruning by laws already found, on top of classes: ~{~a~^; ~}~%"
        (loop for (bound applications plain pruned same) in (reverse *pruned-rows*)
              collect (format nil "~d leaves ~,1fx fewer cells~:[ (CLASSES LOST)~;~]" (/ (1+ bound) 2)
                              (/ plain (max 1 pruned)) same)))
