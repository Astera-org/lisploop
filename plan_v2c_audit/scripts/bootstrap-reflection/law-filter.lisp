;;;; How many laws does observation search propose in the algebra battery's four micro-grammars,
;;;; and how many survive the host shape filter `law-operator-fact`? (scratch copy; mirrors
;;;; build-batteries.lisp:119-173 with counters)
(defvar *args* (cdr (member "--" sb-ext:*posix-argv* :test #'string=)))
(defvar *v2-root* (pathname (concatenate 'string (first *args*) "/")))
(load (merge-pathnames "load.lisp" *v2-root*))
(in-package #:lisploop)
(setf *print-pretty* nil)
(with-knowledge-library ((make-knowledge-library))
  (let* ((ledger (make-ledger)) (gf3 (gf 3))
         (in1 (list (cons 0 gf3))) (in2 (list (cons 0 gf3) (cons 1 gf3))) (in3 (list (cons 0 gf3) (cons 1 gf3) (cons 2 gf3)))
         (rows1 (loop for i below 3 collect (law-assignment in1 i)))
         (rows2 (loop for i below 9 collect (law-assignment in2 i)))
         (rows3 (loop for i below 27 collect (law-assignment in3 i)))
         (specs (list (list "1 var, {+,*}, lits 0 1" in1 rows1 (list (op :+ gf3) (op :* gf3)) '(0 1) 20 20000)
                      (list "2 vars, {+,*}" in2 rows2 (list (op :+ gf3) (op :* gf3)) nil 24 40000)
                      (list "3 vars, {+} only" in3 rows3 (list (op :+ gf3)) nil 44 80000)
                      (list "3 vars, {*} only" in3 rows3 (list (op :* gf3)) nil 44 80000)
                      ;; what the author did NOT run: three variables with both operators
                      (list "3 vars, {+,*} (not in bootstrap)" in3 rows3 (list (op :+ gf3) (op :* gf3)) nil 44 80000)
                      (list "3 vars, {+,*} at 10x work (not in bootstrap)" in3 rows3 (list (op :+ gf3) (op :* gf3)) nil 44 800000))))
    (loop for (label inputs rows ops lits slack work) in specs
          do (let* ((obs (start-observation-search
                          (make-observation-scope (probe-frame gf3 inputs rows)
                                                  (make-language gf3 inputs :operators ops :literals lits))))
                    (_ (resume-observation-search obs (header-bound inputs gf3 slack) work))
                    (laws (propose-observed-laws obs :ledger ledger))
                    (facts (remove nil (mapcar #'law-operator-fact laws))))
               (declare (ignore _))
               (format t "~&~44A observation work=~7:D buckets=~4D proposed laws=~5D  pass host shape filter=~3D ~S~%"
                       label (ledger-total (observation-job-ledger obs)) (length (observation-job-buckets obs))
                       (length laws) (length facts)
                       (remove-duplicates (mapcar (lambda (f) (list (first f) (second f))) facts) :test #'equal))))))
