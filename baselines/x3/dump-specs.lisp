;;;; dump-specs.lisp -- write x3-specs.lisp: the sixteen function specs of the bootstrap as plain data.
;;;; Source of every field: boot-specs.sexp, the dump made by the real bootstrap run in a copy
;;;; (run-boot.sh), cross-checked here against the harness's own copy of the specs and against the
;;;; library files.  The notes are written by hand from logs/analyze-rows.log and the harness logs.

(load (merge-pathnames "x3-common.lisp" (make-pathname :name nil :type nil :defaults *load-truename*)))
(in-package #:lisploop)

(defparameter *boot* (read-boot-specs))
(defparameter *items* (collect-bootstrap-function-specs))
(defparameter *analysis*
  (with-open-file (in (merge-pathnames "x3-row-analysis.sexp" cl-user::*x3-work*))
    (let ((*package* (find-package :lisploop)))
      (loop for form = (read in nil :eof) until (eq form :eof) collect form))))

(defparameter *source-lines*   ; v2/bootstrap/build-batteries.lisp (v1/bootstrap/build-batteries.lisp is identical)
  '((:copy "563") (:inc-all "564") (:dbl-all "565") (:sum-all "566") (:len-all "567") (:prd-all "568")
    (:foldl "609-625") (:filter "626-641") (:map-adjacent "642-658") (:positions "659-674")
    (:scan "786-803") (:shift-seq "834-849") (:seq-corr "851-863") (:best-shift "865-877")
    (:argmax-corr "879-889") (:last-or "891-900")))

(defparameter *schema-notes*   ; [D] plan_v2c_audit/reports/bootstrap-reflection.md, sections 2 and 4.1
  '((:copy "none needed: found without the schemas")
    (:inc-all "none needed: found without the schemas")
    (:dbl-all "none needed: found without the schemas")
    (:sum-all "none needed: found without the schemas")
    (:len-all "none needed: found without the schemas")
    (:prd-all "none needed: found without the schemas")
    (:foldl "state fold: (if (= xs ()) s (self (tail xs) Z ...)); without it the kernel returns an impostor")
    (:filter "none needed: found without the schemas")
    (:map-adjacent "lookahead: (if (= xs ()) base0 (if (= (tail xs) ()) base1 Z)); not found without it")
    (:positions "counter: (if (= xs ()) base Z) with self(tail xs, k+1) in scope; not found without it")
    (:scan "state scan: (if (= xs ()) () (cons Z (self (tail xs) Z ...))); not found without it")
    (:shift-seq "countdown: (if (= xs ()) base (if (< 0 k) Z base')) with self(tail xs, k-1) in scope; not found without it")
    (:seq-corr "none needed: the kernel's own lockstep recursion finds it")
    (:best-shift "counter, with (seq-corr xs ys) and the tuple projections of the recursive result put in scope; not found without it")
    (:argmax-corr "none: a non-recursive job, for which the schema expander returns nothing")
    (:last-or "lookahead: (if (= xs ()) base0 (if (= (tail xs) ()) base1 Z)); without it the kernel returns a program that fits the rows and passes the harness's one held-out input but is right on only 192 of the 200 held-out inputs")))

