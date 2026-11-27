;;;; E5 algebra discovery: what `discover-arithmetic-solver` (milestones/algebra-discovery.lisp, M4)
;;;; finds at its default settings, in how much work and time, and how its work scales when the
;;;; term-size bound (:body-bound, default 16 bits) is raised.
;;;;
;;;;   sbcl --dynamic-space-size 3000 --script e5_algebra.lisp KERNEL-ROOT CPU-SECONDS-PER-CELL
(defvar *root* (pathname (second sb-ext:*posix-argv*)))
(load (merge-pathnames "load.lisp" *root*))
(load (merge-pathnames "milestones/load.lisp" *root*))
(in-package #:lisploop)
(setf *print-pretty* nil)

(defun secs (ticks) (/ ticks (float internal-time-units-per-second 1d0)))

(defun compact (sexp)
  (cond ((atom sexp) sexp)
        ((eq :app (first sexp)) (cons (second (second sexp)) (mapcar #'compact (cddr sexp))))
        ((eq :var (first sexp)) (intern (format nil "X~D" (second sexp)) :keyword))
        ((eq :lit (first sexp)) (let ((v (third sexp))) (if (and (listp v) v) (list 'quote v) (or v "NIL"))))
        (t sexp)))

(defun cell (domain name position body-bound &key (operators '(:+ :- :* :/)))
  "One discovery: (work cpu witness guard records). Work = the discovery ledger + the vocabulary
observation job's ledger (the enumeration that dominates)."
  (let* ((values (if (eq domain :int) '(-4 -3 -2 -1 0 1 2 3 4) (loop for i below (second domain) collect i)))
         (c0 (get-internal-run-time))
         (relation (observe-arithmetic-relation domain name values))
         (discovery (handler-case
                        (discover-arithmetic-solver relation position values
                                                    :operators operators
                                                    :literals (if (eq domain :int) '(-1 0 1) :all)
                                                    :body-bound body-bound)
                      (error (c) c)))
         (cpu (secs (- (get-internal-run-time) c0))))
    (if (typep discovery 'error)
        (list :error (princ-to-string discovery) :cpu cpu)
        (let ((obs (solve-discovery-observations discovery)))
          (list :work (+ (ledger-total (solve-discovery-ledger discovery))
                         (ledger-total (observation-job-ledger obs)))
                :obs-work (ledger-total (observation-job-ledger obs))
                :cpu cpu
                :records (length (observation-job-records obs))
                :buckets (length (observation-job-buckets obs))
                :rows (length (frame-rows (solve-discovery-frame discovery)))
                :witness (compact (ast->sexp (solve-discovery-witness discovery)))
                :guard (compact (ast->sexp (solve-discovery-guard discovery))))))))

(let ((cpu-cap (parse-integer (third sb-ext:*posix-argv*))))
  (format t "E5 kernel=~A~%" cl-user::*root*)
  (format t "~%--- A. default settings (:body-bound 16, operators + - * /), every operator x position ---~%")
  (dolist (domain (list (gf 5) (gf 7) :int))
    (let ((total-work 0) (total-cpu 0))
      (dolist (name '(:+ :- :* :/))
        (dotimes (position 2)
          (let ((r (cell domain name position 16)))
            (incf total-work (or (getf r :work) 0)) (incf total-cpu (getf r :cpu))
            (format t "~8A solve ~A for arg ~D: ~S~%" domain name position r)
            (finish-output))))
      (format t "~8A TOTAL work=~D cpu_s=~,3F~%" domain total-work total-cpu)))
  (format t "~%--- B. raising the term-size bound: solve `k - x = c` (:- position 1) and `x / k = c` (:/ position 0) ---~%")
  (dolist (domain (list (gf 7) :int))
    (dolist (spec '((:- 1) (:/ 0)))
      (let ((prev nil))
        (loop for body-bound in '(12 14 16 18 20 22 24 26 28 30 32 34 36)
              do (let ((r (cell domain (first spec) (second spec) body-bound)))
                   (format t "~8A ~A/~D body-bound=~2D work=~12D obs-work=~12D x=~6,2F records=~8D behaviours=~7D cpu_s=~8,3F witness=~S~%"
                           domain (first spec) (second spec) body-bound
                           (getf r :work) (getf r :obs-work)
                           (if (and prev (getf r :work)) (/ (getf r :work) prev 1d0) 0)
                           (getf r :records) (getf r :buckets) (getf r :cpu)
                           (or (getf r :witness) (getf r :error)))
                   (finish-output)
                   (setf prev (getf r :work))
                   (when (> (getf r :cpu) cpu-cap) (return)))))))
  (format t "~%--- C. one notch on the operator set at the default bound and at 24: + - * / plus MOD (:int only) ---~%")
  (dolist (body-bound '(16 20 24))
    (dolist (ops '((:+ :- :* :/) (:+ :- :* :/ :mod)))
      (let ((r (cell :int :- 1 body-bound :operators ops)))
        (format t ":int -/1 body-bound=~D ops=~S work=~D records=~D behaviours=~D cpu_s=~,3F witness=~S~%"
                body-bound ops (getf r :work) (getf r :records) (getf r :buckets) (getf r :cpu)
                (or (getf r :witness) (getf r :error)))
        (finish-output)))))
