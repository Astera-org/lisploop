(in-package #:lisploop)

;;; ===========================================================================
;;; Plan 8 / P8.2: co-induced (decoder, solver) metrics, frame metrics, code edits,
;;; the arity-scaled Stage A budget, and the eager-proposal limit
;;; ===========================================================================

(defun define-int-scan ()
  "Register `:scan`, which threads an integer state through a sequence of actions."
  (let* ((seq (sequence-type :int))
         (step-type (code-type '((0 . :int) (1 . :int)) :int)))
    (define-function :scan (list (cons 0 seq) (cons 1 :int) (cons 2 step-type)) seq
      (lambda (self)
        (let* ((actions (var 0 seq)) (state (var 1 :int)) (step (var 2 step-type))
               (next (term `(code-eval ,step ,state (at ,actions 0)))))
          (term `(if (= ,actions ()) () (cons ,next (,self (tail ,actions) ,next ,step))) seq))))))

(defun scan-frame (extra-inputs)
  "A running sum from an initial state, with EXTRA-INPUTS further integer inputs that
nothing depends on. Returns the frame and its language."
  (let* ((seq (sequence-type :int))
         (inputs (cons (cons 0 seq) (loop for id from 1 to (1+ extra-inputs) collect (cons id :int)))))
    (values (make-frame (make-schema :inputs inputs :target seq)
                        (loop for (actions state sums) in '(((1 1) 0 (1 2)) ((2 -1 3) 1 (3 2 5)) ((-2 4) 5 (3 7)))
                              for key from 0
                              collect (make-row :key key
                                                :known (append (list actions state)
                                                               (loop for extra below extra-inputs
                                                                     collect (+ 7 (* 2 key) (* 3 extra))))
                                                :requirement (singleton-requirement seq sums))))
            (make-language :int inputs
                           :operators (list (op :+ :int) (op :* :int) (op :scan))
                           :literals '(0 1)))))

(deftest stage-a-budget-scales-with-the-inputs-of-a-lifted-frame
  "An input the step ignores makes the first combinations of two inputs dearer than the
fixed budget could reach; scaled by the lifted frame's arity, Stage A still meets the step
exactly and the search stays cheap (plan 8, probe 2)."
  (with-clean-kernel-state
    (define-int-scan)
    (flet ((solve (extra-inputs &optional scale-p)
             (multiple-value-bind (frame language) (scan-frame extra-inputs)
               (let ((job (start-heuristic-synthesis frame language 100 :library-functions '(:scan))))
                 (unless scale-p
                   ;; The budget before plan 8: twice the base for a lifted frame, whatever its arity.
                   (setf (synthesis-job-heuristic-budget job) 2000))
                 (resume-synthesis job 400000 :stop-on-first t)
                 (check (synthesis-job-best job))
                 (check-synthesized-model (candidate-expression (synthesis-job-best job)) frame
                                          :must-call-ops '(:scan)
                                          :held-out (list (list (append '((5 5 5) 1)
                                                                        (make-list extra-inputs :initial-element 9))
                                                                '(6 11 16))))
                 (values (ledger-total (synthesis-job-ledger job)) job)))))
      (let ((plain (solve 0 t))
            (one-extra (solve 1 t))
            (two-extra (solve 2 t)))
        (check (< plain 30000))
        (check (< one-extra 80000))
        (check (< two-extra 80000)))
      ;; The multiplier itself: one for two inputs, the square of the inputs beyond the first after that.
      (multiple-value-bind (work job) (solve 1 t)
        (declare (ignore work))
        (let* ((lifted (find-if #'lifted-node-p (synthesis-job-nodes job)))
               (frame (synthesis-node-frame lifted)))
          (check (= 3 (length (schema-inputs (frame-schema frame)))))
          (check (= (* 2000 2 4) (stage-a-budget job lifted frame)))
          (check (= 2000 (stage-a-budget job (synthesis-job-root job)
                                         (synthesis-node-frame (synthesis-job-root job))))))))))

(deftest eager-proposal-limit-defers-and-later-promotes
  "With a limit, an expansion materializes its first proposals and keeps the rest until
nothing else is left to do; the slots of a product are never separated."
  (let* ((inputs '((0 . :int)))
         (frame (simple-frame :int inputs '(((1) 4) ((5) 8))))
         (language (make-language :int inputs :operators nil :literals nil))
         (child-language (make-language :int inputs :operators nil :literals '(3)))
         (z (var 9 :int)))
    (flet ((proposal (name decoder score)
             (make-decomposition :name name :decoder decoder :child-id 9 :child-type :int
                                 :bindings (identity-bindings inputs) :language child-language
                                 :bound (header-bound inputs :int 12) :policy-score score))
           (expansion (job)
             (getf (message-evidence (find :expanded (synthesis-job-messages job) :key #'message-claim))
                   :deferred-proposals)))
      (let ((expand (lambda (job node frame language h-model ledger)
                      (declare (ignore job node frame language h-model ledger))
                      (list (proposal :decoy-a (term `(+ (+ ,(var 0 :int) ,(var 0 :int)) ,z)) 0)
                            (proposal :decoy-b (term `(* ,(var 0 :int) ,z)) 1)
                            (proposal :offset (term `(+ ,(var 0 :int) ,z)) 2)))))
        (flet ((run ()
                 (let ((job (start-synthesis frame language 30 :expand expand :max-depth 1)))
                   (resume-synthesis job 200000)
                   (check (synthesis-finished-p job))
                   (check (equal (term `(+ ,(var 0 :int) 3)) (candidate-expression (synthesis-job-best job))))
                   job)))
          (check (null (expansion (run))))
          (let ((*max-eager-proposals-per-node* 1))
            (check (equal '(:decoy-b :offset) (expansion (run))))
            (check-synthesis-resumption
             (lambda () (start-synthesis frame language 30 :expand expand :max-depth 1))
             :budget 200000)))))
    ;; A product is materialized whole or not at all.
    (let* ((slots '((7 . :int) (8 . :int)))
           (plain (make-decomposition :name :plain))
           (other (make-decomposition :name :other))
           (left (make-decomposition :name :left :slots slots))
           (right (make-decomposition :name :right :slots slots))
           (*max-eager-proposals-per-node* 2))
      (check (equal (list plain left right) (eager-proposals (list plain left right))))
      (check (equal (list plain other) (eager-proposals (list plain other left right))))
      (let ((*max-eager-proposals-per-node* 1))
        (check (equal (list left right) (eager-proposals (list left plain right))))))))

(deftest code-corrections-price-edits-not-replacements
  "A predicted tree that differs from its target in a few places is corrected by those
places: the price grows with the edit, never exceeds the replacement, and the packet
rebuilds the target."
  (let* ((scope '((0 . :int) (1 . :int)))
         (code (code-type scope :int))
         (x (var 0 :int)) (y (var 1 :int))
         (target (term `(+ (* (+ ,x ,y) (+ ,x ,y)) (* ,x (+ ,y 7)))))
         (one-leaf (term `(+ (* (+ ,x ,y) (+ ,x ,y)) (* ,x (+ ,y 9)))))
         (one-branch (term `(+ (* (+ ,x ,y) (+ ,x ,y)) (* ,x (* ,x ,x)))))
         (repeated (term `(+ (* (+ ,x 1) (+ ,x 1)) (* ,x (+ ,y 7)))))
         (unrelated (lit :int 0))
         (replacement (value-bit-size target code)))
    (check (= 0 (correction-bit-size target target code)))
    (check (< (correction-bit-size one-leaf target code)
              (correction-bit-size one-branch target code)
              replacement))
    ;; Both places that predicted 1 for y are corrected, and y is paid for once.
    (check (< (correction-bit-size repeated target code) replacement))
    (check (= replacement (correction-bit-size unrelated target code)))
    (check (= replacement (correction-bit-size nil target code nil)))
    (dolist (predicted (list target one-leaf one-branch repeated unrelated))
      (check (equal target (apply-correction-packet predicted (correction-packet predicted target code)
                                                    code))))
    ;; An edit is a packet of its own kind; a replacement is the target.
    (check (eq :code-edit (first (correction-packet one-leaf target code))))
    (check (equal target (correction-packet unrelated target code)))))

(defun shifted-sequence-fixture ()
  "Rows whose target is the first input advanced by the second. Returns frame and language;
the language cannot shift a sequence."
  (let* ((seq (sequence-type :int))
         (inputs (list (cons 0 seq) (cons 1 :int))))
    (values (make-frame (make-schema :inputs inputs :target seq)
                        (loop for (xs k ys) in '(((3 1 4 1 5) 2 (4 1 5 0 0))
                                                 ((2 7 1 8) 0 (2 7 1 8))
                                                 ((6 2 9 3 7) 1 (2 9 3 7 0))
                                                 ((5 8 2 6) 3 (6 0 0 0))
                                                 ((1 9 4) 1 (9 4 0)))
                              for key from 0
                              collect (make-row :key key :known (list xs k)
                                                :requirement (singleton-requirement seq ys))))
            (make-language :int inputs :operators (list (op :+ :int)) :literals '(0 1)))))

(deftest metric-decoder-prices-a-miss-by-its-delta
  "A decoder with a solver for its delta is a metric: a shifted sequence costs its shift,
a miss the decoder cannot describe keeps its built-in price, and the pair persists."
  (with-clean-kernel-state
    (let* ((seq (sequence-type :int))
           (entry (install-sequence-shift-metric))
           (decoders (metric-decoders seq)))
      (check (eq :conjecture (knowledge-entry-status entry)))
      (check (= 1 (length decoders)))
      (check (null (metric-decoders :int)))
      (check (every (lambda (name) (function-definition-total-p (find-function-definition name)))
                    '(:shift-seq :seq-corr :best-shift :argmax-corr)))
      (flet ((price (predicted target)
               (let ((ledger (make-ledger)))
                 (multiple-value-bind (packet bits)
                     (priced-correction predicted target seq :decoders decoders :ledger ledger)
                   (check (equal target (apply-correction-packet predicted packet seq)))
                   (values bits packet (ledger-total ledger))))))
        ;; 1. A shift is priced by the bits of its distance, and smoothly in it.
        (multiple-value-bind (bits packet work) (price '(3 1 4 1 5 9 2 6) '(4 1 5 9 2 6 0 0))
          (check (eq :metric-decoder (first packet)))
          (check (= 2 (third packet)))
          (check (< bits (correction-bit-size '(3 1 4 1 5 9 2 6) '(4 1 5 9 2 6 0 0) seq)))
          (check (plusp work))
          (check (<= bits (price '(3 1 4 1 5 9 2 6) '(9 2 6 0 0 0 0 0)))))
        ;; 2. An exact prediction costs nothing and runs nothing.
        (multiple-value-bind (bits packet work) (price '(3 1 4) '(3 1 4))
          (declare (ignore packet))
          (check (and (zerop bits) (zerop work))))
        ;; 3. Not a shift: the built-in correction stands.
        (check (= (correction-bit-size '(3 1 4 1 5) '(9 9 9 9 9) seq) (price '(3 1 4 1 5) '(9 9 9 9 9))))
        ;; 4. An ambiguous correlation: the solver's delta does not replay, so it is not used.
        (multiple-value-bind (bits packet) (price '(1 2 1 2 1 2) '(1 2 1 2 0 0))
          (check (not (eq :metric-decoder (and (consp packet) (first packet)))))
          (check (= bits (correction-bit-size '(1 2 1 2 1 2) '(1 2 1 2 0 0) seq)))))
      ;; 5. The closest witness of a set is chosen under the same prices.
      (multiple-value-bind (witness bits)
          (select-closest-witness '(3 1 4 1 5) '((9 9 9 9 9) (4 1 5 0 0)) seq t :decoders decoders)
        (check (equal '(4 1 5 0 0) witness))
        (check (< bits (correction-bit-size '(3 1 4 1 5) '(4 1 5 0 0) seq))))
      ;; 6. The pair is library data: it survives a round trip.
      (with-knowledge-library ((deserialize-knowledge-library (serialize-knowledge-library)))
        (let ((restored (metric-decoders seq)))
          (check (= 1 (length restored)))
          (check (= 2 (metric-delta (first restored) '(3 1 4 1 5) '(4 1 5 0 0) seq nil))))))))

(deftest metric-decoder-pulls-a-residual-back-to-its-delta
  "Stage A prices the identity's misses by their shift; Stage B then poses the shift itself,
which the decoder's solver exposes row by row. Without the pair the target is out of reach."
  (with-clean-kernel-state
    (multiple-value-bind (frame language) (shifted-sequence-fixture)
      (let* ((seq (sequence-type :int))
             (inputs (schema-inputs (frame-schema frame)))
             (x0 (var 0 seq)) (x1 (var 1 :int)))
        (flet ((start ()
                 (start-heuristic-synthesis frame language 120 :heuristic-budget 60000)))
          ;; Negative control first, in a library that holds no metric decoder.
          (let ((job (start)))
            (resume-synthesis job 300000 :stop-on-first t)
            (check (null (synthesis-job-best job))))
          (install-sequence-shift-metric)
          (let ((decoder (first (metric-decoders seq))))
            ;; 1. Stage A under the metric: the identity misses by small deltas.
            (let ((model (condense-heuristic frame language :work-limit 60000)))
              (check (equal x0 (heuristic-program model)))
              (let ((proposals (metric-residual-decompositions
                                frame x0 (heuristic-residual model) language 120 nil nil nil)))
                (check (= 1 (length proposals)))
                (check (eq :int (decomposition-child-type (first proposals))))
                ;; 2. Galois soundness of the pullback, and of the solver's narrowing with its fallback.
                ;;    The solver sees the raw requirement: folding would unfold the decoder's call.
                (let* ((proposal (first proposals))
                       (pulled (pullback-frame frame (decomposition-decoder proposal)
                                               (decomposition-child-id proposal) :int
                                               (decomposition-bindings proposal)))
                       (propagation (propagate-requirements
                                     pulled (callable-rules-library (decomposition-solver proposal))
                                     (make-ledger)))
                       (narrowed (propagation-frame propagation)))
                  (check (plusp (propagation-suggested propagation)))
                  (check (plusp (propagation-ambiguous propagation)))
                  (check (propagation-fallback propagation))
                  ;; On the fourth row the best correlation is at the wrong place: that delta
                  ;; does not replay, and the row keeps its requirement, which only 3 meets.
                  (check (equal '(2 0 1 nil 1) (mapcar #'row-singleton-value (frame-rows narrowed))))
                  (check (plusp (propagation-rejected propagation)))
                  (let ((kept (row-requirement (fourth (frame-rows narrowed)))))
                    (check (accepts kept 3))
                    (check (not (accepts kept 1))))
                  (dolist (child (list x1 (lit :int 0) (lit :int 1) (term `(+ ,x1 1)) (term `(+ ,x1 ,x1))))
                    (let ((valid-p (frame-satisfied-by-p
                                    (compose-model (decomposition-decoder proposal)
                                                   (decomposition-child-id proposal) child
                                                   (decomposition-bindings proposal))
                                    frame)))
                      (check (eq valid-p (frame-satisfied-by-p child pulled)))
                      (when valid-p (check (frame-satisfied-by-p child narrowed))))))))
            ;; 3. End to end, with unit-step parity through the staged metric work.
            (multiple-value-bind (batch) (check-synthesis-resumption #'start :budget 300000 :stop-on-first t)
              (let ((expression (candidate-expression (synthesis-job-best batch))))
                (check (equal (app (first decoder) x0 x1) expression))
                (check-synthesized-model expression frame
                                         :must-call-ops '(:shift-seq)
                                         :held-out '((((8 6 7 5 3 0 9) 4) (3 0 9 0 0 0 0))))
                (check (assoc :heuristic-metric
                              (ledger-counts (heuristic-search-ledger
                                              (let ((search (start-heuristic-search frame language)))
                                                (resume-heuristic-search search 60000)
                                                search))))))))
          ;; 4. The staged metric work keeps Stage A itself resumable one unit at a time.
          (check-heuristic-search-resumption (lambda () (start-heuristic-search frame language))
                                             :budget 40000)
          (check inputs))))))

(deftest frame-metric-prices-misses-as-the-problem-says
  "A frame may carry its own metric. Stage A then prices every miss by it, and it follows
the frame for as long as the target type does."
  (let* ((inputs '((0 . :int)))
         (zero-one (term `(if (= ,(var 0 :int) ,(var 1 :int)) 0 1) :int))
         (examples '(((1) 1) ((2) 2) ((3) 3) ((4) 1000)))
         (plain (simple-frame :int inputs examples))
         (scored (make-frame (frame-schema plain) (frame-rows plain) :metric zero-one))
         (language (make-language :int inputs :operators nil :literals '(0))))
    (check (equal '(1000 1) (multiple-value-list (priced-correction 4 1000 :int :metric zero-one))))
    (check (equal '(0 0) (multiple-value-list (priced-correction 7 7 :int :metric zero-one))))
    (let ((plain-model (condense-heuristic plain language :work-limit 20000))
          (scored-model (condense-heuristic scored language :work-limit 20000)))
      (check (equal (var 0 :int) (heuristic-program plain-model)))
      (check (equal (var 0 :int) (heuristic-program scored-model)))
      ;; One miss: its row index and one bit, instead of the bits of a delta of 996.
      (check (< (heuristic-residual-bits scored-model) (heuristic-residual-bits plain-model)))
      (check (equal (heuristic-residual scored-model) (heuristic-residual plain-model))))
    (check-heuristic-search-resumption (lambda () (start-heuristic-search scored language)) :budget 20000)
    ;; The metric is the target type's: kept by a snapshot, dropped where the target changes.
    (check (equal zero-one (frame-metric (snapshot-frame scored))))
    (check (equal zero-one (frame-metric (pullback-frame scored (term `(+ ,(var 0 :int) ,(var 9 :int)))
                                                         9 :int (identity-bindings inputs)))))
    (check (null (frame-metric (pullback-frame scored (term `(if ,(var 9 :bool) ,(var 0 :int) 0) :int)
                                               9 :bool (identity-bindings inputs)))))
    (raises (make-frame (frame-schema plain) (frame-rows plain) :metric (lit :bool t)))))

(deftest frame-descriptors-are-evaluated-once-and-address-entries
  "The descriptors of the candidate combinators are evaluated on a frame once, whichever
entries share them; the verdicts score an entry exactly as evaluating them again would, and
the concepts a frame satisfies address the entries that have them."
  (with-clean-kernel-state
    (define-standard-int-combinators :which '(:map :filter :foldr))
    (let* ((seq (sequence-type :int))
           (inputs (list (cons 4 seq)))
           (frame (simple-frame seq inputs '((((1 2 3)) (2 4 6)) (((5)) (10)) ((()) ()))))
           (names '(:map :filter :foldr)))
      (dolist (name names) (compute-entry-descriptor-profile (find-knowledge-entry name)))
      (let* ((ledger (make-ledger))
             (verdicts (evaluate-frame-descriptors frame 4 :ledger ledger)))
        (check verdicts)
        (check (plusp (ledger-total ledger)))
        (check (every (lambda (verdict) (member (cdr verdict) '(:satisfied :violated :neutral))) verdicts))
        ;; A second copy of each entry's descriptors states nothing new, so it costs nothing.
        (check (equal (remove-duplicates (mapcar #'car verdicts)) (mapcar #'car verdicts)))
        (check (subsetp (evaluate-frame-descriptors frame 4 :describing '(:map)) verdicts :test #'equal))
        (dolist (name names)
          (let ((fresh (make-ledger)) (reused (make-ledger)))
            (check (equal (multiple-value-list (score-entry-by-descriptors name frame 4 :ledger fresh))
                          (multiple-value-list (score-entry-by-descriptors name frame 4 :ledger reused
                                                                                       :verdicts verdicts))))
            (check (<= (ledger-total reused) (ledger-total fresh)))))
        ;; The frame keeps length and changes content: that addresses :map before :filter.
        (let ((addressed (frame-addressed-entries frame 4 :verdicts verdicts)))
          (check (eq :map (knowledge-entry-id (car (first addressed)))))
          (check (every (lambda (pair) (find-knowledge-entries-by-address
                                        (knowledge-entry-compositional-name (car pair))))
                        addressed))))
      ;; Proposals score the same with the shared verdicts as they did entry by entry.
      (let* ((language (make-language :int inputs :operators (mapcar #'op names) :literals '(1 2)))
             (proposals (library-decompositions frame language :child-bound 60)))
        (check (find :map proposals :key (lambda (p) (second (decomposition-name p)))))
        (dolist (proposal proposals)
          (let ((name (decomposition-name proposal)))
            (when (and (consp name) (eq :library (first name)))
              (check (= (decomposition-policy-score proposal)
                        (nth-value 1 (score-entry-by-descriptors (second name) frame 4)))))))))))

