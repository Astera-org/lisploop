(in-package #:lisploop)

;;; ===========================================================================
;;; A job's messages as rows (messages.lisp): what staged work notes, when a job sends
;;; it, and frames built from the rows
;;; ===========================================================================

(defun idle-input-scan-fixture ()
  "A running sum from an initial state with one input that nothing depends on (plan 8,
probe 5), and its language. Defines `:scan`, so call it inside a clean kernel state."
  (let* ((seq (sequence-type :int))
         (step (code-type '((0 . :int) (1 . :int)) :int))
         (inputs (list (cons 0 seq) (cons 1 :int) (cons 2 :int))))
    (define-function :scan (list (cons 0 seq) (cons 1 :int) (cons 2 step)) seq
      (lambda (self)
        (let* ((actions (var 0 seq)) (state (var 1 :int)) (step (var 2 step))
               (next (term `(code-eval ,step ,state (at ,actions 0)))))
          (term `(if (= ,actions ()) () (cons ,next (,self (tail ,actions) ,next ,step))) seq))))
    (values (simple-frame seq inputs '((((1 1) 0 7) (1 2)) (((2 -1 3) 1 9) (3 2 5)) (((-2 4) 5 3) (3 7))))
            (make-language :int inputs
                           :operators (list (op :+ :int) (op :* :int) (op :scan))
                           :literals '(0 1)))))

(defun guarded-exception-fixture ()
  "A frame over three integers whose target keeps one of them unless the other two add up
to it (plan 8, probe 4), and its language: Stage A finds models and buckets for it in stages."
  (let ((inputs '((0 . :int) (1 . :int) (2 . :int))))
    (values (simple-frame :int inputs
                          (loop for (s0 s1 a) in '((0 2 1) (1 2 1) (2 3 1) (3 4 -1) (2 4 -1) (5 2 -1) (3 2 -1))
                                collect (list (list s0 s1 a) (if (= (+ s0 a) s1) (+ s1 a) s1))))
            (make-language :int inputs
                           :operators (list (op :+ :int) (op :- :int) (op := :int) (op :if :int))
                           :literals '(0 1)))))

(defun stage-a-quantum-series (history quantum spent)
  "From HISTORY, what a Stage A search that spent SPENT found and when, what it had at the
end of each quantum: (best-score-or-nil buckets)."
  (loop for end from quantum by quantum
        collect (list (let ((scores (loop for (kind work bits residual) in history
                                          when (and (eq kind :model) (<= work end))
                                            collect (+ bits residual))))
                        (and scores (reduce #'min scores)))
                      (loop for (kind work) in history
                            count (and (eq kind :bucket) (<= work end))))
        until (>= end spent)))

(deftest a-stage-a-search-notes-what-it-found-and-when
  "The history `condense-heuristic` notes gives, for any quantum, what the same search shows
when it is resumed in quanta of that size: the replay that plan9-audit.md Appendix C made
by redefining the function. Nothing is noted outside staged work."
  (with-clean-kernel-state
    (multiple-value-bind (frame language) (guarded-exception-fixture)
      (let ((limit 6000) (quantum 500))
        (check (eq :none *noted*))
        (condense-heuristic frame language :work-limit limit :ledger (make-ledger))
        (check (eq :none *noted*))
        (let* ((event (let ((*noted* nil))
                        (condense-heuristic frame language :work-limit limit :ledger (make-ledger))
                        (check (= 1 (length *noted*)))
                        (first *noted*)))
               (evidence (rest event))
               (job (start-heuristic-search frame language))
               (replayed (loop for end from quantum by quantum
                               do (resume-heuristic-search job end)
                               collect (list (and (heuristic-search-best job)
                                                  (heuristic-score (heuristic-search-best job)))
                                             (length (observation-job-buckets
                                                      (heuristic-search-observation job))))
                               until (>= end limit))))
          (check (eq :stage-a (first event)))
          (check (= limit (getf evidence :work-limit)))
          (check (= (ledger-total (heuristic-search-ledger job)) (getf evidence :spent)))
          ;; The search improves its model twice and adds buckets over several quanta, and
          ;; the history tells it quantum by quantum.
          (check (= 4 (length (remove-duplicates (mapcar #'first replayed)))))
          (check (< 3 (length (remove-duplicates (mapcar #'second replayed)))))
          (check (equal replayed
                        (stage-a-quantum-series (getf evidence :history) quantum
                                                (getf evidence :spent)))))))))

(deftest a-job-publishes-noted-events-when-their-work-is-paid
  "Every published node has a :node row, and each Stage A search a :stage-a row that is sent
only once the job has been charged for it. The rows do not depend on how the job was
stepped, and the verified candidate's node leads back to the root through them."
  (with-clean-kernel-state
    (multiple-value-bind (frame language) (idle-input-scan-fixture)
      (flet ((start ()
               (start-heuristic-synthesis frame language 90
                                          :library-proposals-p t :library-functions '(:scan))))
        (multiple-value-bind (batch stepped)
            (check-synthesis-resumption #'start :budget 200000 :stop-on-first t)
          (check (synthesis-job-best batch))
          (dolist (relation '(:node :stage-a :stage-a-bucket :stage-a-model :verified))
            (check (equal (message-rows relation batch) (message-rows relation stepped))))
          (let ((nodes (message-rows :node batch))
                (searches (message-rows :stage-a batch)))
            (check (equal (mapcar #'second nodes)
                          (loop for node in (synthesis-job-nodes batch)
                                when (member (synthesis-node-phase node) '(:search :done))
                                  collect (synthesis-node-id node))))
            (check searches)
            ;; A search's own work is part of what the job paid before its row was sent.
            (loop for (nil nil at nil spent) in searches
                  do (check (>= at spent)))
            (check (<= (reduce #'+ searches :key #'fifth) (ledger-total (synthesis-job-ledger batch))))
            (check (message-rows :stage-a-bucket batch))
            (check (message-rows :stage-a-model batch))
            (let ((verified (message-rows :verified batch)))
              (check (= 1 (length verified)))
              (check (= (third (first verified)) (ledger-total (synthesis-job-ledger batch))))
              (check (loop for node = (second (first verified))
                             then (third (find node nodes :key #'second))
                           repeat (length nodes)
                           thereis (zerop node))))))
        ;; A job stopped part way shows nothing it has not been charged for.
        (let ((job (start)))
          (resume-synthesis job 1500)
          (check (loop for (nil nil at nil spent) in (message-rows :stage-a job)
                       always (<= spent at 1500))))))))

(deftest a-message-frame-is-an-ordinary-frame
  "Rows of object-language values make a frame the kernel treats like any other: its conflict
check says whether one column is a function of others, a search finds that function, and a
rule about the rows is an expression the VM evaluates on them."
  (let* ((columns '((:quantum . :int) (:buckets . :int) (:improved-p . :bool) (:needed-p . :bool)))
         (rows '((1 2 t t) (2 2 nil nil) (3 2 nil nil) (1 0 nil nil) (2 5 nil t) (4 5 nil t) (5 5 nil nil))))
    ;; Two rows agree on (:improved-p) and differ on :needed-p: no rule over it can be exact.
    (let ((conflict (frame-conflict-p (message-frame columns rows :needed-p :inputs '(:improved-p)))))
      (check conflict)
      (check (eq :incompatible-rows (frame-conflict-kind conflict)))
      (check (equal '(nil) (frame-conflict-known conflict))))
    (let* ((frame (message-frame columns rows :needed-p :inputs '(:quantum :buckets)))
           (inputs (schema-inputs (frame-schema frame)))
           (language (make-language :int inputs :operators (list (op :< :int) (op :+ :int)) :literals '(0 1)))
           (wanted (term `(< ,(var 0 :int) ,(var 1 :int))))
           (job (start-search frame language)))
      (check (equal '((0 . :int) (1 . :int)) inputs))
      (check (eq :bool (schema-target (frame-schema frame))))
      (check (null (frame-conflict-p frame)))
      (resume-search job (description-size wanted inputs) 200000)
      (let ((rule (candidate-expression (search-job-best job))))
        (check (equal rule wanted))
        (check (equal (mapcar #'fourth rows)
                      (loop for (quantum buckets) in rows
                            collect (eval-expr-value rule inputs (list quantum buckets)))))))
    (raises (message-frame columns rows :missing))
    (raises (message-rows :no-such-reader nil))))

(deftest a-message-frame-projects-mixed-tuple-and-code-columns
  "Heterogeneous `:tuple` `:at` carries zero extra bits over homogeneous `:tuple` `:at`,
agrees between the VM and compiled closures (including dynamic slot-type errors), folds only
matching slots, and lets `message-frame` carry mixed tuple and `:code` columns."
  (let* ((code-t (code-type '((0 . :int)) :int))
         (mixed (tuple-type :int :bool code-t))
         (at-int (op :at (tuple-type mixed :int)))
         (at-bool (op :at (tuple-type mixed :bool)))
         (at-code (op :at (tuple-type mixed code-t)))
         (inputs (list (cons 0 mixed) (cons 1 :int)))
         (proj-bool (term `(at ,(var 0 mixed) 1)))
         (dyn-int (app at-int (var 0 mixed) (var 1 :int)))
         (fn-lit (lit (code-type nil (operator-type at-bool)) at-bool))
         (inc-ast (term `(+ ,(var 0 :int) 1)))
         (dbl-ast (term `(* ,(var 0 :int) 2))))
    ;; 1. Zero extra bits in operator encoding and full packet + sexp roundtrips.
    (check (= (operator-bit-size :at (tuple-type (tuple-type :int :bool) :bool))
              (operator-bit-size :at (tuple-type :int :int))))
    (dolist (expr (list proj-bool dyn-int fn-lit))
      (multiple-value-bind (decoded dec-inputs)
          (decode-model (encode-model expr inputs))
        (check (equal expr decoded))
        (check (equal inputs dec-inputs)))
      (check (equal expr (sexp->ast (ast->sexp expr)))))
    ;; 2. VM and closure parity on valid slots and dynamic out-of-type slot errors.
    (check (expression-closure dyn-int inputs))
    (let ((ok-row (list (list 42 t inc-ast) 0))
          (bad-slot-row (list (list 42 t inc-ast) 1))
          (oob-row (list (list 42 t inc-ast) 5)))
      (dolist (row (list ok-row bad-slot-row oob-row))
        (let ((vm-run (let ((*closure-evaluation* nil)) (evaluate dyn-int inputs row)))
              (cl-run (let ((*closure-evaluation* t)) (evaluate dyn-int inputs row))))
          (check (eq (evaluation-status vm-run) (evaluation-status cl-run)))
          (check (equal (evaluation-value vm-run) (evaluation-value cl-run)))
          (check (= (evaluation-work vm-run) (evaluation-work cl-run)))))
      (check (= 42 (eval-expr-value dyn-int inputs ok-row)))
      (check (eq :error (evaluation-status (evaluate dyn-int inputs bad-slot-row))))
      (check (eq :error (evaluation-status (evaluate (app at-code (var 0 mixed) (lit :int 0))
                                                     inputs ok-row)))))
    ;; 3. Constant folding folds matching slots and leaves mismatched slot indices intact.
    (let* ((f-inputs (list (cons 0 :int) (cons 1 :bool) (cons 2 code-t)))
           (tup-expr (app (op :tuple mixed) (var 0 :int) (var 1 :bool) (var 2 code-t))))
      (check (equal (var 1 :bool) (fold-constants (app at-bool tup-expr (lit :int 1)))))
      (check (equal (var 2 code-t) (fold-constants (app at-code tup-expr (lit :int 2)))))
      (let ((mismatch (fold-constants (app at-bool tup-expr (lit :int 0)))))
        (check (app-of-p mismatch :at))
        (check (eq :error (evaluation-status (evaluate mismatch f-inputs (list 7 t inc-ast)))))))
    ;; 4. Mixed-column message-frame + heterogeneous component-bindings.
    (let* ((pair-t (tuple-type :int :bool))
           (cols (list (cons :pair pair-t) (cons :fn code-t) (cons :out :int)))
           (rows (list (list '(10 t) inc-ast 11)
                       (list '(10 nil) dbl-ast 0)
                       (list '(6 t) dbl-ast 12)))
           (frame (message-frame cols rows :out :inputs '(:pair :fn)))
           (m-inputs (schema-inputs (frame-schema frame)))
           (bindings (component-bindings m-inputs)))
      (check (= 3 (length bindings)))
      (check (equal (list :int :bool code-t)
                    (mapcar (lambda (b) (ast-type (cdr b))) bindings)))
      (let ((rule (term `(if (at ,(var 0 pair-t) 1)
                             (code-eval ,(var 1 code-t) (at ,(var 0 pair-t) 0))
                             0))))
        (check (equal '(11 0 12)
                      (loop for row in (frame-rows frame)
                            collect (eval-expr-value rule m-inputs (row-known row)))))))))
