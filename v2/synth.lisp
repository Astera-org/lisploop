(in-package #:lisploop2)

;;; The synthesizer: one move, "refine a hole with a construct" (plan section 7.2).
;;;
;;; A PROBLEM is a space, a requirement on one hole, and a context (the leaves available on that
;;; space). The requirement is either an exact target, a column the hole's term must denote, or
;;; a check, a function that says whether a class will do.
;;;
;;; A problem is attacked by several ROUTES, one for each row of the refinement table that
;;; applies to the type of its hole:
;;;
;;;   leaf        a term from the context: enumeration by class, with the target found by one
;;;               hash probe. After each completed size it also tries the two rows that need no
;;;               new space: a conditional (IF ?g ?a ?b) built from classes already present, and
;;;               an operator with a known inverse (F k ?z).
;;;   tabulate    (TABULATE ?n (lambda (i) ?e)): ?n on the same space, ?e on the space of the
;;;               output's positions.
;;;   select      (GATHER xs (WHERE (LENGTH xs) (lambda (j) ?keep))): ?keep on the space of the
;;;               input's positions.
;;;   where       (WHERE n (lambda (j) ?keep)), for an output that is a list of positions.
;;;   fold        (FOLD ?init (lambda (acc x) ?step) xs): the accumulator is not observed, so
;;;               each step class is run through the fold and compared.
;;;   aggregate   (g (TABULATE n (lambda (i) ?e))) for a library function g from a sequence to
;;;               a scalar: each element class is collected under g and compared.
;;;   tuple       (TUPLE ?a ?b): one requirement for each slot.
;;;
;;; Before any of these, a requirement is reoriented when the rows support it (section 5.4,
;;; "Reorientation"): if a few cheap columns determine the target, and every group of rows that
;;; agree on them has more than one row, the problem is solved on the space of those groups,
;;; with those columns as its only leaves. A term found there cannot read anything that the
;;; rows show to be irrelevant.
;;;
;;; Control. Every route deepens in steps, and the next step always goes to the route whose
;;; next step is predicted to be cheapest, anywhere under the root. So cheap possibilities are
;;; exhausted before dear ones, with no fixed order of routes and no shares set by hand.
;;;
;;; Acceptance inside a problem has three rules.
;;;
;;; Smallest first. The first term that fits is only HELD. Each route knows a lower bound on the
;;; size of anything it may still find, and the routes that could still find a smaller term go
;;; on. The held term is accepted when none is left, or when confirming it has cost as much
;;; again as finding it did (*CONFIRM-RATIO*).
;;;
;;; The size-order rule. For a conditional the first of those two conditions is the only one:
;;; it is accepted once every term without a conditional that is smaller than it has been ruled
;;; out, however long that takes. While a term is held its size bounds the enumeration, and
;;; operators whose result type cannot reach the hole's type within that bound are not
;;; enumerated. That is the look-ahead of section 7.2, step 4, in its types-only form.
;;;
;;; The evidence rule. A term that fits is held only if naming it is a shorter description of
;;; the target than the best description found without it (section 6.3, rule 4). The term's
;;; description is its place in the order of search: the count of candidates that were compared
;;; with the target before it. The rival description is the target written out cell by cell, or
;;; a small class together with the corrections that turn its column into the target. When the
;;; search has compared so many candidates that a fit would no longer be shorter, the problem is
;;; closed as not determined by its rows: a fit found after that would be expected by chance.

(defvar *grammar* '(+ - * / mod < = try at length tabulate fold scan where call left right)
  "The operators a search may use. IF is not enumerated: conditionals come from the split.")
(defvar *library* '() "Names of the library functions in scope, oldest first.")
(defvar *constants* '((:int 0 1)) "The constants in scope, as an alist from type to values.")
(defvar *solvers* '() "Solvers found by reorientation, for the inverse row.")
(defvar *max-size* 12 "The largest term a bank enumerates.")
(defvar *confirm-ratio* 1
  "A held term that is not a conditional is accepted once the work spent since it was found
reaches this multiple of the work spent to find it.")
(defvar *max-classes* 6000000
  "The most classes that the banks of one task may store. Memory, not time, is what a deep search
runs out of first (plan section 8.4), so a task's banks are bounded like its work.")
(defvar *classes-stored* 0 "Classes stored so far by the banks of the task being solved.")
(defvar *task-problems* '() "Every problem made for the task being solved, most recent first.")
(defvar *use-inverses* t)
(defvar *use-lookahead* t)
(defvar *use-evidence* t)
(defvar *use-projection* t)
(defvar *ledger* nil "The ledger that the routes of the task being solved charge.")
(defvar *task-notes* '() "What the search of the task being solved has to report, most recent first.")
(defvar *alternates* nil
  "While a task is being solved: a table from the smallest term of a class to a few other terms of
the same size that denote the same column. They are the rivals that size cannot choose between.")
(defvar *alternates-kept* 2 "How many alternates are kept for each class.")

(defstruct (problem (:constructor %make-problem))
  label space leaves        ; LEAVES: list of (term . column), the context
  type target check         ; the hole's type, and its requirement: TARGET or CHECK
  (depth 0)                 ; how many variables are bound around the hole
  owner                     ; for a problem with a CHECK: the problem whose target it serves
  environments              ; per row, the values of the variables in scope, when the leaves
                            ; alone do not give them (a problem on a projection)
  projected                 ; true for a problem that is already a projection
  bank routes
  solution                  ; the accepted term
  held                      ; a FIT that awaits acceptance
  exhausted                 ; no route has anything left to try
  baseline                  ; bits of the best description of the target found without a fit
  (tries 0)                 ; candidates compared with the target so far
  evidence                  ; bits by which the accepted term beat the baseline
  undetermined              ; true once a fit could no longer beat the baseline
  (spent 0)                 ; work spent under this problem
  confirm-limit)            ; the value of SPENT at which a held term is accepted

(defstruct fit term evidence strict)   ; STRICT: found ahead of its size, so under the size-order rule

(defstruct route
  name step
  cost                      ; function: the predicted cost of this route's next step
  bound                     ; function: a lower bound on the size of anything it may still find
  (status :open))

(defun log2 (x) (/ (log (max 1 x)) (log 2)))

(defun column-bits (column type)
  "The bits to write COLUMN out cell by cell: what an underived column costs."
  (let ((bits 0))
    (loop for value across column
          do (emit-value value type (lambda (width v) (declare (ignore v)) (incf bits width))))
    bits))

(defun correction-bits (target column type)
  "The bits to turn COLUMN into TARGET. One bit says whether they differ at all (an exact column
does not cost zero: section 6.3, rule 5). If they do: the number of rows that differ, and for
each its index and its value. An integer is written as its difference from the column's cell
where that cell is an integer, and any other value is written out."
  (let* ((n (length target)) (bits 1) (exceptions 0))
    (flet ((emit (width v) (declare (ignore v)) (incf bits width)))
      (dotimes (r n)
        (let ((want (svref target r)) (have (svref column r)))
          (unless (cell= want have)
            (incf exceptions)
            (incf bits (index-width n))
            (if (and (eq type :int) (integerp have))
                (emit-positive (signed-code (- want have)) #'emit)
                (emit-value want type #'emit)))))
      (when (plusp exceptions) (emit-positive exceptions #'emit)))
    bits))

(defun make-problem (&rest keys)
  (let ((p (apply #'%make-problem keys)))
    (assert (or (problem-target p) (problem-check p)))
    (when (problem-target p)
      (setf (problem-baseline p) (column-bits (problem-target p) (problem-type p))))
    (push p *task-problems*)
    p))

(defun note-terms-still-held ()
  "For each problem of the task that ends with a term held under the size-order rule, note how
far the search for a smaller term without a conditional had got."
  (dolist (p (reverse *task-problems*))
    (when (and (problem-held p) (fit-strict (problem-held p)) (not (problem-solution p)) (problem-bank p))
      (push (format nil "~a: ~a was still held when the search ended: terms without a conditional had been ruled out up to ~d nodes of the ~d required"
                    (problem-label p) (held-term p) (bank-done (problem-bank p))
                    (1- (term-size (held-term p))))
            *task-notes*))))

(defun problem-n (p) (space-n (problem-space p)))
(defun evidence-owner (p) (or (problem-owner p) p))
(defun closed-p (p) (or (problem-solution p) (problem-exhausted p) (problem-undetermined p)))

(defun row-environments (p)
  "For each row of P's space, the alist from the name of each variable leaf to its value there:
what a term over P's context is evaluated in on that row."
  (or (problem-environments p)
      (loop for r below (problem-n p)
            collect (loop for (term . column) in (problem-leaves p)
                          when (eq :var (term-kind term))
                            collect (cons (term-head term) (svref column r))))))

(defun pulled-leaves (child leaves)
  "The LEAVES of a parent space moved to CHILD along its map."
  (loop for (term . column) in leaves collect (cons term (reindex child column))))

(defun ensure-bank (p)
  (or (problem-bank p)
      (let ((bank (make-bank (problem-space p) (append *grammar* *library*)
                             :types (list (problem-type p) :int :bool))))
        (loop for (term . column) in (problem-leaves p)
              do (let ((class (add-leaf bank term column)))
                   ;; a leaf whose column another leaf already has joins that class; it is a
                   ;; rival of the class's term that the rows cannot tell from it
                   (when (and *alternates* (not (eq term (cls-term class))))
                     (pushnew term (gethash (cls-term class) *alternates*)))))
        (loop for (type . values) in *constants*
              do (dolist (v values) (add-constant bank v type)))
        (setf (problem-bank p) bank))))

;;; --- the evidence rule ---

(defun check-determined (owner)
  "Close OWNER as not determined by its rows once naming even an exact fit would be no shorter
than the best description found without one."
  (when (and *use-evidence* (problem-baseline owner) (not (problem-held owner))
             (not (problem-solution owner)) (not (problem-undetermined owner))
             (>= (+ 1 (log2 (problem-tries owner))) (problem-baseline owner)))
    (push (format nil "~a: after ~:d candidates a fit would not be evidence; the best description without one takes ~,1f bits"
                  (problem-label owner) (problem-tries owner) (problem-baseline owner))
          *task-notes*)
    (setf (problem-undetermined owner) t)))

(defun count-try (p)
  "Record that one more candidate was compared with the requirement of P."
  (let ((owner (evidence-owner p)))
    (incf (problem-tries owner))
    (check-determined owner)))

(defun note-near-miss (p class)
  "A small class that does not denote the target of P may still be the best description of it
so far: its place in the search, and the corrections that turn its column into the target."
  (when (and *use-evidence* (<= (cls-size class) 3))
    (setf (problem-baseline p)
          (min (problem-baseline p)
               (+ (log2 (problem-tries p))
                  (correction-bits (problem-target p) (cls-col class) (problem-type p)))))
    (check-determined p)))

(defun held-term (p) (and (problem-held p) (fit-term (problem-held p))))

(defun offer (p term &key (alternatives 1) strict evidence)
  "Offer TERM, which fits P's requirement, as P's solution. It is held if naming it beats the
baseline and it is smaller than what is held already. ALTERNATIVES is the number of candidates
TERM was one of when it was not found by a single comparison: a conditional is one of every
pairing of two classes and a guard. EVIDENCE, when given, is the evidence already established
for the parts of a composite term. Returns true when TERM is now held."
  (let* ((bits (+ 1 (log2 (* (max 1 (problem-tries p)) alternatives))))
         (evidence (or evidence (and (problem-baseline p) (- (problem-baseline p) bits)))))
    (cond ((and *use-evidence* evidence (<= evidence 0))
           ;; A term found by one comparison closes the problem: every later one will have been
           ;; compared after it. A term that is one of many pairings is only passed over.
           (unless (or (problem-held p) strict (> alternatives 1))
             (push (format nil "~a: ~a fits, but it is one of ~:d candidates (~,1f bits) and the best description without it takes ~,1f bits"
                           (problem-label p) term (* (max 1 (problem-tries p)) alternatives) bits
                           (problem-baseline p))
                   *task-notes*)
             (setf (problem-undetermined p) t))
           nil)
          ((and (problem-held p) (>= (term-size term) (term-size (held-term p)))) nil)
          (t (unless (problem-held p)
               (setf (problem-confirm-limit p)
                     (+ (problem-spent p) (* *confirm-ratio* (max (problem-spent p) (problem-n p))))))
             (setf (problem-held p) (make-fit :term term :evidence evidence :strict strict))
             (when strict
               (push (format nil "~a: at ~:d cells, ~a (~d nodes) fits and is held under the size-order rule"
                             (problem-label p) (if *ledger* (ledger-total *ledger*) 0) term (term-size term))
                     *task-notes*))
             (install-lookahead p)
             t))))

(defun finalize (p)
  (let ((fit (problem-held p)))
    (when (fit-strict fit)
      (push (format nil "~a: at ~:d cells, every smaller term without a conditional is ruled out, and ~a is accepted"
                    (problem-label p) (if *ledger* (ledger-total *ledger*) 0) (fit-term fit))
            *task-notes*))
    (setf (problem-evidence p) (fit-evidence fit)
          (problem-solution p) (fit-term fit))))

;;; --- the look-ahead, types only ---

(defun type-reach (bank goal)
  "For each type, the fewest further nodes that turn a term of that type into a term of type
GOAL, using the bank's operators and a conditional. Returns an alist; a type that is absent
cannot reach GOAL."
  (let ((smallest '()) (reach (list (cons goal 0))) (changed t))
    (loop for c across (bank-all bank)
          do (let ((entry (assoc (cls-type c) smallest :test #'equal)))
               (cond ((null entry) (push (cons (cls-type c) (cls-size c)) smallest))
                     ((< (cls-size c) (cdr entry)) (setf (cdr entry) (cls-size c))))))
    (flet ((smallest (type) (cdr (assoc type smallest :test #'equal)))
           (reach (type) (cdr (assoc type reach :test #'equal)))
           (improve (type cost)
             (let ((entry (assoc type reach :test #'equal)))
               (cond ((null entry) (push (cons type cost) reach) (setf changed t))
                     ((< cost (cdr entry)) (setf (cdr entry) cost changed t))))))
      (loop while changed do
        (setf changed nil)
        ;; a conditional turns a Boolean into the goal type, given two terms of that type
        (when (smallest goal) (improve :bool (+ 1 (* 2 (smallest goal)))))
        (dolist (op (fix-operators bank))
          (let ((onward (reach (op-res op))))
            (when onward
              (loop for type in (op-args op) for k from 0
                    do (let ((others (loop for other in (op-args op) for j from 0
                                           unless (= j k) collect (smallest other))))
                         (unless (member nil others)
                           (improve type (+ 1 onward (reduce #'+ others)))))))))))
    reach))

(defun install-lookahead (p)
  "Bound the rest of the enumeration of P's bank by the size of the held term: a term of the
size being enumerated is skipped when its type cannot reach the hole's type within the bound."
  (when (and *use-lookahead* (problem-held p) (problem-bank p) (problem-target p))
    (let* ((bank (problem-bank p))
           (bound (1- (term-size (held-term p))))
           (reach (type-reach bank (problem-type p))))
      (setf (bank-skip-op bank)
            (lambda (op size)
              (let ((onward (cdr (assoc (op-res op) reach :test #'equal))))
                (or (null onward) (> (+ size onward) bound))))))))

;;; --- the conditional row: (if ?g ?a ?b), from classes already in the bank ---

(defun find-split (p ledger)
  "The smallest conditional (if g a b) that denotes the target of P, with g, a and b classes of
P's bank: a is a class that matches the target exactly on the rows where the Boolean class g is
true, and b one that matches on the rest. Returns the term, or nil, and the number of
alternatives that naming it chooses among: the product of the places of g, a and b in the order
in which the bank made its classes.

Each class of the hole's type is reduced to the set of rows on which it matches the target, as
a bit mask, and only the smallest class of each distinct mask is kept. A guard for a mask is
found by one hash probe, since a Boolean class with that column is a class of the bank."
  (let* ((bank (problem-bank p)) (target (problem-target p)) (type (problem-type p))
         (n (problem-n p)) (full (1- (ash 1 n)))
         (by-mask (make-hash-table)) (masks '()) (best nil) (best-alternatives 1) (work 0))
    ;; one pass over the classes, smallest first: the rows each matches
    (loop for c across (bank-all bank)
          do (cond ((equal type (cls-type c))
                    (let ((mask 0) (column (cls-col c)))
                      (dotimes (r n)
                        (when (cell= (svref column r) (svref target r))
                          (setf mask (logior mask (ash 1 r)))))
                      (incf work n)
                      (unless (or (zerop mask) (= mask full) (gethash mask by-mask))
                        (setf (gethash mask by-mask) c)
                        (push mask masks))))))
    (setf masks (nreverse masks))
    (flet ((guard-for (mask)
             ;; the Boolean class that is true exactly on the rows of MASK, if the bank has one
             (let ((column (make-array n)))
               (dotimes (r n) (setf (svref column r) (logbitp r mask)))
               (incf work n)
               (let ((g (lookup bank column)))
                 (and g (eq :bool (cls-type g)) g)))))
      (dolist (mask masks)
        (let ((a (gethash mask by-mask)))
          ;; only a class of at most this size could make a smaller conditional than the best so far
          (when (or (null best) (< (+ 5 (cls-size a)) (term-size best)))
            ;; the guard first: few masks have one, and the search for b below is the dear part
            (let ((g (guard-for mask)) (not-g (guard-for (logxor full mask))))
              (when (or g not-g)
                ;; b: the smallest class that matches on every row that a does not
                (let ((b (loop for other in masks
                               do (incf work)
                               when (= full (logior mask other))
                                 return (gethash other by-mask))))
                  (when b
                    (loop for (guard form)
                            in (list (list g (and g (app 'if (cls-term g) (cls-term a) (cls-term b))))
                                     (list not-g (and not-g (app 'if (cls-term not-g) (cls-term b)
                                                                 (cls-term a)))))
                          do (when (and form (or (null best) (< (term-size form) (term-size best))))
                               (setf best form
                                     best-alternatives
                                     (* (1+ (cls-id guard)) (1+ (cls-id a)) (1+ (cls-id b))))))))))))))
    (charge ledger :split work)
    (values best best-alternatives)))

;;; --- the inverse row: (f ?z k), through a solver found by reorientation ---

(defun try-inverses (p class ledger)
  "For the new CLASS k of P's bank and each solver of an operator f: the column that the other
argument of f must have for f to give the target, read off the solver's answer. If that column
is a class of the bank and the replay guard holds on every row, f applied to the two classes is
a solution. The probe comes first, because it is cheap and nearly always fails; the guard is
evaluated only when it succeeds. Returns the term with the number of alternatives that naming it
chooses among: the places of the two classes in the bank's order, and the solver."
  (let* ((bank (problem-bank p)) (target (problem-target p)) (space (problem-space p)))
    (dolist (solver *solvers*)
      (let* ((term (solver-term solver)) (unknown (solver-unknown solver))
             (variables (term-variables term))
             (knowns (remove unknown variables)))
        (when (and (= 1 (length knowns))
                   (equal (term-type term) (problem-type p))
                   (equal (term-type (first knowns)) (cls-type class)))
          (let* ((leaves (list (cons (term-head (first knowns)) (cls-col class))
                               (cons (term-head (solver-result solver)) target)))
                 (memo (make-hash-table :test 'eq)))
            (multiple-value-bind (wanted work) (term-column (solver-answer solver) space leaves memo)
              (charge ledger :inverse work)
              (let ((other (lookup bank wanted)))
                (when (and other (equal (cls-type other) (term-type unknown)))
                  (multiple-value-bind (guard guard-work)
                      (term-column (solver-guard solver) space leaves memo)
                    (charge ledger :inverse guard-work)
                    (when (every (lambda (g) (eq g t)) guard)
                      (return (cons (substitute-term term (list (cons unknown (cls-term other))
                                                                (cons (first knowns) (cls-term class))))
                                    (* (1+ (cls-id other)) (1+ (cls-id class))
                                       (length *solvers*)))))))))))))))

;;; --- routes ---

(defun level-cost-predictor (n)
  "Returns two functions for a route that deepens level by level: one that records the cost of
a completed level, and one that predicts the cost of the next from the last two."
  (let ((costs '()))
    (values (lambda (cost) (push (max 1 cost) costs))
            (lambda ()
              (cond ((null costs) n)
                    ((null (rest costs)) (* 4 (first costs)))
                    (t (* (first costs) (max 1 (/ (first costs) (second costs))))))))))

(defun leaf-route (p ledger)
  (let* ((bank (ensure-bank p)) (target (problem-target p)) (type (problem-type p))
         (owner (evidence-owner p)) (partial 0)
         (step-limit nil))   ; the ledger total at which the step in progress must stop
    (multiple-value-bind (record-level predict) (level-cost-predictor (problem-n p))
      (flet ((examine (c)
               ;; compare the class C with the requirement; true when the enumeration should stop
               (incf *classes-stored*)
               (cond ((closed-p owner) t)
                     ;; work charged by the comparisons below counts against the step's budget
                     ((and step-limit (>= (ledger-total ledger) step-limit)) t)
                     ((not (equal type (cls-type c))) nil)
                     (target
                      (count-try p)
                      (cond ((col= (cls-col c) target) (offer p (cls-term c)) t)
                            (t (note-near-miss p c)
                               (when (and *use-inverses* *solvers* (not (closed-p p)))
                                 (let ((term (try-inverses p c ledger)))
                                   (when term
                                     ;; like a conditional, such a term is found ahead of its
                                     ;; size, so it is held under the size-order rule
                                     (offer p (car term) :alternatives (cdr term) :strict t))))
                               (closed-p p))))
                     ((funcall (problem-check p) c) (setf (problem-solution p) (cls-term c)) t)
                     (t (closed-p owner)))))
        (setf (bank-on-new bank) #'examine)
        ;; a term of a class's own size that falls into it is kept as an alternate of its smallest term
        (setf (bank-on-collision bank)
              (lambda (class op args)
                (when (and *alternates* (= (cls-size class) (1+ (bank-done bank)))
                           (< (length (gethash (cls-term class) *alternates*)) *alternates-kept*))
                  (push (app-op op (mapcar #'cls-term args)) (gethash (cls-term class) *alternates*)))
                nil))
        ;; a leaf may already be the answer
        (loop for c across (bank-all bank) until (examine c))
        (make-route
         :name :leaf
         :cost predict
         :bound (lambda () (1+ (bank-done bank)))
         :step
         (lambda (budget)
           (let ((start (ledger-total ledger))
                 (limit (if (problem-held p)
                            (min *max-size* (1- (term-size (held-term p))))
                            *max-size*)))
             (cond ((or (closed-p owner) (problem-solution p)) :exhausted)
                   ((>= (bank-done bank) limit) :exhausted)
                   ((> *classes-stored* *max-classes*)
                    (pushnew (format nil "the task's banks reached ~:d classes, the most a task may store" *max-classes*)
                             *task-notes* :test #'string=)
                    :exhausted)
                   (t
                    (setf step-limit (+ start budget))
                    (let ((result (enumerate bank (1+ (bank-done bank)) ledger budget)))
                      (setf step-limit nil)
                      (incf partial (- (ledger-total ledger) start))
                      (cond ((eq result :cutoff) :working)
                            ((not (eq result :done)) :working) ; a fit, or the problem was closed
                            (t
                             ;; a size is complete: look for a conditional among the classes so far
                             (when (and target (not (closed-p p)))
                               (let ((before (ledger-total ledger)))
                                 (multiple-value-bind (split alternatives) (find-split p ledger)
                                   (when split
                                     (offer p split :alternatives alternatives :strict t)))
                                 (incf partial (- (ledger-total ledger) before))))
                             (funcall record-level partial)
                             (setf partial 0)
                             :working))))))))))))

(defun problem-lower-bound (p)
  "A lower bound on the size of P's solution: its size when P is solved, and otherwise the least
that any open route may still find."
  (cond ((problem-solution p) (term-size (problem-solution p)))
        ((null (problem-routes p)) 1)
        (t (let ((open (open-routes p)))
             (if open
                 (reduce #'min (mapcar (lambda (r) (funcall (route-bound r))) open))
                 most-positive-fixnum)))))

(defun sub-route (name p overhead make-sub finish)
  "A route of P that works through one sub-problem. OVERHEAD is the size of the construct around
the sub-problem's solution. MAKE-SUB builds the sub-problem, or returns nil when the route does
not apply. FINISH offers P the term built from the sub-problem's solution."
  (let ((sub nil) (dead nil))
    (make-route
     :name name
     :cost (lambda () (if sub (problem-next-cost sub) (problem-n p)))
     :bound (lambda () (+ overhead (if sub (problem-lower-bound sub) 1)))
     :step
     (lambda (budget)
       (unless (or sub dead)
         (setf sub (funcall make-sub))
         (unless sub (setf dead t)))
       (cond (dead :exhausted)
             (t (step-problem sub budget)
                (cond ((problem-solution sub) (funcall finish sub) :exhausted)
                      ((closed-p sub) :exhausted)
                      (t :working))))))))

(defun bound-var (depth type) (var (bound-name depth) type))
(defun values-only-p (column) (notany #'status-p column))

(defun tabulate-route (p)
  "(tabulate ?n (lambda (i) ?e)): the length on this space, the element on the space of the
output's positions."
  (let* ((target (problem-target p)) (space (problem-space p))
         (lengths (map 'simple-vector #'length target))
         (index (bound-var (problem-depth p) :int))
         (length-problem (make-problem :label "length" :space space :leaves (problem-leaves p)
                                       :type :int :target lengths :depth (problem-depth p)))
         (element-problem nil))
    (make-route
     :name :tabulate
     :cost (lambda ()
             (cond (element-problem (problem-next-cost element-problem))
                   ((problem-solution length-problem) (problem-n p)) ; the element problem is next
                   (t (problem-next-cost length-problem))))
     :bound (lambda () (+ 1 (problem-lower-bound length-problem)
                          (if element-problem (problem-lower-bound element-problem) 1)))
     :step
     (lambda (budget)
       (cond ((zerop (reduce #'+ lengths)) :exhausted) ; no element is observed
             ((not (problem-solution length-problem))
              (step-problem length-problem budget)
              (if (and (closed-p length-problem) (not (problem-solution length-problem)))
                  :exhausted :working))
             (t
              (unless element-problem
                (multiple-value-bind (positions index-column) (explode space lengths :name :positions)
                  (setf element-problem
                        (make-problem :label "element" :space positions
                                      :leaves (cons (cons index index-column)
                                                    (pulled-leaves positions (problem-leaves p)))
                                      :type (second (problem-type p))
                                      :target (element-column (reindex positions target) index-column)
                                      :depth (1+ (problem-depth p))))))
              (step-problem element-problem budget)
              (cond ((problem-solution element-problem)
                     (offer p (app 'tabulate (problem-solution length-problem)
                                   (lam (list index) (problem-solution element-problem)))
                            :evidence (+ (or (problem-evidence length-problem) 0)
                                         (or (problem-evidence element-problem) 0)))
                     :exhausted)
                    ((closed-p element-problem) :exhausted)
                    (t :working))))))))

(defun subsequence-p (short long)
  (let ((k 0))
    (loop for x across long
          do (when (and (< k (length short)) (cell= x (svref short k))) (incf k)))
    (= k (length short))))

(defun select-route (p leaf)
  "(gather xs (where (length xs) (lambda (j) ?keep))) for the sequence leaf XS: ?keep on the
space of the positions of xs. The requirement on ?keep is checked directly: the elements it
keeps, collected in order, must be the target. No alignment of output to input is computed."
  (destructuring-bind (xs . column) leaf
    (let* ((target (problem-target p)) (space (problem-space p)) (n (problem-n p))
           (index (bound-var (problem-depth p) :int)))
      (sub-route
       :select p 5
       (lambda ()
         (multiple-value-bind (positions index-column)
             (explode space (map 'simple-vector #'length column) :name :input-positions)
           (let ((elements (element-column (reindex positions column) index-column))
                 (pmap (space-pmap positions)))
             (make-problem
              :label "keep" :space positions :type :bool :owner p
              :leaves (cons (cons index index-column) (pulled-leaves positions (problem-leaves p)))
              :depth (1+ (problem-depth p))
              :check
              (lambda (class)
                (count-try p)
                (charge *ledger* :check (length pmap))
                (let ((kept (make-array n :initial-element '())) (keep (cls-col class)))
                  (and (dotimes (k (length pmap) t)
                         (let ((flag (svref keep k)))
                           (cond ((status-p flag) (return nil))
                                 (flag (push (svref elements k) (svref kept (svref pmap k)))))))
                       (dotimes (r n t)
                         (unless (cell= (coerce (reverse (svref kept r)) 'simple-vector)
                                        (svref target r))
                           (return nil))))))))))
       (lambda (sub)
         (offer p (app 'gather xs (app 'where (app 'length xs)
                                       (lam (list index) (problem-solution sub))))))))))

(defun where-route (p leaf)
  "(where (length xs) (lambda (j) ?keep)) for the sequence leaf XS, when the target is a list of
positions of xs in increasing order: ?keep has an exact target on the positions of xs."
  (destructuring-bind (xs . column) leaf
    (let* ((target (problem-target p)) (space (problem-space p))
           (index (bound-var (problem-depth p) :int)))
      (sub-route
       :where p 3
       (lambda ()
         (multiple-value-bind (positions index-column)
             (explode space (map 'simple-vector #'length column) :name :input-positions)
           (and (plusp (space-n positions))
                (make-problem :label "keep" :space positions :type :bool
                              :leaves (cons (cons index index-column)
                                            (pulled-leaves positions (problem-leaves p)))
                              :depth (1+ (problem-depth p))
                              :target (map 'simple-vector (lambda (y j) (and (find j y) t))
                                           (reindex positions target) index-column)))))
       (lambda (sub)
         (offer p (app 'where (app 'length xs) (lam (list index) (problem-solution sub)))
                :evidence (or (problem-evidence sub) 0)))))))

;;; --- the fold row ---

(defun probe-values (type target-value row-values)
  "Values of TYPE on which to try a step function's accumulator: a few made up, and the ones
this row offers."
  (case (type-kind type)
    (:bool (list nil t))
    (:int (let ((seen '()))
            (dolist (v (append (list 0 1 -1 2) (list target-value) row-values))
              (when (integerp v) (pushnew v seen)))
            (let ((sorted (sort seen #'<)))
              (subseq sorted 0 (min 8 (length sorted))))))
    (t nil)))

(defun fold-route (p leaf)
  "(fold ?init (lambda (acc x) ?step) xs) for the sequence leaf XS. The accumulator is not
observed, so the requirement does not split. Step functions are enumerated by class on a probe
space, with one row for each position of xs and each of a few values of the accumulator, and
each class is run through the fold from each candidate start and compared. The classes are
tested knowledge: two steps that agree on the probe rows are tried once."
  (destructuring-bind (xs . column) leaf
    (let* ((target (problem-target p)) (space (problem-space p)) (n (problem-n p))
           (type (problem-type p)) (depth (problem-depth p))
           (acc (bound-var depth type))
           (x (bound-var (1+ depth) (second (term-type xs))))
           (environments (row-environments p))
           (found nil))
      (sub-route
       :fold p 3
       (lambda ()
         (let* ((probes (let ((v (make-array n)))
                          (dotimes (r n v)
                            (setf (svref v r)
                                  (coerce (probe-values type (svref target r)
                                                        (loop for (nil . col) in (problem-leaves p)
                                                              collect (svref col r)))
                                          'simple-vector)))))
                (starts (loop for c across (bank-all (ensure-bank p))
                              when (and (= 1 (cls-size c)) (equal type (cls-type c)))
                                collect (cls-term c))))
           (unless (or (null starts) (zerop n) (zerop (length (svref probes 0))))
             (multiple-value-bind (positions index-column)
                 (explode space (map 'simple-vector #'length column))
               (let ((elements (element-column (reindex positions column) index-column))
                     (probes-at-position (reindex positions probes)))
                 (multiple-value-bind (grid probe-index)
                     (explode positions (map 'simple-vector #'length probes-at-position) :name :probe)
                   (and (plusp (space-n grid))
                        (make-problem
                         :label "step" :space grid :type type :depth (+ 2 depth) :owner p
                         :leaves (list* (cons acc (map 'simple-vector #'svref
                                                       (reindex grid probes-at-position) probe-index))
                                        (cons x (reindex grid elements))
                                        (pulled-leaves grid (pulled-leaves positions (problem-leaves p))))
                         :check
                         (lambda (class)
                           (dolist (start starts nil)
                             (count-try p)
                             (when (closed-p p) (return nil))
                             (let ((program (app 'fold start (lam (list acc x) (cls-term class)) xs)))
                               (when (loop for env in environments for r from 0
                                           always (multiple-value-bind (value work)
                                                      (run-term program env :fuel 100000)
                                                    (charge *ledger* :check work)
                                                    (cell= value (svref target r))))
                                 (setf found program)
                                 (return t)))))))))))))
       (lambda (sub) (declare (ignore sub)) (offer p found))))))

;;; --- the aggregate row ---

(defun aggregate-functions (element-type result-type)
  "The library functions in scope that take one sequence of ELEMENT-TYPE to RESULT-TYPE."
  (loop for name in *library*
        for op = (find-op name (list (seq-of element-type)) nil)
        when (and op (equal result-type (op-res op)))
          collect name))

(defun aggregate-route (p name count-term count-column)
  "(NAME (tabulate COUNT (lambda (i) ?e))): ?e is not observed, so each element class on the
space of COUNT positions is collected, given to the library function NAME, and compared."
  (let* ((target (problem-target p)) (space (problem-space p)) (n (problem-n p))
         (op (find-op name (list (seq-of :int))))
         (index (bound-var (problem-depth p) :int)))
    (sub-route
     (list :aggregate name) p (+ 2 (term-size count-term))
     (lambda ()
       (when (and (every #'integerp count-column) (notany #'minusp count-column)
                  (plusp (reduce #'+ count-column)))
         (multiple-value-bind (positions index-column) (explode space count-column)
           (make-problem
            :label "element" :space positions :type :int :owner p
            :leaves (cons (cons index index-column) (pulled-leaves positions (problem-leaves p)))
            :depth (1+ (problem-depth p))
            :check
            (lambda (class)
              (count-try p)
              (let ((collected (collect positions (cls-col class))) (*spent* 0))
                (prog1 (dotimes (r n t)
                         (let ((s (svref collected r)))
                           (unless (and (not (status-p s))
                                        (cell= (funcall (op-fn op) s) (svref target r)))
                             (return nil))))
                  (charge *ledger* :check (+ (space-n positions) n *spent*)))))))))
     (lambda (sub)
       (offer p (app name (app 'tabulate count-term (lam (list index) (problem-solution sub)))))))))

;;; --- the tuple row ---

(defun tuple-route (p)
  "(tuple ?a ?b): one requirement for each slot."
  (let* ((target (problem-target p)) (types (rest (problem-type p)))
         (parts (loop for type in types for k from 0
                      collect (make-problem :label (format nil "slot ~d" k)
                                            :space (problem-space p) :leaves (problem-leaves p)
                                            :type type :depth (problem-depth p)
                                            :target (map 'simple-vector (lambda (v) (nth k v)) target)))))
    (make-route
     :name :tuple
     :cost (lambda ()
             (let ((open (remove-if #'closed-p parts)))
               (if open (reduce #'min (mapcar #'problem-next-cost open)) 1)))
     :bound (lambda () (1+ (reduce #'+ (mapcar #'problem-lower-bound parts))))
     :step
     (lambda (budget)
       (let ((open (remove-if #'closed-p parts)))
         (when open
           (step-problem (first (sort (copy-list open) #'< :key #'problem-next-cost)) budget))
         (cond ((every #'problem-solution parts)
                (offer p (apply #'app 'tuple (mapcar #'problem-solution parts))
                       :evidence (reduce #'+ (mapcar (lambda (q) (or (problem-evidence q) 0)) parts)))
                :exhausted)
               ((some (lambda (part) (and (closed-p part) (not (problem-solution part)))) parts)
                (when (some #'problem-undetermined parts) (setf (problem-undetermined p) t))
                :exhausted)
               (t :working)))))))

;;; --- reorienting a requirement onto the columns that determine it ---

(defun determining-classes (p)
  "The coarsest supported set of cheap columns that determines the target of P, or nil. The
cheap columns are the classes of P's bank of at most two nodes: the leaves, and one operator
applied to a leaf, such as the length of a sequence. A set of one or two of them qualifies when
the target is the same on all rows that agree on the set, and every such group has at least two
rows, so that the agreement is seen and not vacuous. Among the sets that qualify, the one with
the fewest groups is returned, with the group number of each row and the number of groups."
  (let* ((bank (ensure-bank p)) (n (problem-n p)) (target (problem-target p))
         (cheap (remove-if (lambda (c)
                             (or (> (cls-size c) 2)
                                 (every (lambda (v) (cell= v (svref (cls-col c) 0))) (cls-col c))))
                           (coerce (bank-all bank) 'list)))
         (best nil))
    (flet ((consider (classes)
             (multiple-value-bind (groups count) (group-rows (mapcar #'cls-col classes) n)
               (charge *ledger* :dependency n)
               (when (and (< count n) (or (null best) (< count (third best))))
                 (let ((sizes (make-array count :initial-element 0))
                       (value (make-array count :initial-element nil))
                       (ok t))
                   (dotimes (r n)
                     (let ((g (svref groups r)))
                       (if (zerop (svref sizes g))
                           (setf (svref value g) (svref target r))
                           (unless (cell= (svref value g) (svref target r)) (setf ok nil)))
                       (incf (svref sizes g))))
                   (when (and ok (every (lambda (size) (>= size 2)) sizes))
                     (setf best (list classes groups count))))))))
      (dolist (c cheap) (consider (list c)))
      (loop for (a . rest) on cheap do (dolist (b rest) (consider (list a b)))))
    best))

(defun projection-route (p classes groups count)
  "Solve P on the space of the groups of rows that agree on CLASSES, with those classes as the
only leaves."
  (let* ((n (problem-n p))
         (first-row (let ((rows (make-array count :initial-element nil)))
                      (dotimes (r n rows)
                        (unless (svref rows (svref groups r)) (setf (svref rows (svref groups r)) r)))))
         (pick (lambda (column) (map 'simple-vector (lambda (r) (svref column r)) first-row)))
         (environments (row-environments p)))
    (sub-route
     :reorient p 0
     (lambda ()
       (make-problem :label (format nil "~a, as a function of ~{~a~^ and ~}" (problem-label p)
                                    (mapcar #'cls-term classes))
                     :space (make-space count :name :groups)
                     :leaves (loop for c in classes collect (cons (cls-term c) (funcall pick (cls-col c))))
                     :type (problem-type p) :depth (problem-depth p)
                     :target (funcall pick (problem-target p))
                     :environments (map 'list (lambda (r) (nth r environments)) first-row)
                     :projected t))
     (lambda (sub)
       (offer p (problem-solution sub) :evidence (or (problem-evidence sub) 0))))))

;;; --- which routes apply, and the scheduler ---

(defun sequence-leaves (p &optional element-type)
  (remove-if-not (lambda (leaf)
                   (let ((type (term-type (car leaf))))
                     (and (seq-type-p type)
                          (or (null element-type) (equal element-type (second type)))
                          (values-only-p (cdr leaf)))))
                 (problem-leaves p)))

(defun make-routes (p)
  "The routes for P: a short fixed list keyed on the type of the hole."
  ;; a requirement that a few supported columns determine is solved on those columns alone
  (when (and *use-projection* (problem-target p) (not (problem-projected p))
             (values-only-p (problem-target p)))
    (let ((bank (ensure-bank p)))
      (when (< (bank-done bank) 2) (enumerate bank 2 *ledger* most-positive-fixnum))
      (let ((found (determining-classes p)))
        (when found
          (return-from make-routes (list (apply #'projection-route p found)))))))
  (let ((type (problem-type p)) (target (problem-target p))
        (routes (list (leaf-route p *ledger*))))
    (flet ((add (route) (setf routes (append routes (list route)))))
      (when (and target (values-only-p target) (< (problem-depth p) 2))
        (cond ((seq-type-p type)
               (add (tabulate-route p))
               (dolist (leaf (sequence-leaves p (second type)))
                 (when (every #'subsequence-p target (cdr leaf))
                   (add (select-route p leaf))))
               (when (equal type (seq-of :int))
                 (dolist (leaf (sequence-leaves p))
                   (when (every (lambda (y xs)
                                  (and (every (lambda (j) (and (<= 0 j) (< j (length xs)))) y)
                                       (loop for k from 1 below (length y)
                                             always (< (svref y (1- k)) (svref y k)))))
                                target (cdr leaf))
                     (add (where-route p leaf))))))
              ((eq :tuple (type-kind type))
               (add (tuple-route p)))
              (t
               (dolist (leaf (sequence-leaves p))
                 (add (fold-route p leaf)))
               (when (eq type :int)
                 (dolist (name (aggregate-functions :int type))
                   (dolist (leaf (sequence-leaves p))
                     (add (aggregate-route p name (app 'length (car leaf))
                                           (map 'simple-vector #'length (cdr leaf)))))))))))
    routes))

(defun open-routes (p) (remove :exhausted (problem-routes p) :key #'route-status))

(defun live-routes (p)
  "The routes of P that may be stepped next. With nothing held: every open route. While a term
is held: the open routes that could still find a smaller one. Once confirming the held term has
cost as much as finding it: none, except the leaf route when the held term is a conditional,
which the size-order rule requires to be ruled out in full."
  (let ((open (open-routes p)) (held (problem-held p)))
    (if (null held)
        open
        (let ((rivals (remove-if-not (lambda (r) (< (funcall (route-bound r)) (term-size (fit-term held))))
                                     open)))
          (cond ((< (problem-spent p) (problem-confirm-limit p)) rivals)
                ((fit-strict held) (remove-if-not (lambda (r) (eq :leaf (route-name r))) rivals))
                (t '()))))))

(defun settle (p)
  "Close P if no route is left that could change its answer: accept the held term, or mark P
exhausted."
  (when (and (problem-routes p) (not (closed-p p)) (null (live-routes p)))
    (let ((held (problem-held p)))
      (cond ((null held) (setf (problem-exhausted p) t))
            (t (let ((cut (remove-if-not (lambda (r) (< (funcall (route-bound r)) (term-size (fit-term held))))
                                         (open-routes p))))
                 (when cut
                   (push (format nil "~a: ~a was accepted before every smaller term was ruled out (~{~a~^, ~})"
                                 (problem-label p) (fit-term held)
                                 (mapcar (lambda (r) (format nil "~(~a~) reached size ~d" (route-name r)
                                                             (1- (funcall (route-bound r)))))
                                         cut))
                         *task-notes*)))
               (finalize p))))))

(defun problem-next-cost (p)
  "The predicted cost of the cheapest next step anywhere under P."
  (cond ((null (problem-routes p)) (problem-n p))
        ((closed-p p) most-positive-fixnum)
        (t (let ((live (live-routes p)))
             (if live
                 (reduce #'min (mapcar (lambda (r) (funcall (route-cost r))) live))
                 1)))))

(defun step-problem (p budget)
  "Take the one step under P that is predicted to be cheapest, within BUDGET."
  (unless (problem-routes p) (setf (problem-routes p) (make-routes p)))
  (settle p)
  (unless (closed-p p)
    (let* ((route (first (sort (copy-list (live-routes p)) #'<
                               :key (lambda (r) (funcall (route-cost r))))))
           (before (ledger-total *ledger*))
           (status (funcall (route-step route) budget)))
      (incf (problem-spent p) (max 1 (- (ledger-total *ledger*) before)))
      (when (eq status :exhausted) (setf (route-status route) :exhausted))
      (settle p))))

(defun advance (p ledger budget)
  "Spend up to BUDGET on P, one cheapest step at a time. Returns P's solution, or nil. P can be
advanced again."
  (let ((*ledger* ledger) (start (ledger-total ledger)))
    (loop
      (when (closed-p p) (return (problem-solution p)))
      (let ((left (- budget (- (ledger-total ledger) start))))
        (when (<= left 0) (return nil))
        (step-problem p left)))))
