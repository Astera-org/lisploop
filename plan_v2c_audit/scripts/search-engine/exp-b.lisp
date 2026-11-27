;;; EXP-B: does a larger top-level budget rescue a spec that fails at the shipped budget?
;;; Args: SPEC BOUND MAX-DEPTH(or nil) HEURISTIC-BUDGET MAX-WORK WALL-SECONDS SCHEMAS(0/1) [CONDENSE-BUDGET]
;;; Read-only with respect to the repository: loads sources, writes nothing.
(load "/home/tlh24/lisploop/load.lisp")
(load "/home/tlh24/lisploop/bootstrap/recursion-schemas.lisp")
(in-package #:lisploop)
(clear-knowledge-library)

(defparameter *args* (rest sb-ext:*posix-argv*))
(defun arg (n) (nth n *args*))
(defun int-arg (n) (let ((a (arg n))) (if (or (null a) (string= a "nil")) nil (parse-integer a))))

(defparameter *seq-t* (sequence-type :int))
(defparameter *bin-t* (code-type '((0 . :int) (1 . :int)) :int))

(defun spec-data (name)
  "(inputs target rows operators literals constants) copied from bootstrap/build-batteries.lisp."
  (let ((sub-step (term `(- ,(var 0 :int) ,(var 1 :int))))
        (add-step (term `(+ ,(var 0 :int) ,(var 1 :int)))))
    (cond
      ((string= name "map-adjacent")
       (list (list (cons 0 *seq-t*) (cons 1 *bin-t*)) *seq-t*
             (list (list (list '() sub-step) '())
                   (list (list '(9) sub-step) '())
                   (list (list '(4 9) sub-step) '(5))
                   (list (list '(1 4 9) sub-step) '(3 5))
                   (list (list '() add-step) '())
                   (list (list '(5) add-step) '())
                   (list (list '(2 5) add-step) '(7))
                   (list (list '(1 2 5) add-step) '(3 7)))
             (list (op :cons :int) (op :tail :int) (op :at *seq-t*) (op := *seq-t*)
                   (op :if *seq-t*) (op :code-eval *bin-t*))
             nil (list (lit *seq-t* '()))))
      ((string= name "scan")
       (list (list (cons 0 *seq-t*) (cons 1 :int) (cons 2 *bin-t*)) *seq-t*
             (list (list (list '() 4 add-step) '())
                   (list (list '() 5 add-step) '())
                   (list (list '() 2 add-step) '())
                   (list (list '(3) 2 add-step) '(5))
                   (list (list '(-1 3) 3 add-step) '(2 5))
                   (list (list '(2 -1 3) 1 add-step) '(3 2 5))
                   (list (list '() 6 sub-step) '())
                   (list (list '(4) 10 sub-step) '(6))
                   (list (list '(1 4) 11 sub-step) '(10 6)))
             (list (op :cons :int) (op :tail :int) (op :at *seq-t*)
                   (op := *seq-t*) (op :if *seq-t*) (op :code-eval *bin-t*))
             nil (list (lit *seq-t* '()))))
      ((string= name "positions")
       (list (list (cons 0 *seq-t*) (cons 1 :int)) *seq-t*
             '(((() 0) ()) ((() 1) ()) ((() 2) ()) ((() 3) ()) ((() 4) ())
               (((7) 2) (2)) (((4) 3) (3)) (((7) 0) (0))
               (((6 7) 1) (1 2)) (((9 4) 2) (2 3)) (((5 6 7) 0) (0 1 2)))
             (list (op :cons :int) (op :tail :int) (op :at *seq-t*) (op := *seq-t*)
                   (op :if *seq-t*) (op :+ :int))
             '(0 1) (list (lit *seq-t* '()))))
      (t (error "unknown spec ~A" name)))))

(defun short (x &optional (n 70))
  (let ((s (with-standard-io-syntax (let ((*print-pretty* nil)) (prin1-to-string x)))))
    (if (> (length s) n) (concatenate 'string (subseq s 0 n) "...") s)))

(defun dump-job (job)
  (let ((nodes (synthesis-job-nodes job)))
    (format t "  nodes=~D by-phase=~S expansions=~S deferred-total=~D pending=~D~%"
            (length nodes)
            (loop for ph in '(:prepare :preparation :search :done)
                  collect (cons ph (count ph nodes :key #'synthesis-node-phase)))
            (loop for ex in '(nil :paying :done)
                  collect (cons ex (count ex nodes :key #'synthesis-node-expansion)))
            (loop for n in nodes sum (length (synthesis-node-deferred-proposals n)))
            (length (synthesis-job-pending job)))
    (format t "  nogoods=~D reused-subproblems=~D messages=~D trace-entries=~D~%"
            (length (synthesis-job-nogoods job)) (synthesis-job-reused-subproblems job)
            (length (synthesis-job-messages job)) (length (synthesis-job-trace job)))
    (format t "  claims=~S~%"
            (let ((table nil))
              (dolist (m (synthesis-job-messages job) table)
                (let ((e (assoc (message-claim m) table)))
                  (if e (incf (cdr e)) (push (cons (message-claim m) 1) table))))))
    (dolist (n nodes)
      (let* ((search (synthesis-node-search n))
             (p (synthesis-node-proposal n))
             (frame (synthesis-node-frame n)))
        (format t "  node ~3D parent=~3A depth=~D phase=~8A exp=~6A bound=~4A prio=~A rows=~A inputs=~A~%      proposal=~A~%      search: ~A~%"
                (synthesis-node-id n)
                (and (synthesis-node-parent n) (synthesis-node-id (synthesis-node-parent n)))
                (node-depth n) (synthesis-node-phase n) (synthesis-node-expansion n)
                (synthesis-node-bound n)
                (let ((pr (synthesis-node-priority n)))
                  (cond ((null pr) "-") ((>= pr most-positive-fixnum) "MAX") (t pr)))
                (and frame (length (frame-rows frame)))
                (and frame (length (schema-inputs (frame-schema frame))))
                (short (and p (decomposition-name p)) 110)
                (if search
                    (format nil "work=~D completed-bound=~D header=~D rejected=~D results=~D enum-size=~A syntax=~A"
                            (ledger-total (search-job-ledger search))
                            (search-job-completed-bound search)
                            (language-header-size (search-job-language search)
                                                  (schema-target (frame-schema (search-job-frame search))))
                            (search-job-rejected search)
                            (length (search-job-results search))
                            (and (search-job-enumerator search) (enumerator-size (search-job-enumerator search)))
                            (and (search-job-enumerator search)
                                 (loop for b being the hash-values of
                                       (enumerator-buckets (search-job-enumerator search))
                                       sum (length b))))
                    (format nil "none~@[ (follows node ~D)~]" (synthesis-node-reused-from n))))))))

(let* ((name (arg 0))
       (bound (int-arg 1)) (max-depth (int-arg 2)) (hb (int-arg 3))
       (max-work (int-arg 4)) (wall (int-arg 5))
       (schemas-p (equal (arg 6) "1"))
       (condense (or (int-arg 7) 20000))
       (quantum (or (int-arg 8) 32))
       (data (spec-data name))
       (id (intern (string-upcase name) :keyword)))
  (destructuring-bind (inputs target rows ops lits consts) data
    (let* ((lib (make-knowledge-library)))
      (with-knowledge-library (lib)
        (let* ((spec (register-knowledge-spec (keyword-id "SPEC/~A" id) inputs target rows
                                              :target-id id :operators ops :literals lits
                                              :constants consts :library lib))
               (frame (spec-entry-frame spec))
               (lang (make-language :int inputs :operators ops :literals lits :constants consts))
               (job (start-recursive-synthesis frame lang bound
                                               :self-name id :max-depth max-depth
                                               :heuristic-budget hb
                                               :condense-budget condense
                                               :quantum quantum
                                               :expanders (when schemas-p (list (recursion-schema-expander)))))
               (start (get-internal-real-time))
               (chunk 1000000)
               (status :cutoff))
          (format t "SPEC ~A bound=~A max-depth=~A heuristic-budget=~A condense-budget=~A max-work=~A wall=~A schemas=~A~%"
                  name bound max-depth hb condense max-work wall schemas-p)
          (loop
            (let ((limit (min max-work (+ (ledger-total (synthesis-job-ledger job)) chunk))))
              (resume-synthesis job limit :stop-on-first t))
            (let ((elapsed (/ (- (get-internal-real-time) start) (float internal-time-units-per-second))))
              (cond ((synthesis-job-best job) (setf status :solved) (return))
                    ((synthesis-finished-p job) (setf status :finished-without-solution) (return))
                    ((>= (ledger-total (synthesis-job-ledger job)) max-work) (setf status :work-cutoff) (return))
                    ((>= elapsed wall) (setf status :wall-cutoff) (return)))))
          (let ((elapsed (/ (- (get-internal-real-time) start) (float internal-time-units-per-second))))
            (format t "RESULT status=~S work=~D wall_s=~,2F work/s=~,0F~%"
                    status (ledger-total (synthesis-job-ledger job)) elapsed
                    (/ (ledger-total (synthesis-job-ledger job)) (max elapsed 0.001)))
            (format t "  quantum=~D heap_MiB=~,1F best-bits=~A best-run-work=~A~%" quantum
                    (/ (sb-kernel:dynamic-usage) 1048576.0)
                    (and (synthesis-job-best job) (candidate-size (synthesis-job-best job)))
                    (and (synthesis-job-best job) (candidate-run-work (synthesis-job-best job))))
            (format t "  best=~A~%" (and (synthesis-job-best job)
                                        (short (ast->sexp (candidate-expression (synthesis-job-best job))) 300)))
            (format t "  ledger=~S~%" (sort (copy-list (ledger-counts (synthesis-job-ledger job))) #'> :key #'cdr))
            (dump-job job)))))))
