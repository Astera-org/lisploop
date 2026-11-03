(in-package #:lisploop)

(defun parity-key-expression (&optional (var-id 0))
  "Object-level `:int` remainder expression `(- r (* (/ r '2) '2))` computing `r mod 2`."
  (let ((r (var var-id :int))
        (two (lit :int 2)))
    (app (op :- :int)
         r
         (app (op :* :int)
              (app (op :/ :int) r two)
              two))))

(defun parity-zero-guard (&optional (var-id 0))
  "Object-level `:bool` guard `(= (- r (* (/ r '2) '2)) '0)` testing evenness of `r`."
  (app (op := :int) (parity-key-expression var-id) (lit :int 0)))

(defun run-m7-supplied-and-discovered-views ()
  (let ((work (make-ledger)))
    (format t "~%M7 / Part 1 / Supplied vs. autonomously discovered views, M8C conflict pruning, and 3-way model comparison.~%")
    ;; 1A & 1B: Interleaved integer sequences (r=0,1,2,3 with alternating offsets a_0=1, a_1=3)
    (multiple-value-bind (frame decoder supplied-r-to-j true-labels records)
        (integer-lifting-fixture :offsets '(1 3) :steps 7 :repetitions 2 :ledger work)
      (declare (ignore supplied-r-to-j true-labels records))
      (let* ((parent-inputs (schema-inputs (frame-schema frame)))
             (t-bindings (list (cons 1 (var 1 :int))))
             (t-inputs (list (cons 1 :int)))
             (child-lang (make-language :int t-inputs :operators (list (op :+ :int)) :literals '(1 3)))
             (child-bound (description-size (app (op :+ :int) (lit :int 3) (var 1 :int)) t-inputs))
             (samples '(-4 -3 -2 -1 0 1 2 3 4))
             (plus-rel (observe-arithmetic-relation :int :+ samples))
             (plus-solver (discover-arithmetic-solver plus-rel 1 samples :literals '(-1 0 1)))
             (_ (integer-solver-held-out plus-solver))
             (parity-guard (parity-zero-guard 0))
             ;; Candidate guard expressions over (r, t): simple equality guards + parity guard
             (r0-guard (app (op := :int) (var 0 :int) (lit :int 0)))
             (t0-guard (app (op := :int) (var 1 :int) (lit :int 0)))
             (guard-candidates (list r0-guard t0-guard parity-guard))
             (guard-lang (make-language :int parent-inputs
                                        :operators (list (op := :int) (op :- :int) (op :* :int) (op :/ :int))
                                        :literals '(0 2)))
             (guard-bound (reduce #'max guard-candidates
                                  :key (lambda (e) (description-size e parent-inputs)))))
        (declare (ignore _))
        ;; Supplied view control
        (multiple-value-bind (supplied-props supplied-conflict)
            (synthesize-supplied-partition-view
             frame parity-guard child-lang
             :child-bindings t-bindings :child-bound child-bound
             :decoder decoder :child-id 9 :child-type :int :solver plus-solver :ledger work)
          (assert (null supplied-conflict))
          (assert (= 2 (length supplied-props)))
          (dolist (p supplied-props)
            (assert (plusp (replay-model (partition-view-proposal-model p) frame work)))))
        ;; Autonomous view discovery across candidate guards (with M8C conflict pruning on r=0 and t=0)
        (let* ((bool-frame (make-frame (make-schema :domain :int :inputs parent-inputs :target :bool)
                                       (loop for row in (frame-rows frame)
                                             collect (make-row :key (copy-tree (row-key row))
                                                               :known (copy-tree (row-known row))
                                                               :requirement (lit :bool t)))))
               (scope (make-observation-scope bool-frame guard-lang))
               (obs-job (start-observation-search scope :expressions guard-candidates)))
          (resume-observation-search obs-job guard-bound 1000000)
          (charge work :view-guard-search (ledger-total (observation-job-ledger obs-job))))
        (multiple-value-bind (r0-props r0-conflict)
            (synthesize-supplied-partition-view frame r0-guard child-lang
                                                :child-bindings t-bindings :child-bound child-bound
                                                :decoder decoder :child-id 9 :child-type :int
                                                :solver plus-solver :ledger work)
          (multiple-value-bind (t0-props t0-conflict)
              (synthesize-supplied-partition-view frame t0-guard child-lang
                                                  :child-bindings t-bindings :child-bound child-bound
                                                  :decoder decoder :child-id 9 :child-type :int
                                                  :solver plus-solver :ledger work)
            (assert (and (null r0-props) r0-conflict))
            (assert (and (null t0-props) t0-conflict))
            (assert (eq :incompatible-rows (frame-conflict-kind (partition-view-proposal-conflict r0-conflict))))
            (assert (eq :incompatible-rows (frame-conflict-kind (partition-view-proposal-conflict t0-conflict))))
            (format t "M8C conflict pruning refuted non-separating guards ~S (conflict keys ~S) and ~S (conflict keys ~S) in O(|Omega|).~%"
                    r0-guard (frame-conflict-keys (partition-view-proposal-conflict r0-conflict))
                    t0-guard (frame-conflict-keys (partition-view-proposal-conflict t0-conflict)))))
        ;; Compare 3 architectures on the interleaved 28-row frame:
        ;; (1) Unfactored lookup, (2) Separate-parts partition, (3) Shared-decoder with context-dependent argument
        (multiple-value-bind (props)
            (synthesize-supplied-partition-view
             frame parity-guard child-lang
             :child-bindings t-bindings :child-bound child-bound
             :decoder decoder :child-id 9 :child-type :int :solver plus-solver :ledger work)
          (let* ((sep-prop (find :separate-parts props :key #'partition-view-proposal-kind))
                 (shared-prop (find :shared-decoder props :key #'partition-view-proposal-kind))
                 (lookup-expr (lookup-model frame work))
                 (lookup-bits (description-size lookup-expr parent-inputs)))
            (assert (and sep-prop shared-prop))
            (assert (< (partition-view-proposal-bits shared-prop)
                       (partition-view-proposal-bits sep-prop)))
            (assert (< (partition-view-proposal-bits sep-prop) lookup-bits))
            (format t "3-way comparison on 28 interleaved (:INT) rows:~%")
            (format t "  1. Shared decoder d(X, (if G Z1 Z0)): ~S (S=~D bits, W_run=~D)~%"
                    (partition-view-proposal-model shared-prop)
                    (partition-view-proposal-bits shared-prop)
                    (replay-model (partition-view-proposal-model shared-prop) frame work))
            (format t "  2. Separate per-part models (if G M1 M0): ~S (S=~D bits, W_run=~D)~%"
                    (partition-view-proposal-model sep-prop)
                    (partition-view-proposal-bits sep-prop)
                    (replay-model (partition-view-proposal-model sep-prop) frame work))
            (format t "  3. Unfactored parent lookup (r,t)->y: S=~D bits, W_run=~D~%"
                    lookup-bits (replay-model lookup-expr frame work))))))
    ;; 1C: Autonomous grammar-enumerated view discovery on GF(7) 2-regime sequences
    (let ((field (gf 7)))
      (multiple-value-bind (gf-frame gf-decoder)
          (gf7-lifting-fixture :offsets '(1 3) :steps 7 :repetitions 1 :ledger work)
        (let* ((parent-inputs (schema-inputs (frame-schema gf-frame)))
               (iota-t (gf7-iota-conversion (var 1 :int) :steps 7 :ledger work))
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
               (gf-rel (observe-arithmetic-relation field :+ '(0 1 2 3 4 5 6)))
               (plus-solver (validate-arithmetic-solver (discover-arithmetic-solver gf-rel 1 '(0 1 2 3 4 5 6)))))
          (multiple-value-bind (best-prop proposals conflicts)
              (discover-partition-views gf-frame guard-lang child-lang
                                        :guard-bound guard-bound
                                        :child-bindings t-bindings
                                        :child-bound child-bound
                                        :decoder gf-decoder :child-id 9 :child-type field
                                        :solver plus-solver :ledger work)
            (let ((sep-prop (find :separate-parts proposals :key #'partition-view-proposal-kind))
                  (shared-prop (find :shared-decoder proposals :key #'partition-view-proposal-kind))
                  (lookup-prop (find :lookup proposals :key #'partition-view-proposal-kind)))
              (assert (and best-prop sep-prop shared-prop lookup-prop))
              (assert (plusp (length conflicts)))
              (assert (eq :shared-decoder (partition-view-proposal-kind best-prop)))
              (assert (< (partition-view-proposal-bits shared-prop)
                         (partition-view-proposal-bits lookup-prop)))
              (assert (< (partition-view-proposal-bits shared-prop)
                         (partition-view-proposal-bits sep-prop)))
              (format t "GF(7) autonomous view search: discovered guard ~S (~D conflicting guards pruned); shared-decoder S=~D bits vs lookup S=~D bits vs separate-parts S=~D bits.~%"
                      (partition-view-proposal-guard best-prop)
                      (length conflicts)
                      (partition-view-proposal-bits shared-prop)
                      (partition-view-proposal-bits lookup-prop)
                      (partition-view-proposal-bits sep-prop)))))))
    (report-ledger "M7 Part 1 view discovery & 3-way comparison" work)))

(defun run-m7-storage-shuffle-and-permutation-controls ()
  (let ((work (make-ledger)))
    (format t "~%M7 / Part 2 / Shuffled physical storage, inverse permutation reconstruction, and target-leakage controls.~%")
    (multiple-value-bind (frame decoder supplied-r-to-j true-labels records)
        (integer-lifting-fixture :offsets '(1 3) :steps 7 :repetitions 2 :ledger work)
      (declare (ignore supplied-r-to-j true-labels))
      (let* ((n (length (frame-rows frame)))
             ;; Deterministic non-trivial physical permutation (even positions reversed, then odd positions)
             (perm (append (reverse (loop for i below n by 2 collect i))
                           (loop for i from 1 below n by 2 collect i)))
             (shuffled-frame (shuffle-frame-rows frame perm work))
             (parity-guard (parity-zero-guard 0))
             (t-bindings (list (cons 1 (var 1 :int))))
             (t-inputs (list (cons 1 :int)))
             (child-lang (make-language :int t-inputs :operators (list (op :+ :int)) :literals '(1 3)))
             (child-bound (description-size (app (op :+ :int) (lit :int 3) (var 1 :int)) t-inputs))
             (samples '(-4 -3 -2 -1 0 1 2 3 4))
             (plus-rel (observe-arithmetic-relation :int :+ samples))
             (plus-solver (discover-arithmetic-solver plus-rel 1 samples :literals '(-1 0 1)))
             (_ (integer-solver-held-out plus-solver)))
        (declare (ignore _))
        ;; 2A: Physical storage permutation preserves discovered models, bit sizes, and replay work
        (multiple-value-bind (orig-props)
            (synthesize-supplied-partition-view frame parity-guard child-lang
                                                :child-bindings t-bindings :child-bound child-bound
                                                :decoder decoder :child-id 9 :child-type :int
                                                :solver plus-solver :ledger work)
          (multiple-value-bind (shuf-props)
              (synthesize-supplied-partition-view shuffled-frame parity-guard child-lang
                                                  :child-bindings t-bindings :child-bound child-bound
                                                  :decoder decoder :child-id 9 :child-type :int
                                                  :solver plus-solver :ledger work)
            (let ((orig-shared (find :shared-decoder orig-props :key #'partition-view-proposal-kind))
                  (shuf-shared (find :shared-decoder shuf-props :key #'partition-view-proposal-kind)))
              (assert (equal (partition-view-proposal-model orig-shared)
                             (partition-view-proposal-model shuf-shared)))
              (assert (= (partition-view-proposal-bits orig-shared)
                         (partition-view-proposal-bits shuf-shared)))
              (assert (= (replay-model (partition-view-proposal-model orig-shared) frame work)
                         (replay-model (partition-view-proposal-model shuf-shared) shuffled-frame work)))
              (format t "Shuffled physical storage (~D rows): discovered identical model ~S (S=~D bits, W_run=~D).~%"
                      n (partition-view-proposal-model shuf-shared)
                      (partition-view-proposal-bits shuf-shared)
                      (partition-view-proposal-run-work shuf-shared)))))
        ;; 2B: Sorting / grouping an ordered sequence requires and pays for the inverse permutation
        (let* ((ordered-targets (mapcar #'fourth records))
               ;; Group/sort values by parity of value (including duplicate values across repetitions)
               (value-labels (mapcar (lambda (v) (mod v 2)) ordered-targets))
               (val-part (partition-rows ordered-targets value-labels work))
               (concat-groups (apply #'append (partition-groups val-part)))
               (pmodel (partition-model val-part :int work))
               (decoded-pmodel (decode-model (encode-model pmodel nil)))
               (pmodel-run (evaluate decoded-pmodel nil nil :ledger work)))
          (assert (not (equal ordered-targets concat-groups)))
          (assert (eq :value (evaluation-status pmodel-run)))
          (assert (equal ordered-targets (evaluation-value pmodel-run)))
          (assert (equal ordered-targets (reassemble-partition val-part work)))
          (format t "Ordered sequence grouping with ties/multiplicity: partition-model (S=~D bits) reconstructs all ~D values in exact order.~%"
                  (description-size pmodel nil) (length ordered-targets)))
        ;; 2C: Target-leakage control — withholding `r` leaves no free runtime regime selector over `t`
        (let* ((t-only-frame (orient-observations '(:int :int :int) records '(1) '(2)
                                                  :lookup-p t :ledger work))
               (t-guard-lang (make-language :int '((1 . :int)) :operators (list (op := :int)) :literals '(0 1 2))))
          (multiple-value-bind (best-t-prop t-props t-conflicts)
              (discover-partition-views t-only-frame t-guard-lang child-lang
                                        :guard-bound (description-size (app (op := :int) (var 1 :int) (lit :int 2)) '((1 . :int)))
                                        :child-bound child-bound :ledger work)
            (assert (null best-t-prop))
            (assert (null t-props))
            (assert (plusp (length t-conflicts)))
            (format t "Target-leakage control (r withheld): 0 valid runtime views over t alone (~D candidate splits refuted by conflict check).~%"
                    (length t-conflicts))))))
    (report-ledger "M7 Part 2 shuffle, permutation & target-leakage controls" work)))

(defun run-m7-locality-scheduling-and-canonical-reserve ()
  (let ((work (make-ledger)))
    (format t "~%M7 / Part 3 / Locality-prioritized scheduling, 1-in-4 canonical reserve on distant matches, and induced locality.~%")
    ;; 3A: Co-local repeated structures at (3, 4) under a tight pair budget (pair-budget = 6)
    (multiple-value-bind (co-trees inputs co-oracle)
        (locality-abstraction-fixture :domain :int :mode :co-local :ledger work)
      (multiple-value-bind (can-comp can-struct)
          (discover-subexpression-abstractions co-trees inputs
                                               :schedule :canonical :pair-budget 6 :ledger work)
        (declare (ignore can-comp))
        (multiple-value-bind (loc-comp loc-struct)
            (discover-subexpression-abstractions co-trees inputs
                                                 :schedule :locality :pair-budget 6 :ledger work)
          (assert (not (patterns-isomorphic-p (getf co-oracle :pattern)
                                              (subexpression-abstraction-pattern can-struct)
                                              inputs work)))
          (assert (patterns-isomorphic-p (getf co-oracle :pattern)
                                         (subexpression-abstraction-pattern loc-struct)
                                         inputs work))
          (assert (plusp (subexpression-abstraction-gain loc-comp)))
          (verify-corpus-abstraction-replay loc-comp co-trees inputs work)
          (format t "Co-local mode (planted at ~S, pair-budget=6): :locality recovers planted template (gain=~D bits) while :canonical misses it.~%"
                  (getf co-oracle :planted-indices)
                  (subexpression-abstraction-gain loc-comp)))))
    ;; 3B: Distant repeated structures at (0, 5): :locality-only (window <= 1) misses, while :locality (1-in-4 reserve) recovers it
    (multiple-value-bind (dist-trees inputs dist-oracle)
        (locality-abstraction-fixture :domain :int :mode :distant :ledger work)
      (multiple-value-bind (win-comp win-struct)
          (discover-subexpression-abstractions dist-trees inputs
                                               :schedule :locality-only :ledger work)
        (declare (ignore win-comp))
        (multiple-value-bind (res-comp res-struct)
            (discover-subexpression-abstractions dist-trees inputs
                                                 :schedule :locality :ledger work)
          (assert (not (patterns-isomorphic-p (getf dist-oracle :pattern)
                                              (subexpression-abstraction-pattern win-struct)
                                              inputs work)))
          (assert (patterns-isomorphic-p (getf dist-oracle :pattern)
                                         (subexpression-abstraction-pattern res-struct)
                                         inputs work))
          (assert (plusp (subexpression-abstraction-gain res-comp)))
          (verify-corpus-abstraction-replay res-comp dist-trees inputs work)
          (format t "Distant mode (planted at ~S): local-window-only misses match, while 1-in-4 canonical reserve recovers it (gain=~D bits).~%"
                  (getf dist-oracle :planted-indices)
                  (subexpression-abstraction-gain res-comp)))))
    ;; 3C: Interleaved repeated structures at (0, 2, 4): induced locality via priced parity key `(- i (* (/ i 2) 2))`
    (multiple-value-bind (int-trees inputs int-oracle)
        (locality-abstraction-fixture :domain :int :mode :interleaved :ledger work)
      (let ((parity-key (parity-key-expression 0)))
        (multiple-value-bind (raw-comp raw-struct)
            (discover-subexpression-abstractions int-trees inputs
                                                 :schedule :locality-only :pair-budget 1 :ledger work)
          (declare (ignore raw-comp))
          (multiple-value-bind (ind-comp ind-struct)
              (discover-subexpression-abstractions int-trees inputs
                                                   :schedule :locality-only :pair-budget 1
                                                   :locality-key parity-key :ledger work)
            (assert (not (patterns-isomorphic-p (getf int-oracle :pattern)
                                                (subexpression-abstraction-pattern raw-struct)
                                                inputs work)))
            (assert (patterns-isomorphic-p (getf int-oracle :pattern)
                                           (subexpression-abstraction-pattern ind-struct)
                                           inputs work))
            (assert (plusp (subexpression-abstraction-gain ind-comp)))
            (verify-corpus-abstraction-replay ind-comp int-trees inputs work)
            (format t "Interleaved mode (planted at ~S, pair-budget=1): priced parity key ~S induces adjacency and recovers all 3 occurrences (gain=~D bits).~%"
                    (getf int-oracle :planted-indices)
                    parity-key
                    (subexpression-abstraction-gain ind-comp))))))
    (report-ledger "M7 Part 3 locality scheduling & canonical reserve" work)))

(defun run-m7 ()
  (run-m7-supplied-and-discovered-views)
  (run-m7-storage-shuffle-and-permutation-controls)
  (run-m7-locality-scheduling-and-canonical-reserve))
