(defvar *v2* (second sb-ext:*posix-argv*))
(load (merge-pathnames "load.lisp" *v2*))
(in-package #:lisploop)
(defmacro try (label form)
  `(handler-case (let ((v ,form)) (format t "~&OK    ~A => ~S~%" ,label v))
     (error (e) (format t "~&FAIL  ~A => ~A~%" ,label (remove #\Newline (princ-to-string e))))))
(let* ((c (var 0 :int)) (k (var 1 :int))
       (inputs '((0 . :int) (1 . :int)))
       (replay (term `(= (* (/ ,c ,k) ,k) ,c)))
       (guarded (term `(if (= ,k 0) ,(lit :bool nil) ,replay))))
  (try "replay total?" (provably-total-p replay))
  (try "guarded replay total?" (provably-total-p guarded))
  (try "body bits replay / guarded / witness (/ c k)"
       (list (scoped-bits replay (reference-width inputs replay))
             (scoped-bits guarded (reference-width inputs guarded))
             (scoped-bits (term `(/ ,c ,k)) (reference-width inputs (term `(/ ,c ,k))))))
  (try "description-size replay / guarded"
       (list (description-size replay inputs) (description-size guarded inputs)))
  (try "guarded exact on -3..3 grid (divisibility)?"
       (loop for cc from -3 to 3 always
         (loop for kk from -3 to 3 always
           (let ((s (evaluate guarded inputs (list cc kk))))
             (and (eq :value (evaluation-status s))
                  (eq (not (null (evaluation-value s)))
                      (and (/= kk 0) (zerop (rem cc kk))))))))))
;; PIT sanity: does grid {0..d}^k agreement really certify? just count runs for (x-y)(x+y)=x^2-y^2
(format t "~&PIT grid size for (x-y)(x+y)=x*x-y*y with per-var degree 2: ~D runs~%" (* 3 3))