(defparameter *notes*
  '((:copy "Seed corpus. Not stored in any battery; the definition is the program the bootstrap's seed synthesis returns. The rows are the four suffixes of (4 1 3).")
    (:inc-all "Seed corpus. Not stored in any battery. The rows are the four suffixes of (4 1 3); the elements are 1, 3 and 4 only.")
    (:dbl-all "Seed corpus. Not stored in any battery. The definition doubles by adding an element to itself, although the whitelist offers * and the literal 2.")
    (:sum-all "Seed corpus. Not stored in any battery. The rows are the four suffixes of (4 2 3).")
    (:len-all "Seed corpus. Not stored in any battery. The output does not depend on the elements.")
    (:prd-all "Seed corpus. Not stored in any battery. The product of the empty sequence is 1.")
    (:foldl "Left fold: f(...f(f(x1, e0), e1)..., en). UNDERDETERMINED BY ITS ROWS: the function argument x2 is the same code value, (- x0 x1), in all nine rows. A program that ignores x2 and subtracts fits every row, and so does a fold from the right end. The rows are the call trace of a left fold with subtraction: the second argument steps 12, 11, 9, 6.")
    (:filter "Keeps the elements for which the predicate x1 holds, in order. The predicate is (< 0 x0) in four rows and the evenness test (= (* (/ x0 2) 2) x0) in three. The definition returns x0 itself, not a literal (), in the empty case.")
    (:map-adjacent "One output per adjacent pair: f(e[i+1], e[i]), the later element first. The function argument is (- x0 x1) in four rows and (+ x0 x1) in four. No row has a sequence longer than 3, so at most two outputs per row.")
    (:positions "The index list x1, x1+1, ... as long as x0; the elements of x0 do not matter. This is not 'positions of a value'. Every recursive call the definition makes on these rows is itself a row (the bootstrap's comment at build-batteries.lisp:659-661 says so).")
    (:scan "Running fold: the outputs are f(x1, e0), f(f(x1, e0), e1), ... The function argument is (+ x0 x1) in six rows, three of them with an empty sequence, and (- x0 x1) in three, one of them empty. The rows are the call trace of the definition.")
    (:shift-seq "Shift left by x1 with zero fill, same length as x0. For x1 <= 0 the definition returns x0 unchanged. x1 is 0, 1 or 2 in the rows and never negative. The definition appends a zero with (concat (cons <seq> ((0)))), which needs cons at element type (:seq :int) and the author-supplied constant ((0)); the full grammar keeps the constant and lacks that cons. An equivalent for x1 >= 0 exists in the full grammar: (if (= x0 ()) x0 (cons (if (< x1 (length x0)) (at x0 x1) 0) (shift-seq (tail x0) x1))).")
    (:seq-corr "Sum of the products e[i]*f[i] over the common prefix of the two sequences. Three rows have sequences of unequal length.")
    (:best-shift "Returns the tuple (best correlation, shift): the largest seq-corr of a suffix of x0 with x1, shifts counted from x2, the empty suffix scoring 0; an earlier shift wins a tie. x1 is (4 1) in six rows and (5 0) in three, always of length 2. No row has a tie or a negative correlation: the variant in which a later shift wins a tie fits all nine rows. The definition applies a quoted three-argument lambda with code-eval. Needs seq-corr.")
    (:argmax-corr "Three rows. The shift of x0 that best matches x1: (at (best-shift x0 x1 0) 1). Not recursive. Needs best-shift and, through it, seq-corr. The full grammar has no tuple accessor for this spec, because no tuple type occurs in its signature, so this definition cannot be written in it.")
    (:last-or "The last element of x0, or the default x1 when x0 is empty. x1 is 7, 9 or 2. In the bootstrap this entry exists only to serve the guard of a solver, and no other entry calls it. In the gate's regime the present kernel returns a program that fits all seven rows and is wrong when the last element of a longer sequence equals the default.")))

(defun item (id) (find id *items* :key (lambda (it) (getf it :id))))
(defun rec (id) (find id *boot* :key (lambda (r) (getf r :id))))
(defun ana (id) (find id *analysis* :key (lambda (r) (getf r :id))))

(defun decoded-rows (r)
  (loop for (enc-known enc-exp) in (getf r :rows)
        collect (list (mapcar (lambda (s) (ast-value (sexp->ast s))) enc-known)
                      (ast-value (sexp->ast enc-exp)))))

(defun plain-rows (r)
  (let ((inputs (getf r :inputs)) (target (getf r :target)))
    (loop for (known expected) in (decoded-rows r)
          collect (list (loop for v in known for (nil . ty) in inputs collect (plain-value v ty))
                        (plain-value expected target)))))

(defun op-name-plain (o) (psym "~A" (symbol-name (second o))))

