(in-package #:lisploop2)

;;; Cells and types.
;;;
;;; A cell holds a value or a status (plan section 5.2).
;;;
;;; Values, by type:
;;;   :int               a Lisp integer
;;;   (:gf p)            an integer in [0, p): an element of the prime field of p elements
;;;   :bool              T or NIL
;;;   (:seq T)           a simple-vector of values of type T, so reading an element costs one unit
;;;   (:tuple T1 ... Tk) a Lisp list of k values
;;;   (:fn (T1 ...) R)   an FNVAL: a function-valued input, a library function, or a closure
;;;
;;; Statuses, in place of a value:
;;;   FAULT     the computation failed here; it records which operator failed on which arguments
;;;   FUEL-OUT  the computation was cut off by its fuel limit
;;;   PENDING   the computation waits on a named call
;;;
;;; A column is typed, so NIL as "false" and NIL as "the empty tuple" never meet in one column.

(defstruct status)
(defstruct (fault (:include status) (:constructor make-fault (op args))) op args)
(defstruct (fuel-out (:include status)))
(defstruct (pending (:include status) (:constructor make-pending (call))) call)

(defvar *fuel-out* (make-fuel-out) "The one out-of-fuel cell.")

(defstruct (fnval (:constructor make-fnval (name arity fn)))
  "A function as a value. NAME identifies it: two function cells are equal when their names are
EQUAL. A function given as code is named by that code. FN takes ARITY values and returns a value
or a status."
  name arity fn)

(defmethod print-object ((f fault) stream)
  (format stream "#<fault ~a~{ ~s~}>" (fault-op f) (fault-args f)))
(defmethod print-object ((f fnval) stream)
  (format stream "#<fn ~a>" (fnval-name f)))

;;; --- equality and hashing of cells ---
;;;
;;; Two faults are equal as cells whatever their detail. No program can tell one failure from
;;; another: TRY, the one form that observes a failure, treats them all alike. So two terms that
;;; fail on the same rows and agree elsewhere denote the same column. The detail of a fault is
;;; kept in the cell as data for learning guards (plan section 7.1, change 2). Two pending cells
;;; are equal only when they wait on the same call.

(defun cell= (a b)
  (cond ((eql a b) t)
        ((integerp a) nil)
        ((simple-vector-p a)
         (and (simple-vector-p b) (= (length a) (length b))
              (dotimes (i (length a) t)
                (unless (cell= (svref a i) (svref b i)) (return nil)))))
        ((consp a)
         (and (consp b) (cell= (car a) (car b)) (cell= (cdr a) (cdr b))))
        ((fault-p a) (fault-p b))
        ((pending-p a) (and (pending-p b) (equal (pending-call a) (pending-call b))))
        ((fnval-p a) (and (fnval-p b) (equal (fnval-name a) (fnval-name b))))
        (t nil)))

(defconstant +hash-mask+ #xFFFFFFFFF "Hashes are kept to 36 bits, so they stay fixnums.")

(defun cell-hash (v)
  (cond ((integerp v) (logand v #xFFFFFFF))
        ((null v) #x10000001)
        ((eq v t) #x10000002)
        ((simple-vector-p v)
         (let ((h 7))
           (dotimes (i (length v) (+ h #x20000000))
             (setf h (logand (+ (* h 31) (cell-hash (svref v i))) #xFFFFFFF)))))
        ((consp v)
         (let ((h 11))
           (dolist (e v (+ h #x30000000))
             (setf h (logand (+ (* h 37) (cell-hash e)) #xFFFFFFF)))))
        ((fault-p v) #x10000003)
        ((fuel-out-p v) #x10000004)
        ((pending-p v) (logior #x40000000 (logand (sxhash (pending-call v)) #xFFFFFFF)))
        ((fnval-p v) (logior #x50000000 (logand (sxhash (fnval-name v)) #xFFFFFFF)))
        (t (error "Not a cell: ~s" v))))

(declaim (inline hash-mix))
(defun hash-mix (h cell-hash)
  "One step of an FNV-style hash over the cells of a column."
  (logand (* (logxor h cell-hash) 16777619) +hash-mask+))

(defconstant +hash-seed+ 2166136261)

(defun col-hash (col)
  (let ((h +hash-seed+))
    (dotimes (r (length col) h)
      (setf h (hash-mix h (cell-hash (svref col r)))))))

(defun col= (a b)
  "Exact equality of two columns. Every hash hit is confirmed with this."
  (and (= (length a) (length b))
       (dotimes (r (length a) t)
         (unless (cell= (svref a r) (svref b r)) (return nil)))))

;;; --- types ---

(defun gf (p) (list :gf p))
(defun seq-of (type) (list :seq type))
(defun fn-type (args res) (list :fn args res))

(defun type-kind (type) (if (consp type) (first type) type))
(defun gf-type-p (type) (and (consp type) (eq :gf (first type))))
(defun seq-type-p (type) (and (consp type) (eq :seq (first type))))
(defun fn-type-p (type) (and (consp type) (eq :fn (first type))))
(defun numeric-type-p (type) (or (eq type :int) (gf-type-p type)))

(defun type-variable-p (x)
  (and (symbolp x) (plusp (length (symbol-name x))) (char= #\? (char (symbol-name x) 0))))

(defun match-type (pattern type bindings)
  "Match the type PATTERN, which may contain type variables such as ?A, against the concrete
TYPE. Returns the extended bindings, or :FAIL. The variable ?N matches only a numeric type."
  (cond ((eq bindings :fail) :fail)
        ((type-variable-p pattern)
         (let ((bound (assoc pattern bindings)))
           (cond (bound (if (equal (cdr bound) type) bindings :fail))
                 ((and (eq pattern '?n) (not (numeric-type-p type))) :fail)
                 (t (acons pattern type bindings)))))
        ((atom pattern) (if (eq pattern type) bindings :fail))
        ((atom type) :fail)
        ((/= (length pattern) (length type)) :fail)
        (t (loop for p in pattern for q in type
                 do (setf bindings (match-type p q bindings))
                    (when (eq bindings :fail) (return :fail))
                 finally (return bindings)))))

(defun substitute-type (pattern bindings)
  (cond ((type-variable-p pattern)
         (let ((bound (assoc pattern bindings)))
           (if bound (cdr bound) (error "Unbound type variable ~s" pattern))))
        ((atom pattern) pattern)
        (t (mapcar (lambda (p) (substitute-type p bindings)) pattern))))

(defun value-of-type-p (value type)
  "True when VALUE is a well-formed value of TYPE. Used at the boundary, where rows come in."
  (case (type-kind type)
    (:int (integerp value))
    (:bool (or (eq value t) (null value)))
    (:gf (and (integerp value) (<= 0 value) (< value (second type))))
    (:seq (and (simple-vector-p value)
               (every (lambda (v) (value-of-type-p v (second type))) value)))
    (:tuple (and (listp value) (= (length value) (length (rest type)))
                 (every #'value-of-type-p value (rest type))))
    (:fn (and (fnval-p value) (= (fnval-arity value) (length (second type)))))
    (t nil)))
