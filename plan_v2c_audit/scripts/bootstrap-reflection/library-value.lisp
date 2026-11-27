;;;; Does the bootstrapped library make NEW synthesis cheaper / reach further? (scratch copy)
;;;; Held-out tasks, none in the curriculum. Same primitive grammar and literals in every regime;
;;;; regimes differ only in what library is loaded and whether its functions are offered.
;;;; argv tail: <v2-root> <budget>
(defvar *args* (cdr (member "--" sb-ext:*posix-argv* :test #'string=)))
(defvar *v2-root* (pathname (concatenate 'string (first *args*) "/")))
(defvar *budget* (parse-integer (second *args*)))
(load (merge-pathnames "load.lisp" *v2-root*))
(load (merge-pathnames "bootstrap/recursion-schemas.lisp" *v2-root*))
(load (merge-pathnames "tests/support.lisp" *v2-root*))
(in-package #:lisploop)
(setf *print-pretty* nil)

(defparameter *seq* (sequence-type :int))
(defparameter *tasks*
  ;; (id target rows held-out)
  `((:add2-all ,*seq* (((()) ()) (((3)) (5)) (((1 3)) (3 5)) (((4 1 3)) (6 3 5)))            (((9 -2 5)) (11 0 7)))
    (:sum-sq   :int   (((()) 0) (((3)) 9) (((2 3)) 13) (((4 2 3)) 29))                        (((1 -2 5)) 30))
    (:pos-only ,*seq* (((()) ()) (((3)) (3)) (((-2 3)) (3)) (((4 -2 3)) (4 3)) (((-1)) ()))    (((-5 8 0 3 -1)) (8 3)))
    (:run-sum  ,*seq* (((()) ()) (((3)) (3)) (((1 3)) (1 4)) (((4 1 3)) (4 5 8)))             (((2 -5 7 1)) (2 -3 4 5)))
    (:diffs    ,*seq* (((()) ()) (((9)) ()) (((4 9)) (5)) (((1 4 9)) (3 5)))                  (((10 3 9 1)) (-7 6 -8)))
    (:count-pos :int  (((()) 0) (((3)) 1) (((-2 3)) 1) (((4 -2 3)) 2) (((-1)) 0))              (((-5 8 0 3 -1)) 2))
    (:sq-pos   ,*seq* (((()) ()) (((3)) (9)) (((-2 3)) (9)) (((4 -2 3)) (16 9)) (((-1)) ()))   (((-5 8 0 3 -1)) (64 9)))
    (:last     :int   (((()) 0) (((3)) 3) (((2 5)) 5) (((4 2 7)) 7))                           (((9 5 2)) 2))))

(defun prim-ops (target)
  (append (when (seq-type-p target) (list (op :cons :int)))
          (list (op :tail :int) (op :at *seq*) (op := *seq*) (op :if target)
                (op :+ :int) (op :* :int) (op :- :int) (op :< :int))))

(defparameter *lib-fns* '(:map :foldr :foldl :filter :map-adjacent :scan))

(defun run-task (task regime budget)
  (destructuring-bind (id target rows held) task
    (with-clean-kernel-state
      (let* ((inputs (list (cons 0 *seq*)))
             (frame (simple-frame target inputs rows))
             (lib-p (member regime '(:lib-proposals :lib-grammar :lib-grammar+proposals :lib-nonrec)))
             (_ (when lib-p (dolist (b (battery-names)) (load-battery b :check-examples-p nil))))
             (ops (append (prim-ops target)
                          (when (member regime '(:lib-grammar :lib-grammar+proposals))
                            (loop for f in *lib-fns* when (defined-function-p f) collect (op f)))))
             (lang (make-language :int inputs :operators ops :literals '(0 1 2)
                                              :constants (list (lit *seq* '()))))
             (t0 (get-internal-real-time))
             (job (handler-case
                      (ecase regime
                        (:kernel-only
                         (start-recursive-synthesis frame lang 130 :self-name id :max-depth 2 :heuristic-budget 15000))
                        (:kernel+schemas
                         (start-recursive-synthesis frame lang 130 :self-name id :max-depth 2 :heuristic-budget 15000
                                                                   :expanders (list (recursion-schema-expander))))
                        (:lib-grammar           ; library functions are plain operators; no lifting proposals
                         (start-recursive-synthesis frame lang 130 :self-name id :max-depth 2 :heuristic-budget 15000))
                        (:lib-proposals         ; kernel chooses which library combinator to lift
                         (start-recursive-synthesis frame lang 130 :self-name id :max-depth 2 :heuristic-budget 15000
                                                                   :library-proposals-p t))
                        (:lib-grammar+proposals
                         (start-recursive-synthesis frame lang 130 :self-name id :max-depth 2 :heuristic-budget 15000
                                                                   :library-proposals-p t))
                        (:lib-nonrec
                         (start-heuristic-synthesis frame lang 130 :max-depth 2 :library-proposals-p t)))
                    (error (e) (format t "   START-ERROR ~A~%" e) nil))))
        (declare (ignore _))
        (when job
          (handler-case (resume-synthesis job budget :stop-on-first t)
            (error (e) (format t "   RUN-ERROR ~A~%" e))))
        (let* ((best (and job (synthesis-job-best job)))
               (expr (and best (candidate-expression best)))
               (sound (and best
                           (ignore-errors
                            (destructuring-bind (args want) held
                              (if (synthesis-job-self-name job)
                                  (progn (commit-synthesis-job job :name id)
                                         (let ((run (evaluate (apply #'app (op id) (loop for v in args collect (lit *seq* v)))
                                                              nil nil :budget 50000)))
                                           (and (eq :value (evaluation-status run)) (equal want (evaluation-value run)))))
                                  (multiple-value-bind (v ok) (eval-expr-value expr inputs args)
                                    (and ok (equal want v))))))))
               (calls (and expr (loop for f in (append *lib-fns* '(:positions :scan-pair :shift-seq :seq-corr :best-shift :argmax-corr :last-or))
                                      when (expression-calls-operator-p expr f) collect f)))
               (chain (and job (job-winning-node job)
                           (loop for cur = (job-winning-node job) then (synthesis-node-parent cur)
                                 while cur for p = (synthesis-node-proposal cur)
                                 when p collect (let ((n (decomposition-name p))) (if (consp n) (first n) n))))))
          (format t "~&~10A ~22A -> ~8A work=~10:D nodes=~3D msgs=~4D nogoods=~2D reused=~2D bits=~4A calls=~S chain=~S ~,2Fs~%"
                  id regime (cond ((null job) "ERROR") ((null best) "no") (sound "SOUND") (t "UNSOUND"))
                  (if job (ledger-total (synthesis-job-ledger job)) 0)
                  (if job (length (synthesis-job-nodes job)) 0)
                  (if job (length (synthesis-job-messages job)) 0)
                  (if job (length (synthesis-job-nogoods job)) 0)
                  (if job (synthesis-job-reused-subproblems job) 0)
                  (and best (candidate-size best)) calls chain
                  (/ (- (get-internal-real-time) t0) internal-time-units-per-second))
          (when expr (format t "             ~S~%" (ast->sexp expr)))
          (finish-output))))))

(dolist (task *tasks*)
  (dolist (regime '(:kernel-only :kernel+schemas :lib-grammar :lib-proposals :lib-grammar+proposals :lib-nonrec))
    (run-task task regime cl-user::*budget*))
  (terpri))
