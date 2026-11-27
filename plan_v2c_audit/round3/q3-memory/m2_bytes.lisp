;;; m2_bytes.lisp -- live bytes per entry, in SBCL, for the four kinds of entry the memory
;;; rule distinguishes.  The structures are those of plan_v2c_audit/proto/tg-probe.lisp
;;; (cls struct, table: column hash -> ((column . class) ...), per-size vector, `all` vector);
;;; nothing is loaded from the repository.  32 rows of fixnums, 200,000 entries per kind.
;;;
;;;   full     a stored class: column + cls struct + term + dedupe-table entry + two vector slots
;;;   colonly  a column kept in the dedupe table only (cut from the bank, mode (b))
;;;   hashonly the column's hash kept in a table, no column (the prototype's frontier mode)
;;;   record   a cut record: hash -> #(size f op arg1 arg2), no column (policy K)
;;;
;;; run: sbcl --script m2_bytes.lisp

(defstruct cls id col type size term)
(defparameter *rows* 32)
(defparameter *n* 200000)

(defun col-hash (col)
  (let ((h 2166136261))
    (dotimes (r (length col) h)
      (setf h (logand (* (logxor h (logand (svref col r) #xFFFFFFF)) 16777619) #xFFFFFFFFF)))))

(defun rnd-col (state)
  (let ((v (make-array *rows*)))
    (dotimes (r *rows* v) (setf (svref v r) (- (random 2000001 state) 1000000)))))

(defun live () (sb-ext:gc :full t) (sb-kernel:dynamic-usage))

(defun measure (kind)
  (let* ((state (sb-ext:seed-random-state 7))
         (table (make-hash-table))
         (by (make-array 16 :adjustable t :fill-pointer 0))
         (all (make-array 64 :adjustable t :fill-pointer 0))
         (t1 '(+ x y)) (t2 '(* x x))
         (buf nil)
         (m0 (live)))
    (dotimes (i *n*)
      (setf buf (rnd-col state))
      (let ((h (col-hash buf)))
        (ecase kind
          (:full (let ((c (make-cls :id i :col buf :type :int :size 9 :term (list '+ t1 t2))))
                   (push (cons buf c) (gethash h table))
                   (vector-push-extend c by)
                   (vector-push-extend c all)))
          (:colonly (push (cons buf nil) (gethash h table)))
          (:hashonly (setf (gethash h table) t))
          (:record (setf (gethash h table) (vector 9 11 '+ t1 t2))))))
    (setf buf nil)
    (let ((m1 (live)))
      (format t "~10a ~7,1f live bytes per entry  (~d entries, table count ~d)~%"
              kind (/ (- m1 m0) (float *n*)) *n* (hash-table-count table))
      ;; keep the structures alive until after the measurement
      (list table by all))))

(format t "# SBCL ~a, ~d rows of fixnums per column~%" (lisp-implementation-version) *rows*)
(dolist (k '(:full :colonly :hashonly :record))
  (measure k))
