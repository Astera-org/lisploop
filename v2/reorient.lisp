(in-package #:lisploop2)

;;; Reorientation: finding inverses and their guards from a table.
;;;
;;; Take c = t(u, k), a term in an unknown u and known variables k, and ask for u given k and c
;;; (plan sections 5.3, 7.2, 8.2). The simplest t is one operator, c = op(u, k).
;;;
;;;   1. The table. A space with one row for each combination of values on which t is defined,
;;;      and a column for each variable and for the result.
;;;   2. The dependency test. One group-by on the known columns and the result says on which
;;;      rows the unknown is determined. That is uniqueness, and it is read off the table.
;;;   3. The answer. On the sub-space of the rows where the unknown is determined, a term over
;;;      the known columns and the result that denotes the unknown. This is ordinary enumeration
;;;      by class with an exact target, over the operators in scope. No language of answers is
;;;      supplied.
;;;   4. The guard needs no search. The answer is a solution exactly where, replayed forward
;;;      through t, it gives the result back. That replay is the solver's guard.
;;;   5. The uniqueness guard. On the whole table, a Boolean term that denotes the mask of
;;;      step 2. Where it holds as well, the answer is the only solution.
;;;
;;; A finite table creates false dependencies at its boundary: a value of the unknown can look
;;; unique only because its rivals lie outside the range. So the range of the unknown used to
;;; judge uniqueness may be wider than the range of the rows that are solved on.

(defstruct solver
  term unknown                  ; c = TERM, to be solved for the variable UNKNOWN
  result                        ; the variable that stands for c
  share                         ; the share of table rows on which the unknown is determined
  answer                        ; a term over the known variables and the result, or nil
  guard                         ; the replay guard: where it holds, ANSWER is a solution
  unique-guard                  ; a term for the mask of the dependency test, TRUE when it holds
                                ; on every row, or nil when no term was found
  grade                         ; :certified, :tested or :observed
  certificate                   ; set by CERTIFY-SOLVER when the solver is sound on its whole domain
  rows work candidates notes)

(defun cartesian-product (lists)
  (if (null lists)
      (list '())
      (loop for v in (first lists)
            append (mapcar (lambda (rest) (cons v rest)) (cartesian-product (rest lists))))))

(defun term-table (term variables ranges)
  "The table of TERM: one row for each combination of values of VARIABLES, drawn from RANGES,
on which TERM has a value. Returns the space, an alist from variable name to column, and the
column of the result."
  (let* ((rows (cartesian-product ranges))
         (all (make-space (length rows)))
         (leaves (loop for v in variables for k from 0
                       collect (cons (term-head v)
                                     (map 'simple-vector (lambda (row) (nth k row)) rows))))
         (value (term-column term all leaves))
         (defined (subspace all (map 'simple-vector (lambda (c) (not (status-p c))) value)
                            :name (list :table term))))
    (values defined
            (loop for (name . column) in leaves collect (cons name (reindex defined column)))
            (reindex defined value))))

(defun find-column (bank target type max-size ledger budget)
  "Enumerate BANK until a class of TYPE has the column TARGET. Returns the class or nil. The
check is one hash probe per new class."
  (let ((hash (col-hash target)))
    (flet ((hit (c) (and (equal type (cls-type c)) (col= (cls-col c) target) c)))
      (or (let ((c (lookup bank target hash))) (and c (hit c)))
          (progn
            (setf (bank-on-new bank) #'hit)
            (let ((result (enumerate bank max-size ledger budget)))
              (setf (bank-on-new bank) nil)
              (and (cls-p result) result)))))))

(defun replay-guard (term unknown answer result)
  "The guard of a solver: ANSWER, put in place of UNKNOWN in TERM, gives RESULT. A replay that
fails counts as false."
  (app 'try (app '= (substitute-term term (list (cons unknown answer))) result) (false)))

(defun reorient-term (term unknown
                      &key ranges inner op-names constants (result-name 'c) (max-size 9)
                           (ledger (make-ledger)) (budget 5000000))
  "Solve c = TERM for its variable UNKNOWN.

RANGES gives one list of values for each variable of TERM, in the order of TERM-VARIABLES; for
a finite type it defaults to every value. INNER, when given, lists the values of the unknown
that the rows solved on may have; RANGES then gives the wider range used to judge uniqueness.
OP-NAMES are the operators in scope for the answer and the uniqueness guard, and CONSTANTS is
an alist from type to constant values. Returns a SOLVER; its ANSWER is nil when none was found
within MAX-SIZE and BUDGET."
  (let* ((variables (term-variables term))
         (ranges (or ranges (mapcar (lambda (v) (type-values (term-type v))) variables)))
         (result (var result-name (term-type term)))
         (knowns (remove unknown variables))
         (start (ledger-total ledger))
         (notes '()))
    (assert (member unknown variables))
    (assert (not (member result variables)))
    (multiple-value-bind (wide leaves value) (term-table term variables ranges)
      (let ((wide-mask (dependency (cdr (assoc (term-head unknown) leaves))
                                   (append (mapcar (lambda (v) (cdr (assoc (term-head v) leaves)))
                                                   knowns)
                                           (list value))
                                   (space-n wide))))
        (charge ledger :dependency (space-n wide))
        ;; the rows that are solved on: all of them, or those whose unknown lies in INNER
        (let* ((table (if inner
                          (subspace wide (map 'simple-vector
                                              (lambda (u) (and (member u inner :test #'cell=) t))
                                              (cdr (assoc (term-head unknown) leaves)))
                                    :name (list :table term))
                          wide))
               (pull (lambda (column) (if inner (reindex table column) column)))
               (leaves (loop for (name . column) in leaves collect (cons name (funcall pull column))))
               (value (funcall pull value))
               (mask (funcall pull wide-mask))
               (share (if (zerop (space-n table)) 0 (/ (count t mask) (space-n table))))
               (solver (make-solver :term term :unknown unknown :result result :share share
                                    :rows (space-n table) :candidates 0)))
          (labels ((left () (max 0 (- budget (- (ledger-total ledger) start))))
                   (fresh-bank (space pull types)
                     ;; a bank over the known variables, the result, and the constants
                     (let ((bank (make-bank space op-names :types types)))
                       (dolist (v knowns)
                         (add-leaf bank v (funcall pull (cdr (assoc (term-head v) leaves)))))
                       (add-leaf bank result (funcall pull value))
                       (loop for (type . values) in constants
                             do (dolist (c values) (add-constant bank c type)))
                       bank)))
            ;; the answer: a term for the unknown, on the rows where it is determined
            (if (zerop share)
                (push "the unknown is determined on no row" notes)
                (let* ((determined (if (= share 1) table (subspace table mask)))
                       (pull2 (if (= share 1) #'identity
                                  (lambda (column) (reindex determined column))))
                       (bank (fresh-bank determined pull2 nil))
                       (class (find-column bank (funcall pull2 (cdr (assoc (term-head unknown) leaves)))
                                           (term-type unknown) max-size ledger (left))))
                  (incf (solver-candidates solver) (bank-candidates bank))
                  (if class
                      (setf (solver-answer solver) (cls-term class)
                            (solver-guard solver) (replay-guard term unknown (cls-term class) result)
                            (solver-grade solver) :observed)
                      (push "no term found for the unknown" notes))))
            ;; the uniqueness guard: a Boolean term for the mask, on the whole table
            (cond ((= share 1) (setf (solver-unique-guard solver) (true)))
                  ((plusp share)
                   (let ((bank (fresh-bank table #'identity '(:bool))))
                     (add-constant bank t :bool) (add-constant bank nil :bool)
                     (let ((class (find-column bank mask :bool max-size ledger (left))))
                       (incf (solver-candidates solver) (bank-candidates bank))
                       (if class
                           (setf (solver-unique-guard solver) (cls-term class))
                           (push "no term found for the uniqueness mask" notes))))))
            (setf (solver-work solver) (- (ledger-total ledger) start)
                  (solver-notes solver) (nreverse notes))
            solver))))))

(defun reorient (name arg-types position &rest keys &key ranges &allow-other-keys)
  "Solve c = NAME(...) for the argument at POSITION. The unknown is called U and the known
arguments K, or K0, K1, ... when there are several. RANGES, when given, lists the values of
each argument in order. The other keys are those of REORIENT-TERM."
  (declare (ignorable ranges))
  (let* ((known-count (1- (length arg-types)))
         (names (let ((k -1))
                  (loop for i below (length arg-types)
                        collect (cond ((= i position) 'u)
                                      ((= known-count 1) 'k)
                                      (t (intern (format nil "K~d" (incf k)) '#:lisploop2))))))
         (variables (mapcar #'var names arg-types)))
    (apply #'reorient-term (apply #'app name variables) (nth position variables) keys)))

(defun check-solver (solver ranges result-values)
  "Check SOLVER on every combination of values of its known variables and of RESULT-VALUES,
against a search for every value of the unknown that gives the result. RANGES lists the values
of each variable of the solver's term, in the order of TERM-VARIABLES; the range of the unknown
is the one searched. Returns a property list:
  :SOUND     wherever the guard holds, the answer gives the result back
  :COMPLETE  the guard holds wherever some value of the unknown gives the result
  :UNIQUE    wherever the guard and the uniqueness guard both hold, one value only does
  :EXACT     the two guards both hold exactly where one value only gives the result
  :COUNTEREXAMPLES  the first failure of each kind, as (kind environment)"
  (let* ((term (solver-term solver)) (unknown (solver-unknown solver))
         (variables (term-variables term))
         (knowns (remove unknown variables))
         (known-ranges (loop for v in variables for range in ranges
                             unless (eq v unknown) collect range))
         (unknown-values (nth (position unknown variables) ranges))
         (result-name (term-head (solver-result solver)))
         (sound t) (complete t) (unique t) (exact t) (counterexamples '()))
    (flet ((note (kind env)
             (unless (assoc kind counterexamples) (push (list kind env) counterexamples))))
      (dolist (known-values (cartesian-product known-ranges))
        (let ((known-env (pairlis (mapcar #'term-head knowns) known-values)))
          (dolist (c result-values)
            (let* ((env (acons result-name c known-env))
                   (guard (eq t (run-term (solver-guard solver) env)))
                   (unique-guard (and (solver-unique-guard solver)
                                      (eq t (run-term (solver-unique-guard solver) env))))
                   (solutions (loop for u in unknown-values
                                    when (cell= c (run-term term (acons (term-head unknown) u known-env)))
                                      collect u))
                   (answer (and guard (run-term (solver-answer solver) env))))
              (when (and guard (not (member answer solutions :test #'cell=)))
                (setf sound nil) (note :unsound env))
              (when (and solutions (not guard))
                (setf complete nil) (note :incomplete env))
              (when (and guard unique-guard (/= 1 (length solutions)))
                (setf unique nil) (note :not-unique env))
              (unless (eq (and guard unique-guard) (= 1 (length solutions)))
                (setf exact nil) (note :not-exact env)))))))
    (list :sound sound :complete complete :unique unique :exact exact
          :counterexamples (nreverse counterexamples))))

(defun certify-solver (solver)
  "Check SOLVER on its whole domain, which must be finite, and grade it :CERTIFIED when it is
sound there. Returns the property list of CHECK-SOLVER."
  (let* ((term (solver-term solver))
         (report (check-solver solver
                               (mapcar (lambda (v) (type-values (term-type v))) (term-variables term))
                               (type-values (term-type term)))))
    (when (getf report :sound)
      (setf (solver-grade solver) :certified
            (solver-certificate solver)
            (apply #'attest :certified :exhaustive
                   (remove nil (list term (solver-answer solver) (solver-guard solver)
                                     (solver-unique-guard solver))))))
    report))
