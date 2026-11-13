(in-package #:lisploop)

(defun define-test-map-candidate-functions ()
  "Define `:inc-list` and `:double-list` recursive list functions for library tests."
  (let* ((seq-type (sequence-type :int))
         (inputs (list (cons 0 seq-type)))
         (xs (var 0 seq-type))
         (empty-xs (app (op := seq-type) xs (lit seq-type '())))
         (head-xs (app (op :at seq-type) xs (lit :int 0)))
         (tail-xs (app (op :tail :int) xs)))
    (define-function :inc-list inputs seq-type
      (lambda (self)
        (app (op :if seq-type)
             empty-xs
             (lit seq-type '())
             (app (op :cons :int)
                  (app (op :+ :int) head-xs (lit :int 1))
                  (app self tail-xs)))))
    (define-function :double-list inputs seq-type
      (lambda (self)
        (app (op :if seq-type)
             empty-xs
             (lit seq-type '())
             (app (op :cons :int)
                  (app (op :* :int) head-xs (lit :int 2))
                  (app self tail-xs)))))))

(defun shift-curriculum-fixtures ()
  "Shared continual-learning sequence curriculum (`inc`, `add3`, `shift4`, `add-len`)."
  (let* ((seq-type (sequence-type :int))
         (inputs (list (cons 0 seq-type)))
         (base-ops (list (op :+ :int) (op :cons :int) (op :tail :int)
                         (op :at seq-type) (op := seq-type) (op :if seq-type)))
         (len-ops (append base-ops (list (op :length :int)))))
    (list :seq-type seq-type
          :inputs inputs
          :inc-frame (simple-frame seq-type inputs
                                   '(((()) ()) (((2)) (3)) (((5 2)) (6 3)) (((0 5 2)) (1 6 3))))
          :add3-frame (simple-frame seq-type inputs
                                    '(((()) ()) (((2)) (5)) (((5 2)) (8 5)) (((0 5 2)) (3 8 5))))
          :shift4-frame (simple-frame seq-type inputs
                                      '(((()) ()) (((2)) (6)) (((5 2)) (9 6)) (((0 5 2)) (4 9 6))))
          :add-len-frame (simple-frame seq-type inputs
                                       '(((()) ()) (((5)) (6)) (((5 2)) (7 4)) (((0 5 2)) (3 8 5))))
          :inc-lang (make-language :int inputs :operators base-ops :literals '(1)
                                   :constants (list (lit seq-type '())))
          :add3-lang (make-language :int inputs :operators base-ops :literals '(3)
                                    :constants (list (lit seq-type '())))
          :shift4-lang (make-language :int inputs :operators base-ops :literals '(4)
                                      :constants (list (lit seq-type '())))
          :len-lang (make-language :int inputs :operators len-ops :literals '(0 1)
                                   :constants (list (lit seq-type '()))))))

(deftest library-l1-metaprogramming-and-persistence-roundtrip
  (with-clean-kernel-state
    ;; 1. Verify all 9 standard knowledge kinds are registered via `define-knowledge-kind`
    (dolist (k '(:function :descriptor :relation :law :solver :functor
                 :nogood-schema :dip-feature :heuristic))
      (let ((spec (find-knowledge-kind-spec k)))
        (check (knowledge-kind-spec-p spec))
        (check (eq k (knowledge-kind-spec-name spec)))))
    ;; 2. Verify extensibility of `define-knowledge-kind` with a temporary custom kind
    (unwind-protect
         (progn
           (define-knowledge-kind :test-custom-kind
             (:priority 99)
             (:validate (entry library)
               (declare (ignore library))
               (assert (eq :int (knowledge-entry-target entry))))
             (:install (entry library ledger)
               (declare (ignore library ledger))
               (setf (getf (knowledge-entry-metadata entry) :installed-p) t))
             (:consume (entry context ledger)
               (evaluate (knowledge-entry-expression entry)
                         (knowledge-entry-inputs entry)
                         context
                         :ledger ledger)))
           (let* ((custom-entry
                    (register-knowledge-entry
                     (make-knowledge-entry
                      :id :custom-triple
                      :kind :test-custom-kind
                      :domain :int
                      :inputs '((0 . :int))
                      :target :int
                      :expression (app (op :* :int) (var 0 :int) (lit :int 3))
                      :status :validated)))
                  (eval-res (consume-knowledge-entry custom-entry '(7))))
             (check (eq t (getf (knowledge-entry-metadata custom-entry) :installed-p)))
             (check (eq :value (evaluation-status eval-res)))
             (check (= 21 (evaluation-value eval-res)))
             (remove-knowledge-entry :custom-triple)))
      (setf *knowledge-kind-specs*
            (remove :test-custom-kind *knowledge-kind-specs*
                    :key #'knowledge-kind-spec-name :test #'eq)))
    ;; 3. Populate one entry of each standard kind and verify installation + consumption
    (define-test-map-candidate-functions)
    (check (find-knowledge-entry :inc-list))
    (check (find-knowledge-entry :inc-list/descriptor))
    ;; Relation
    (let ((rel-entry (register-knowledge-relation
                      :bonus-table '((1 100) (2 200))
                      :domain :int
                      :inputs '((0 . :int))
                      :target :int
                      :parametric (app (op :* :int) (var 0 :int) (lit :int 10)))))
      (check (eq :relation (knowledge-entry-kind rel-entry)))
      (check (= 100 (evaluation-value (consume-knowledge-entry rel-entry '(1)))))
      (check (= 50 (evaluation-value (consume-knowledge-entry rel-entry '(5))))))
    ;; Law (over GF(5))
    (let* ((gf5 (gf 5))
           (comm-law (make-law gf5 (list (cons 0 gf5) (cons 1 gf5))
                               (app (op :+ gf5) (var 0 gf5) (var 1 gf5))
                               (app (op :+ gf5) (var 1 gf5) (var 0 gf5))))
           (comm-val (resume-law-validation (start-law-validation comm-law) 10000))
           (law-entry (register-knowledge-law comm-val :id :gf5-add-comm)))
      (check (eq :validated (knowledge-entry-status law-entry)))
      (check (eq t (evaluation-value (consume-knowledge-entry law-entry '(2 4)))))
      (check (member '(:governs :+) (knowledge-edges-from :gf5-add-comm :governs) :test #'equal)))
    ;; Solver (over GF(5))
    (let* ((gf5 (gf 5))
           (solver-entry (register-kernel-arithmetic-solver gf5 :+ 0)))
      (check (eq :solver (knowledge-entry-kind solver-entry)))
      (check (eq :validated (knowledge-entry-status solver-entry)))
      (check (= 2 (evaluation-value (consume-knowledge-entry solver-entry '(3 0))))))
    ;; Nogood schema
    (let* ((seq-type (sequence-type :int))
           (ng (make-nogood-clause
                :kind :uip-clause
                :clause-expr (app (op := seq-type) (var 0 seq-type) (lit seq-type '()))))
           (ng-entry (register-knowledge-nogood-schema ng
                                                       :id :uip-empty-seq
                                                       :inputs (list (cons 0 seq-type)))))
      (check (eq :nogood-schema (knowledge-entry-kind ng-entry)))
      (check (eq t (evaluation-value (consume-knowledge-entry ng-entry '(nil))))))
    ;; DIP feature
    (let* ((seq-type (sequence-type :int))
           (dip-expr (app (op :< :int)
                          (app (op :at seq-type) (var 0 seq-type) (lit :int 0))
                          (lit :int 0)))
           (dip-entry (register-knowledge-dip-feature
                       dip-expr
                       :id :dip-neg-head
                       :inputs (list (cons 0 seq-type))
                       :target :bool)))
      (check (eq :dip-feature (knowledge-entry-kind dip-entry)))
      (check (eq t (evaluation-value (consume-knowledge-entry dip-entry '((-3 1 2)))))))
    ;; Heuristic priority predictor
    (let* ((h-inputs (loop for i from 0 below 6 collect (cons i :int)))
           (h-expr (app (op :+ :int) (var 0 :int) (var 4 :int)))
           (h-entry (register-knowledge-heuristic h-expr
                                                  :id :test-priority-heuristic
                                                  :inputs h-inputs)))
      (check (eq :heuristic (knowledge-entry-kind h-entry)))
      (check (equal h-expr (knowledge-library-priority-predictor *knowledge-library*)))
      (check (= 15 (evaluation-value (consume-knowledge-entry h-entry '(10 0 0 0 5 0))))))
    ;; 4. Consolidate functions into `:map` and induce `:functor` so all 9 kinds exist simultaneously
    (register-kernel-arithmetic-solver :int :+ 0)
    (consolidate-library-functions *knowledge-library* :library-names '(:map))
    (induce-functorial-solvers *knowledge-library*)
    (dolist (k '(:function :descriptor :relation :law :solver :functor
                 :nogood-schema :dip-feature :heuristic))
      (check (plusp (length (knowledge-entries-of-kind k)))))
    ;; 5. Verify `explain-knowledge-library` report structure and stream output
    (let* ((out (make-string-output-stream))
           (report (explain-knowledge-library :stream out))
           (printed (get-output-stream-string out)))
      (check (plusp (getf report :total-entries)))
      (check (plusp (length printed)))
      (check (search "Knowledge Library" printed)))
    ;; 6. Verify homoiconic serialization + disk round-trip (`save-knowledge-library` / `load-knowledge-library`)
    (let* ((sexp (serialize-knowledge-library *knowledge-library*))
           (tmp-path (merge-pathnames
                      (format nil "lisploop-lib-test-~D.sexp" (get-universal-time))
                      #P"/tmp/")))
      (unwind-protect
           (progn
             (check (eq :knowledge-library (first sexp)))
             (save-knowledge-library tmp-path *knowledge-library*)
             (with-knowledge-library ((make-knowledge-library))
               (load-knowledge-library tmp-path :library *knowledge-library*)
               (dolist (k '(:function :descriptor :relation :law :solver :functor
                            :nogood-schema :dip-feature :heuristic))
                 (check (plusp (length (knowledge-entries-of-kind k)))))
               (let ((inc-e (find-knowledge-entry :inc-list)))
                 (check inc-e)
                 (check (equal '(11 21 31)
                               (evaluation-value (consume-knowledge-entry inc-e '((10 20 30)))))))
               (check (rewrite-library-p (as-rewrite-library *knowledge-library* :domain (gf 5))))
               (check (propagator-library-p (as-propagator-library *knowledge-library*)))
               (check (knowledge-library-priority-predictor *knowledge-library*))))
        (when (probe-file tmp-path)
          (delete-file tmp-path))))))

(deftest library-l2-irreducible-residuals-and-delayed-condensation
  (with-clean-kernel-state
    ;; 1. Bare first-order `:lookup` table and `:member` relation
    (let ((lookup-rel (register-knowledge-relation
                       :bare-lookup
                       '((10 42) (20 99) (30 -7))
                       :domain :int
                       :inputs '((0 . :int))
                       :target :int
                       :relation-kind :lookup))
          (member-rel (register-knowledge-relation
                       :bare-set
                       '(2 3 5 7 11)
                       :domain :int
                       :inputs '((0 . :int))
                       :target :bool
                       :relation-kind :member)))
      (check (= 99 (evaluation-value (consume-knowledge-entry lookup-rel '(20)))))
      (check (eq :error (evaluation-status (consume-knowledge-entry lookup-rel '(999)))))
      (check (eq t (evaluation-value (consume-knowledge-entry member-rel '(7)))))
      (check (null (evaluation-value (consume-knowledge-entry member-rel '(8))))))
    ;; 2. Hybrid (parametric + irreducible exception table) execution
    (let* ((param-expr (app (op :* :int) (var 0 :int) (lit :int 2)))
           (hybrid-rel (register-knowledge-relation
                        :hybrid-double-with-outliers
                        '((3 99) (7 -1))
                        :domain :int
                        :inputs '((0 . :int))
                        :target :int
                        :parametric param-expr)))
      (check (= 99 (evaluation-value (consume-knowledge-entry hybrid-rel '(3)))))
      (check (= -1 (evaluation-value (consume-knowledge-entry hybrid-rel '(7)))))
      (check (= 8 (evaluation-value (consume-knowledge-entry hybrid-rel '(4)))))
      (check (= 20 (evaluation-value (consume-knowledge-entry hybrid-rel '(10))))))
    ;; 3. Second-order bare `:relation` over `:code` values
    (let* ((ctype (code-type '((0 . :int)) :int))
           (inc-code (app (op :+ :int) (var 0 :int) (lit :int 1)))
           (dec-code (app (op :- :int) (var 0 :int) (lit :int 1)))
           (dbl-code (app (op :* :int) (var 0 :int) (lit :int 2)))
           (hlf-code (app (op :/ :int) (var 0 :int) (lit :int 2)))
           (code-rel (register-knowledge-relation
                      :code-inverse-table
                      (list (list inc-code dec-code)
                            (list dbl-code hlf-code))
                      :domain :int
                      :inputs (list (cons 0 ctype))
                      :target ctype
                      :relation-kind :lookup)))
      (check (equal dec-code (evaluation-value (consume-knowledge-entry code-rel (list inc-code)))))
      (check (equal hlf-code (evaluation-value (consume-knowledge-entry code-rel (list dbl-code)))))
      (let* ((sexp (knowledge-entry->sexp code-rel))
             (restored (sexp->knowledge-entry sexp)))
        (check (equal dec-code (evaluation-value (consume-knowledge-entry restored (list inc-code)))))))
    ;; 4. Delayed structure discovery (`consolidate-residual-relations`)
    (let ((batch1 (register-knowledge-relation
                   :empirical-batch-1
                   '((0 1) (1 4) (2 7))
                   :domain :int
                   :inputs '((0 . :int))
                   :target :int
                   :status :empirical))
          (batch2 (register-knowledge-relation
                   :empirical-batch-2
                   '((3 10) (4 13) (5 16))
                   :domain :int
                   :inputs '((0 . :int))
                   :target :int
                   :status :empirical)))
      (check (null (knowledge-entry-expression batch1)))
      (check (null (knowledge-entry-expression batch2)))
      (let ((condensed (consolidate-residual-relations
                        (list batch1 batch2) *knowledge-library* (make-ledger))))
        (check (= 2 (length condensed)))
        (check (knowledge-entry-expression batch1))
        (check (null (knowledge-entry-residual batch1)))
        (check (plusp (knowledge-entry-gain batch1)))
        (check (= 1 (evaluation-value (consume-knowledge-entry batch1 '(0)))))
        (check (= 16 (evaluation-value (consume-knowledge-entry batch1 '(5)))))
        (check (= 31 (evaluation-value (consume-knowledge-entry batch1 '(10)))))))))

(deftest library-l3-higher-order-edges-functors-and-descriptors
  (with-clean-kernel-state
    (define-test-map-candidate-functions)
    ;; 1. Consolidate `:inc-list` and `:double-list` into `:map`
    (multiple-value-bind (accepted _ref _led)
        (consolidate-library-functions *knowledge-library* :library-names '(:map))
      (declare (ignore _ref _led))
      (check (= 1 (length accepted)))
      (check (eq :map (library-abstraction-name (first accepted)))))
    ;; 2. Verify relational edges (`:refactored-by` and `:abstracts`) and auxiliary code
    (check (member '(:refactored-by :map)
                   (knowledge-edges-from :inc-list :refactored-by)
                   :test #'equal))
    (check (member '(:abstracts :inc-list)
                   (knowledge-edges-from :map :abstracts)
                   :test #'equal))
    (let ((inc-entry (find-knowledge-entry :inc-list))
          (map-entry (find-knowledge-entry :map)))
      (check (equal (app (op :+ :int) (var 0 :int) (lit :int 1))
                    (knowledge-entry-auxiliary-code inc-entry)))
      ;; 3. Verify behavioral `:descriptor` (`trigger`) on `:map` and `:inc-list`
      (check (knowledge-entry-trigger inc-entry))
      (check (knowledge-entry-trigger map-entry))
      (check (find-knowledge-entry :map/descriptor))
      ;; Verify `library-decompositions` prunes `:map` when sequence lengths mismatch
      (let* ((seq-type (sequence-type :int))
             (inputs (list (cons 0 seq-type)))
             (lang (make-language :int inputs
                                  :operators (list (op :+ :int) (op :cons :int)
                                                   (op :tail :int) (op :at seq-type)
                                                   (op := seq-type) (op :if seq-type)
                                                   (op :map))
                                  :literals '(0 1 2)))
             (mismatch-frame (simple-frame seq-type inputs '((((1 2 3)) (10 20)))))
             (match-frame (simple-frame seq-type inputs '((((1 2 3)) (10 20 30))))))
        (check (null (library-decompositions mismatch-frame lang :ledger (make-ledger))))
        (check (plusp (length (library-decompositions match-frame lang :ledger (make-ledger)))))))
    ;; 4. Register element-level `:solver` for `:+` and induce second-order `:functor` solvers
    (register-kernel-arithmetic-solver :int :+ 0)
    (let ((induced (induce-functorial-solvers *knowledge-library*)))
      (check (>= (length induced) 3))
      (check (find-knowledge-entry :map/functor))
      (check (find-knowledge-entry :map/invert-+-0))
      (check (find-knowledge-entry :inc-list/inverter)))
    ;; 5. Verify induced unary solver inverts `(= (:inc-list X0) '(11 21 31))` -> `(= X0 '(10 20 30))`
    (let* ((seq-type (sequence-type :int))
           (inputs (list (cons 0 seq-type)))
           (frame1 (make-frame (make-schema :domain :int :inputs inputs :target seq-type)
                               (list (make-row :key 0 :known '((0))
                                               :requirement (app (op := seq-type)
                                                                 (app (op :inc-list) (var 0 seq-type))
                                                                 (lit seq-type '(11 21 31)))))))
           (prop1 (propagate-requirements frame1 *knowledge-library* (make-ledger)))
           (req1 (row-requirement (first (frame-rows (propagation-frame prop1))))))
      (check (equal (app (op := seq-type) (var 0 seq-type) (lit seq-type '(10 20 30)))
                    req1)))
    ;; 6. Verify second-order functorial solver inverts `(= (:map X0 '(+ X0 '7)) '(17 27 37))`
    (let* ((seq-type (sequence-type :int))
           (ctype (code-type '((0 . :int)) :int))
           (inputs (list (cons 0 seq-type)))
           (plus7-code (lit ctype (app (op :+ :int) (var 0 :int) (lit :int 7))))
           (frame2 (make-frame (make-schema :domain :int :inputs inputs :target seq-type)
                               (list (make-row :key 0 :known '((0))
                                               :requirement (app (op := seq-type)
                                                                 (app (op :map) (var 0 seq-type) plus7-code)
                                                                 (lit seq-type '(17 27 37)))))))
           (prop2 (propagate-requirements frame2 *knowledge-library* (make-ledger)))
           (req2 (row-requirement (first (frame-rows (propagation-frame prop2))))))
      (check (equal (app (op := seq-type) (var 0 seq-type) (lit seq-type '(10 20 30)))
                    req2)))))

(deftest library-l4-continual-learning-curriculum-amortization
  (with-clean-kernel-state
    (destructuring-bind (&key inputs inc-frame add3-frame shift4-frame add-len-frame
                              inc-lang add3-lang shift4-lang len-lang &allow-other-keys)
        (shift-curriculum-fixtures)
      (let ((cold-inc-work 0)
            (cold-inc-size 0)
            (cold-inc-body 0)
            (cold-shift4-work 0)
            (cold-shift4-size 0)
            (cold-shift4-body 0)
            (cold-add-len-work 0)
            (serialized nil))
        ;; 1. Cold baseline of `shift-by-4` in an empty library
        (with-knowledge-library ((make-knowledge-library))
          (let ((cold-job (start-recursive-synthesis shift4-frame shift4-lang 90
                                                     :self-name :shift4-cold
                                                     :library *knowledge-library*)))
            (resume-synthesis cold-job 120000 :stop-on-first t)
            (check (synthesis-job-best cold-job))
            (setf cold-shift4-work (ledger-total (synthesis-job-ledger cold-job))
                  cold-shift4-size (candidate-size (synthesis-job-best cold-job))
                  cold-shift4-body (body-size (candidate-expression (synthesis-job-best cold-job)) inputs))))
        ;; 2. Run 1 (Cold Discovery -> Consolidation -> Persistence)
        (with-knowledge-library ((make-knowledge-library))
          (let ((j-inc (start-recursive-synthesis inc-frame inc-lang 90
                                                  :self-name :inc-list
                                                  :library *knowledge-library*))
                (j-add3 (start-recursive-synthesis add3-frame add3-lang 90
                                                   :self-name :add3-list
                                                   :library *knowledge-library*)))
            (resume-synthesis j-inc 120000 :stop-on-first t)
            (resume-synthesis j-add3 120000 :stop-on-first t)
            (check (synthesis-job-best j-inc))
            (check (synthesis-job-best j-add3))
            (setf cold-inc-work (ledger-total (synthesis-job-ledger j-inc))
                  cold-inc-size (candidate-size (synthesis-job-best j-inc))
                  cold-inc-body (body-size (candidate-expression (synthesis-job-best j-inc)) inputs))
            (register-kernel-arithmetic-solver :int :+ 0)
            (let ((report (consolidate-knowledge-library *knowledge-library*
                                                         :synthesis-jobs (list j-inc j-add3)
                                                         :library-names '(:map))))
              (check (> (getf report :after-version) (getf report :before-version)))
              (check (find-knowledge-entry :map))
              (check (find-knowledge-entry :map/descriptor))
              (check (find-knowledge-entry :map/functor))
              (check (find-knowledge-entry :map/invert-+-0))
              (check (find-knowledge-entry :default-priority-predictor)))
            (let ((j-len (start-recursive-synthesis add-len-frame len-lang 90
                                                    :self-name :add-len
                                                    :library *knowledge-library*)))
              (resume-synthesis j-len 120000 :stop-on-first t)
              (check (synthesis-job-best j-len))
              (setf cold-add-len-work (ledger-total (synthesis-job-ledger j-len)))
              (commit-synthesis-job j-len :name :add-len :library *knowledge-library*)
              (check (= 1 (length (knowledge-entries-of-kind :nogood-schema))))
              (check (= 1 (length (knowledge-entries-of-kind :dip-feature))))
              (let ((ng-entry (first (knowledge-entries-of-kind :nogood-schema)))
                    (dip-entry (first (knowledge-entries-of-kind :dip-feature))))
                (check (member (list :repairs (knowledge-entry-id ng-entry))
                               (knowledge-edges-from dip-entry :repairs)
                               :test #'equal))))
            (setf serialized (serialize-knowledge-library *knowledge-library*))))
        ;; 3. Run 2 (Warm Synthesis after Deserialization)
        (with-knowledge-library ((deserialize-knowledge-library serialized))
          (let ((warm-inc-job (start-recursive-synthesis inc-frame inc-lang 90
                                                         :self-name :inc-warm
                                                         :library *knowledge-library*)))
            (resume-synthesis warm-inc-job 120000 :stop-on-first t)
            (check (synthesis-job-best warm-inc-job))
            (check (< (ledger-total (synthesis-job-ledger warm-inc-job)) cold-inc-work))
            (check (< (candidate-size (synthesis-job-best warm-inc-job)) cold-inc-size))
            (check (< (body-size (candidate-expression (synthesis-job-best warm-inc-job)) inputs)
                      cold-inc-body)))
          (let ((warm-shift4-job (start-recursive-synthesis shift4-frame shift4-lang 90
                                                            :self-name :shift4-warm
                                                            :library *knowledge-library*)))
            (resume-synthesis warm-shift4-job 120000 :stop-on-first t)
            (check (synthesis-job-best warm-shift4-job))
            (check (< (ledger-total (synthesis-job-ledger warm-shift4-job)) cold-shift4-work))
            (check (< (candidate-size (synthesis-job-best warm-shift4-job)) cold-shift4-size))
            (check (< (body-size (candidate-expression (synthesis-job-best warm-shift4-job)) inputs)
                      cold-shift4-body))
            (commit-synthesis-job warm-shift4-job :name :shift4-warm :library *knowledge-library*)
            (let ((s4-entry (find-knowledge-entry :shift4-warm)))
              (check s4-entry)
              (check (find-knowledge-entry :shift4-warm/descriptor))
              (check (equal '(14 24 34)
                            (evaluation-value (consume-knowledge-entry s4-entry '((10 20 30))))))
              (check (member '(:refactored-by :map)
                             (knowledge-edges-from :shift4-warm :refactored-by)
                             :test #'equal))))
          (let ((warm-len-job (start-recursive-synthesis add-len-frame len-lang 90
                                                         :self-name :add-len-warm
                                                         :library *knowledge-library*)))
            (resume-synthesis warm-len-job 120000 :stop-on-first t)
            (check (synthesis-job-best warm-len-job))
            (check (some (lambda (m)
                           (and (eq :conflict (message-claim m))
                                (getf (message-evidence m) :reused-nogood)))
                         (synthesis-job-messages warm-len-job)))
            (check (< (ledger-total (synthesis-job-ledger warm-len-job)) cold-add-len-work))))))))

(deftest library-m9-compositional-names-overlapping-policy-and-deferred-proposals
  "Verify M9.2, M9.3, and M9.4 contracts without locking in brittle 5-segment address literals
or magic score constants (aligned with `plan7-m9-policy.md`)."
  (with-clean-kernel-state
    ;; 1. Smooth `:seq` correction packet round-trip and bit-size gradient
    (let* ((seq-type (sequence-type :int))
           (base '(10 20 30 40))
           (near '(10 21 30 40))
           (far '(99 88 77 66))
           (longer '(10 20 30 40 50))
           (pkt-near (correction-packet base near seq-type))
           (pkt-far (correction-packet base far seq-type))
           (pkt-longer (correction-packet base longer seq-type)))
      (check (equal near (apply-correction-packet base pkt-near seq-type)))
      (check (equal far (apply-correction-packet base pkt-far seq-type)))
      (check (equal longer (apply-correction-packet base pkt-longer seq-type)))
      (check (< (correction-bit-size base near seq-type)
                (correction-bit-size base far seq-type)))
      (check (<= (correction-bit-size base far seq-type)
                 (value-bit-size far seq-type))))
    ;; 2. Compositional secondary addresses and multi-facet descriptor profiles
    (define-standard-int-combinators)
    (let* ((seq-type (sequence-type :int))
           (b-code (code-type '((0 . :int) (1 . :int)) :int))
           (xs (var 0 seq-type)))
      (define-function :map-adjacent (list (cons 0 seq-type) (cons 1 b-code)) seq-type
        (lambda (self)
          (app (op :if seq-type)
               (app (op := seq-type) xs (lit seq-type '()))
               (lit seq-type '())
               (app (op :if seq-type)
                    (app (op := seq-type) (app (op :tail :int) xs) (lit seq-type '()))
                    (lit seq-type '())
                    (app (op :cons :int)
                         (app (op :code-eval b-code) (var 1 b-code)
                              (app (op :at seq-type) (app (op :tail :int) xs) (lit :int 0))
                              (app (op :at seq-type) xs (lit :int 0)))
                         (app self (app (op :tail :int) xs) (var 1 b-code)))))))
      (let* ((entries (mapcar #'find-knowledge-entry '(:map :filter :foldr :map-adjacent)))
             (cnames (mapcar #'knowledge-entry-compositional-name entries)))
        ;; Every combinator derives a distinct keyword compositional address starting with "FUNCTION/"
        ;; and resolves via `find-knowledge-entries-by-address` under both its full compositional name
        ;; and every `descriptor-clause-id` in its profile.
        (check (= 4 (length (remove-duplicates cnames :test #'eq))))
        (dolist (entry entries)
          (let ((cname (knowledge-entry-compositional-name entry))
                (profile (knowledge-entry-descriptor-profile entry)))
            (check (keywordp cname))
            (check (= 0 (or (search "FUNCTION/" (symbol-name cname)) -1)))
            (check (plusp (length profile)))
            (check (member entry (find-knowledge-entries-by-address cname)))
            (dolist (clause profile)
              (check (descriptor-clause-p clause))
              (check (member entry (find-knowledge-entries-by-address (descriptor-clause-id clause)))))))
        ;; Homoiconic serialization round-trip preserves compositional addresses and profile lookup
        (let ((orig-map-cname (knowledge-entry-compositional-name (first entries)))
              (packet (serialize-knowledge-library *knowledge-library*)))
          (with-knowledge-library ((deserialize-knowledge-library packet))
            (let* ((restored-map (find-knowledge-entry :map))
                   (profile (knowledge-entry-descriptor-profile restored-map)))
              (check (eq orig-map-cname (knowledge-entry-compositional-name restored-map)))
              (check (plusp (length profile)))
              (check (member restored-map (find-knowledge-entries-by-address orig-map-cname)))
              (dolist (clause profile)
                (check (member restored-map
                               (find-knowledge-entries-by-address (descriptor-clause-id clause)))))))))
      ;; 3. Relational overlapping policy scoring across sequence task families
      (let* ((inputs (list (cons 0 seq-type)))
             (map-frame (simple-frame seq-type inputs '(((()) ()) (((1 2 3)) (5 6 7)))))
             (filt-frame (simple-frame seq-type inputs '(((()) ()) (((1 5 2 8)) (5 8)))))
             (diff-frame (simple-frame seq-type inputs '(((()) ()) (((10 13 19)) (3 6))))))
        ;; Equal-length non-subset task: `:map` scores strictly better (lower) than `:filter` & `:map-adjacent`
        (multiple-value-bind (m-ok m-score m-clauses) (score-entry-by-descriptors :map map-frame 0)
          (multiple-value-bind (f-ok f-score _fc) (score-entry-by-descriptors :filter map-frame 0)
            (declare (ignore _fc))
            (check m-ok)
            (check f-ok)
            (check (plusp (length m-clauses)))
            (check (minusp m-score))
            (check (< m-score f-score))))
        ;; Length-contracting subset task: `:map` is soundly pruned, `:filter` gets a net bonus & beats `:map-adjacent`
        (multiple-value-bind (m-ok-filt _ms _mc) (score-entry-by-descriptors :map filt-frame 0)
          (declare (ignore _ms _mc))
          (check (null m-ok-filt)))
        (multiple-value-bind (f-ok-filt f-score-filt f-clauses-filt)
            (score-entry-by-descriptors :filter filt-frame 0)
          (multiple-value-bind (_a-ok a-score-filt _ac)
              (score-entry-by-descriptors :map-adjacent filt-frame 0)
            (declare (ignore _a-ok _ac))
            (check f-ok-filt)
            (check (plusp (length f-clauses-filt)))
            (check (minusp f-score-filt))
            (check (< f-score-filt a-score-filt))))
        ;; Length-decrement-by-1 stencil task: `:map` is soundly pruned, `:map-adjacent` gets a net bonus & beats `:filter`
        (multiple-value-bind (m-ok-diff _ms _mc) (score-entry-by-descriptors :map diff-frame 0)
          (declare (ignore _ms _mc))
          (check (null m-ok-diff)))
        (multiple-value-bind (a-ok-diff a-score-diff a-clauses-diff)
            (score-entry-by-descriptors :map-adjacent diff-frame 0)
          (multiple-value-bind (_f-ok f-score-diff _fc)
              (score-entry-by-descriptors :filter diff-frame 0)
            (declare (ignore _f-ok _fc))
            (check a-ok-diff)
            (check (plusp (length a-clauses-diff)))
            (check (minusp a-score-diff))
            (check (< a-score-diff f-score-diff))))))
    ;; 4. Deferred proposals & warm synthesis efficiency with `:register-templates-p t`
    (destructuring-bind (&key seq-type inputs inc-frame add3-frame shift4-frame
                              inc-lang add3-lang shift4-lang &allow-other-keys)
        (shift-curriculum-fixtures)
      (let ((cold-work 0))
        (with-knowledge-library ((make-knowledge-library))
          (let ((cold-job (start-recursive-synthesis shift4-frame shift4-lang 90
                                                     :self-name :shift4-cold-m9
                                                     :library *knowledge-library*)))
            (resume-synthesis cold-job 120000 :stop-on-first t)
            (check (synthesis-job-best cold-job))
            (setf cold-work (ledger-total (synthesis-job-ledger cold-job)))))
        (with-knowledge-library ((make-knowledge-library))
          (let ((j-inc (start-recursive-synthesis inc-frame inc-lang 90
                                                  :self-name :inc-m9
                                                  :library *knowledge-library*))
                (j-add3 (start-recursive-synthesis add3-frame add3-lang 90
                                                   :self-name :add3-m9
                                                   :library *knowledge-library*)))
            (resume-synthesis j-inc 120000 :stop-on-first t)
            (resume-synthesis j-add3 120000 :stop-on-first t)
            (commit-synthesis-job j-inc :name :inc-m9 :library *knowledge-library* :register-templates-p t)
            (commit-synthesis-job j-add3 :name :add3-m9 :library *knowledge-library* :register-templates-p t)
            (consolidate-knowledge-library *knowledge-library*
                                           :synthesis-jobs (list j-inc j-add3)
                                           :library-names '(:map))
            (remember-decoder-template
             (make-decomposition
              :decoder (app (op :if seq-type)
                            (app (op := seq-type) (var 0 seq-type) (lit seq-type '()))
                            (lit seq-type '())
                            (app (op :cons :int) (var 1 :int) (var 0 seq-type)))
              :child-id 1
              :child-type :int
              :bindings (list (cons 0 (app (op :at seq-type) (var 0 seq-type) (lit :int 0)))))
             inputs)
            (let ((warm-job (start-recursive-synthesis shift4-frame shift4-lang 90
                                                       :self-name :shift4-warm-m9
                                                       :library *knowledge-library*)))
              (resume-synthesis warm-job 120000 :stop-on-first t)
              (check (synthesis-job-best warm-job))
              (check (< (ledger-total (synthesis-job-ledger warm-job)) cold-work))
              (when (synthesis-node-deferred-proposals (synthesis-job-root warm-job))
                (let ((promoted (promote-next-deferred-proposal warm-job))
                      (before-work (ledger-total (synthesis-job-ledger warm-job))))
                  (check (synthesis-node-p promoted))
                  (resume-synthesis warm-job (+ before-work 50))
                  (check (<= (ledger-total (synthesis-job-ledger warm-job)) (+ before-work 50))))))))))))

(deftest library-unified-descriptors-and-synchronized-executables
  (with-clean-kernel-state
    ;; 1. Synchronized `knowledge-entry-executable` fast closure parity, non-persistence, and auto-resync
    (let ((entry (register-knowledge-entry
                  (make-knowledge-entry :id :TEST/EXEC-ENTRY
                                        :kind :descriptor
                                        :inputs '((0 . (:seq :int)) (1 . (:seq :int)))
                                        :target :bool
                                        :guard (bool-not (term `(= ,(var 0 '(:seq :int)) ())))
                                        :expression (term `(= (length ,(var 0 '(:seq :int)))
                                                              (length ,(var 1 '(:seq :int)))))))))
      (check (entry-executable-p (knowledge-entry-executable entry)))
      (check (functionp (entry-executable-expr-fn (knowledge-entry-executable entry))))
      (check (functionp (entry-executable-guard-fn (knowledge-entry-executable entry))))
      ;; Parity with VM `evaluate` across satisfied, falsified, and `:unresolved` inputs
      (dolist (args '(((1 2) (3 4)) ((1 2) (3)) (:unresolved (3))))
        (let ((vm-run (evaluate (knowledge-entry-expression entry)
                                (knowledge-entry-inputs entry) args))
              (fast-run (consume-knowledge-entry entry args :ledger (make-ledger))))
          (check (eq (evaluation-status vm-run) (evaluation-status fast-run)))
          (when (eq :value (evaluation-status vm-run))
            (check (equal (evaluation-value vm-run) (evaluation-value fast-run))))))
      ;; `:executable` is excluded from serialized plists and rebuilt on load
      (let* ((sexp (serialize-knowledge-library *knowledge-library*))
             (entries-plist (getf (rest sexp) :entries))
             (saved-entry (find :TEST/EXEC-ENTRY entries-plist :key (lambda (p) (getf p :id))))
             (reloaded (deserialize-knowledge-library sexp))
             (reloaded-entry (find-knowledge-entry :TEST/EXEC-ENTRY reloaded)))
        (check saved-entry)
        (check (null (getf saved-entry :executable)))
        (check (entry-executable-p (knowledge-entry-executable reloaded-entry)))
        (check (functionp (entry-executable-expr-fn (knowledge-entry-executable reloaded-entry)))))
      ;; Mutating an AST slot automatically invalidates and resynchronizes `entry-executable`
      (setf (knowledge-entry-expression entry)
            (term `(< (length ,(var 1 '(:seq :int))) (length ,(var 0 '(:seq :int))))))
      (multiple-value-bind (val status)
          (eval-entry-slot entry :expr '((1 2 3) (9)))
        (check (eq :value status))
        (check (eq t val))))
    ;; 2. Observation-synthesized `:descriptor` AST entries and relational `score-entry-by-descriptors`
    (let* ((seq-type (sequence-type :int))
           (fn-inputs (list (cons 0 seq-type)))
           (x0 (var 0 seq-type)))
      (define-function :shift-up-desc-test fn-inputs seq-type
        (lambda (self)
          (term `(if (= ,x0 ())
                     ()
                     (cons (+ (at ,x0 0) 3)
                           (,self (tail ,x0)))))))
      (let* ((fn-entry (find-knowledge-entry :SHIFT-UP-DESC-TEST *knowledge-library*))
             (desc-edges (knowledge-edges-to :SHIFT-UP-DESC-TEST :describes *knowledge-library*))
             (descs (mapcar (lambda (e) (find-knowledge-entry (second e) *knowledge-library*))
                            desc-edges)))
        (check fn-entry)
        (check (>= (length descs) 2))
        ;; Every descriptor's behavioral predicate is an object-language `:bool` AST with a compiled closure
        (check (every (lambda (d)
                        (and (eq :bool (expression-type (knowledge-entry-expression d)
                                                        (knowledge-entry-inputs d)))
                             (functionp (entry-executable-expr-fn (ensure-entry-executable d)))))
                      descs))
        ;; Structurally backed shape invariant carries `:necessary` evidence; sampled step-delta stays `:empirical`
        (check (some (lambda (d) (knowledge-evidence-current-p d :necessary)) descs))
        (check (some (lambda (d) (not (knowledge-evidence-current-p d :necessary))) descs))
        ;; Relational scoring: constant-step frame beats non-constant equal-length frame, and
        ;; length-contracting frame is soundly pruned.
        (let ((const-delta-frame (simple-frame seq-type fn-inputs '((((1 4 9)) (6 9 14)))))
              (nonconst-frame (simple-frame seq-type fn-inputs '((((1 4 9)) (2 10 99)))))
              (contract-frame (simple-frame seq-type fn-inputs '((((1 4 9)) (4))))))
          (multiple-value-bind (ok1 score1 matched1)
              (score-entry-by-descriptors fn-entry const-delta-frame 0)
            (multiple-value-bind (ok2 score2 matched2)
                (score-entry-by-descriptors fn-entry nonconst-frame 0)
              (multiple-value-bind (ok3 _s3 _m3)
                  (score-entry-by-descriptors fn-entry contract-frame 0)
                (declare (ignore _s3 _m3))
                (check ok1)
                (check ok2)
                (check (null ok3))
                (check (minusp score1))
                (check (< score1 score2))
                (check (> (length matched1) (length matched2)))))))))))
