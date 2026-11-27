;;;; analyze-rows.lisp -- what the rows of the sixteen specs do and do not determine.
;;;; For each spec (rows and reference definition taken from boot-specs.sexp, the dump of the real bootstrap):
;;;;   1. the reference definition reproduces every spec row and all 200 held-out rows in the kernel VM;
;;;;   2. per-parameter statistics: distinct values, constant or not, sequence lengths, integer ranges,
;;;;      which code values occur and how often;
;;;;   3. "droppable": is the output a function of the OTHER parameters on these rows?
;;;;   4. trace closure: with the function replaced by an oracle table of its own rows (what the kernel's
;;;;      recursion search does, decompose.lisp:781-785), does the reference body evaluate on every row?
;;;;      A row that needs a self-call whose arguments are not a row comes back :unresolved.
;;;;   5. for the four specs with a function argument, mutants of the reference (the argument replaced by a
;;;;      fixed operator, its arguments swapped, the fold direction reversed): which mutants fit every row,
;;;;      and how each scores on the 200 held-out rows and on the harness's one hand-written input.

(load (merge-pathnames "x3-common.lisp" (make-pathname :name nil :type nil :defaults *load-truename*)))
(in-package #:lisploop)

(defparameter *boot* (read-boot-specs))
(defparameter *heldout*
  (let ((tab (make-hash-table :test 'eq)))
    (dolist (form (read-plain-file (merge-pathnames "x3-heldout.lisp" cl-user::*x3-work*)) tab)
      (setf (gethash (intern (symbol-name (getf form :name)) :keyword) tab) (getf form :rows)))))

(defun rec (id) (find id *boot* :key (lambda (r) (getf r :id))))
(defun rec-rows (r)
  "Decoded rows ((values...) expected) of record R."
  (loop for (enc-known enc-exp) in (getf r :rows)
        collect (list (mapcar (lambda (s) (ast-value (sexp->ast s))) enc-known)
                      (ast-value (sexp->ast enc-exp)))))

(defun define-reference (r)
  (let ((id (getf r :id)) (expr (getf r :expression)))
    (define-function id (getf r :inputs) (getf r :target)
      (lambda (self) (declare (ignore self)) (sexp->ast expr)))))

(defun call-value (id inputs values &optional (budget 1000000))
  "(status value) of function ID on VALUES."
  (let* ((call (apply #'app (op id) (loop for v in values for (nil . ty) in inputs collect (lit ty v))))
         (run (evaluate call nil nil :budget budget)))
    (list (evaluation-status run) (evaluation-value run) (evaluation-error run))))

(defun fits-rows (id inputs rows)
  (count-if (lambda (row) (destructuring-bind (st val err) (call-value id inputs (first row))
                            (declare (ignore err))
                            (and (eq st :value) (equal val (second row)))))
            rows))

(defvar *out-of-budget* 0 "Held-out rows of the last `fits-heldout` whose evaluation ran out of work.")
(defun fits-heldout (id inputs &optional (budget 1000000))
  "How many of the 200 held-out rows function ID gets right, each evaluation given BUDGET work units."
  (setf *out-of-budget* 0)
  (count-if (lambda (row)
              (destructuring-bind (st val err)
                  (call-value id inputs (loop for a in (first row) for (nil . ty) in inputs
                                              collect (unplain-value a ty))
                              budget)
                (declare (ignore err))
                (when (eq st :unknown) (incf *out-of-budget*))
                (and (eq st :value) (equal val (second row)))))
            (gethash id *heldout*)))

(defun fits-one-input (id inputs)
  (every (lambda (tc) (destructuring-bind (st val err) (call-value id inputs (first tc) 20000)
                        (declare (ignore err))
                        (and (eq st :value) (equal val (second tc)))))
         (held-out-test-cases id)))

(defun param-stats (inputs rows)
  (loop for (pid . ty) in inputs for pos from 0
        for vals = (mapcar (lambda (row) (nth pos (first row))) rows)
        for distinct = (remove-duplicates vals :test #'equal)
        collect
        (append
         (list :param (psym "X~D" pid) :type ty :distinct (length distinct) :constant (= 1 (length distinct)))
         (cond ((seq-type-p ty)
                (let ((lens (mapcar #'length vals)) (elems (reduce #'append vals)))
                  (list :lengths (sort (remove-duplicates lens) #'<)
                        :length-histogram (loop for l in (sort (remove-duplicates lens) #'<)
                                                collect (list l (count l lens)))
                        :element-range (and elems (list (reduce #'min elems) (reduce #'max elems)))
                        :distinct-elements (length (remove-duplicates elems)))))
               ((eq ty :int) (list :range (list (reduce #'min vals) (reduce #'max vals))
                                   :values (sort (copy-list distinct) #'<)))
               ((code-type-p ty)
                (list :code-values (loop for d in distinct
                                         collect (list (plain-code d ty) (count d vals :test #'equal)))))))))

(defun droppable (inputs rows)
  "Parameters P such that the rows are consistent with a function that ignores P."
  (loop for (pid) in inputs for pos from 0
        when (let ((tab (make-hash-table :test 'equal)) (ok t))
               (dolist (row rows ok)
                 (let* ((key (loop for v in (first row) for i from 0 unless (= i pos) collect v))
                        (seen (gethash key tab :none)))
                   (cond ((eq seen :none) (setf (gethash key tab) (second row)))
                         ((not (equal seen (second row))) (setf ok nil))))))
          collect (psym "X~D" pid)))

(defun trace-closure (r rows)
  "Evaluate the reference body on each row with the function itself answered from the table of rows."
  (let* ((id (getf r :id)) (inputs (getf r :inputs)) (target (getf r :target))
         (body (sexp->ast (getf r :expression)))
         (table (loop for (known expected) in rows collect (cons known expected)))
         (self-recursive (expression-calls-operator-p body id))
         (open nil) (closed 0))
    (when self-recursive
      (define-function id inputs target nil :oracle-table (remove-duplicates table :test #'equal :key #'car))
      (dolist (row rows)
        (let ((run (evaluate body inputs (first row) :budget 100000)))
          (if (and (eq :value (evaluation-status run)) (equal (second row) (evaluation-value run)))
              (incf closed)
              (push (list (plain-args (first row) inputs) (evaluation-status run)
                          (remove #\Newline (or (evaluation-error run) "")))
                    open))))
      (define-reference r))
    (list :self-recursive (not (null self-recursive)) :rows (length rows) :closed closed
          :open (nreverse open))))

(defun plain-args (values inputs)
  (loop for v in values for (nil . ty) in inputs collect (plain-value v ty)))

;;; --- mutants of the reference, as plain forms -------------------------------------------------------
(defun plain->ast (form inputs expected)
  "A plain definition (as written by `plain`) back into a kernel AST."
  (labels ((conv (f)
             (cond ((integerp f) f)
                   ((symbolp f) (let ((i (parse-integer (symbol-name f) :start 1))) (var i (cdr (assoc i inputs)))))
                   ((eq (first f) (psym "LIT")) (lit (second f) (unplain-value (third f) (second f))))
                   (t (cons (first f) (mapcar #'conv (rest f)))))))
    (term (conv form) expected)))

(defun rewrite-calls (form param fn)
  "Every (code-eval PARAM a ...) in FORM replaced by (FN a ...)."
  (cond ((atom form) form)
        ((and (eq (first form) (psym "CODE-EVAL")) (eq (second form) param))
         (apply fn (mapcar (lambda (a) (rewrite-calls a param fn)) (cddr form))))
        ((eq (first form) (psym "LIT")) form)
        (t (cons (first form) (mapcar (lambda (a) (rewrite-calls a param fn)) (rest form))))))

(defun mutants (id plain-def)
  (flet ((p (s) (psym s)))
    (let ((bin (lambda (param)
                 (list (list "argument replaced by +" (rewrite-calls plain-def param (lambda (a b) (list (p "+") a b))))
                       (list "argument replaced by -" (rewrite-calls plain-def param (lambda (a b) (list (p "-") a b))))
                       (list "argument replaced by *" (rewrite-calls plain-def param (lambda (a b) (list (p "*") a b))))
                       (list "argument applied with its two inputs swapped"
                             (rewrite-calls plain-def param (lambda (a b) (list (p "CODE-EVAL") param b a))))))))
      (case id
        (:foldl (append (funcall bin (p "X2"))
                        (list (list "fold from the right end: f(foldl(tail), head)"
                                    (read-from-string-x3p
                                     "(if (= x0 (lit (:seq :int) ())) x1 (code-eval x2 (foldl (tail x0) x1 x2) (at x0 0)))"))
                              (list "the kernel's impostor in the gate's regime: foldl(tail) - head"
                                    (read-from-string-x3p
                                     "(if (= x0 (lit (:seq :int) ())) x1 (- (foldl (tail x0) x1 x2) (at x0 0)))")))))
        (:scan (funcall bin (p "X2")))
        (:map-adjacent (funcall bin (p "X1")))
        (:filter (list (list "predicate replaced by (< 0 x)"
                             (rewrite-calls plain-def (p "X1") (lambda (a) (list (p "<") 0 a))))
                       (list "predicate replaced by evenness"
                             (rewrite-calls plain-def (p "X1")
                                            (lambda (a) (list (p "=") (list (p "*") (list (p "/") a 2) 2) a))))
                       (list "predicate replaced by true"
                             (rewrite-calls plain-def (p "X1") (lambda (a) (declare (ignore a)) (list (p "LIT") :bool t))))))
        (:shift-seq
         (list (list "equal to the reference for k >= 0, and written only with operators of the full grammar"
                     (read-from-string-x3p
                      "(if (= x0 (lit (:seq :int) ())) x0 (cons (if (< x1 (length x0)) (at x0 x1) 0) (shift-seq (tail x0) x1)))"))))
        (:best-shift
         (list (list "the reference without its quoted lambda (operators of the full grammar plus seq-corr)"
                     (read-from-string-x3p
                      "(if (= x0 (lit (:seq :int) ())) (tuple 0 x2) (if (< (seq-corr x0 x1) (at (best-shift (tail x0) x1 (+ x2 1)) 0)) (best-shift (tail x0) x1 (+ x2 1)) (tuple (seq-corr x0 x1) x2)))"))
               (list "ties broken the other way (a later shift wins a tie)"
                     (read-from-string-x3p
                      "(if (= x0 (lit (:seq :int) ())) (tuple 0 x2) (if (< (at (best-shift (tail x0) x1 (+ x2 1)) 0) (seq-corr x0 x1)) (tuple (seq-corr x0 x1) x2) (best-shift (tail x0) x1 (+ x2 1))))"))))
        (:argmax-corr
         (list (list "the prototype's impostor (verify-review/logs/r1.log:103), in the kernel's operators"
                     (read-from-string-x3p "(if (= (length x1) 2) (- (length x0) (length x1)) 2)"))))
        (:last-or (list (list "the kernel's impostor in the gate's regime"
                              (read-from-string-x3p
                               "(if (= x0 (lit (:seq :int) ())) x1 (if (= x1 (last-or (tail x0) x1)) (at x0 0) (last-or (tail x0) x1)))"))))))))

(defun read-from-string-x3p (s)
  (let ((*package* (find-package :x3p))) (read-from-string s)))

(defun test-mutant (r rows label plain-form)
  (let* ((id (getf r :id)) (inputs (getf r :inputs)) (target (getf r :target)))
    (define-function id inputs target (lambda (self) (declare (ignore self)) (plain->ast plain-form inputs target)))
    ;; Scored twice: with the harness's evaluation budget of 1,000,000 work per input, and with
    ;; 200,000,000, so that a program that is right but slow is told apart from one that is wrong.
    (prog1 (let* ((h (fits-heldout id inputs)) (h-out *out-of-budget*)
                  (h-big (if (plusp h-out) (fits-heldout id inputs 200000000) h))
                  (h-big-out (if (plusp h-out) *out-of-budget* 0)))
             (list :mutant label :program (emit-string plain-form)
                   :rows-fit (fits-rows id inputs rows) :rows (length rows)
                   :held-out-200 h :held-out-200-out-of-budget h-out
                   :held-out-200-large-budget h-big :held-out-200-large-budget-out-of-budget h-big-out
                   :held-out-1 (fits-one-input id inputs)))
      (define-reference r))))

(let ((*closure-evaluation* nil))
  (with-clean-kernel-state
    (dolist (r *boot*) (define-reference r))
    (with-open-file (out (merge-pathnames "x3-row-analysis.sexp" cl-user::*x3-work*)
                         :direction :output :if-exists :supersede)
      (dolist (id *x3-order*)
        (let* ((r (rec id)) (inputs (getf r :inputs)) (rows (rec-rows r))
               (plain-def (plain (sexp->ast (getf r :expression))))
               (stats (param-stats inputs rows))
               (closure (trace-closure r rows))
               (result (list :id id
                             :reference-fits-rows (fits-rows id inputs rows) :rows (length rows)
                             :reference-fits-held-out-200 (fits-heldout id inputs)
                             :reference-fits-held-out-1 (fits-one-input id inputs)
                             :distinct-outputs (length (remove-duplicates (mapcar #'second rows) :test #'equal))
                             :params stats
                             :droppable (droppable inputs rows)
                             :trace-closure closure
                             :mutants (loop for (label form) in (mutants id plain-def)
                                            collect (test-mutant r rows label form)))))
          (format t "~&~%=== ~(~A~) ===~%" id)
          (format t "reference definition: ~A~%" (emit-string plain-def))
          (format t "reference fits ~D/~D spec rows, ~D/200 held-out rows, harness one-input check ~A~%"
                  (getf result :reference-fits-rows) (length rows)
                  (getf result :reference-fits-held-out-200) (if (getf result :reference-fits-held-out-1) "passes" "FAILS"))
          (format t "rows ~D, distinct outputs ~D~%" (length rows) (getf result :distinct-outputs))
          (dolist (s stats)
            (format t "  ~A : ~A  distinct values ~D~:[~; CONSTANT ACROSS ROWS~]" (emit-string (getf s :param))
                    (emit-string (getf s :type)) (getf s :distinct) (getf s :constant))
            (when (getf s :lengths)
              (format t "; lengths ~A (length:rows ~{~{~D:~D~}~^ ~}); elements ~A, ~D distinct"
                      (getf s :lengths) (getf s :length-histogram) (getf s :element-range) (getf s :distinct-elements)))
            (when (getf s :range) (format t "; values ~A" (getf s :values)))
            (when (getf s :code-values)
              (format t "; ~{~{~A in ~D rows~}~^, ~}"
                      (mapcar (lambda (cv) (list (emit-string (first cv)) (second cv))) (getf s :code-values))))
            (terpri))
          (format t "parameters the rows do not show to matter (output is a function of the others): ~A~%"
                  (if (getf result :droppable) (emit-string (getf result :droppable)) "none"))
          (if (getf closure :self-recursive)
              (progn
                (format t "trace closure: ~D of ~D rows evaluate when self-calls are answered from the rows~%"
                        (getf closure :closed) (getf closure :rows))
                (dolist (o (getf closure :open))
                  (format t "    not closed: ~A -> ~A ~A~%" (emit-string (first o)) (second o) (third o))))
              (format t "trace closure: not applicable (the reference does not call itself)~%"))
          (dolist (m (getf result :mutants))
            (format t "  mutant [~A]: fits ~D/~D rows~:[~; <-- FITS EVERY ROW~]; held-out 200: ~D/200~A; harness one input: ~A~%      ~A~%"
                    (getf m :mutant) (getf m :rows-fit) (getf m :rows) (= (getf m :rows-fit) (getf m :rows))
                    (getf m :held-out-200)
                    (if (plusp (getf m :held-out-200-out-of-budget))
                        (format nil " (~D ran out of the 1,000,000-unit evaluation budget; with 200,000,000 units: ~D/200, ~D out of budget)"
                                (getf m :held-out-200-out-of-budget)
                                (getf m :held-out-200-large-budget)
                                (getf m :held-out-200-large-budget-out-of-budget))
                        "")
                    (if (getf m :held-out-1) "passes" "fails") (getf m :program)))
          (let ((*package* (find-package :lisploop))) (format out "~S~%" result)))))))