(defun write-spec (out id)
  (let* ((r (rec id)) (it (item id)) (a (ana id))
         (inputs (getf r :inputs)) (target (getf r :target))
         (meta (getf r :spec-metadata))
         (rows (plain-rows r))
         (seed (eq :seed-corpus (getf it :battery)))
         (closure (getf a :trace-closure))
         (keys (getf r :keys)))
    ;; with a self-reference defined, so that the definition can be rebuilt and printed readably
    (with-clean-kernel-state
      (dolist (b *boot*)
        (define-function (getf b :id) (getf b :inputs) (getf b :target)
          (let ((e (getf b :expression))) (lambda (self) (declare (ignore self)) (sexp->ast e)))))
      (flet ((field (key value &optional raw)
               (format out "~% ~(~S~) " key)
               (if raw (write-string value out) (emit value out))))
        (format out "~%(:name ~(~A~)" id)
        (field :params (loop for (pid . ty) in inputs collect (list (psym "X~D" pid) ty)))
        (field :returns target)
        (format out "~% :rows (")
        (dolist (row rows) (format out "~%   ") (emit row out))
        (format out ")")
        (field :definition (getf r :expression))
        (field :definition-readable (plain (sexp->ast (getf r :expression))))
        (field :definition-source
               (if seed
                   "not stored in any battery; this is the program the bootstrap's seed synthesis returns, dumped from a run of the bootstrap in a copy (boot-specs.sexp)"
                   (format nil "v2/library/~(~A~).sexp, entry ~S, :EXPRESSION; the bootstrap run in a copy regenerates it identically"
                           (getf it :battery) id)))
        (field :definition-bits (getf r :bits))
        (field :bootstrap-work (getf r :work))
        (field :spec-id (psym "~A" (symbol-name (getf r :spec-id))))
        (field :spec-source
               (format nil "v2/bootstrap/build-batteries.lisp:~A~:[; stored as ~S in v2/library/~(~A~).sexp~;; not stored in any battery~]"
                       (second (assoc id *source-lines*)) seed (getf r :spec-id) (getf it :battery)))
        (field :battery (if seed (psym "SEED-CORPUS") (psym "~A" (symbol-name (getf it :battery)))))
        (field :function-arguments
               (loop for s in (getf a :params)
                     when (getf s :code-values)
                       collect (list (getf s :param)
                                     (loop for (cv n) in (getf s :code-values) collect (list cv :rows n)))))
        (field :whitelist (getf meta :operators))
        (field :whitelist-readable
               (loop for o in (getf meta :operators)
                     collect (if (member (second o) +operator-names+)
                                 (list (op-name-plain o) (third o))     ; a primitive, at this type
                                 (op-name-plain o))))                   ; a library function
        (field :literals (getf meta :literals))
        (field :constants (getf meta :constants))
        (field :bootstrap-settings
               (list :bound (or (getf keys :bound) 130) :budget (or (getf keys :budget) 350000)
                     :heuristic-budget 15000 :max-depth 2
                     :recursive (if (eq nil (getf keys :recursive-p t)) (psym "NO") (psym "YES"))
                     :schemas-offered (psym "ALL-FIVE")))
        (field :schema-used (second (assoc id *schema-notes*)))
        (field :library-in-bootstrap-before
               (loop for f in (getf r :functions-in-library-before) collect (psym "~A" (symbol-name f))))
        (field :calls-library-functions
               (let ((names nil))
                 (labels ((walk (x)
                            ;; an operator node is (:op NAME TYPE); do not descend into its type
                            (cond ((atom x) nil)
                                  ((eq :op (first x))
                                   (unless (or (eq id (second x)) (member (second x) +operator-names+))
                                     (pushnew (second x) names)))
                                  ((member (first x) '(:var)) nil)
                                  ((eq :lit (first x))
                                   (when (and (consp (second x)) (eq :code (first (second x))))
                                     (walk (third x))))
                                  ((eq :app (first x)) (mapc #'walk (rest x))))))
                   (walk (getf r :expression)))
                 (loop for n in (nreverse names) collect (psym "~A" (symbol-name n)))))
        (field :trace-closed-rows
               (if (getf closure :self-recursive)
                   (list (getf closure :closed) :of (getf closure :rows)
                         :not-closed (mapcar #'first (getf closure :open)))
                   (psym "NOT-RECURSIVE")))
        (field :harness-held-out-case
               (let ((tc (first (held-out-test-cases id))))
                 (list (loop for v in (first tc) for (nil . ty) in inputs collect (plain-value v ty))
                       (plain-value (second tc) target))))
        (field :notes (second (assoc id *notes*)))
        (format out ")~%")))
    ;; checks
    (let ((back (loop for (args expected) in rows
                      collect (list (loop for v in args for (nil . ty) in inputs collect (unplain-value v ty))
                                    (unplain-value expected target)))))
      (assert (equal back (decoded-rows r)) () "round trip of the rows of ~S failed" id)
      (assert (equal (getf r :rows) (knowledge-entry-residual (getf it :spec))) ()
              "bootstrap rows and harness rows differ for ~S" id))
    (length rows)))

(let ((path (merge-pathnames "x3-specs.lisp" cl-user::*x3-work*)) (total 0))
  (with-open-file (out path :direction :output :if-exists :supersede)
    (format out ";;;; x3-specs.lisp -- the sixteen function specs behind gate X3 (plan_v2c.md 11.2), as plain data.~%")
    (format out ";;;; Written by base-x3/dump-specs.lisp from boot-specs.sexp, the dump of the real bootstrap~%")
    (format out ";;;; (v2/bootstrap/build-batteries.lisp) run in a copy.  One form per spec, in bootstrap order.~%")
    (format out ";;;; Readable with READ in any package: integers, lists, strings, keywords and plain symbols only.~%")
    (format out ";;;;~%")
    (format out ";;;; Types are the kernel's: :int, :bool, (:seq T), (:tuple T1 T2), and (:code ((0 . T0) (1 . T1)) T)~%")
    (format out ";;;;   for quoted code with parameters 0, 1 of types T0, T1 and result type T.  (0 :seq :int) is the~%")
    (format out ";;;;   dotted pair (0 . (:seq :int)) as Lisp prints it.~%")
    (format out ";;;; :params      ((x0 TYPE) (x1 TYPE) ...), the kernel's variables 0, 1, ...~%")
    (format out ";;;; :rows        (((arg0 arg1 ...) expected) ...), in the order of the bootstrap.~%")
    (format out ";;;;   A sequence is a list of integers and () is the empty sequence.  A tuple is a list.  Booleans are~%")
    (format out ";;;;   t and nil in the kernel; no parameter or result of these specs is a Boolean.  In Lisp nil and ()~%")
    (format out ";;;;   are one object, so only the declared type tells false from the empty sequence.~%")
    (format out ";;;;   A function or predicate argument is the kernel's quoted code term, written here~%")
    (format out ";;;;   (code (x0 x1) BODY): BODY is an expression over the code's own parameters and nothing else.~%")
    (format out ";;;; :definition  the library's definition in the kernel's portable typed form, as stored in~%")
    (format out ";;;;   v2/library/*.sexp: (:app OP ARG...), (:op NAME TYPE), (:var N TYPE), (:lit TYPE VALUE).~%")
    (format out ";;;; :definition-readable  the same with types dropped: x0 x1 for variables, bare integers,~%")
    (format out ";;;;   (lit TYPE VALUE) for any other literal, (code (params) body) for a quoted code literal.~%")
    (format out ";;;; :whitelist   the operators the bootstrap's author allows for this spec; :literals and :constants~%")
    (format out ";;;;   likewise.  Gate X3 ignores the whitelist.  The Stage 0 harness keeps :constants in every regime.~%")
    (format out ";;;; :trace-closed-rows  (N :of M ...): on N of the M rows the definition evaluates when its own~%")
    (format out ";;;;   recursive calls are answered only from the table of rows (logs/analyze-rows.log).~%")
    (format out ";;;; :harness-held-out-case  the one hand-written input of v2/experiments/stage0-audit.lisp:59-84.~%")
    (dolist (id *x3-order*) (incf total (write-spec out id))))
  ;; read the file back with nothing but the scratch package and compare the rows again
  (let ((forms (read-plain-file path)))
    (assert (= 16 (length forms)))
    (loop for form in forms for id in *x3-order*
          for r = (rec id)
          do (assert (eq (getf form :name) (psym "~A" (symbol-name id))))
             (assert (equal (getf form :rows) (plain-rows r)) () "rows read back differ for ~S" id)
             (assert (equal (getf form :definition) (getf r :expression)) () "definition read back differs for ~S" id))
    (format t "~&wrote ~A: 16 specs, ~D rows; read back and compared: rows and definitions identical~%"
            (namestring path) total)))
