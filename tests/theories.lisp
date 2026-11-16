(in-package #:lisploop)

;;; Plan 8, P8.4: theory motifs over folds, and the amortization of library entries.

(deftest monoid-motif-transfers-between-folds
  "Functions refactored through one fold whose steps share associativity and an identity are
instances of one motif relating that fold to another. A later instance inherits the equation
as a replayed conjecture without any search; a step without the laws inherits nothing."
  (with-clean-kernel-state
    (define-standard-int-combinators :which '(:foldr :foldl))
    (let* ((seq (sequence-type :int))
           (xs (var 0 seq))
           (a (var 0 :int)) (b (var 1 :int)) (c (var 2 :int))
           (step-type (code-type '((0 . :int) (1 . :int)) :int))
           (samples '((0 0 0) (1 2 3) (-2 5 7) (4 -1 2))))
      (labels ((fold-function (name operator identity)
                 (define-function name (list (cons 0 seq)) :int
                   (app (op :foldr) xs (lit :int identity) (lit step-type (app operator a b))))
                 (add-knowledge-edge name :refactored-by :foldr)
                 (add-knowledge-edge :foldr :abstracts name))
               (sampled-law (inputs left right)
                 ;; Integer laws can only be sampled, so they are registered as conjectures.
                 (register-knowledge-law
                  (resume-law-validation
                   (start-law-validation (make-law :int inputs left right)
                                         :samples (mapcar (lambda (sample) (subseq sample 0 (length inputs)))
                                                          samples))
                   100000)))
               (associativity (operator)
                 (sampled-law (arithmetic-inputs :int 3)
                              (app operator (app operator a b) c) (app operator a (app operator b c))))
               (identity-law (operator identity)
                 (sampled-law (arithmetic-inputs :int 1) (app operator a (lit :int identity)) a))
               (entries () (length (knowledge-library-entries *knowledge-library*)))
               (folds (name list)
                 (list (result (app (op name) (lit seq list)))
                       (result (app (op :foldl) (lit seq list)
                                    (second (rest (knowledge-entry-expression (find-knowledge-entry name))))
                                    (third (rest (knowledge-entry-expression (find-knowledge-entry name)))))))))
        ;; 1. One operator is not a theory: its star is recorded and nothing is quotiented.
        (fold-function :sum (op :+ :int) 0)
        (associativity (op :+ :int))
        (identity-law (op :+ :int) 0)
        (check (null (induce-fold-motifs *knowledge-library*)))
        (check (null (knowledge-entries-of-kind :motif)))
        (check (equal '((:associative :+)) (knowledge-edges-from :law-0 :associative)))
        (check (equal '((:identity :+ (0))) (knowledge-edges-from :law-1 :identity)))
        ;; 2. A second operator with the same star forms the motif and transfers it to both.
        (fold-function :product (op :* :int) 1)
        (associativity (op :* :int))
        (identity-law (op :* :int) 1)
        (let* ((added (induce-fold-motifs *knowledge-library*))
               (motif (first (knowledge-entries-of-kind :motif))))
          (check (equal '(:motif :law :law) (mapcar #'knowledge-entry-kind added)))
          (check (eq :foldr=foldl/monoid (knowledge-entry-id motif)))
          (check (eq :conjecture (knowledge-entry-status motif)))
          (check (equal '((:instance :sum) (:instance :product)) (knowledge-edges-from motif :instance)))
          (dolist (name '(:sum :product))
            (let ((law (find-knowledge-entry (keyword-id "~A/VIA-FOLDL" name))))
              (check (eq :conjecture (knowledge-entry-status law)))
              (check (not (knowledge-evidence-current-p law :equivalence)))
              (check (equal '((:induced-by :foldr=foldl/monoid)) (knowledge-edges-from law :induced-by)))
              ;; The equation holds on sequences the probes never visited.
              (dolist (list '((7 -3 2 9 4) (6)))
                (check (apply #'= (folds name list))))))
          ;; The motif is itself a relation the VM decides: true of a monoid, false of subtraction.
          (flet ((holds-p (operator base)
                   (evaluation-value (consume-knowledge-entry motif (list '(3 4 5) base (app operator a b))))))
            (check (holds-p (op :+ :int) 0))
            (check (holds-p (op :* :int) 1))
            (check (not (holds-p (op :- :int) 0))))
          ;; 3. Consolidating again is a fixed point, in the pass and in the whole library.
          (let ((count (entries)))
            (check (null (induce-fold-motifs *knowledge-library*)))
            (consolidate-knowledge-library *knowledge-library*)
            (check (= count (entries))))
          ;; 4. A later instance over a defined operator inherits the equation with no search.
          (define-function :shift-add (arithmetic-inputs :int) :int (term `(+ (+ ,a ,b) 1)))
          (fold-function :shifted-sum (op :shift-add) -1)
          (associativity (op :shift-add))
          (identity-law (op :shift-add) -1)
          (let* ((work (make-ledger))
                 (transferred (induce-fold-motifs *knowledge-library* :ledger work)))
            (check (equal '(:shifted-sum/via-foldl) (mapcar #'knowledge-entry-id transferred)))
            (check (member '(:instance :shifted-sum) (knowledge-edges-from motif :instance) :test #'equal))
            (check (apply #'= 11 (folds :shifted-sum '(4 2 3))))
            (check (< (ledger-total work) 2000)))
          ;; 5. Subtraction has an identity on one side and is not associative: no transfer,
          ;;    and rightly, since the two folds of it differ.
          (fold-function :alternating (op :- :int) 0)
          (identity-law (op :- :int) 0)
          (check (null (induce-fold-motifs *knowledge-library*)))
          (check (null (find-knowledge-entry :alternating/via-foldl)))
          (check (not (apply #'= (folds :alternating '(3 4 5)))))
          ;; 6. The motif and what it induced survive persistence, and the restored library
          ;;    is a fixed point of consolidation too.
          (let* ((restored (deserialize-knowledge-library (serialize-knowledge-library *knowledge-library*)))
                 (count (length (knowledge-library-entries restored))))
            (check (= count (entries)))
            (check (= 1 (length (knowledge-entries-of-kind :motif restored))))
            (consolidate-knowledge-library restored)
            (check (= count (length (knowledge-library-entries restored))))))))))

(deftest unamortized-library-entries-are-archived
  "A function the library lifts is credited the bits it saves the solutions found through it
and charged for its failed lifts. A decoy that is lifted and never pays is archived after
`*archive-epochs*` workload batches: still defined, no longer proposed. One that an active
entry calls is kept, and a batch without jobs changes nothing."
  (with-clean-kernel-state
    (define-standard-int-combinators :which '(:map))
    (let* ((seq (sequence-type :int))
           (xs (var 0 seq))
           (unary (code-type '((0 . :int)) :int))
           (code (var 1 unary))
           (inputs (list (cons 0 seq))))
      ;; Two decoys of map's own signature. Each applies its step twice, so no step in the
      ;; grammar below makes it compute any of the tasks.
      (dolist (name '(:map-twice :map-again))
        (define-function name (list (cons 0 seq) (cons 1 unary)) seq
          (lambda (self)
            (term `(if (= ,xs ()) ()
                       (cons (code-eval ,code (code-eval ,code (at ,xs 0)))
                             (,self (tail ,xs) ,code)))
                  seq))))
      ;; The second decoy has a caller in the library.
      (define-function :uses-map-again inputs seq
        (app (op :map-again) xs (lit unary (term `(+ ,(var 0 :int) 1)))))
      (labels ((language ()
                 (make-language :int inputs
                                :operators (list (op :map) (op :map-twice) (op :map-again)
                                                 (op :+ :int) (op :* :int))
                                :literals '(1 3)
                                :constants (list (lit seq '()))))
               (solve (step)
                 (let ((job (start-heuristic-synthesis
                             (simple-frame seq inputs
                                           (loop for list in '((1 2 3) (4 0) (-2 5 7 1))
                                                 collect (list (list list) (mapcar step list))))
                             (language) 75 :max-depth 2)))
                   (resume-synthesis job 60000 :stop-on-first t)
                   (check (expression-calls-operator-p (candidate-expression (synthesis-job-best job)) :map))
                   job))
               (lifted-p (job name)
                 (some (lambda (node) (eq (find-knowledge-entry name)
                                          (node-library-entry node *knowledge-library*)))
                       (synthesis-job-nodes job)))
               (account (name key)
                 (getf (knowledge-entry-metadata (find-knowledge-entry name)) key))
               (batch (job)
                 (cdr (assoc :archived
                             (getf (consolidate-knowledge-library *knowledge-library*
                                                                  :synthesis-jobs (list job)
                                                                  :condense-heuristic-p nil)
                                   :consolidated)))))
        (check (= 3 *archive-epochs*))
        ;; 1. Two batches: map pays its way, the decoys run up a debt, nothing is archived yet.
        (dolist (step (list #'1+ (lambda (x) (* x x))))
          (let ((job (solve step)))
            (check (lifted-p job :map-twice))
            (check (lifted-p job :map-again))
            (check (null (batch job)))))
        (check (plusp (account :map :net-utility)))
        (check (zerop (account :map :stale-epochs)))
        (dolist (decoy '(:map-twice :map-again))
          (check (minusp (account decoy :net-utility)))
          (check (= 2 (account decoy :stale-epochs)))
          (check (knowledge-entry-active-p (find-knowledge-entry decoy))))
        ;; 2. A batch without jobs is not a workload: no epoch passes.
        (let ((before (copy-tree (knowledge-entry-metadata (find-knowledge-entry :map-twice)))))
          (consolidate-knowledge-library *knowledge-library*)
          (check (equal before (knowledge-entry-metadata (find-knowledge-entry :map-twice)))))
        ;; 3. The third batch archives the decoy nothing calls, and only it.
        (check (equal '(:map-twice) (mapcar #'knowledge-entry-id (batch (solve (lambda (x) (+ x x)))))))
        (check (not (knowledge-entry-active-p (find-knowledge-entry :map-twice))))
        (check (knowledge-entry-active-p (find-knowledge-entry :map-again)))
        (check (equal '(:uses-map-again)
                      (mapcar #'knowledge-entry-id
                              (entry-live-callers (find-knowledge-entry :map-again) *knowledge-library*))))
        (check (knowledge-entry-active-p (find-knowledge-entry :map)))
        ;; 4. Archived is not removed: the function still runs and can be lifted by name,
        ;;    and a new job no longer proposes it.
        (check (equal '(3 4) (result (app (op :map-twice) (lit seq '(1 2))
                                          (lit unary (term `(+ ,(var 0 :int) 1)))))))
        (flet ((candidates (&rest keys)
                 (mapcar #'function-definition-name
                         (apply #'candidate-library-definitions (language) keys))))
          (check (equal '(:map :map-again) (candidates)))
          (check (equal '(:map-twice) (candidates :functions '(:map-twice)))))
        (let ((job (solve #'1+)))
          (check (not (lifted-p job :map-twice)))
          (check (lifted-p job :map-again)))
        ;; 5. The standing survives persistence.
        (let ((restored (deserialize-knowledge-library (serialize-knowledge-library *knowledge-library*))))
          (check (not (knowledge-entry-active-p (find-knowledge-entry :map-twice restored))))
          (check (knowledge-entry-active-p (find-knowledge-entry :map restored)))
          (check (equal (account :map :net-utility)
                        (getf (knowledge-entry-metadata (find-knowledge-entry :map restored)) :net-utility))))))))
