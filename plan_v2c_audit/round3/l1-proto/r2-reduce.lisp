;;;; r2-reduce.lisp -- verify-review R2: scalar targets by MONOIDAL PUSHFORWARD.
;;;; Loaded after tg-probe-r2.lisp (probe + MODs 1-6) and r1-spec.lisp (spec rows, references).
;;;; All of this file is an ADDITION.  It uses REDUCE-PMAP / *AGGS* (MODs 4, 6 in the probe copy).
(in-package :tg)

(defvar *ntests* 0)                       ; pushed-forward columns compared with the target

;;; (A) GRANTED SHAPE -- the smallest version: the position space is given (a term over the
;;; example inputs); every new class on it is pushed forward under each aggregate of its
;;; cell type and compared with the scalar target.  First fit, in size order.
(defun reduce-bank (base leaves ys shape-term counts)
  "The class bank on the position space {(r,i) : i < COUNTS[r]}, with a hook that tests each
   new class's pushforwards against YS and throws the program on a match."
  (multiple-value-bind (b2 i) (explode base counts)
    (let ((bank (new-bank b2 *d-ops*)))
      (add-leaf bank 'i :int i)
      (dolist (l leaves) (add-leaf bank (first l) (second l) (pull b2 (third l))))
      (setf (bank-on-new bank)
            (lambda (c)
              (loop for (name type e fn) in *aggs*
                    when (eq type (cls-type c))
                      do (incf *ntests*)
                         (when (col= ys (reduce-pmap b2 (cls-col c) e fn))
                           (throw :stop `(fold-space ,shape-term ,name (lambda (i) ,(cls-term c))))))))
      bank)))
(defun run-reduce (bank size limit)
  "Enumerate BANK up to element SIZE; size 1 = the leaves (added before the hook existed)."
  (let ((r (catch :stop (when (= size 1) (map nil (bank-on-new bank) (bank-all bank))) nil)))
    (or r (and (> size 1) (run bank size :limit limit)))))
(defun solve-reduce-granted (exs base leaves ys shape-term max-size limit)
  (let* ((counts (map 'simple-vector (lambda (ex) (ev shape-term (car ex))) exs))
         (bank (reduce-bank base leaves ys shape-term counts))
         (r (loop for s from 1 to max-size
                  do (let ((r (run-reduce bank s limit)))
                       (when (consp r) (return r))
                       (when (member r '(:budget :time)) (return nil))))))
    (tally bank)
    (push (format nil "granted shape; B'=~d rows, ~d classes, ~d pushforward tests"
                  (base-n (bank-base bank)) (length (bank-all bank)) *ntests*) *note*)
    r))

;;; (B) ENUMERATED SHAPE: shapes are the classes of the probe's own shape bank (lengths,
;;; integer inputs, 0, 1 under *shape-ops*) up to SHAPE-SIZE, non-negative and non-constant;
;;; iterative deepening on (shape size + element size), so the first fit is size-minimal
;;; over shape and element together.
(defun shape-classes (base leaves shape-size)
  (let ((shape (new-bank base *shape-ops*)))
    (dolist (l leaves) (unless (eq (second l) :seq) (apply #'add-leaf shape l)))
    (run shape shape-size)
    (tally shape)
    (remove-if-not (lambda (c) (and (eq (cls-type c) :int)
                                    (every (lambda (v) (and (integerp v) (<= 0 v))) (cls-col c))
                                    (notevery (lambda (v) (eql v (svref (cls-col c) 0))) (cls-col c))))
                   (coerce (bank-all shape) 'list))))
(defun solve-reduce (base leaves ys &key (max-total 10) (shape-size 3) (limit 30000000))
  (let ((shapes (shape-classes base leaves shape-size)) (banks '()) (result nil))
    (block search
      (loop for total from 2 to max-total do
        (dolist (sc shapes)
          (when (< (cls-size sc) total)
            (let* ((bank (or (cdr (assoc sc banks))
                             (let ((b (reduce-bank base leaves ys (cls-term sc) (cls-col sc))))
                               (push (cons sc b) banks) b)))
                   (r (run-reduce bank (- total (cls-size sc)) limit)))
              (when (consp r) (setf result r) (return-from search))
              (when (member r '(:budget :time)) (push (format nil "~a in shape ~s" r (cls-term sc)) *note*)
                    (return-from search)))))))
    (dolist (b banks) (tally (cdr b)))
    (push (format nil "~d shapes (size<=~d), ~d position banks, ~d classes in all, ~d pushforward tests"
                  (length shapes) shape-size (length banks)
                  (loop for b in banks sum (length (bank-all (cdr b)))) *ntests*) *note*)
    result))

;;; ---------------- driver ----------------
(defun r2-report (label task exs thunk)
  (setf *ntests* 0)
  (report label task exs thunk))

(defun r2-one (task exs &key granted (max-total 10))
  (let* ((base (make-base :n (length exs))) (leaves (input-cols task exs))
         (ys (map 'simple-vector #'cdr exs)))
    (when granted
      (r2-report (format nil "granted ~a" granted) task exs
                 (lambda () (solve-reduce-granted exs base leaves ys granted 9 30000000))))
    (r2-report "enumerated shape" task exs
               (lambda () (solve-reduce base leaves ys :max-total max-total)))))

(defun r2 ()
  (let ((*package* (find-package :tg)) (*print-pretty* nil) (*print-case* :downcase))
    (format t "=== R2: monoidal pushforward; aggregates ~a; d-ops ~a ===~%"
            (mapcar #'first *aggs*) (mapcar #'op-name *d-ops*))
    (check-refs)
    (format t "~%--- seq-corr from its 7 kernel spec rows ---~%")
    (r2-one (spec-task "seq-corr") (spec-exs "seq-corr") :granted '(min (len xs) (len ys)))
    (format t "~%--- sum-all / len-all / prd-all / last-or from their kernel spec rows ---~%")
    (dolist (n '("sum-all" "len-all" "prd-all" "last-or"))
      (r2-one (spec-task n) (spec-exs n) :granted '(len xs)))
    (format t "~%--- the probe's own three fold tasks on its own 12 random examples (seed 1), where its fold path gets 3/3 ---~%")
    (dolist (task *fold-tasks*)
      (r2-one task (gen-examples task 1 12 7) :granted '(len xs)))
    (format t "~%--- what it cannot do: foldl (spec rows), argmax-corr (spec rows) ---~%")
    (r2-one (spec-task "foldl") (spec-exs "foldl") :granted '(len xs))
    (r2-one (spec-task "argmax-corr") (spec-exs "argmax-corr"))
    (finish-output)))
