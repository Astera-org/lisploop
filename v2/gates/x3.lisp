;;; Gate X3 (plan_v2c.md section 11.2): the 16-spec ladder.
;;;
;;;   sbcl --dynamic-space-size 16000 --script gates/x3.lisp [quick]
;;;
;;; The specs and their rows are those of the present kernel's bootstrap, as recorded in
;;; ../baselines/x3/x3-specs.lisp. They are given as plain rows of inputs and output: no operator
;;; whitelist, no recursion schema, and no use of the fact that the rows are closed under the
;;; library's recursion. The grammar is every operator of this kernel, and every function of the
;;; ladder that this kernel has itself solved before the spec in hand.
;;;
;;; Held-out scoring uses both of the recorded procedures: the 200 inputs of
;;; plan_v2c_audit/verify-review, and the one hand-written input of the Stage 0 harness. A
;;; program is sound when it is right on all 201.

(load (merge-pathnames "common.lisp" (make-pathname :name nil :type nil :defaults *load-truename*)))
(in-package #:lisploop2)

(defparameter *quick* (member "quick" sb-ext:*posix-argv* :test #'string=))

(defstruct spec task held-out)

(defun read-specs ()
  "The sixteen specs in the order of the ladder, each with its 201 held-out rows."
  (let ((held-out (read-forms (baseline-path "x3/x3-heldout.lisp"))))
    (loop for form in (read-forms (baseline-path "x3/x3-specs.lisp"))
          for name = (getf form :name)
          for task = (read-task name (getf form :params) (getf form :returns) (getf form :rows))
          for types = (mapcar #'term-type (task-params task))
          for more = (getf (find name held-out :key (lambda (f) (getf f :name))) :rows)
          collect (make-spec
                   :task task
                   :held-out (loop for (inputs output) in (cons (getf form :harness-held-out-case) more)
                                   collect (cons (mapcar #'read-value inputs types)
                                                 (read-value output (task-returns task))))))))

(defun held-out-score (program spec)
  (count-if (lambda (row) (cell= (cdr row) (program-value program (spec-task spec) row :fuel 1000000)))
            (spec-held-out spec)))

(defstruct result name outcome score verdict)

(defun verdict (outcome score total)
  "How the gate counts an outcome."
  (let ((program (outcome-program outcome)))
    (ecase (outcome-status outcome)
      (:solved (if (= score total) :sound :impostor))
      (:underdetermined (if program :underdetermined-with-a-fit :underdetermined))
      (:unsolved :unsolved)
      (:unverified :defect))))

(defun run-ladder (specs &key (budget 400000000) (ladder t) (label ""))
  "Solve the specs in order. With LADDER each solved function joins the library for the specs
after it; without, every spec starts from an empty library. Returns a list of RESULTs."
  (let ((*library* '()) (results '()) (t0 (get-internal-real-time)))
    (dolist (spec specs)
      (let* ((task (spec-task spec))
             (outcome (solve-task task :budget budget))
             (program (outcome-program outcome))
             (total (length (spec-held-out spec)))
             (score (and program (held-out-score program spec))))
        (push (make-result :name (task-name task) :outcome outcome :score score
                           :verdict (verdict outcome score total))
              results)
        (when (and ladder (eq :solved (outcome-status outcome)))
          (define-from-task task program))))
    (setf results (nreverse results))
    (format t "~%--- ~a: budget ~:d cells per spec, ~:[each spec alone~;ladder~]; ~,1f s ---~%"
            label budget ladder (seconds-since t0))
    results))

(defun count-verdict (results verdict) (count verdict results :key #'result-verdict))

(defun summary-line (results)
  (format nil "sound ~d, underdetermined ~d (with a fit ~d), unsolved ~d, impostors ~d, defects ~d; work ~:d"
          (count-verdict results :sound)
          (+ (count-verdict results :underdetermined) (count-verdict results :underdetermined-with-a-fit))
          (count-verdict results :underdetermined-with-a-fit)
          (count-verdict results :unsolved) (count-verdict results :impostor)
          (count-verdict results :defect)
          (reduce #'+ results :key (lambda (r) (outcome-work (result-outcome r))))))

(defun print-details (results)
  (dolist (r results)
    (let ((o (result-outcome r)))
      (format t "~%~a: ~a~@[, held-out ~d/201~]~@[, evidence ~,1f bits~]; work ~:d, ~,2f s~%~@[   ~a~%~]~@[   held, not accepted: ~a~%~]~{   note: ~a~%~}"
              (result-name r) (result-verdict r) (result-score r) (outcome-evidence o)
              (outcome-work o) (outcome-seconds o) (outcome-program o) (outcome-held o)
              (outcome-notes o)))))

(defun print-table (results)
  (format t "~%~14a ~28a ~9a ~14a ~9a~%" "spec" "outcome" "held-out" "work (cells)" "seconds")
  (dolist (r results)
    (let ((o (result-outcome r)))
      (format t "~14a ~28a ~9a ~14:d ~9,2f~%" (result-name r) (result-verdict r)
              (if (result-score r) (format nil "~d/201" (result-score r)) "-")
              (outcome-work o) (outcome-seconds o)))))

;;; ---------------------------------------------------------------------------------------------

(format t "Gate X3: the 16-spec ladder~%")
(format t "kernel: ~a~%" (lisp-implementation-version))

(let ((specs (read-specs)) (t0 (get-internal-real-time)))
  (format t "specs ~d; rows per spec ~{~d~^ ~}; held-out rows per spec ~d~%" (length specs)
          (mapcar (lambda (s) (length (task-rows (spec-task s)))) specs)
          (length (spec-held-out (first specs))))

  ;; the solvers of the inverse row come from the operators' own tables (gate X2)
  (setf *solvers* (integer-solvers))
  (format t "solvers found from operator tables for the inverse row: ~d (~,2f s)~%~{   ~a~%~}"
          (length *solvers*) (seconds-since t0)
          (mapcar (lambda (s) (format nil "~a = c, for ~a: ~a" (solver-term s) (solver-unknown s) (solver-answer s)))
                  *solvers*))

  ;; 1. the gate's own run
  (let ((main (run-ladder specs :budget 400000000 :label "1. the gate's run")))
    (print-table main)
    (format t "~%~a~%" (summary-line main))
    (print-details main)
    (let ((sound (count-verdict main :sound))
          (claimed (+ (count-verdict main :underdetermined)
                      (count-verdict main :underdetermined-with-a-fit))))
      (format t "~%GATE X3~%")
      (format t "  held-out-sound programs: ~d of 16~%" sound)
      (format t "  reported as underdetermined by their rows: ~d (~{~a~^, ~})~%" claimed
              (loop for r in main
                    when (member (result-verdict r) '(:underdetermined :underdetermined-with-a-fit))
                      collect (result-name r)))
      (format t "  sound, counting a correct report of underdetermination as sound: ~d of 16 (the gate asks for 14; today's kernel has 7 to 10)~%"
              (+ sound claimed))
      (format t "  programs returned as answers that fit the rows and fail held-out: ~d~%"
              (count-verdict main :impostor))
      (format t "  conditionals accepted: ~d, each only after every smaller term without one was ruled out~%"
              (count-if (lambda (r)
                          (let ((p (outcome-program (result-outcome r))))
                            (and p (eq :solved (outcome-status (result-outcome r)))
                                 (search "(if " (format nil "~a" p)))))
                        main))))

  (unless *quick*
    ;; 2. how the count moves with the budget
    (format t "~%~%=== 2. Budget ===~%")
    (dolist (budget '(1000000 10000000 100000000 1000000000))
      (let ((results (run-ladder specs :budget budget :label (format nil "budget ~:d" budget))))
        (format t "~a~%" (summary-line results))
        (format t "   by spec: ~{~a~^ ~}~%"
                (mapcar (lambda (r) (format nil "~(~a~):~a" (result-name r)
                                            (ecase (result-verdict r)
                                              (:sound "ok") (:impostor "IMPOSTOR") (:unsolved "-")
                                              (:underdetermined "u") (:underdetermined-with-a-fit "u+")
                                              (:defect "DEFECT"))))
                        results))))

    ;; 3. what each mechanism contributes
    (format t "~%~%=== 3. Ablations, at 400,000,000 cells ===~%")
    (flet ((ablate (label thunk)
             (let ((results (funcall thunk)))
               (format t "~a~%   ~a~%   differs from the gate's run on: ~{~a~^; ~}~%" label (summary-line results)
                       (or (loop for r in results
                                 unless (member (result-verdict r) '(:sound))
                                   collect (format nil "~(~a~) ~(~a~)~@[ ~d/201~]" (result-name r)
                                                   (result-verdict r) (result-score r)))
                           '("nothing"))))))
      (ablate "each spec alone, with an empty library"
              (lambda () (run-ladder specs :ladder nil :label "no ladder")))
      (ablate "without reorienting a requirement onto the columns that determine it"
              (lambda () (let ((*use-projection* nil)) (run-ladder specs :label "no reorientation of requirements"))))
      (ablate "without the inverse row"
              (lambda () (let ((*use-inverses* nil)) (run-ladder specs :label "no inverse row"))))
      (ablate "without the evidence rule"
              (lambda () (let ((*use-evidence* nil)) (run-ladder specs :label "no evidence rule"))))
      (ablate "accepting the first fit, without confirming it against smaller terms"
              (lambda () (let ((*confirm-ratio* 0)) (run-ladder specs :label "no confirmation")))))

    ;; 4. what the size-order rule costs, with and without the look-ahead
    (format t "~%~%=== 4. The size-order rule and the look-ahead ===~%")
    (format t "With TRY in the grammar no spec of the ladder needs a conditional, so the rule is measured in two other ways.~%")
    (format t "~%(a) Five small tasks whose answer is a conditional, over + - * / mod < =. 'found' is the work at which the conditional first fitted and was held; 'accepted' is the work at which every smaller term without a conditional had been ruled out.~%")
    (flet ((rows-of (function inputs) (loop for input in inputs collect (list input (apply function input))))
           (stamp (outcome what)
             ;; the work recorded in the note that says the conditional was held, or accepted
             (let ((note (find-if (lambda (n) (search what n)) (outcome-notes outcome))))
               (and note (parse-integer (remove #\, (subseq note (+ 4 (search ": at " note))
                                                            (search " cells" note))))))))
      (let ((pairs '((3 5) (5 3) (-2 4) (4 -2) (0 0) (7 7) (-3 -8) (-8 -3) (1 2) (2 1) (6 -6) (-6 6)
                     (9 1) (0 5) (5 0) (-1 -1)))
            (*grammar* '(+ - * / mod < =)) (*library* '()) (*solvers* '()))
        (format t "~10a ~38a ~9a ~12a ~8a ~14a ~8a~%" "task" "answer" "found" "accepted" "ratio" "no look-ahead" "saving")
        (loop for (name params rows)
                in (list (list 'magnitude '((x0 :int)) (rows-of #'abs '((3) (-2) (0) (7) (-5) (1) (-1) (-9) (4) (-6))))
                         (list 'larger '((x0 :int) (x1 :int)) (rows-of #'max pairs))
                         (list 'clamp-low '((x0 :int) (x1 :int)) (rows-of (lambda (x lo) (if (< x lo) lo x)) pairs))
                         (list 'gap '((x0 :int) (x1 :int)) (rows-of (lambda (p q) (abs (- p q))) pairs))
                         (list 'safe-div '((x0 :int) (x1 :int))
                               (rows-of (lambda (p q) (if (zerop q) 0 (truncate p q))) pairs)))
              do (let* ((on (solve-task (read-task name params :int rows) :budget 400000000))
                        (off (let ((*use-lookahead* nil))
                               (solve-task (read-task name params :int rows) :budget 400000000)))
                        (found (stamp on "is held under")) (accepted (stamp on "is accepted")))
                   (format t "~10a ~38a ~9:d ~12:d ~7,0fx ~14:d ~7,2fx~%" name (outcome-program on)
                           found accepted (/ accepted (max 1 found)) (stamp off "is accepted")
                           (/ (stamp off "is accepted") (max 1 accepted)))))))
    (format t "~%(b) shift-seq with TRY out of the grammar, alone, at 1,000,000,000 cells.~%")
    (let ((*grammar* (remove 'try *grammar*))
          (spec (find 'shift-seq specs :key (lambda (s) (task-name (spec-task s))))))
      (dolist (lookahead '(t nil))
        (let* ((*use-lookahead* lookahead) (*library* '())
               (outcome (solve-task (spec-task spec) :budget 1000000000)))
          (format t "look-ahead ~:[off~;on~]: ~a, ~:d cells, ~,1f s~%~{   ~a~%~}" lookahead
                  (outcome-status outcome) (outcome-work outcome) (outcome-seconds outcome)
                  (remove-if-not (lambda (n) (or (search "held" n) (search "most a task may store" n)))
                                 (outcome-notes outcome)))))))
  (format t "~%total time ~,1f s~%" (seconds-since t0)))
