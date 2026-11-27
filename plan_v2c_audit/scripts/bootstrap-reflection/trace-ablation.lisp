;;;; "Trace-complete" example ablation (scratch copy): keep each bootstrap spec's operators,
;;;; literals, constants, types and the recursion schemas; replace only its rows by ordinary
;;;; black-box I/O rows in which the recursive calls' intermediate states are NOT themselves rows.
(defvar *args* (cdr (member "--" sb-ext:*posix-argv* :test #'string=)))
(defvar *v2-root* (pathname (concatenate 'string (first *args*) "/")))
(load (merge-pathnames "load.lisp" *v2-root*))
(load (merge-pathnames "bootstrap/recursion-schemas.lisp" *v2-root*))
(load (merge-pathnames "tests/support.lisp" *v2-root*))
(in-package #:lisploop)
(setf *print-pretty* nil)
(defparameter *sub* (term `(- ,(var 0 :int) ,(var 1 :int))))
(defparameter *add* (term `(+ ,(var 0 :int) ,(var 1 :int))))
(defparameter *alt-rows*
  `((:foldl :sequences
     ((() 7 ,*sub*) 7) ((() 9 ,*sub*) 9) (((3) 9 ,*sub*) 6) (((2 3) 9 ,*sub*) 4) (((1 2 3) 9 ,*sub*) 3)
     ((() 10 ,*sub*) 10) (((4) 10 ,*sub*) 6) (((1 4) 10 ,*sub*) 5) (((5 1 4) 10 ,*sub*) 0))
    (:scan :scans
     ((() 1 ,*add*) ()) (((3) 1 ,*add*) (4)) (((-1 3) 1 ,*add*) (0 3)) (((2 -1 3) 1 ,*add*) (3 2 5))
     ((() 10 ,*sub*) ()) (((4) 10 ,*sub*) (6)) (((1 4) 10 ,*sub*) (9 5)) (((5 1 4) 10 ,*sub*) (5 4 0)) ((() 4 ,*add*) ()))
    (:positions :sequences
     ((() 0) ()) (((7) 0) (0)) (((6 7) 0) (0 1)) (((5 6 7) 0) (0 1 2))
     ((() 2) ()) (((4) 2) (2)) (((9 4) 2) (2 3)) (((1 9 4) 2) (2 3 4)) ((() 1) ()) (((8) 1) (1)) (((3 8) 1) (1 2)))
    (:best-shift :sequence-shift
     ((() (4 1) 0) (0 0)) (((1) (4 1) 0) (4 0)) (((4 1) (4 1) 0) (17 0)) (((3 4 1) (4 1) 0) (17 1))
     ((() (5 0) 0) (0 0)) (((2) (5 0) 0) (10 0)) (((5 2) (5 0) 0) (25 0)) (((1 5 2) (5 0) 0) (25 1)) (((7 1 5 2) (5 0) 0) (35 0)))
    (:shift-seq :sequence-shift
     ((() 0) ()) ((() 1) ()) (((5) 0) (5)) (((1 5) 0) (1 5)) (((4 1 5) 0) (4 1 5))
     (((5) 1) (0)) (((1 5) 1) (5 0)) (((4 1 5) 1) (1 5 0)) (((4 1 5) 2) (5 0 0)) (((7 4 1 5) 2) (1 5 0 0))
     (((3 1 4 1 5) 2) (4 1 5 0 0)) (((3 1 4 1 5) 3) (1 5 0 0 0)) (((2 8) 2) (0 0)))))

(defun held (id)
  (case id
    (:foldl (list (list '(1 2 3) 10 (term `(- (* 2 ,(var 0 :int)) ,(var 1 :int)))) 69))
    (:scan (list (list '(1 2 3) 10 (term `(- (* 2 ,(var 0 :int)) ,(var 1 :int)))) '(19 36 69)))
    (:positions '(((10 20 30 40) 2) (2 3 4 5)))
    (:best-shift '(((2 4 1) (4 1) 0) (17 1)))
    (:shift-seq '(((8 6 4 2) 2) (4 2 0 0)))))

(defun run (id battery rows label budget)
  (with-clean-kernel-state
    (load-battery :sequences :only '(:map :foldr) :check-examples-p nil)
    (when (eq id :best-shift) (load-battery :sequence-shift :only '(:seq-corr) :check-examples-p nil))
    (let* ((src (deserialize-knowledge-library (read-battery battery)))
           (orig (find-knowledge-entry (keyword-id "SPEC/~A" id) src))
           (meta (knowledge-entry-metadata orig))
           (inputs (knowledge-entry-inputs orig)) (target (knowledge-entry-target orig))
           (rows (or rows (with-knowledge-library (src) (spec-entry-rows orig))))
           (frame (simple-frame target inputs rows))
           (lang (make-language :int inputs :operators (mapcar #'sexp->ast (getf meta :operators))
                                            :literals (getf meta :literals)
                                            :constants (mapcar #'sexp->ast (getf meta :constants))))
           (job (start-recursive-synthesis frame lang 130 :self-name id :max-depth 2 :heuristic-budget 15000
                                                          :expanders (list (recursion-schema-expander)))))
      (handler-case (resume-synthesis job budget :stop-on-first t)
        (error (e) (format t "   RUN-ERROR ~A~%" e)))
      (let* ((best (synthesis-job-best job))
             (sound (and best (ignore-errors
                               (commit-synthesis-job job :name id)
                               (destructuring-bind (args want) (held id)
                                 (let ((run (evaluate (apply #'app (op id) (loop for v in args for (nil . ty) in inputs collect (lit ty v)))
                                                      nil nil :budget 50000)))
                                   (and (eq :value (evaluation-status run)) (equal want (evaluation-value run)))))))))
        (format t "~&~12A ~22A rows=~2D budget=~10:D -> ~8A work=~10:D nodes=~2D unresolved-rows-in-nodes=~S~%"
                id label (length rows) budget (cond ((null best) "no") (sound "SOUND") (t "IMPOSTOR"))
                (ledger-total (synthesis-job-ledger job)) (length (synthesis-job-nodes job))
                (loop for n in (synthesis-job-nodes job)
                      for f = (synthesis-node-frame n)
                      collect (and f (count-if (lambda (r) (member :unresolved (row-known r))) (frame-rows f)))))
        (when (and best (not sound)) (format t "    ~S~%" (ast->sexp (candidate-expression best))))
        (finish-output)))))

(loop for (id battery . rows) in *alt-rows*
      do (run id battery nil "trace-complete(orig)" 350000)
         (dolist (b '(350000 3500000 35000000))
           (run id battery rows "black-box I/O" b)))
