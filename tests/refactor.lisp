(in-package #:lisploop)

(defun outcome-signature (expression inputs values)
  (let ((run (evaluate expression inputs values)))
    (list (evaluation-status run) (when (eq :value (evaluation-status run)) (evaluation-value run)))))

(deftest folding-preserves-partial-contexts-and-conjunctions
  (let* ((pair (tuple-type :int :int)) (z (var 0 pair))
         (x (app (op :at pair) z (lit :int 0))) (y (app (op :at pair) z (lit :int 1)))
         (predicate (bool-and (bool-and (app (op :member :int) x (lit (sequence-type :int) '(1 2 3)))
                                        (app (op := :int) y (lit :int 0)))
                              (bool-not (app (op := :int) x (lit :int 3)))))
         (folded (fold-constants predicate))
         (singleton (fold-constants
                     (bool-and (bool-and (app (op :member :int) x (lit (sequence-type :int) '(1 2)))
                                         (app (op := :int) y (lit :int 0)))
                               (app (op :member :int) x (lit (sequence-type :int) '(2 3)))))))
    (check (equal folded
                  (bool-and (app (op :member :int) x (lit (sequence-type :int) '(1 2)))
                            (app (op := :int) y (lit :int 0)))))
    (check (equal singleton (app (op := pair) z (lit pair '(2 0)))))
    (loop for a from -1 to 4 do (loop for b from -1 to 2 do
      (check (equal (outcome-signature predicate (list (cons 0 pair)) (list (list a b)))
                    (outcome-signature folded (list (cons 0 pair)) (list (list a b))))))))
  (let* ((z (var 0 :int))
         (partial (app (op := :int) (app (op :at (sequence-type :int))
                                         (lit (sequence-type :int) '(5 6)) z) (lit :int 5))))
    (dolist (predicate (list partial (bool-not partial) (bool-and partial (lit :bool nil))
                            (app (op :if :bool) partial (lit :bool nil) (lit :bool t))))
      (loop for value from -2 to 4 do
        (check (equal (outcome-signature predicate '((0 . :int)) (list value))
                      (outcome-signature (fold-constants predicate) '((0 . :int)) (list value)))))))
  (let* ((expr (app (op :+ :int) (lit :int 3) (lit :int 4))) (ledger (make-ledger)))
    (check (equal expr (fold-constants expr nil :ledger ledger :budget 0)))
    (check (zerop (ledger-total ledger)))))

(deftest exhaustive-small-partial-boolean-contexts
  (let* ((z (var 0 :int))
         (atoms (list (lit :bool nil) (lit :bool t)
                      (singleton-requirement :int 0) (singleton-requirement :int 1)
                      (set-requirement :int '(0 1))
                      (app (op := :int) (app (op :/ :int) (lit :int 1) z) (lit :int 0))
                      (app (op := :int) (app (op :at (sequence-type :int))
                                              (lit (sequence-type :int) '(0 1)) z) (lit :int 0)))))
    (dolist (a atoms) (dolist (b atoms) (dolist (c atoms)
      (dolist (expr (list (app (op :if :bool) a b c) (bool-and (bool-and a b) c)))
        (let ((folded (fold-constants expr)))
          (loop for value from -2 to 3 do
            (check (equal (outcome-signature expr '((0 . :int)) (list value))
                          (outcome-signature folded '((0 . :int)) (list value))))))))))))

(deftest full-input-tightening-and-search-isolation
  (let* ((inputs '((0 . :int) (1 . :int)))
         (frame (make-frame (make-schema :inputs inputs :target :int)
                            (list (make-row :key :a :known '(0 0) :requirement (set-requirement :int '(0 1)))
                                  (make-row :key :b :known '(0 1) :requirement (singleton-requirement :int 1)))))
         (requirements (tighten-same-input-requirements frame))
         (language (make-language :int inputs :operators nil :literals nil))
         (job (start-search frame language :expressions (list (var 1 :int)))))
    (check (accepts (aref requirements 0) 0))
    (setf (row-requirement (first (frame-rows frame))) (singleton-requirement :int 9)
          (language-inputs language) nil)
    (resume-search job 100 10000)
    (check (search-job-best job)))
  (let* ((frame (make-frame (make-schema :inputs nil :target :int)
                            (list (make-row :key 0 :known nil :requirement (set-requirement :int '(1 2)))
                                  (make-row :key 1 :known nil :requirement (singleton-requirement :int 2)))))
         (reqs (tighten-same-input-requirements frame)))
    (check (every (lambda (r) (and (accepts r 2) (not (accepts r 1)))) reqs))))

(deftest heuristic-budget-resumption-and-original-loss
  (let* ((frame (simple-frame :int '((0 . :int)) '(((0) 0) ((1) 1) ((2) 9))))
         (language (make-language :int '((0 . :int)) :operators nil :literals '(0 1)))
         (bound (+ (header-size '((0 . :int)) :int) 6))
         (batch (start-heuristic-search frame language :description-limit bound))
         (unit (start-heuristic-search frame language :description-limit bound))
         (ledger (make-ledger)))
    (condense-heuristic frame language :work-limit 1 :ledger ledger)
    (check (= 1 (ledger-total ledger)))
    (check (eq :bounded-exhaustion (message-claim (resume-heuristic-search batch 100000))))
    (loop for limit from 1 to (ledger-total (heuristic-search-ledger batch)) do
      (resume-heuristic-search unit limit)
      (check (= limit (ledger-total (heuristic-search-ledger unit)))))
    (check (equalp (heuristic-search-best batch) (heuristic-search-best unit)))
    (check (equalp (heuristic-search-ledger batch) (heuristic-search-ledger unit)))
    (check (equal (var 0 :int) (heuristic-program (heuristic-search-best batch))))))

(defun recursive-control ()
  (let* ((inputs '((0 . :int)))
         (frame (simple-frame :int inputs '(((0) 3) ((1) 4) ((2) 5))))
         (language (make-language :int inputs :operators nil :literals '(0 1 2 3)))
         (child-language (make-language :int nil :operators nil :literals '(0 1 2 3)))
         (inner (make-decomposition :name :inner :decoder (app (op :+ :int) (lit :int 1) (var 9 :int))
                                   :child-id 9 :child-type :int :bindings nil :language child-language :bound 30))
         (outer (make-decomposition :name :outer :decoder (app (op :+ :int) (var 0 :int) (var 9 :int))
                                   :child-id 9 :child-type :int :bindings nil :language child-language
                                   :bound 15 :children (list inner)))
         (bad (make-decomposition :name :bad-dependency :decoder (var 9 :int) :child-id 9
                                 :child-type :int :bindings nil :language child-language :bound 30)))
    (start-synthesis frame language 28 :decompositions (list bad outer) :quantum 7)))

(deftest recursive-composition-budget-and-informative-messages
  (let ((batch (recursive-control)) (unit (recursive-control)))
    (check (eq :bounded-exhaustion (message-claim (resume-synthesis batch 100000))))
    (check (synthesis-job-best batch))
    (check (some (lambda (message) (eq :conflict (message-claim message))) (synthesis-job-messages batch)))
    (check (some (lambda (message) (and (eq :child-candidate (message-claim message))
                                       (getf (message-evidence message) :parent-id)))
                 (synthesis-job-messages batch)))
    (loop for limit from 1 to (ledger-total (synthesis-job-ledger batch)) do
      (resume-synthesis unit limit)
      (check (= limit (ledger-total (synthesis-job-ledger unit)))))
    (check (equalp (synthesis-job-ledger batch) (synthesis-job-ledger unit)))
    (check (equalp (synthesis-job-best batch) (synthesis-job-best unit)))
    (let* ((root (synthesis-job-root batch)) (model (candidate-expression (synthesis-job-best batch))))
      (check (evaluate-model-run-work model (synthesis-node-frame root))))))

(deftest direct-selector-competes-with-fibers-and-dependencies
  (let* ((inputs '((0 . :int) (1 . :int)))
         (frame (make-frame (make-schema :inputs inputs :target :int)
                            (list (make-row :key 0 :known '(0 0) :requirement (set-requirement :int '(0 1)))
                                  (make-row :key 1 :known '(0 1) :requirement (singleton-requirement :int 1)))))
         (language (make-language :int inputs :operators nil :literals '(0 1)))
         (job (start-selector-search frame language 30 :fibers t :dependencies t)))
    (resume-synthesis job 100000)
    (check (synthesis-job-best job))
    (check (find (var 1 :int) (synthesis-job-results job) :key #'candidate-expression :test #'equal))
    (check (plusp (cdr (assoc :preparation (ledger-counts (synthesis-job-ledger job))))))))

(deftest view-orchestration-total-budget
  (let* ((frame (simple-frame :int '((0 . :int)) '(((0) 1) ((1) 2)) :lookup-p t))
         (guard (app (op := :int) (var 0 :int) (lit :int 0)))
         (language (make-language :int '((0 . :int)) :operators nil :literals '(1 2)))
         (ledger (make-ledger)))
    (multiple-value-bind (proposals conflict status)
        (synthesize-supplied-partition-view frame guard language :work-limit 3 :ledger ledger)
      (check (null proposals)) (check (null conflict)) (check (eq :cutoff (message-claim status))))
    (check (= 3 (ledger-total ledger)))))

(deftest composition-prices-parent-instead-of-local-child
  (let* ((frame (simple-frame :int '((0 . :int)) '(((0) 1))))
         (language (make-language :int '((0 . :int)) :operators nil :literals nil))
         (child-language (make-language :int '((0 . :int)) :operators nil :literals '(1)))
         (binding (app (op :+ :int) (app (op :+ :int) (var 0 :int) (lit :int 1)) (lit :int 0)))
         (proposal (make-decomposition :name :expensive-context :decoder (var 9 :int) :child-id 9
                                       :child-type :int :bindings (list (cons 0 binding))
                                       :language child-language :bound 30))
         (job (start-synthesis frame language 25 :decompositions (list proposal))))
    (resume-synthesis job 100000)
    ;; Variable is the shortest child, but literal 1 is the shortest complete parent.
    (check (find binding (synthesis-job-results job) :key #'candidate-expression :test #'equal))
    (check (equal (lit :int 1) (candidate-expression (synthesis-job-best job))))))

(deftest synthesized-dependency-features-and-cutoff-evidence
  (let* ((inputs '((0 . :int) (1 . :int)))
         (frame (simple-frame :int inputs '(((0 0) 0) ((1 0) 1) ((0 1) 1))))
         (features (make-language :int inputs :operators (list (op :+ :int)) :literals nil))
         (selectors (make-language :int inputs :operators nil :literals nil))
         (bound (description-size (app (op :+ :int) (var 0 :int) (var 1 :int)) inputs))
         (job (start-dependency-search frame features selectors bound 25)))
    (check (eq :cutoff (message-claim (resume-dependency-search job 1))))
    (check (= 1 (ledger-total (dependency-search-ledger job))))
    (check (eq :bounded-exhaustion (message-claim (resume-dependency-search job 100000))))
    (check (find (app (op :+ :int) (var 0 :int) (var 1 :int)) (dependency-search-features job) :test #'equal))
    (check (synthesis-job-best (dependency-search-synthesis job)))))

(deftest inverse-grid-witness-is-synthesized-and-serializable
  (let* ((pair (tuple-type :int :int)) (seq (sequence-type :int))
         (z (var 9 pair))
         (decoder (app (op :at seq)
                       (app (op :at (sequence-type seq)) (lit (sequence-type seq) '((0 5) (7 0)))
                            (app (op :at pair) z (lit :int 0)))
                       (app (op :at pair) z (lit :int 1))))
         (parent (simple-frame :int nil '((nil 5))))
         (child (pullback-frame parent decoder 9 pair nil))
         (language (make-language :int nil :operators (list (op :tuple pair)) :literals '(0 1)))
         (job (start-search child language))
         (bound (description-size (app (op :tuple pair) (lit :int 0) (lit :int 1)) nil)))
    (resume-search job bound 100000)
    (check (search-job-best job))
    (let* ((learned (candidate-expression (search-job-best job)))
           (library-program (decode-model (encode-model learned nil))))
      (check (equal '(0 1) (result library-program)))
      (check (evaluate-model-run-work (compose-model decoder 9 library-program nil) parent)))))

(deftest fiber-proposals-report-uncertainty-and-budget
  (let* ((frame (simple-frame :int '((0 . :int)) '(((0) 1) ((1) 2))))
         (ledger (make-ledger)))
    (multiple-value-bind (classes labels refined partition status) (infer-fibers frame ledger 1)
      (declare (ignore labels refined partition))
      (check (null classes)) (check (eq :cutoff (message-claim status)))
      (check (= 1 (ledger-total ledger))))
    (multiple-value-bind (classes labels refined partition status) (infer-fibers frame nil 100000 0)
      (declare (ignore labels partition))
      (check (= 2 (length classes))) (check refined)
      (check (eq :cutoff (getf (message-evidence status) :search-status)))
      (check (eq :unresolved (getf (message-evidence status) :feasibility))))))

(deftest shared-decoder-survives-separate-branch-conflict
  (let* ((frame (simple-frame :int '((0 . :int)) '(((0) 1) ((1) 2) ((2) 3))))
         (guard (app (op := :int) (var 0 :int) (lit :int 0)))
         (language (make-language :int '((1 . :int)) :operators nil :literals '(1)))
         (decoder (app (op :+ :int) (var 0 :int) (var 9 :int))))
    (multiple-value-bind (proposals conflict)
        (synthesize-supplied-partition-view frame guard language :child-bindings (list (cons 1 (lit :int 0)))
                                            :child-bound 30 :decoder decoder :child-id 9 :child-type :int)
      (check conflict)
      (check (null (find :separate-parts proposals :key #'partition-view-proposal-kind)))
      (let ((shared (find :shared-decoder proposals :key #'partition-view-proposal-kind)))
        (check shared)
        (check (evaluate-model-run-work (partition-view-proposal-model shared) frame))))))

(deftest correction-encoder-ordered-domains-tuples-and-set-witnesses
  (let ((field (gf 7))
        (pair-type (tuple-type :int :int)))
    ;; 1. Integer difference encoding: zero on equality, symmetric, monotonic in magnitude.
    (check (= 0 (correction-bit-size 42 42 :int)))
    (check (= 1 (correction-packet 10 11 :int)))
    (check (= -1 (correction-packet 11 10 :int)))
    (check (= 4 (correction-bit-size 10 11 :int)))
    (check (= 4 (correction-bit-size 11 10 :int)))
    (check (< (correction-bit-size 100 101 :int) (correction-bit-size 100 250 :int)))
    (check (< (correction-bit-size 1000 1001 :int) (value-bit-size 1001 :int)))
    ;; Fallback when evaluation failed (:error -> predicted-p = nil).
    (check (= (value-bit-size 1001 :int) (correction-bit-size nil 1001 :int nil)))
    ;; 2. GF(p) Lee modular difference encoding.
    (check (= 1 (centered-mod-difference 6 0 7)))
    (check (= -1 (centered-mod-difference 0 6 7)))
    (check (= -2 (centered-mod-difference 0 5 7)))
    (check (= 0 (correction-bit-size 4 4 field)))
    (check (= (correction-bit-size 0 1 field) (correction-bit-size 0 6 field)))
    (check (< (correction-bit-size 0 1 field) (correction-bit-size 0 2 field)))
    (check (= (correction-bit-size 0 2 field) (correction-bit-size 0 5 field)))
    ;; 3. Componentwise tuple correction packet.
    (check (equal '(1 0) (correction-packet '(10 1000) '(11 1000) pair-type)))
    (check (= 5 (correction-bit-size '(10 1000) '(11 1000) pair-type)))
    (check (< (correction-bit-size '(10 1000) '(11 1000) pair-type)
              (value-bit-size '(11 1000) pair-type)))
    ;; 4. Order-independent minimum-bit witness selection on set requirements.
    (multiple-value-bind (w1 bits1 pkt1) (select-closest-witness 100 '(500 101) :int t)
      (multiple-value-bind (w2 bits2 pkt2) (select-closest-witness 100 '(101 500) :int t)
        (check (= 101 w1 w2))
        (check (= 4 bits1 bits2))
        (check (= 1 pkt1 pkt2)))))
  ;; 5. Heuristic search prefers close approximation x0 over distant constant '0
  ;;    and selects the closest set-requirement witness regardless of list order.
  (let* ((inputs '((0 . :int)))
         (schema (make-schema :inputs inputs :target :int))
         (frame (make-frame schema
                            (list (make-row :key :r0 :known '(100) :requirement (set-requirement :int '(900 101)))
                                  (make-row :key :r1 :known '(200) :requirement (singleton-requirement :int 201))
                                  (make-row :key :r2 :known '(300) :requirement (singleton-requirement :int 301)))))
         (language (make-language :int inputs :operators nil :literals '(0)))
         (bound (+ (header-size inputs :int) 6))
         (heuristic (condense-heuristic frame language :description-limit bound)))
    (check (heuristic-model-p heuristic))
    (check (equal (var 0 :int) (heuristic-program heuristic)))
    (check (equal '((:r0 . 101) (:r1 . 201) (:r2 . 301)) (heuristic-residual heuristic)))))

(deftest frame-linkage-preservation-and-metric-anti-collapse
  ;; 1. Frame transformations preserve pairs and anchors across 1-to-1 row mappings.
  (let* ((inputs '((0 . :int)))
         (base (simple-frame :int inputs '(((0) 1) ((0) 1) ((2) 3) ((2) 3))))
         (linked (with-frame-linkage base :labels '(0 0 1 1)))
         (pairs (frame-pairs linked))
         (anchors (frame-anchors linked))
         (decoder (app (op :+ :int) (var 0 :int) (var 9 :int)))
         (bindings (list (cons 0 (var 0 :int))))
         (pulled (pullback-frame linked decoder 9 :int bindings))
         (projected (project-frame-rows linked bindings))
         (labeled (context-label-frame linked '(0 0 1 1) :bindings bindings))
         (relation (observe-arithmetic-relation :int :+ '(0 1 2 3)))
         (discovery (discover-arithmetic-solver relation 1 '(0 1 2 3) :operators '(:-) :literals nil :body-bound 12))
         (propagated (propagation-frame (propagate-arithmetic-child linked decoder 9 bindings discovery (make-ledger)))))
    (check (and pairs anchors))
    (dolist (transformed (list pulled projected labeled propagated))
      (check (equal pairs (frame-pairs transformed)))
      (check (equal anchors (frame-anchors transformed)))))
  ;; 2. Relational metric pricing on pairs and anchors rejects constant collapse
  ;;    in favor of an informative approximate invariant and preserves unit-step parity.
  (let* ((inputs '((0 . :int)))
         (schema (make-schema :inputs inputs :target :int))
         (raw-rows (loop for k from 0 below 8
                         for x in '(0 0 0 0 10 10 10 11)
                         collect (make-row :key k :known (list x) :requirement (lit :bool t))))
         (frame (with-frame-linkage (make-frame schema raw-rows)
                                    :labels '(0 0 0 0 1 1 1 1)))
         (language (make-language :int inputs :operators nil :literals '(0)))
         (bound (+ (header-size inputs :int) 6))
         (scope (make-observation-scope frame language))
         (obs-job (start-observation-search scope)))
    (resume-observation-search obs-job bound 100000)
    (let ((const-bucket (find '(0 0 0 0 0 0 0 0) (observation-job-buckets obs-job)
                              :key #'observation-bucket-values :test #'equal))
          (var-bucket (find '(0 0 0 0 10 10 10 11) (observation-job-buckets obs-job)
                            :key #'observation-bucket-values :test #'equal)))
      (check const-bucket)
      (check var-bucket)
      ;; Constant '0 has 0 pair bits but positive anchor collision bits.
      (check (zerop (observation-bucket-pair-bits const-bucket)))
      (check (plusp (observation-bucket-anchor-bits const-bucket)))
      ;; Variable x0 separates anchors (0 anchor bits) with a single +1 pair drift on (6 7).
      (check (zerop (observation-bucket-anchor-bits var-bucket)))
      (check (plusp (observation-bucket-pair-bits var-bucket)))
      (check (< (observation-bucket-residual-bits var-bucket)
                (observation-bucket-residual-bits const-bucket))))
    (let ((batch (start-heuristic-search frame language :description-limit bound))
          (unit (start-heuristic-search frame language :description-limit bound)))
      (check (eq :bounded-exhaustion (message-claim (resume-heuristic-search batch 100000))))
      (loop for limit from 1 to (ledger-total (heuristic-search-ledger batch)) do
        (resume-heuristic-search unit limit)
        (check (= limit (ledger-total (heuristic-search-ledger unit)))))
      (check (equalp (heuristic-search-best batch) (heuristic-search-best unit)))
      (check (equalp (heuristic-search-ledger batch) (heuristic-search-ledger unit)))
      ;; Heuristic search rejects the collapsed constant '0 and selects x0 with its 1-pair correction.
      (check (equal (var 0 :int) (heuristic-program (heuristic-search-best batch))))
      (check (not (heuristic-exact-p (heuristic-search-best batch))))
      (check (equal '(((:pair 6 7) . 1)) (heuristic-residual (heuristic-search-best batch)))))))

(deftest standalone-anchors-correction-roundtrip-and-component-deduplication
  ;; 1. `apply-correction-packet` is the exact right-inverse of `correction-packet`.
  (let ((field (gf 7))
        (tup-type (tuple-type :int (gf 7))))
    (dolist (pair '((-5 12) (100 101) (42 42)))
      (let* ((pred (first pair)) (targ (second pair))
             (pkt (correction-packet pred targ :int t)))
        (check (equal targ (apply-correction-packet pred pkt :int t)))
        (check (equal targ (apply-correction-packet nil (correction-packet nil targ :int nil) :int nil)))))
    (loop for a from 0 below 7 do
      (loop for b from 0 below 7 do
        (let ((pkt (correction-packet a b field t)))
          (check (= b (apply-correction-packet a pkt field t))))))
    (let* ((p-tup '(10 6)) (t-tup '(12 1))
           (pkt (correction-packet p-tup t-tup tup-type t)))
      (check (equal '(2 2) pkt))
      (check (equal t-tup (apply-correction-packet p-tup pkt tup-type t)))))
  ;; 2. Standalone anchors (without pairs) and second-endpoint anchors work in `make-observation-scope`
  ;;    and `start-heuristic-search`.
  (let* ((inputs '((0 . :int)))
         (schema (make-schema :inputs inputs :target :int))
         (rows (list (make-row :key :a :known '(10) :requirement (lit :bool t))
                     (make-row :key :b :known '(20) :requirement (lit :bool t))))
         (standalone (make-frame schema rows :anchors '(:a :b)))
         (second-ep (make-frame schema rows :pairs '((:a :b)) :anchors '(:a :b)))
         (language (make-language :int inputs :operators nil :literals '(0)))
         (bound (+ (header-size inputs :int) 6)))
    (check (observation-scope-frame (make-observation-scope standalone language)))
    (check (observation-scope-frame (make-observation-scope second-ep language)))
    (let ((h (condense-heuristic standalone language :description-limit bound)))
      (check (heuristic-model-p h))
      ;; `x0` separates standalone anchors :a and :b with 0 residual bits, beating constant '0.
      (check (equal (var 0 :int) (heuristic-program h)))
      (check (heuristic-exact-p h))))
  ;; 3. `relational-linkage-residual` does not double-charge a row when both `:pair` drift
  ;;    and `:anchor` collision fire in the same connected component.
  (let* ((inputs '((0 . :int)))
         (schema (make-schema :inputs inputs :target :int))
         (rows (loop for k from 0 below 4
                     collect (make-row :key k :known (list k) :requirement (lit :bool t))))
         (frame (make-frame schema rows :pairs '((0 1) (2 3)) :anchors '(0 2))))
    ;; Output vector '(5 5 5 9): anchor 2 collides with anchor 0 (both 5), AND pair (2 3) drifts (5 -> 9).
    ;; Row 3 is already charged by (:pair 2 3), so (:anchor ...) only charges row 2.
    (multiple-value-bind (entries total-bits pair-bits anchor-bits)
        (relational-linkage-residual frame '(5 5 5 9) :type :int)
      (check (= (+ pair-bits anchor-bits) total-bits))
      (check (find '(:pair 2 3) entries :key #'car :test #'equal))
      (check (find '(:anchor 2) entries :key #'car :test #'equal))
      (check (not (find '(:anchor 3) entries :key #'car :test #'equal))))))

(deftest pulled-back-child-frame-folding-solver-propagation-and-heuristic-scoring
  ;; 1. `frame-conflict-p` returns the folded frame as its second value without mutating input.
  (let* ((inputs '((0 . :int)))
         (parent (simple-frame :int inputs '(((0) 5) ((1) 1) ((2) 2))))
         (guard (app (op := :int) (var 0 :int) (lit :int 0)))
         (decoder (app (op :if :int) guard (var 9 :int) (var 0 :int)))
         (raw-child (pullback-frame parent decoder 9 :int (list (cons 0 (var 0 :int))))))
    (multiple-value-bind (conflict folded-child) (frame-conflict-p raw-child)
      (check (null conflict))
      (check (frame-p folded-child))
      ;; Covered rows (x=1, x=2 where guard is false) fold to `'t` in folded-child!
      (check (equal (singleton-requirement :int 5) (row-requirement (first (frame-rows folded-child)))))
      (check (equal (lit :bool t) (row-requirement (second (frame-rows folded-child)))))
      (check (equal (lit :bool t) (row-requirement (third (frame-rows folded-child)))))
      ;; Input raw-child remains un-mutated.
      (check (not (equal (lit :bool t) (row-requirement (second (frame-rows raw-child))))))))
  ;; 2. `start-heuristic-search` / `condense-heuristic` scores candidates on pulled-back symbolic
  ;;    child frames (where raw `extract-allowed-values` is `:unknown`) instead of dropping them.
  (let* ((inputs '((0 . :int)))
         (parent (simple-frame :int inputs '(((100) 101) ((200) 201) ((300) 309))))
         (decoder (app (op :+ :int) (var 0 :int) (var 9 :int)))
         (pulled (pullback-frame parent decoder 9 :int (list (cons 0 (var 0 :int)))))
         (child-lang (make-language :int inputs :operators nil :literals '(0 1)))
         (bound (+ (header-size inputs :int) 6))
         (h (condense-heuristic pulled child-lang :description-limit bound)))
    (check (every (lambda (r) (eq :unknown (extract-allowed-values (row-requirement r))))
                  (frame-rows pulled)))
    (check (heuristic-model-p h))
    ;; Latent displacement is +1 on rows 0 and 1, and +9 on outlier row 2 -> chooses literal '1!
    (check (equal (lit :int 1) (heuristic-program h)))
    (check (equal '((2 . 9)) (heuristic-residual h))))
  ;; 3. `decomposition-solver` invokes `propagate-arithmetic-child` during node preparation.
  (let* ((field (gf 5))
         (inputs (list (cons 0 field)))
         (parent (simple-frame field inputs '(((1) 4) ((2) 0) ((3) 1))))
         (relation (observe-arithmetic-relation field :+ '(0 1 2 3 4)))
         (solver (discover-arithmetic-solver relation 1 '(0 1 2 3 4) :operators '(:+) :literals '(0 1 2 3 4) :body-bound 16))
         (child-lang (make-language field nil :operators nil :literals '(0 1 2 3)))
         (prop (make-decomposition :name :with-solver
                                   :decoder (app (op :+ field) (var 0 field) (var 9 field))
                                   :child-id 9 :child-type field :bindings nil
                                   :language child-lang :bound 25 :solver solver))
         (job (start-synthesis parent (make-language field inputs :operators nil :literals '(0))
                               20 :decompositions (list prop))))
    (check (eq :bounded-exhaustion (message-claim (resume-synthesis job 100000))))
    (check (synthesis-job-best job))
    (check (evaluate-model-run-work (candidate-expression (synthesis-job-best job)) parent))))

(deftest stage-a-to-stage-b-additive-and-conditional-residual-synthesis
  ;; 1. Path B1 (Additive / Displacement Residual Pullback):
  ;;    Target is y = 100*x0 + x1 + 1 on :int. Stage A with small bound condenses `100*x0`
  ;;    (supplied as input coordinate 0 = 100*x0, coordinate 1 = x1), leaving small displacement
  ;;    residuals (+1, +2) that Stage B synthesizes as `x1 + 1` and composes into `x0 + (x1 + 1)`.
  (let* ((inputs '((0 . :int) (1 . :int)))
         (frame (simple-frame :int inputs '(((100 0) 101)
                                            ((100 1) 102)
                                            ((200 0) 201)
                                            ((200 1) 202))))
         (stage-a-lang (make-language :int inputs :operators nil :literals '(0 1)))
         (child-lang (make-language :int inputs :operators (list (op :+ :int)) :literals '(1)))
         (stage-a-bound (+ (header-size inputs :int) 6))
         (child-bound (description-size (app (op :+ :int) (var 1 :int) (lit :int 1)) inputs)))
    (multiple-value-bind (proposals h-model)
        (heuristic-decompositions frame stage-a-lang
                                  :child-language child-lang
                                  :description-limit stage-a-bound
                                  :child-bound child-bound
                                  :additive-p t :conditional-p nil)
      (check (heuristic-model-p h-model))
      (check (equal (var 0 :int) (heuristic-program h-model)))
      (check (= 1 (length proposals)))
      (check (equal (list :heuristic-additive (var 0 :int))
                    (decomposition-name (first proposals)))))
    (let ((job (start-heuristic-synthesis frame stage-a-lang stage-a-bound
                                          :child-language child-lang
                                          :child-bound child-bound
                                          :additive-p t :conditional-p nil)))
      (check (eq :bounded-exhaustion (message-claim (resume-synthesis job 200000))))
      (check (synthesis-job-best job))
      (check (evaluate-model-run-work (candidate-expression (synthesis-job-best job)) frame))))
  ;; 2. Path B2 (Conditional Exception-Patching / Decision-List Pullback):
  ;;    Rows x0 in {1, 2, 3, 4} follow y = x0, while outlier row x0 = 0 has target y = 9.
  ;;    Stage A condenses `x0` with 1 exception on row x0 = 0; `heuristic-decompositions`
  ;;    synthesizes a separating guard G(x0) and pulls back through `(if G(x0) x0 Z)`,
  ;;    folding all 4 covered rows to `'t` so Stage B synthesizes `Z = '9`.
  (let* ((inputs '((0 . :int)))
         (frame (simple-frame :int inputs '(((0) 9) ((1) 1) ((2) 2) ((3) 3) ((4) 4))))
         (stage-a-lang (make-language :int inputs :operators nil :literals '(0 1)))
         (child-lang (make-language :int inputs :operators nil :literals '(9)))
         (stage-a-bound (+ (header-size inputs :int) 6))
         (child-bound (description-size (lit :int 9) inputs)))
    (multiple-value-bind (proposals h-model)
        (heuristic-decompositions frame stage-a-lang
                                  :child-language child-lang
                                  :description-limit stage-a-bound
                                  :child-bound child-bound
                                  :additive-p nil :conditional-p t)
      (check (heuristic-model-p h-model))
      (check (equal (var 0 :int) (heuristic-program h-model)))
      (check (= 1 (length proposals)))
      (check (eq :heuristic-conditional (first (decomposition-name (first proposals))))))
    (let ((job (start-heuristic-synthesis frame stage-a-lang stage-a-bound
                                          :child-language child-lang
                                          :child-bound child-bound
                                          :additive-p nil :conditional-p t)))
      (check (eq :bounded-exhaustion (message-claim (resume-synthesis job 200000))))
      (check (synthesis-job-best job))
      (check (evaluate-model-run-work (candidate-expression (synthesis-job-best job)) frame)))))

(deftest heuristic-agenda-routing-exact-promotion-and-episode-returns
  ;; Multiple child decompositions where early branches are high-residual decoys and
  ;; the last branch is a promising low-residual branch (`z = (1 + 1) + 1 = 3`, where Stage A
  ;; probe at literal bound sees `'1` has a +2 residual on `:good-offset` vs >100 on decoys).
  (let* ((inputs '((0 . :int)))
         (frame (simple-frame :int inputs '(((0) 3) ((1) 4) ((2) 5) ((3) 6))))
         (root-lang (make-language :int inputs :operators nil :literals '(0)))
         (child-lang (make-language :int inputs
                                    :operators (list (op :+ :int) (op :* :int))
                                    :literals '(0 1)))
         (target-expr (app (op :+ :int)
                           (app (op :+ :int) (lit :int 1) (lit :int 1))
                           (lit :int 1)))
         (child-bound (description-size target-expr inputs))
         (probe-bound (description-size (lit :int 1) inputs))
         (make-proposals
           (lambda ()
             (list (make-decomposition :name :decoy-1
                                       :decoder (app (op :+ :int) (lit :int 100) (var 9 :int))
                                       :child-id 9 :child-type :int
                                       :bindings (list (cons 0 (var 0 :int)))
                                       :language child-lang :bound child-bound)
                   (make-decomposition :name :decoy-2
                                       :decoder (app (op :+ :int) (lit :int 200) (var 9 :int))
                                       :child-id 9 :child-type :int
                                       :bindings (list (cons 0 (var 0 :int)))
                                       :language child-lang :bound child-bound)
                   (make-decomposition :name :decoy-3
                                       :decoder (app (op :+ :int) (lit :int 300) (var 9 :int))
                                       :child-id 9 :child-type :int
                                       :bindings (list (cons 0 (var 0 :int)))
                                       :language child-lang :bound child-bound)
                   (make-decomposition :name :good-offset
                                       :decoder (app (op :+ :int) (var 0 :int) (var 9 :int))
                                       :child-id 9 :child-type :int
                                       :bindings (list (cons 0 (var 0 :int)))
                                       :language child-lang :bound child-bound))))
         (rr-job (start-synthesis frame root-lang 16
                                  :decompositions (funcall make-proposals)
                                  :policy :round-robin :quantum 12))
         (h-batch (start-synthesis frame root-lang 16
                                   :decompositions (funcall make-proposals)
                                   :policy :heuristic :heuristic-bound probe-bound
                                   :heuristic-budget 2000 :quantum 12))
         (h-unit (start-synthesis frame root-lang 16
                                  :decompositions (funcall make-proposals)
                                  :policy :heuristic :heuristic-bound probe-bound
                                  :heuristic-budget 2000 :quantum 12)))
    (resume-synthesis rr-job 500000 :stop-on-first t)
    (resume-synthesis h-batch 500000 :stop-on-first t)
    (check (synthesis-job-best rr-job))
    (check (synthesis-job-best h-batch))
    (check (equal (candidate-expression (synthesis-job-best rr-job))
                  (candidate-expression (synthesis-job-best h-batch))))
    ;; Heuristic agenda routing prioritizes `:good-offset` over the 3 decoys and finds
    ;; the verified root candidate in strictly less total discovery work than round-robin.
    (check (< (candidate-discovery-work (synthesis-job-best h-batch))
              (candidate-discovery-work (synthesis-job-best rr-job))))
    ;; Unit-step resumption parity holds under `:policy :heuristic`.
    (loop for limit from 1 to (ledger-total (synthesis-job-ledger h-batch)) do
      (resume-synthesis h-unit limit :stop-on-first t)
      (check (= limit (ledger-total (synthesis-job-ledger h-unit)))))
    (check (equalp (synthesis-job-ledger h-batch) (synthesis-job-ledger h-unit)))
    (check (equalp (synthesis-job-best h-batch) (synthesis-job-best h-unit)))
    ;; Episode return computation G_t = B_t - B_T - lambda * (W_T - W_t).
    (let ((returns (synthesis-episode-returns h-batch :search-weight 1/1000 :default-baseline 500)))
      (check returns)
      (check (every (lambda (r) (numberp (getf r :return))) returns))
      (check (> (getf (first returns) :bt) (getf (first returns) :b-final))))))

(deftest conflict-nogood-sibling-pruning-and-child-dag-reuse
  ;; 1. Conflict-driven sibling pruning via induced anchor nogoods:
  ;;    Rows :r0 (0 0)->0 and :r1 (0 1)->1 have incompatible targets.
  ;;    When the first pure-projection child (:dep-nil) conflicts on (:r0 :r1),
  ;;    the induced nogood (0 :r0 :r1) prunes subsequent sibling projections (like x0)
  ;;    that alias :r0 and :r1 without pulling back or folding the full frame.
  (let* ((inputs '((0 . :int) (1 . :int)))
         (rows (cons (make-row :key :r0 :known '(0 0) :requirement (singleton-requirement :int 0))
                     (cons (make-row :key :r1 :known '(0 1) :requirement (singleton-requirement :int 1))
                           (loop for k from 2 below 12
                                 collect (make-row :key k :known (list 0 k)
                                                   :requirement (singleton-requirement :int k))))))
         (frame (make-frame (make-schema :inputs inputs :target :int) rows))
         (lang (make-language :int inputs :operators nil :literals nil))
         (proposals (dependency-proposals frame lang 20))
         (job (start-synthesis frame lang 20 :decompositions proposals)))
    (check (eq :bounded-exhaustion (message-claim (resume-synthesis job 200000))))
    (check (synthesis-job-nogoods job))
    (check (some (lambda (msg)
                   (and (eq :conflict (message-claim msg))
                        (getf (message-evidence msg) :reused-nogood)))
                 (synthesis-job-messages job)))
    (check (synthesis-job-best job))
    (check (equal (var 1 :int) (candidate-expression (synthesis-job-best job)))))
  ;; 2. Child-frame DAG caching across observationally equivalent branches:
  ;;    Two decompositions with observationally identical bindings (`(+ x0 0)` vs `x0`)
  ;;    induce the exact same child `(frame, language)`. The second reuses the first's
  ;;    child search while still reconstructing and pricing both at the parent.
  (let* ((inputs '((0 . :int)))
         (frame (simple-frame :int inputs '(((1) 1) ((2) 2) ((3) 3))))
         (root-lang (make-language :int inputs :operators nil :literals '(0)))
         (child-lang (make-language :int inputs :operators nil :literals nil))
         (verbose-binding (app (op :+ :int) (var 0 :int) (lit :int 0)))
         (compact-binding (var 0 :int))
         (p1 (make-decomposition :name :verbose :decoder (var 9 :int) :child-id 9 :child-type :int
                                 :bindings (list (cons 0 verbose-binding))
                                 :language child-lang :bound 20))
         (p2 (make-decomposition :name :compact :decoder (var 9 :int) :child-id 9 :child-type :int
                                 :bindings (list (cons 0 compact-binding))
                                 :language child-lang :bound 20))
         (job (start-synthesis frame root-lang 10 :decompositions (list p1 p2))))
    (check (eq :bounded-exhaustion (message-claim (resume-synthesis job 100000))))
    (check (= 1 (synthesis-job-reused-subproblems job)))
    (check (some (lambda (msg) (eq :subproblem-reused (message-claim msg)))
                 (synthesis-job-messages job)))
    ;; Both reconstructions are verified at the root, and the compact parent `x0` wins over `(+ x0 0)`.
    (check (find verbose-binding (synthesis-job-results job) :key #'candidate-expression :test #'equal))
    (check (find compact-binding (synthesis-job-results job) :key #'candidate-expression :test #'equal))
    (check (equal compact-binding (candidate-expression (synthesis-job-best job))))))
