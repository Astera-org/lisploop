(in-package #:lisploop2)

;;; The store: spaces, columns, classes.
;;;
;;; Evaluating one term on N rows gives an execution graph that is N copies of the term's own
;;; shape. The store keeps the factors and not the product: the term once, the rows once, and
;;; the values at the crossings as one column per class (plan section 5.1).

;;; --- spaces and maps ---

(defstruct (space (:constructor %make-space))
  "A finite set of rows. PARENT and PMAP are set when the space was made from another: PMAP is
the map back, a vector that gives, for each row of this space, a row of PARENT."
  (n 0 :type fixnum) parent pmap name)

(defmethod print-object ((s space) stream)
  (format stream "#<space ~@[~a ~]~d rows>" (space-name s) (space-n s)))

(defun make-space (n &key name) (%make-space :n n :name name))

(defun constant-column (space value)
  (make-array (space-n space) :initial-element value))

(defun explode (space counts &key name)
  "The space with one row for each pair (row r of SPACE, index i below COUNTS[r]), with its map
back to SPACE. Returns the new space and its index column. This is unnesting: a sequence-valued
column unfolds into a space of positions when COUNTS holds its lengths."
  (let ((pmap '()) (index '()))
    (dotimes (r (space-n space))
      (dotimes (i (svref counts r)) (push r pmap) (push i index)))
    (values (%make-space :n (length pmap) :parent space :name name
                         :pmap (coerce (nreverse pmap) 'simple-vector))
            (coerce (nreverse index) 'simple-vector))))

(defun subspace (space mask &key name)
  "The space of the rows of SPACE at which MASK is true, with its map back."
  (let ((pmap (coerce (loop for r below (space-n space) when (svref mask r) collect r)
                      'simple-vector)))
    (%make-space :n (length pmap) :parent space :pmap pmap :name name)))

(defun reindex (child column)
  "Move a column of the parent space along the map: each row of CHILD reads its parent's cell."
  (map 'simple-vector (lambda (r) (svref column r)) (space-pmap child)))

(defun collect (child column)
  "Move a column of CHILD back along the map: each parent row gathers the cells of its child
rows, in order, as a sequence. A parent row with a child cell that is a status gets that status."
  (let* ((n (space-n (space-parent child)))
         (lists (make-array n :initial-element '()))
         (bad (make-array n :initial-element nil)))
    (loop for r across (space-pmap child) for v across column
          do (if (status-p v)
                 (unless (svref bad r) (setf (svref bad r) v))
                 (push v (svref lists r))))
    (let ((out (make-array n)))
      (dotimes (r n out)
        (setf (svref out r)
              (or (svref bad r) (coerce (reverse (svref lists r)) 'simple-vector)))))))

(defun element-column (sequences index &optional (offset 0))
  "The column whose cell is element INDEX+OFFSET of the row's sequence, and a fault where that
is out of range."
  (map 'simple-vector
       (lambda (s i)
         (let ((j (+ i offset)))
           (cond ((status-p s) s)
                 ((and (<= 0 j) (< j (length s))) (svref s j))
                 (t (make-fault 'at (list s j))))))
       sequences index))

;;; --- group-by and the dependency test ---

(defun group-rows (columns n)
  "Group the rows 0..N-1 by their cells in COLUMNS. Returns a vector that gives each row the
number of its group, and the number of groups. Rows are in one group when they agree on every
column. This is one pass and one hash table: the group-by that the dependency test, the fibers
of a column, and the tables of section 6 are all computed with."
  (let ((table (make-hash-table)) (groups (make-array n)) (count 0))
    (dotimes (r n (values groups count))
      (let* ((h (let ((h +hash-seed+))
                  (dolist (c columns h) (setf h (hash-mix h (cell-hash (svref c r)))))))
             (hit (find-if (lambda (entry)
                             (every (lambda (c) (cell= (svref c r) (svref c (car entry)))) columns))
                           (gethash h table))))
        (if hit
            (setf (svref groups r) (cdr hit))
            (progn (push (cons r count) (gethash h table))
                   (setf (svref groups r) count)
                   (incf count)))))))

(defun dependency (target keys n)
  "Is the column TARGET a function of the columns KEYS on these N rows? Returns the mask of the
rows that lie in a group where TARGET takes one value only, and the share of rows for which
that holds. The share is 1 exactly when TARGET is determined by KEYS."
  (multiple-value-bind (groups count) (group-rows keys n)
    (let ((first-value (make-array count :initial-element nil))
          (seen (make-array count :initial-element nil))
          (single (make-array count :initial-element t)))
      (dotimes (r n)
        (let ((g (svref groups r)))
          (cond ((not (svref seen g))
                 (setf (svref seen g) t (svref first-value g) (svref target r)))
                ((not (cell= (svref first-value g) (svref target r)))
                 (setf (svref single g) nil)))))
      (let ((mask (make-array n)))
        (dotimes (r n) (setf (svref mask r) (svref single (svref groups r))))
        (values mask (if (zerop n) 1 (/ (count t mask) n)))))))

;;; --- classes and banks ---

(defstruct (cls (:constructor %make-cls))
  "All the terms that denote one column on a space. It stores the column once, the smallest
term that denotes it, and an evidence grade (plan section 5.5): :observed means the same column
on this space, which is exact for any question about this space."
  (id 0 :type fixnum) col type (size 1 :type fixnum) term (grade :observed))

(defmethod print-object ((c cls) stream)
  (format stream "#<class ~d ~a>" (cls-id c) (cls-term c)))

(defstruct (bank (:constructor %make-bank))
  "Every class found so far on one space, from one set of leaves and operators. The class table
is content-addressed by column, so it is also the memo of evaluation: a term whose column is
already present costs one evaluation and stores nothing."
  space
  op-names types                          ; what the bank was asked to enumerate over
  (operators :unset)                      ; the operators themselves, fixed at the first enumeration
  (leaves '())                            ; variable name -> its column on this space
  (table (make-hash-table))               ; column hash -> list of classes with that hash
  (by (make-hash-table :test 'equal))     ; (type . size) -> vector of classes, in creation order
  (all (make-array 64 :adjustable t :fill-pointer 0))
  (done 1 :type fixnum)                   ; the largest size fully enumerated
  cursor                                  ; where enumeration stands inside size DONE + 1
  staged                                  ; a candidate that is evaluated and not yet paid for
  (debt 0 :type fixnum)                   ; the work still owed for STAGED
  buffer                                  ; scratch column for candidates
  (candidates 0) (cells 0) (collisions 0) (dropped 0)
  skip-op                                 ; function of (operator size): true when no term of that
                                          ; size built with the operator can be part of an answer
  (skipped 0)                             ; operators skipped at some size by SKIP-OP
  skip-candidate                          ; function of (operator classes): true when the candidate
                                          ; need not be evaluated, because a law already places it
  (pruned 0)                              ; candidates skipped by SKIP-CANDIDATE
  on-new                                  ; function of a new class; a true value stops enumeration
  on-collision)                           ; function of (class op args) when a term hits a class

(defun make-bank (space op-names &key types)
  "A bank on SPACE over the operators named OP-NAMES, instantiated at TYPES and at the types of
the leaves added before the first enumeration."
  (%make-bank :space space :op-names op-names :types types
              :buffer (make-array (space-n space) :initial-element nil)))

(defun bank-size (bank) (length (bank-all bank)))

(defun classes (bank type size)
  (or (gethash (cons type size) (bank-by bank)) #()))

(defun lookup (bank column &optional (hash (col-hash column)))
  "The class of BANK whose column is COLUMN, or nil. One hash probe."
  (dolist (c (gethash hash (bank-table bank)))
    (when (col= (cls-col c) column) (return c))))

(defun new-class (bank column hash type size term)
  (let ((c (%make-cls :id (bank-size bank) :col column :type type :size size :term term))
        (key (cons type size)))
    (push c (gethash hash (bank-table bank)))
    (vector-push-extend c (or (gethash key (bank-by bank))
                              (setf (gethash key (bank-by bank))
                                    (make-array 16 :adjustable t :fill-pointer 0))))
    (vector-push-extend c (bank-all bank))
    c))

(defun add-leaf (bank term column)
  "Enter a leaf: the class of TERM, a variable or constant whose column on this space is COLUMN.
A leaf whose column is already present joins that class."
  (assert (= (length column) (space-n (bank-space bank))))
  (assert (eq :unset (bank-operators bank)) () "Leaves must be added before enumeration starts")
  (when (eq :var (term-kind term))
    (setf (bank-leaves bank) (append (bank-leaves bank) (list (cons (term-head term) column)))))
  (or (lookup bank column)
      (new-class bank column (col-hash column) (term-type term) 1 term)))

(defun add-constant (bank value type)
  (add-leaf bank (const value type) (constant-column (bank-space bank) value)))

(defun fix-operators (bank)
  "The operators of BANK. They are fixed at the first enumeration, from the types of the leaves."
  (if (eq :unset (bank-operators bank))
      (setf (bank-operators bank)
            (op-instances (bank-op-names bank)
                          (remove-duplicates
                           (append (bank-types bank) (map 'list #'cls-type (bank-all bank)))
                           :test #'equal :from-end t)))
      (bank-operators bank)))

;;; --- evaluation by column ---

(defun apply-op-column (op columns buffer n)
  "Apply OP down the argument COLUMNS into BUFFER. Returns the hash of the result, whether any
cell is a value, and the work spent beyond one unit per row."
  (declare (type simple-vector buffer) (type fixnum n))
  (let ((fn (op-fn op)) (h +hash-seed+) (any nil) (*spent* 0))
    (declare (type function fn) (type fixnum h))
    (macrolet ((cell-loop (form)
                 `(dotimes (r n)
                    (let ((v ,form))
                      (unless (status-p v) (setf any t))
                      (setf (svref buffer r) v
                            h (hash-mix h (cell-hash v)))))))
      (if (op-strict op)
          (ecase (op-arity op)
            (1 (let ((a (first columns)))
                 (declare (type simple-vector a))
                 (cell-loop (let ((x (svref a r))) (if (status-p x) x (funcall fn x))))))
            (2 (let ((a (first columns)) (b (second columns)))
                 (declare (type simple-vector a b))
                 (cell-loop (let ((x (svref a r)) (y (svref b r)))
                              (cond ((status-p x) x) ((status-p y) y) (t (funcall fn x y)))))))
            (3 (let ((a (first columns)) (b (second columns)) (c (third columns)))
                 (declare (type simple-vector a b c))
                 (cell-loop (let ((x (svref a r)) (y (svref b r)) (z (svref c r)))
                              (cond ((status-p x) x) ((status-p y) y) ((status-p z) z)
                                    (t (funcall fn x y z))))))))
          (cell-loop (apply fn (mapcar (lambda (c) (svref c r)) columns)))))
    (values h any *spent*)))

;;; --- enumeration, by size, of terms over classes ---
;;;
;;; A candidate is one operator applied to classes already in the bank. Its arguments are
;;; classes and never raw terms, so each class is built on once however many terms denote it.
;;; The sizes of the argument classes of a candidate of size S sum to S - 1, so the classes a
;;; size is built from are complete before it starts, and the order of candidates is fixed.
;;;
;;; Enumeration is resumable and its result does not depend on how its budget is sliced. A
;;; candidate is evaluated, and its column is filed only once its cost has been charged. If the
;;; budget ends first, the candidate stays staged with its debt, and the next call pays the rest
;;; before doing anything else. This is v1's discipline of staged work (PAY-DEBT).

(defstruct cursor size ops op splits vectors index)

(defun size-splits (total parts)
  "Every way to write TOTAL as an ordered sum of PARTS positive integers."
  (cond ((= parts 0) (if (= total 0) (list '()) '()))
        ((= parts 1) (if (plusp total) (list (list total)) '()))
        (t (loop for first from 1 to (- total (1- parts))
                 append (mapcar (lambda (rest) (cons first rest))
                                (size-splits (- total first) (1- parts)))))))

(defun next-candidate (bank cursor)
  "The next candidate of the cursor's size as an operator and a list of argument classes, or
nil when the size is exhausted."
  (loop
    (cond ((cursor-vectors cursor)
           (let* ((vectors (cursor-vectors cursor)) (index (cursor-index cursor))
                  (k (length vectors))
                  (args (loop for v across vectors for i across index collect (aref v i))))
             ;; advance like an odometer, the last argument fastest
             (loop for p downfrom (1- k) to 0
                   do (if (< (incf (svref index p)) (length (svref vectors p)))
                          (return)
                          (setf (svref index p) 0))
                   finally (setf (cursor-vectors cursor) nil))
             (return (values (cursor-op cursor) args))))
          ((cursor-splits cursor)
           (let* ((split (pop (cursor-splits cursor)))
                  (vectors (map 'simple-vector (lambda (type size) (classes bank type size))
                                (op-args (cursor-op cursor)) split)))
             (unless (some (lambda (v) (zerop (length v))) vectors)
               (setf (cursor-vectors cursor) vectors
                     (cursor-index cursor) (make-array (length vectors) :initial-element 0)))))
          ((cursor-ops cursor)
           (let ((op (pop (cursor-ops cursor))))
             (if (and (bank-skip-op bank) (funcall (bank-skip-op bank) op (cursor-size cursor)))
                 (incf (bank-skipped bank))
                 (setf (cursor-op cursor) op
                       (cursor-splits cursor)
                       (size-splits (1- (cursor-size cursor)) (op-arity op))))))
          (t (return nil)))))

(defun stage-candidate (bank op args)
  "Evaluate the candidate into the bank's buffer and stage it with its cost."
  (let ((n (space-n (bank-space bank))))
    (multiple-value-bind (hash any extra)
        (apply-op-column op (mapcar #'cls-col args) (bank-buffer bank) n)
      (incf (bank-candidates bank))
      (setf (bank-staged bank) (list op args hash any)
            (bank-debt bank) (+ n extra)))))

(defun file-candidate (bank)
  "File the staged candidate, which is now paid for: a new class, or a collision with a class
already present. A column with no value in it is dropped. Returns what a hook returned."
  (destructuring-bind (op args hash any) (bank-staged bank)
    (setf (bank-staged bank) nil)
    (incf (bank-cells bank) (space-n (bank-space bank)))
    (cond ((not any) (incf (bank-dropped bank)) nil)
          (t (let ((old (lookup bank (bank-buffer bank) hash)))
               (cond (old (incf (bank-collisions bank))
                          (and (bank-on-collision bank)
                               (funcall (bank-on-collision bank) old op args)))
                     (t (let ((c (new-class bank (copy-seq (bank-buffer bank)) hash (op-res op)
                                            (1+ (bank-done bank))
                                            (app-op op (mapcar #'cls-term args)))))
                          (and (bank-on-new bank) (funcall (bank-on-new bank) c))))))))))

(defun enumerate (bank max-size ledger budget)
  "Enumerate the terms of BANK up to MAX-SIZE nodes, charging LEDGER at most BUDGET units.
Returns :DONE when every size up to MAX-SIZE is complete, :CUTOFF when the budget ended first,
or the true value that a hook returned, which stops enumeration at that candidate. In every
case the bank can be enumerated further by another call."
  (let ((left budget) (operators (fix-operators bank)))
    (flet ((pay ()
             (let ((paid (min left (bank-debt bank))))
               (charge ledger :enumerate paid)
               (decf left paid)
               (decf (bank-debt bank) paid)
               (zerop (bank-debt bank)))))
      (loop
        (when (bank-staged bank)
          (unless (pay) (return :cutoff))
          (let ((stop (file-candidate bank)))
            (when stop (return stop))))
        (when (>= (bank-done bank) max-size) (return :done))
        (unless (bank-cursor bank)
          (setf (bank-cursor bank)
                (make-cursor :size (1+ (bank-done bank))
                             :ops (copy-list operators))))
        (multiple-value-bind (op args) (next-candidate bank (bank-cursor bank))
          (cond ((null op)
                 (setf (bank-done bank) (cursor-size (bank-cursor bank))
                       (bank-cursor bank) nil))
                ((and (bank-skip-candidate bank) (funcall (bank-skip-candidate bank) op args))
                 (incf (bank-pruned bank)))
                (t (stage-candidate bank op args))))))))

;;; --- evaluating a given term on a space ---

(defun term-column (term space leaves &optional (memo (make-hash-table :test 'eq)))
  "The column that TERM denotes on SPACE. LEAVES is an alist from variable names to their
columns on SPACE. MEMO, a table from term to column, shares the work across calls: with
hash-consed terms a shared sub-term is evaluated once. Returns the column and the work spent,
one unit per cell and what the cell functions spend inside. A term with a lambda in it has no
column of its own; such a term is evaluated row by row with EV."
  (let ((n (space-n space)) (work 0))
    (labels ((walk (term)
               (or (gethash term memo)
                   (setf (gethash term memo)
                         (ecase (term-kind term)
                           (:const (constant-column space (term-head term)))
                           (:var (or (cdr (assoc (term-head term) leaves))
                                     (error "No column for the variable ~a" (term-head term))))
                           (:app (let ((columns (mapcar #'walk (term-args term)))
                                       (out (make-array n)))
                                   (multiple-value-bind (hash any extra)
                                       (apply-op-column (term-head term) columns out n)
                                     (declare (ignore hash any))
                                     (incf work (+ n extra)))
                                   out)))))))
      (values (walk term) work))))
