(in-package #:lisploop)

(defun best-composed-lifting-model (decoder child-id candidates bindings parent-inputs &optional ledger)
  "Compose each candidate child expression with DECODER and BINDINGS and return
the composed parent model with minimum total description size S."
  (let ((best-model nil)
        (best-candidate nil)
        (best-bits nil))
    (dolist (cand candidates)
      (let* ((expr (if (candidate-p cand) (candidate-expression cand) cand))
             (composed (compose-model decoder child-id expr bindings ledger))
             (bits (description-size composed parent-inputs)))
        (when (or (null best-bits) (< bits best-bits))
          (setf best-model composed
                best-candidate cand
                best-bits bits))))
    (values best-model best-candidate best-bits)))

(deftest hard-em-infer-fibers-and-cannot-links
  ;; 1. Confidence ordering: singletons nucleate classes first, cannot-links separate incompatible
  ;;    singletons, and ambiguous finite-set rows merge into compatible classes for free.
  (let* ((schema (make-schema :inputs '((0 . :int)) :target :int))
         (frame (make-frame schema
                            (list (make-row :key :ambig-a :known '(10) :requirement (set-requirement :int '(1 2)))
                                  (make-row :key :sing-2  :known '(20) :requirement (singleton-requirement :int 2))
                                  (make-row :key :sing-3  :known '(30) :requirement (singleton-requirement :int 3))
                                  (make-row :key :ambig-b :known '(40) :requirement (set-requirement :int '(2 3))))))
         (ledger (make-ledger)))
    (multiple-value-bind (classes labels refined partition) (infer-fibers frame ledger)
      (check (= 2 (length classes)))
      (check (equal '(0 0 1 0) labels))
      (check (plusp (ledger-total ledger)))
      (check (equal '((2) (2) (3) (2))
                    (mapcar (lambda (row) (extract-allowed-values (row-requirement row)))
                            (frame-rows refined))))
      (check (equal (frame-rows frame) (reassemble-partition partition)))))
  ;; 2. Purely ambiguous intersecting sets collapse to a single shared singleton fiber via M-step votes.
  (let* ((schema (make-schema :inputs '((0 . :int)) :target :int))
         (frame (make-frame schema
                            (list (make-row :key :s1 :known '(1) :requirement (set-requirement :int '(1 2)))
                                  (make-row :key :s2 :known '(2) :requirement (set-requirement :int '(2 3)))
                                  (make-row :key :s3 :known '(3) :requirement (set-requirement :int '(2 4)))))))
    (multiple-value-bind (classes labels refined) (infer-fibers frame)
      (check (= 1 (length classes)))
      (check (equal '(0 0 0) labels))
      (check (every (lambda (row) (equal '(2) (extract-allowed-values (row-requirement row))))
                    (frame-rows refined))))))

(deftest condense-heuristic-with-priced-residual
  ;; Synthesize an intensional heuristic selector directly over underconstrained fibers with one outlier row.
  ;; The MDL objective prices the outlier in the residual during training and drops it at deployment.
  (let* ((field (gf 5))
         (inputs (list (cons 0 field)))
         (schema (make-schema :domain field :inputs inputs :target field))
         ;; Rows 0..3 follow y = x, while row 4 (x=4) has an outlier target y=0.
         (frame (make-frame schema
                            (list (make-row :key 0 :known '(0) :requirement (set-requirement field '(0 4)))
                                  (make-row :key 1 :known '(1) :requirement (set-requirement field '(1)))
                                  (make-row :key 2 :known '(2) :requirement (set-requirement field '(2)))
                                  (make-row :key 3 :known '(3) :requirement (set-requirement field '(3)))
                                  (make-row :key 4 :known '(4) :requirement (set-requirement field '(0))))))
         (language (make-language field inputs :operators (list (op :+ field)) :literals '(0 1)))
         (ledger (make-ledger))
         (heuristic (condense-heuristic frame language :ledger ledger)))
    (check (heuristic-model-p heuristic))
    (check (plusp (ledger-total ledger)))
    ;; `x0` matches rows 0, 1, 2, 3 and has a 1-row residual on key 4.
    (check (equal (var 0 field) (heuristic-program heuristic)))
    (check (= 1 (length (heuristic-residual heuristic))))
    (check (equal (cons 4 0) (first (heuristic-residual heuristic)))))
  ;; Direct requirement synthesis vs pre-clustering trap:
  ;; When row 0 has fiber {0, 4} at x=0 and row 3 (x=3) has outlier singleton {4},
  ;; pre-clustering fibers before synthesis would merge row 0 into {4} and break `x0` on row 0.
  ;; Evaluating `check-requirement` directly on `{0, 4}` lets `x0` satisfy row 0 (outputting 0)
  ;; with only the single outlier residual on row 3.
  (let* ((field (gf 5))
         (inputs (list (cons 0 field)))
         (schema (make-schema :domain field :inputs inputs :target field))
         (frame (make-frame schema
                            (list (make-row :key 0 :known '(0) :requirement (set-requirement field '(0 4)))
                                  (make-row :key 1 :known '(1) :requirement (set-requirement field '(1)))
                                  (make-row :key 2 :known '(2) :requirement (set-requirement field '(2)))
                                  (make-row :key 3 :known '(3) :requirement (set-requirement field '(4)))
                                  (make-row :key 4 :known '(4) :requirement (set-requirement field '(4))))))
         (language (make-language field inputs :operators (list (op :+ field)) :literals '(0 1)))
         (heuristic (condense-heuristic frame language)))
    (check (equal (var 0 field) (heuristic-program heuristic)))
    (check (= 1 (length (heuristic-residual heuristic))))
    (check (equal (cons 3 4) (first (heuristic-residual heuristic))))))

(deftest hard-em-bridge-vs-leaf-disambiguation
  ;; Four-row bridge-vs-leaf ambiguity trap:
  ;;   Row 0 (bridge): {1, 2}
  ;;   Row 1 (bridge): {2, 3}
  ;;   Row 2 (leaf):   {1, 4}
  ;;   Row 3 (leaf):   {3, 5}
  ;; Naive greedy merging of the two bridge rows into Z=2 strands both leaf rows (K=3 classes).
  ;; Minimal-MDL partition search resolves all permutations into K=2 singleton classes (Z=1 and Z=3).
  (let ((schema (make-schema :inputs '((0 . :int)) :target :int))
        (specs (list (list :b1 '(0) '(1 2))
                     (list :b2 '(1) '(2 3))
                     (list :l1 '(2) '(1 4))
                     (list :l2 '(3) '(3 5)))))
    (dolist (order '((0 1 2 3) (2 3 0 1) (0 2 1 3) (1 3 0 2) (3 1 2 0)))
      (let* ((rows (loop for idx in order
                         for (key known vals) = (nth idx specs)
                         collect (make-row :key key :known known
                                           :requirement (set-requirement :int vals))))
             (frame (make-frame schema rows))
             (ledger (make-ledger)))
        (multiple-value-bind (classes labels refined part) (infer-fibers frame ledger)
          (check (= 2 (length classes)))
          (check (= 4 (length labels)))
          (check (plusp (ledger-total ledger)))
          (check (equal (frame-rows frame) (reassemble-partition part)))
          ;; Every refined row must be narrowed to a singleton {1} or {3} compatible with its original set.
          (let ((class-vals (mapcar (lambda (c) (extract-allowed-values (fiber-class-requirement c)))
                                    classes)))
            (check (or (equal '((1) (3)) class-vals)
                       (equal '((3) (1)) class-vals))))
          (loop for orig-row in (frame-rows frame)
                for ref-row in (frame-rows refined)
                do (let ((orig-vals (extract-allowed-values (row-requirement orig-row)))
                         (ref-vals (extract-allowed-values (row-requirement ref-row))))
                     (check (= 1 (length ref-vals)))
                     (check (member (first ref-vals) orig-vals :test #'equal)))))))))

(deftest hard-em-same-input-must-link-and-conjunct-propagation
  ;; 1. Multiple rows sharing the same input `row-known` must pre-tighten their requirements
  ;;    before clustering, turning three width-3 sets on known=(0) into singleton Z=2.
  (let* ((schema (make-schema :inputs '((0 . :int)) :target :int))
         (frame (make-frame schema
                            (list (make-row :key :r0-a :known '(0) :requirement (set-requirement :int '(1 2 3)))
                                  (make-row :key :r0-b :known '(0) :requirement (set-requirement :int '(2 3 4)))
                                  (make-row :key :r0-c :known '(0) :requirement (set-requirement :int '(1 2 5)))
                                  (make-row :key :r1-a :known '(1) :requirement (set-requirement :int '(3 4)))
                                  (make-row :key :r1-b :known '(1) :requirement (set-requirement :int '(4 5)))))))
    (multiple-value-bind (classes labels refined) (infer-fibers frame)
      (check (= 2 (length classes)))
      (check (equal '(0 0 0 1 1) labels))
      (check (equal '((2) (2) (2) (4) (4))
                    (mapcar (lambda (r) (extract-allowed-values (row-requirement r)))
                            (frame-rows refined))))))
  ;; 2. Multi-conjunct equality propagation on relational pulled-back requirements:
  ;;    When r=0 has `(+ '0 Z) = '1` and `(+ '1 Z) = '2`, and r=1 has `(+ '0 Z) = '3` and `(+ '1 Z) = '4`,
  ;;    same-input pre-tightening builds 2-conjunct trees per r, and `fold-constants` propagates
  ;;    conjunct equalities across trees to detect their mutual incompatibility (`'nil`).
  (let* ((field (gf 7))
         (schema (make-schema :domain field :inputs '((0 . :int)) :target field))
         (z (var 0 field))
         (req (lambda (k c)
                (app (op := field) (app (op :+ field) (lit field k) z) (lit field c))))
         (frame (make-frame schema
                            (list (make-row :key :s0-t0 :known '(0) :requirement (funcall req 0 1))
                                  (make-row :key :s0-t1 :known '(0) :requirement (funcall req 1 2))
                                  (make-row :key :s0-t2 :known '(0) :requirement (funcall req 2 3))
                                  (make-row :key :s1-t0 :known '(1) :requirement (funcall req 0 3))
                                  (make-row :key :s1-t1 :known '(1) :requirement (funcall req 1 4))
                                  (make-row :key :s1-t2 :known '(1) :requirement (funcall req 2 5))))))
    (multiple-value-bind (classes labels) (infer-fibers frame)
      (check (= 2 (length classes)))
      (check (equal '(0 0 0 1 1 1) labels)))))

(deftest explicit-dependency-projection-and-fiber-refinement
  ;; 1. Unconstrained `'t` rows and ambiguous `{1, 3}` rows in a multi-input `(r, t)` frame:
  ;;    explicitly hypothesize `X0` (`r`) as the context before tightening its buckets.
  ;;    The unprojected frame must retain its unconstrained rows.
  (let* ((schema (make-schema :inputs '((0 . :int) (1 . :int)) :target :int))
         (frame (make-frame schema
                            (list (make-row :key :unconstrained-r1 :known '(1 0) :requirement (lit :bool t))
                                  (make-row :key :ambig-r1         :known '(1 1) :requirement (set-requirement :int '(1 3)))
                                  (make-row :key :sing-r0-a        :known '(0 2) :requirement (singleton-requirement :int 1))
                                  (make-row :key :sing-r0-b        :known '(0 3) :requirement (singleton-requirement :int 1))
                                  (make-row :key :sing-r1-a        :known '(1 2) :requirement (singleton-requirement :int 3))
                                  (make-row :key :sing-r1-b        :known '(1 3) :requirement (singleton-requirement :int 3))
                                  (make-row :key :ambig-r0         :known '(0 1) :requirement (set-requirement :int '(1 3)))
                                  (make-row :key :unconstrained-r0 :known '(0 0) :requirement (lit :bool t))))))
    (let ((original (tighten-same-input-requirements frame)))
      (check (unconstrained-requirement-p (aref original 0)))
      (check (unconstrained-requirement-p (aref original 7))))
    ;; Choosing r as the context is an explicit hypothesis, not preprocessing.
    (multiple-value-bind (classes labels refined)
        (infer-fibers (project-frame-rows frame (list (cons 0 (var 0 :int)))))
      (check (= 2 (length classes)))
      ;; Rows 0, 1, 4, 5 have r=1 (target 3); rows 2, 3, 6, 7 have r=0 (target 1).
      (let ((targets (mapcar (lambda (r) (first (extract-allowed-values (row-requirement r))))
                             (frame-rows refined))))
        (check (equal '(3 3 1 1 3 3 1 1) targets))
        (check (= (nth 0 labels) (nth 4 labels)))
        (check (= (nth 1 labels) (nth 4 labels)))
        (check (= (nth 6 labels) (nth 2 labels)))
        (check (= (nth 7 labels) (nth 2 labels)))))))

(deftest hard-em-relational-member-filtering-and-cannot-links
  ;; 1. Subexpression `:member` filtering and 1-element `:member` normalization in `fold-constants`:
  ;;    `(member (+ '1 Z) '(2))` normalizes to `(= (+ '1 Z) '2)`, and conjoining
  ;;    `(member (+ '1 Z) '(2 4))` with `(= (+ '1 Z) '4)` filters the set to `(= (+ '1 Z) '4)`.
  (let* ((field (gf 7))
         (z (var 0 field))
         (term (app (op :+ field) (lit field 1) z))
         (unit-member (app (op :member field) term (lit (sequence-type field) '(2))))
         (pair-member (app (op :member field) term (lit (sequence-type field) '(2 4))))
         (eq-four (app (op := field) term (lit field 4)))
         (eq-five (app (op := field) term (lit field 5))))
    (check (equal (app (op := field) term (lit field 2))
                  (fold-constants unit-member)))
    (check (equal eq-four
                  (conjoin-requirements pair-member eq-four)))
    (check (equal eq-four
                  (conjoin-requirements eq-four pair-member)))
    (check (equal (lit :bool nil)
                  (conjoin-requirements pair-member eq-five))))
  ;; 2. Cannot-link soundness on contradictory frames: when two rows share identical `row-known`
  ;;    and have incompatible singletons `Z=1` vs `Z=3`, tightening preserves the contradiction
  ;;    explicitly; `frame-conflict-p` detects unsatisfiable rows in the refined frame.
  (let* ((schema (make-schema :inputs '((0 . :int)) :target :int))
         (bad-frame (make-frame schema
                                (list (make-row :key :c0 :known '(5) :requirement (singleton-requirement :int 1))
                                      (make-row :key :c1 :known '(5) :requirement (singleton-requirement :int 3))))))
    (multiple-value-bind (classes labels refined) (infer-fibers bad-frame)
      (check (= 2 (length classes)))
      (check (equal '(0 1) labels))
      (let ((conflict (frame-conflict-p refined)))
        (check conflict)
        (check (eq :unsatisfiable-row (frame-conflict-kind conflict)))))))

(deftest hard-em-multi-regime-and-higher-arity-fibers
  ;; 1. Width-3 bridge vs non-singleton clusters:
  ;;    Row 0: {1, 2, 3} (bridge via 3)
  ;;    Row 1: {3, 4, 5} (bridge via 3)
  ;;    Row 2: {1, 2, 6} (leaf for {1, 2})
  ;;    Row 3: {4, 5, 7} (leaf for {4, 5})
  ;;    Merging Row 0 and Row 1 into {3} would require K=3 classes.
  ;;    Minimal-MDL partition search finds the K=2 partition {1, 2} and {4, 5}.
  (let* ((schema (make-schema :inputs '((0 . :int)) :target :int))
         (frame (make-frame schema
                            (list (make-row :key :w0 :known '(0) :requirement (set-requirement :int '(1 2 3)))
                                  (make-row :key :w1 :known '(1) :requirement (set-requirement :int '(3 4 5)))
                                  (make-row :key :w2 :known '(2) :requirement (set-requirement :int '(1 2 6)))
                                  (make-row :key :w3 :known '(3) :requirement (set-requirement :int '(4 5 7)))))))
    (multiple-value-bind (classes labels refined) (infer-fibers frame)
      (check (= 2 (length classes)))
      (check (equal '(0 1 0 1) labels))
      (check (equal '((1 2) (4 5) (1 2) (4 5))
                    (mapcar (lambda (r) (extract-allowed-values (row-requirement r)))
                            (frame-rows refined))))))
  ;; 2. Three-regime (K=3) disambiguation with 2-way and 3-way ambiguous rows resolved by conflict-free projection onto r:
  (let* ((schema (make-schema :inputs '((0 . :int) (1 . :int)) :target :int))
         (frame (make-frame schema
                            (list (make-row :key :r0-leaf1 :known '(0 0) :requirement (set-requirement :int '(1 10)))
                                  (make-row :key :r0-leaf2 :known '(0 1) :requirement (set-requirement :int '(1 11)))
                                  (make-row :key :r1-leaf1 :known '(1 0) :requirement (set-requirement :int '(3 20)))
                                  (make-row :key :r1-leaf2 :known '(1 1) :requirement (set-requirement :int '(3 21)))
                                  (make-row :key :r2-leaf1 :known '(2 0) :requirement (set-requirement :int '(5 30)))
                                  (make-row :key :r2-leaf2 :known '(2 1) :requirement (set-requirement :int '(5 31)))
                                  ;; Ambiguous rows compatible with multiple regimes, disambiguated by r in {0,1,2}
                                  (make-row :key :r2-ambig :known '(2 2) :requirement (set-requirement :int '(1 3 5)))
                                  (make-row :key :r1-ambig :known '(1 2) :requirement (set-requirement :int '(1 3)))
                                  (make-row :key :r0-ambig :known '(0 2) :requirement (set-requirement :int '(1 5)))))))
    (multiple-value-bind (classes labels refined)
        (infer-fibers (project-frame-rows frame (list (cons 0 (var 0 :int)))))
      (check (= 3 (length classes)))
      (check (equal '(0 0 1 1 2 2 2 1 0) labels))
      (check (equal '((1) (1) (3) (3) (5) (5) (5) (3) (1))
                    (mapcar (lambda (r) (extract-allowed-values (row-requirement r)))
                            (frame-rows refined)))))))

(deftest m5-supplied-lift-and-repetition-compression
  ;; Compression savings grow monotonically with repetitions (1, 2, 4, 8)
  (let ((field (gf 7))
        (prev-saving 0))
    (dolist (reps '(1 2 4 8))
      (let ((ledger (make-ledger)))
        (multiple-value-bind (frame decoder r-to-j row-labels records)
            (gf7-lifting-fixture :offsets '(1 3) :steps 7 :repetitions reps :ledger ledger)
          (when (= reps 1)
            ;; Occurrence keys are distinct from supplied coordinate r
            (check (= 14 (length (frame-rows frame))))
            (check (= 14 (length records)))
            (check (equal '(:seq 0 0) (row-key (first (frame-rows frame)))))
            (check (equal '(0 0) (row-known (first (frame-rows frame)))))
            (check (equal '(0 0 0 0 0 0 0 1 1 1 1 1 1 1) row-labels)))
          (let* ((parent-inputs (schema-inputs (frame-schema frame)))
                 (bindings (list (cons 3 r-to-j)))
                 (child (pullback-frame frame decoder 9 field bindings ledger))
                 (child-inputs (schema-inputs (frame-schema child)))
                 (job (start-search child (make-language field child-inputs)))
                 (bound (description-size (app (op :+ field) (lit field 1)
                                               (app (op :* field) (lit field 2) (var 3 field)))
                                          child-inputs)))
            (when (= reps 1)
              ;; Child receives only j in GF(7); requirements remain symbolic predicates without inverse enumeration
              (check (equal (list (cons 3 field)) child-inputs))
              (check (every (lambda (r) (eq :unknown (extract-allowed-values (row-requirement r))))
                            (frame-rows child)))
              (check (null (frame-conflict-p child :ledger ledger))))
            (check (eq :bounded-exhaustion (message-claim (resume-search job bound 10000000))))
            (check (search-job-best job))
            (multiple-value-bind (lifted-model chosen-cand lifted-bits)
                (best-composed-lifting-model decoder 9 (search-job-results job) bindings parent-inputs ledger)
              (declare (ignore chosen-cand))
              (let* ((lookup-bits (description-size (lookup-model frame ledger) parent-inputs))
                     (seq-bits (description-size (lit (sequence-type field) (mapcar #'fourth records)) nil))
                     (saving (- lookup-bits lifted-bits)))
                (check (< lifted-bits lookup-bits))
                (check (plusp (replay-model lifted-model frame ledger)))
                (check (> saving prev-saving))
                (when (= reps 8)
                  (check (< lifted-bits seq-bits)))
                (setf prev-saving saving)))))))))

(deftest m5-contradictory-t-only-and-context-restoration
  (let ((field (gf 7))
        (ledger (make-ledger)))
    (multiple-value-bind (frame decoder r-to-j row-labels records)
        (gf7-lifting-fixture :offsets '(1 3) :steps 7 :repetitions 1 :ledger ledger)
      ;; 1. Restricting child to t only produces an immediate frame conflict and 0 solutions
      (let* ((t-bindings (list (cons 3 (var 1 :int))))
             (bad-child (pullback-frame frame decoder 9 field t-bindings ledger))
             (bad-inputs (schema-inputs (frame-schema bad-child)))
             (conflict (frame-conflict-p bad-child :ledger ledger))
             (bad-job (start-search bad-child (make-language field bad-inputs))))
        (check conflict)
        (check (eq :incompatible-rows (frame-conflict-kind conflict)))
        (check (equal '((:seq 0 0) (:seq 1 0)) (frame-conflict-keys conflict)))
        (check (eq :bounded-exhaustion
                   (message-claim (resume-search bad-job (+ (header-size bad-inputs field) 16) 1000000))))
        (check (null (search-job-results bad-job))))
      ;; 2. Encoding labels over t only fails conflict check and lookup-model;
      ;;    applying r->j on a t-only parent frame lacking r fails typing/scope check.
      (let* ((t-label-frame (context-label-frame frame row-labels
                                                 :bindings (list (cons 1 (var 1 :int)))
                                                 :label-type field :ledger ledger))
             (t-only-parent (orient-observations (list :int :int field) records '(1) '(2)
                                                 :lookup-p t :ledger ledger)))
        (check (frame-conflict-p t-label-frame :ledger ledger))
        (raises (lookup-model t-label-frame ledger))
        (raises (pullback-frame t-only-parent decoder 9 field
                                (list (cons 3 r-to-j)) ledger)))
      ;; 3. Restoring context via paid lookup-model over parent's r repairs the frame and replays.
      (let* ((r-label-frame (context-label-frame frame row-labels
                                                 :bindings (list (cons 0 (var 0 :int)))
                                                 :label-type field :ledger ledger))
             (paid-r-to-j (lookup-model r-label-frame ledger))
             (restored-bindings (list (cons 3 paid-r-to-j)))
             (restored-child (pullback-frame frame decoder 9 field restored-bindings ledger))
             (child-inputs (schema-inputs (frame-schema restored-child)))
             (job (start-search restored-child (make-language field child-inputs)))
             (bound (description-size (app (op :+ field) (lit field 1)
                                           (app (op :+ field) (var 3 field) (var 3 field)))
                                      child-inputs)))
        (check (null (frame-conflict-p restored-child :ledger ledger)))
        (check (eq :bounded-exhaustion (message-claim (resume-search job bound 10000000))))
        (let ((composed (compose-model decoder 9 (candidate-expression (search-job-best job))
                                       restored-bindings ledger)))
          (check (plusp (replay-model composed frame ledger))))))))

(deftest m5-unsupervised-hard-em-discovery-and-selector-deployment
  (let ((field (gf 7))
        (ledger (make-ledger)))
    (multiple-value-bind (frame decoder supplied-r-to-j true-labels)
        (gf7-lifting-fixture :offsets '(1 3) :steps 7 :repetitions 2 :ledger ledger)
      (declare (ignore supplied-r-to-j))
      ;; 1. Unsupervised discovery both directly on raw pulled-back requirements and via M4 certified solver
      (let* ((raw-child (pullback-frame frame decoder 9 field (list (cons 0 (var 0 :int))) ledger))
             (plus-solver (arithmetic-control field :+ 1))
             (prop (propagate-requirements raw-child plus-solver ledger)))
        (check (certified-solve-discovery-p plus-solver))
        (check (= 28 (propagation-narrowed prop)))
        (multiple-value-bind (raw-classes raw-labels) (infer-fibers raw-child ledger)
          (multiple-value-bind (classes discovered-labels refined-frame part)
              (infer-fibers (propagation-frame prop) ledger)
            (declare (ignore refined-frame))
            (check (= 2 (length raw-classes)))
            (check (= 2 (length classes)))
            (check (equal true-labels raw-labels))
            (check (equal true-labels discovered-labels))
            (check (equal (frame-rows (propagation-frame prop)) (reassemble-partition part)))
            (check (equal (list (singleton-requirement field 1)
                                (singleton-requirement field 3))
                          (mapcar #'fiber-class-requirement classes)))
            ;; 2. Deploy discovered labels via paid lookup-model over r AND verify M4 propagation
            ;;    amortizes child search work compared to unpropagated child search.
            (let* ((label-frame (context-label-frame frame discovered-labels
                                                     :bindings (list (cons 0 (var 0 :int)))
                                                     :label-type field :ledger ledger))
                   (paid-map (lookup-model label-frame ledger))
                   (bindings (list (cons 3 paid-map)))
                   (unprop-child (pullback-frame frame decoder 9 field bindings ledger))
                   (prop-child (propagation-frame (propagate-requirements unprop-child plus-solver ledger)))
                   (child-inputs (schema-inputs (frame-schema unprop-child)))
                   (bound (description-size (app (op :+ field) (lit field 1)
                                                 (app (op :+ field) (var 3 field) (var 3 field)))
                                            child-inputs))
                   (unprop-job (start-search unprop-child (make-language field child-inputs)))
                   (prop-job (start-search prop-child (make-language field child-inputs))))
              (check (eq :bounded-exhaustion (message-claim (resume-search unprop-job bound 10000000))))
              (check (eq :bounded-exhaustion (message-claim (resume-search prop-job bound 10000000))))
              (check (equal (candidate-expression (search-job-best unprop-job))
                            (candidate-expression (search-job-best prop-job))))
              ;; Certified M4 propagation eliminates repeated iota(t) lookup during child search
              (check (< (ledger-total (search-job-ledger prop-job))
                        (ledger-total (search-job-ledger unprop-job))))
              (let ((composed (compose-model decoder 9 (candidate-expression (search-job-best prop-job))
                                             bindings ledger)))
                (check (plusp (replay-model composed frame ledger)))))
            ;; 3. Deploy discovered labels via condense-heuristic intensional selector
            (let* ((regime-records
                     (loop for row in (frame-rows frame)
                           for j in discovered-labels
                           collect (list (row-key row) j (second (row-known row))
                                         (first (extract-allowed-values (row-requirement row))))))
                   (regime-frame (orient-observations (list field :int field) regime-records '(0 1) '(2)
                                                      :lookup-p t :ledger ledger))
                   (regime-label-frame (context-label-frame regime-frame discovered-labels
                                                            :bindings (list (cons 0 (var 0 field)))
                                                            :label-type field :ledger ledger))
                   (selector-lang (make-language field (list (cons 0 field))
                                                 :operators (list (op :+ field)) :literals '(0 1)))
                   (heuristic (condense-heuristic regime-label-frame selector-lang :ledger ledger))
                   (sel-bindings (list (cons 3 (heuristic-program heuristic))))
                   (sel-child (propagation-frame
                               (propagate-requirements
                                (pullback-frame regime-frame decoder 9 field sel-bindings ledger)
                                plus-solver ledger)))
                   (sel-inputs (schema-inputs (frame-schema sel-child)))
                   (sel-job (start-search sel-child (make-language field sel-inputs)))
                   (sel-bound (description-size (app (op :+ field) (lit field 1)
                                                     (app (op :+ field) (var 3 field) (var 3 field)))
                                                sel-inputs)))
              (check (heuristic-exact-p heuristic))
              (check (equal (var 0 field) (heuristic-program heuristic)))
              (check (eq :bounded-exhaustion (message-claim (resume-search sel-job sel-bound 10000000))))
              (let ((composed (compose-model decoder 9 (candidate-expression (search-job-best sel-job))
                                             sel-bindings ledger)))
                (check (plusp (replay-model composed regime-frame ledger)))))))))))

(deftest m5-integer-lifting-and-tentative-propagation
  ;; End-to-end Milestone 5 lifting over :INT (y_{j,t} = a_j + t with offsets a_0=1, a_1=3):
  ;; 1. Supplied lift r -> j in :INT and repetition compression scaling (reps = 1, 2, 4)
  (let ((prev-saving most-negative-fixnum))
    (dolist (reps '(1 2 4))
      (let ((ledger (make-ledger)))
        (multiple-value-bind (frame decoder r-to-j row-labels records)
            (integer-lifting-fixture :offsets '(1 3) :steps 7 :repetitions reps :ledger ledger)
          (declare (ignore row-labels records))
          (let* ((parent-inputs (schema-inputs (frame-schema frame)))
                 (bindings (list (cons 3 r-to-j)))
                 (child (pullback-frame frame decoder 9 :int bindings ledger))
                 (child-inputs (schema-inputs (frame-schema child)))
                 (job (start-search child (make-language :int child-inputs :literals '(0 1 2 3))))
                 (bound (description-size (app (op :+ :int) (lit :int 1)
                                               (app (op :+ :int) (var 3 :int) (var 3 :int)))
                                          child-inputs)))
            (check (null (frame-conflict-p child :ledger ledger)))
            (check (eq :bounded-exhaustion (message-claim (resume-search job bound 10000000))))
            (multiple-value-bind (lifted-model chosen-cand lifted-bits)
                (best-composed-lifting-model decoder 9 (search-job-results job) bindings parent-inputs ledger)
              (declare (ignore chosen-cand))
              (let* ((lookup-bits (description-size (lookup-model frame ledger) parent-inputs))
                     (saving (- lookup-bits lifted-bits)))
                (check (< lifted-bits lookup-bits))
                (check (plusp (replay-model lifted-model frame ledger)))
                (check (> saving prev-saving))
                (setf prev-saving saving))))))))
  ;; 2. Contradictory t-only restriction on :INT, unavailable context rejection, and paid restoration
  (let ((ledger (make-ledger)))
    (multiple-value-bind (frame decoder r-to-j row-labels records)
        (integer-lifting-fixture :offsets '(1 3) :steps 7 :repetitions 1 :ledger ledger)
      (let* ((t-bindings (list (cons 3 (var 1 :int))))
             (bad-child (pullback-frame frame decoder 9 :int t-bindings ledger))
             (bad-inputs (schema-inputs (frame-schema bad-child)))
             (conflict (frame-conflict-p bad-child :ledger ledger))
             (bad-job (start-search bad-child (make-language :int bad-inputs :literals '(0 1 2 3))))
             (t-label-frame (context-label-frame frame row-labels
                                                 :bindings (list (cons 1 (var 1 :int)))
                                                 :label-type :int :ledger ledger))
             (t-only-parent (orient-observations '(:int :int :int) records '(1) '(2)
                                                 :lookup-p t :ledger ledger)))
        (check conflict)
        (check (eq :incompatible-rows (frame-conflict-kind conflict)))
        (check (equal '((:seq 0 0) (:seq 1 0)) (frame-conflict-keys conflict)))
        (check (eq :bounded-exhaustion
                   (message-claim (resume-search bad-job (+ (header-size bad-inputs :int) 16) 1000000))))
        (check (null (search-job-results bad-job)))
        (check (frame-conflict-p t-label-frame :ledger ledger))
        (raises (lookup-model t-label-frame ledger))
        (raises (pullback-frame t-only-parent decoder 9 :int (list (cons 3 r-to-j)) ledger)))))
  ;; 3. Unsupervised Hard-EM fiber discovery on :INT (raw relational + tentative M4 solver propagation)
  (let ((ledger (make-ledger)))
    (multiple-value-bind (frame decoder supplied-r-to-j true-labels)
        (integer-lifting-fixture :offsets '(1 3) :steps 7 :repetitions 2 :ledger ledger)
      (declare (ignore supplied-r-to-j))
      (let* ((raw-child (pullback-frame frame decoder 9 :int (list (cons 0 (var 0 :int))) ledger))
             (plus-solver (arithmetic-control :int :+ 1))
             (prop (propagate-requirements raw-child plus-solver ledger)))
        ;; Integer solver is tentative (:conjecture), not certified (:validated), yet suggests all 28 rows via forward replay
        (check (not (certified-solve-discovery-p plus-solver)))
        (check (eq :conjecture (law-validation-status (solve-discovery-validation plus-solver))))
        (check (= 0 (propagation-narrowed prop)))
        (check (= 28 (propagation-suggested prop)))
        (check (= 0 (propagation-rejected prop)))
        (multiple-value-bind (raw-classes raw-labels) (infer-fibers raw-child ledger)
          (multiple-value-bind (classes discovered-labels) (infer-fibers (propagation-frame prop) ledger)
            (check (= 2 (length raw-classes)))
            (check (= 2 (length classes)))
            (check (equal true-labels raw-labels))
            (check (equal true-labels discovered-labels))
            (check (equal (list (singleton-requirement :int 1)
                                (singleton-requirement :int 3))
                          (mapcar #'fiber-class-requirement classes)))
            ;; Deploy discovered :INT labels via paid lookup-model + multi-lane tentative propagation search
            (let* ((label-frame (context-label-frame frame discovered-labels
                                                     :bindings (list (cons 0 (var 0 :int)))
                                                     :label-type :int :ledger ledger))
                   (paid-map (lookup-model label-frame ledger))
                   (bindings (list (cons 3 paid-map)))
                   (child-prop (propagate-requirements (pullback-frame frame decoder 9 :int bindings ledger)
                                                       plus-solver ledger))
                   (child-inputs (schema-inputs (frame-schema (propagation-frame child-prop))))
                   (child-lang (make-language :int child-inputs :literals '(0 1 2 3)))
                   (bound (description-size (app (op :+ :int) (lit :int 1)
                                                 (app (op :+ :int) (var 3 :int) (var 3 :int)))
                                            child-inputs))
                   (psearch (start-propagation-search child-prop child-lang)))
              (resume-propagation-search psearch bound 10000000)
              (check (propagation-search-best psearch))
              (let ((composed (compose-model decoder 9 (candidate-expression (propagation-search-best psearch))
                                             bindings ledger)))
                (check (plusp (replay-model composed frame ledger)))))
            ;; Deploy discovered :INT labels via condense-heuristic intensional selector
            (let* ((regime-records
                     (loop for row in (frame-rows frame)
                           for j in discovered-labels
                           collect (list (row-key row) j (second (row-known row))
                                         (first (extract-allowed-values (row-requirement row))))))
                   (regime-frame (orient-observations '(:int :int :int) regime-records '(0 1) '(2)
                                                      :lookup-p t :ledger ledger))
                   (regime-label-frame (context-label-frame regime-frame discovered-labels
                                                            :bindings (list (cons 0 (var 0 :int)))
                                                            :label-type :int :ledger ledger))
                   (selector-lang (make-language :int '((0 . :int))
                                                 :operators (list (op :+ :int)) :literals '(0 1)))
                   (heuristic (condense-heuristic regime-label-frame selector-lang :ledger ledger)))
              (check (heuristic-exact-p heuristic))
              (check (equal (var 0 :int) (heuristic-program heuristic))))))))))
