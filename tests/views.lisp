(in-package #:lisploop)

(deftest view-discovery-and-three-way-comparison
  ;; 1. Interleaved :INT sequences (r=0,1,2,3 with alternating offsets a_0=1, a_1=3):
  ;;    - Non-separating guards `(= r '0)` and `(= t '0)` are immediately refuted by `frame-conflict-p` (M8C).
  ;;    - Parity guard `(= (- r (* (/ r '2) '2)) '0)` cleanly separates the two regimes.
  ;;    - Shared decoder `d(X, (if G Z1 Z0))` is strictly smaller than separate per-part models `(if G M1 M0)`,
  ;;      which is strictly smaller than unfactored parent lookup `(r,t) -> y`.
  (let ((ledger (make-ledger)))
    (multiple-value-bind (frame decoder)
        (integer-lifting-fixture :offsets '(1 3) :steps 7 :repetitions 2 :ledger ledger)
      (let* ((parent-inputs (schema-inputs (frame-schema frame)))
             (t-bindings (list (cons 1 (var 1 :int))))
             (t-inputs (list (cons 1 :int)))
             (child-lang (make-language :int t-inputs :operators (list (op :+ :int)) :literals '(1 3)))
             (child-bound (description-size (app (op :+ :int) (lit :int 3) (var 1 :int)) t-inputs))
             (plus-solver (arithmetic-control :int :+ 1))
             (parity-guard (parity-zero-guard 0))
             (r0-guard (app (op := :int) (var 0 :int) (lit :int 0)))
             (t0-guard (app (op := :int) (var 1 :int) (lit :int 0))))
        ;; M8C conflict pruning on non-separating guards
        (multiple-value-bind (r0-props r0-conflict)
            (synthesize-supplied-partition-view frame r0-guard child-lang
                                                :child-bindings t-bindings :child-bound child-bound
                                                :decoder decoder :child-id 9 :child-type :int
                                                :solver plus-solver :ledger ledger)
          (check (null r0-props))
          (check r0-conflict)
          (check (eq :incompatible-rows (frame-conflict-kind (partition-view-proposal-conflict r0-conflict)))))
        (multiple-value-bind (t0-props t0-conflict)
            (synthesize-supplied-partition-view frame t0-guard child-lang
                                                :child-bindings t-bindings :child-bound child-bound
                                                :decoder decoder :child-id 9 :child-type :int
                                                :solver plus-solver :ledger ledger)
          (check (null t0-props))
          (check t0-conflict)
          (check (eq :incompatible-rows (frame-conflict-kind (partition-view-proposal-conflict t0-conflict)))))
        ;; Valid parity view synthesis & 3-way comparison
        (multiple-value-bind (props conflict)
            (synthesize-supplied-partition-view frame parity-guard child-lang
                                                :child-bindings t-bindings :child-bound child-bound
                                                :decoder decoder :child-id 9 :child-type :int
                                                :solver plus-solver :ledger ledger)
          (check (null conflict))
          (let ((sep-prop (find :separate-parts props :key #'partition-view-proposal-kind))
                (shared-prop (find :shared-decoder props :key #'partition-view-proposal-kind))
                (lookup-bits (description-size (lookup-model frame ledger) parent-inputs)))
            (check sep-prop)
            (check shared-prop)
            (check (< (partition-view-proposal-bits shared-prop)
                      (partition-view-proposal-bits sep-prop)))
            (check (< (partition-view-proposal-bits sep-prop) lookup-bits))
            (check (plusp (replay-model (partition-view-proposal-model sep-prop) frame ledger)))
            (check (plusp (replay-model (partition-view-proposal-model shared-prop) frame ledger))))))))
  ;; 2. Autonomous grammar-enumerated view discovery on GF(7) two-regime sequences
  (let ((field (gf 7))
        (ledger (make-ledger)))
    (multiple-value-bind (gf-frame gf-decoder)
        (gf7-lifting-fixture :offsets '(1 3) :steps 7 :repetitions 1 :ledger ledger)
      (let* ((parent-inputs (schema-inputs (frame-schema gf-frame)))
             (iota-t (gf7-iota-conversion (var 1 :int) :steps 7 :ledger ledger))
             (t-bindings (list (cons 1 iota-t)))
             (t-inputs (list (cons 1 field)))
             (guard-lang (make-language :int parent-inputs :operators (list (op := :int)) :literals '(0 1)))
             (guard-bound (description-size (app (op := :int) (var 0 :int) (lit :int 0)) parent-inputs))
             (part-expr-0 (app (op :+ field) (var 1 field) (lit field 1)))
             (part-expr-1 (app (op :+ field) (var 1 field) (lit field 3)))
             (child-lang (make-language field t-inputs
                                        :operators (list (op :+ field))
                                        :literals '(1 3)))
             (child-bound (max (description-size part-expr-0 t-inputs)
                               (description-size part-expr-1 t-inputs)))
             (plus-solver (arithmetic-control field :+ 1)))
        (multiple-value-bind (best-prop proposals conflicts)
            (discover-partition-views gf-frame guard-lang child-lang
                                      :guard-bound guard-bound
                                      :child-bindings t-bindings
                                      :child-bound child-bound
                                      :decoder gf-decoder :child-id 9 :child-type field
                                      :solver plus-solver :ledger ledger)
          (let ((sep-prop (find :separate-parts proposals :key #'partition-view-proposal-kind))
                (shared-prop (find :shared-decoder proposals :key #'partition-view-proposal-kind))
                (lookup-prop (find :lookup proposals :key #'partition-view-proposal-kind)))
            (check best-prop)
            (check sep-prop)
            (check shared-prop)
            (check lookup-prop)
            (check (plusp (length conflicts)))
            (check (eq :shared-decoder (partition-view-proposal-kind best-prop)))
            (check (< (partition-view-proposal-bits shared-prop)
                      (partition-view-proposal-bits lookup-prop)))
            (check (< (partition-view-proposal-bits shared-prop)
                      (partition-view-proposal-bits sep-prop)))
            (check (plusp (replay-model (partition-view-proposal-model best-prop) gf-frame ledger)))))))))

(deftest view-physical-shuffle-and-permutation-reconstruction
  (let ((ledger (make-ledger)))
    (multiple-value-bind (frame decoder supplied-r-to-j true-labels records)
        (integer-lifting-fixture :offsets '(1 3) :steps 7 :repetitions 2 :ledger ledger)
      (declare (ignore supplied-r-to-j true-labels))
      (let* ((n (length (frame-rows frame)))
             (perm (append (reverse (loop for i below n by 2 collect i))
                           (loop for i from 1 below n by 2 collect i)))
             (shuffled-frame (shuffle-frame-rows frame perm ledger))
             (parity-guard (parity-zero-guard 0))
             (t-bindings (list (cons 1 (var 1 :int))))
             (t-inputs (list (cons 1 :int)))
             (child-lang (make-language :int t-inputs :operators (list (op :+ :int)) :literals '(1 3)))
             (child-bound (description-size (app (op :+ :int) (lit :int 3) (var 1 :int)) t-inputs))
             (plus-solver (arithmetic-control :int :+ 1)))
        ;; 1. Physical storage shuffle preserves discovered models, bit sizes, and replay work
        (multiple-value-bind (orig-props)
            (synthesize-supplied-partition-view frame parity-guard child-lang
                                                :child-bindings t-bindings :child-bound child-bound
                                                :decoder decoder :child-id 9 :child-type :int
                                                :solver plus-solver :ledger ledger)
          (multiple-value-bind (shuf-props)
              (synthesize-supplied-partition-view shuffled-frame parity-guard child-lang
                                                  :child-bindings t-bindings :child-bound child-bound
                                                  :decoder decoder :child-id 9 :child-type :int
                                                  :solver plus-solver :ledger ledger)
            (let ((orig-shared (find :shared-decoder orig-props :key #'partition-view-proposal-kind))
                  (shuf-shared (find :shared-decoder shuf-props :key #'partition-view-proposal-kind)))
              (check (equal (partition-view-proposal-model orig-shared)
                            (partition-view-proposal-model shuf-shared)))
              (check (= (partition-view-proposal-bits orig-shared)
                        (partition-view-proposal-bits shuf-shared)))
              (check (= (replay-model (partition-view-proposal-model orig-shared) frame ledger)
                        (replay-model (partition-view-proposal-model shuf-shared) shuffled-frame ledger))))))
        ;; 2. Ordered sequence grouping with ties/multiplicity retains and prices inverse permutation
        (let* ((ordered-targets (mapcar #'fourth records))
               (value-labels (mapcar (lambda (v) (mod v 2)) ordered-targets))
               (val-part (partition-rows ordered-targets value-labels ledger))
               (concat-groups (apply #'append (partition-groups val-part)))
               (pmodel (partition-model val-part :int ledger))
               (decoded-pmodel (decode-model (encode-model pmodel nil)))
               (pmodel-run (evaluate decoded-pmodel nil nil :ledger ledger)))
          (check (not (equal ordered-targets concat-groups)))
          (check (eq :value (evaluation-status pmodel-run)))
          (check (equal ordered-targets (evaluation-value pmodel-run)))
          (check (equal ordered-targets (reassemble-partition val-part ledger))))
        ;; 3. Target-leakage control: withholding `r` leaves 0 conflict-free runtime views over `t`
        (let* ((t-only-frame (orient-observations '(:int :int :int) records '(1) '(2)
                                                  :lookup-p t :ledger ledger))
               (t-guard-lang (make-language :int '((1 . :int)) :operators (list (op := :int)) :literals '(0 1 2))))
          (multiple-value-bind (best-t-prop t-props t-conflicts)
              (discover-partition-views t-only-frame t-guard-lang child-lang
                                        :guard-bound (description-size (app (op := :int) (var 1 :int) (lit :int 2)) '((1 . :int)))
                                        :child-bound child-bound :ledger ledger)
            (check (null best-t-prop))
            (check (null t-props))
            (check (plusp (length t-conflicts)))))
        ;; 4. Computed `pairs` and `anchors` from view partitions and `infer-fibers`
        (multiple-value-bind (true-frame false-frame labels part linked-frame)
            (evaluate-guard-partition frame parity-guard :child-bindings t-bindings :ledger ledger)
          (declare (ignore true-frame false-frame labels part))
          (check (= (- (length (frame-rows frame)) 2) (length (frame-pairs linked-frame))))
          (check (= 2 (length (frame-anchors linked-frame))))
          ;; Passing `linked-frame` into `make-observation-scope` validates `pairs` and `anchors`
          (let* ((parent-inputs (schema-inputs (frame-schema linked-frame)))
                 (scope (make-observation-scope linked-frame
                                                (make-language :int parent-inputs
                                                               :operators (list (op := :int))
                                                               :literals '(0))))
                 (obs-job (start-observation-search scope :expressions (list parity-guard))))
            (resume-observation-search obs-job (description-size parity-guard parent-inputs) 100000)
            (check (= 1 (length (observation-invariants obs-job))))))
        (let ((child-frame (pullback-frame frame decoder 9 :int (list (cons 0 (var 0 :int))) ledger)))
          (multiple-value-bind (f-pairs f-anchors refined)
              (fiber-pairs-and-anchors child-frame ledger)
            (check (= (- (length (frame-rows child-frame)) 2) (length f-pairs)))
            (check (= 2 (length f-anchors)))
            (check (equal f-pairs (frame-pairs refined)))
            (check (equal f-anchors (frame-anchors refined)))))))))

(deftest view-locality-scheduling-and-canonical-reserve
  (let ((ledger (make-ledger)))
    ;; 1. Co-local repeated structures at (3, 4) under pair-budget = 6:
    ;;    :locality recovers the planted template and positive compression gain, whereas :canonical misses it.
    (multiple-value-bind (co-trees inputs co-oracle)
        (locality-abstraction-fixture :domain :int :mode :co-local :ledger ledger)
      (multiple-value-bind (can-comp can-struct)
          (discover-subexpression-abstractions co-trees inputs
                                               :schedule :canonical :pair-budget 6 :ledger ledger)
        (declare (ignore can-comp))
        (multiple-value-bind (loc-comp loc-struct)
            (discover-subexpression-abstractions co-trees inputs
                                                 :schedule :locality :pair-budget 6 :ledger ledger)
          (check (not (patterns-isomorphic-p (getf co-oracle :pattern)
                                             (subexpression-abstraction-pattern can-struct)
                                             inputs ledger)))
          (check (patterns-isomorphic-p (getf co-oracle :pattern)
                                        (subexpression-abstraction-pattern loc-struct)
                                        inputs ledger))
          (check (plusp (subexpression-abstraction-gain loc-comp)))
          (check (plusp (verify-corpus-abstraction-replay loc-comp co-trees inputs ledger))))))
    ;; 2. Distant repeated structures at (0, 5):
    ;;    :locality-only (window <= 1) misses, while :locality (1-in-4 canonical reserve) recovers it.
    (multiple-value-bind (dist-trees inputs dist-oracle)
        (locality-abstraction-fixture :domain :int :mode :distant :ledger ledger)
      (multiple-value-bind (win-comp win-struct)
          (discover-subexpression-abstractions dist-trees inputs
                                               :schedule :locality-only :ledger ledger)
        (declare (ignore win-comp))
        (multiple-value-bind (res-comp res-struct)
            (discover-subexpression-abstractions dist-trees inputs
                                                 :schedule :locality :ledger ledger)
          (check (not (patterns-isomorphic-p (getf dist-oracle :pattern)
                                             (subexpression-abstraction-pattern win-struct)
                                             inputs ledger)))
          (check (patterns-isomorphic-p (getf dist-oracle :pattern)
                                        (subexpression-abstraction-pattern res-struct)
                                        inputs ledger))
          (check (plusp (subexpression-abstraction-gain res-comp)))
          (check (plusp (verify-corpus-abstraction-replay res-comp dist-trees inputs ledger))))))
    ;; 3. Interleaved repeated structures at (0, 2, 4):
    ;;    priced parity key `(- i (* (/ i 2) 2))` induces adjacency and recovers all 3 planted occurrences at pair-budget = 1.
    (multiple-value-bind (int-trees inputs int-oracle)
        (locality-abstraction-fixture :domain :int :mode :interleaved :ledger ledger)
      (let ((parity-key (parity-key-expression 0)))
        (multiple-value-bind (raw-comp raw-struct)
            (discover-subexpression-abstractions int-trees inputs
                                                 :schedule :locality-only :pair-budget 1 :ledger ledger)
          (declare (ignore raw-comp))
          (multiple-value-bind (ind-comp ind-struct)
              (discover-subexpression-abstractions int-trees inputs
                                                   :schedule :locality-only :pair-budget 1
                                                   :locality-key parity-key :ledger ledger)
            (check (not (patterns-isomorphic-p (getf int-oracle :pattern)
                                               (subexpression-abstraction-pattern raw-struct)
                                               inputs ledger)))
            (check (patterns-isomorphic-p (getf int-oracle :pattern)
                                          (subexpression-abstraction-pattern ind-struct)
                                          inputs ledger))
            (check (plusp (subexpression-abstraction-gain ind-comp)))
            (check (plusp (verify-corpus-abstraction-replay ind-comp int-trees inputs ledger)))))))
    ;; 4. Generated 2D tuple space and `:at` coordinate projection / quotienting:
    ;;    On a 3x2 grid over i=0..5 where planted occurrences sit in column 0 (i=0, 2, 4):
    ;;    - Isotropic 2D key `(tuple (/ i '2) (mod i '2))` projected onto column via `:at`
    ;;      `(at (tuple (/ i '2) (mod i '2)) '1)` quotients trees into column fibers (0,2,4) and (1,3,5).
    ;;    - Anisotropic 2D tuple key `(tuple (/ i '2) (* '2 (mod i '2)))` gives L1 distance 1 along
    ;;      columns (between i=0 and i=2) and L1 distance 2 across columns (between i=0 and i=1).
    ;;    Both recover all 3 planted occurrences at `pair-budget = 1` where raw 1D index order fails.
    (multiple-value-bind (grid-trees inputs grid-oracle)
        (locality-abstraction-fixture :domain :int :mode :interleaved :ledger ledger)
      (let* ((pair-type (tuple-type :int :int))
             (row-expr (app (op :/ :int) (var 0 :int) (lit :int 2)))
             (col-expr (parity-key-expression 0))
             (iso-2d-key (app (op :tuple pair-type) row-expr col-expr))
             (aniso-2d-key (app (op :tuple pair-type)
                                row-expr
                                (app (op :* :int) (lit :int 2) col-expr)))
             (projected-col-key (app (op :at pair-type) iso-2d-key (lit :int 1))))
        ;; Verify `compute-tree-locality-positions` returns the generated 2D coordinates and quotient
        (multiple-value-bind (pos-vec labels-vec reps residual)
            (compute-tree-locality-positions (length grid-trees) iso-2d-key ledger)
          (declare (ignore pos-vec))
          (check (= 6 (length reps)))
          (check (equal '((0 0) (0 1) (1 0) (1 1) (2 0) (2 1)) (coerce labels-vec 'list)))
          (check (equal '(0 1 2 3 4 5) residual)))
        (multiple-value-bind (pos-vec labels-vec reps residual)
            (compute-tree-locality-positions (length grid-trees) projected-col-key ledger)
          (declare (ignore pos-vec labels-vec))
          (check (equal '(0 1) reps))
          (check (equal '(0 1 0 1 0 1) residual)))
        (dolist (key-expr (list aniso-2d-key projected-col-key))
          (multiple-value-bind (comp struct)
              (discover-subexpression-abstractions grid-trees inputs
                                                   :schedule :locality-only :pair-budget 1
                                                   :locality-key key-expr :ledger ledger)
            (check (patterns-isomorphic-p (getf grid-oracle :pattern)
                                          (subexpression-abstraction-pattern struct)
                                          inputs ledger))
            (check (plusp (subexpression-abstraction-gain comp)))
            (check (plusp (verify-corpus-abstraction-replay comp grid-trees inputs ledger)))))))))

(deftest view-experiment-runner
  (run-m7)
  (check t))

(deftest view-tentative-conflict-preserves-original-alternatives
  (let* ((frame (simple-frame :int '((0 . :int) (1 . :int))
                              '(((2 0) 1) ((3 0) 1) ((2 1) 1) ((3 1) 1))))
         (guard (app (op := :int) (var 1 :int) (lit :int 0)))
         (decoder (app (op :/ :int) (var 9 :int) (var 0 :int)))
         (language (make-language :int '((2 . :int)) :operators nil :literals '(1 2 3))))
    (multiple-value-bind (proposals conflict)
        (synthesize-supplied-partition-view frame guard language
         :child-bindings (list (cons 2 (lit :int 0))) :child-bound 30
         :decoder decoder :child-id 9 :child-type :int :solver (arithmetic-control :int :/ 0))
      (check (null conflict))
      (let ((shared (find :shared-decoder proposals :key #'partition-view-proposal-kind)))
        (check shared)
        (check (every (lambda (model) (equal model (lit :int 3))) (partition-view-proposal-part-models shared)))
        (check (evaluate-model-run-work (partition-view-proposal-model shared) frame))))))
