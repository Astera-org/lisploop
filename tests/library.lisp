(in-package #:lisploop)

(defun define-test-map-candidate-functions ()
  "Define `:inc-list` and `:double-list` recursive list functions for library tests."
  (let* ((seq-type (sequence-type :int))
         (inputs (list (cons 0 seq-type)))
         (xs (var 0 seq-type))
         (empty-xs (app (op := seq-type) xs (lit seq-type '())))
         (head-xs (app (op :at seq-type) xs (lit :int 0)))
         (tail-xs (app (op :tail :int) xs)))
    (define-function :inc-list inputs seq-type nil)
    (define-function :inc-list inputs seq-type
      (app (op :if seq-type)
           empty-xs
           (lit seq-type '())
           (app (op :cons :int)
                (app (op :+ :int) head-xs (lit :int 1))
                (app (op :inc-list) tail-xs))))
    (define-function :double-list inputs seq-type nil)
    (define-function :double-list inputs seq-type
      (app (op :if seq-type)
           empty-xs
           (lit seq-type '())
           (app (op :cons :int)
                (app (op :* :int) head-xs (lit :int 2))
                (app (op :double-list) tail-xs))))))

(deftest library-l1-metaprogramming-and-persistence-roundtrip
  (unwind-protect
       (with-knowledge-library ((make-knowledge-library))
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
                (rel (observe-arithmetic-relation gf5 :+ '(0 1 2 3 4)))
                (disc (discover-arithmetic-solver rel 0 '(0 1 2 3 4) :operators '(:+ :-)))
                (solver-entry (register-knowledge-solver disc :id :gf5-add-solve-0)))
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
         (register-knowledge-solver :+
                                    :id :int-add-solve-0
                                    :domain :int
                                    :inputs (arithmetic-inputs :int)
                                    :target :int
                                    :position 0
                                    :witness (app (op :- :int) (var 1 :int) (var 0 :int))
                                    :guard (lit :bool t)
                                    :certified-p t
                                    :unique-p t)
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
                    ;; Every kind is restored
                    (dolist (k '(:function :descriptor :relation :law :solver :functor
                                 :nogood-schema :dip-feature :heuristic))
                      (check (plusp (length (knowledge-entries-of-kind k)))))
                    ;; Restored `:inc-list` and `:map` execute in the VM
                    (let ((inc-e (find-knowledge-entry :inc-list)))
                      (check inc-e)
                      (check (equal '(11 21 31)
                                    (evaluation-value (consume-knowledge-entry inc-e '((10 20 30)))))))
                    ;; Restored rewrite library and propagator library work immediately
                    (check (rewrite-library-p (as-rewrite-library *knowledge-library* :domain (gf 5))))
                    (check (propagator-library-p (as-propagator-library *knowledge-library*)))
                    (check (knowledge-library-priority-predictor *knowledge-library*))))
             (when (probe-file tmp-path)
               (delete-file tmp-path)))))
    (clear-function-definitions)))

(deftest library-l2-irreducible-residuals-and-delayed-condensation
  (unwind-protect
       (with-knowledge-library ((make-knowledge-library))
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
           ;; Exception keys use the residual lookup table
           (check (= 99 (evaluation-value (consume-knowledge-entry hybrid-rel '(3)))))
           (check (= -1 (evaluation-value (consume-knowledge-entry hybrid-rel '(7)))))
           ;; Non-exception keys smoothly fall back to 2 * X0 without error
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
           ;; Verify second-order `:code` relation round-trips through serialization
           (let* ((sexp (knowledge-entry->sexp code-rel))
                  (restored (sexp->knowledge-entry sexp)))
             (check (equal dec-code (evaluation-value (consume-knowledge-entry restored (list inc-code)))))))
         ;; 4. Delayed structure discovery (`consolidate-residual-relations`):
         ;; Two small empirical residual tables for 3*x + 1 that pool across tasks and condense!
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
             ;; Condensed algebraic expression generalizes to unseen inputs (e.g. x = 10 -> 31)!
             (check (= 1 (evaluation-value (consume-knowledge-entry batch1 '(0)))))
             (check (= 16 (evaluation-value (consume-knowledge-entry batch1 '(5)))))
             (check (= 31 (evaluation-value (consume-knowledge-entry batch1 '(10))))))))
    (clear-function-definitions)))

(deftest library-l3-higher-order-edges-functors-and-descriptors
  (unwind-protect
       (with-knowledge-library ((make-knowledge-library))
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
           ;; Verify `library-decompositions` prunes `:map` when input/output sequence lengths mismatch
           ;; and admits `:map` when lengths match!
           (let* ((seq-type (sequence-type :int))
                  (inputs (list (cons 0 seq-type)))
                  (lang (make-language :int inputs
                                       :operators (list (op :+ :int) (op :cons :int)
                                                        (op :tail :int) (op :at seq-type)
                                                        (op := seq-type) (op :if seq-type)
                                                        (op :map))
                                       :literals '(0 1 2)))
                  (mismatch-frame
                    (simple-frame seq-type inputs
                                  '((((1 2 3)) (10 20)))))
                  (match-frame
                    (simple-frame seq-type inputs
                                  '((((1 2 3)) (10 20 30))))))
             ;; This structural descriptor now carries current necessary-condition evidence.
             (check (null (library-decompositions mismatch-frame lang :ledger (make-ledger))))
             (check (plusp (length (library-decompositions match-frame lang :ledger (make-ledger)))))))
         ;; 4. Register element-level `:solver` for `:+` and induce second-order `:functor` solvers
         (register-knowledge-solver :+
                                    :id :int-add-solve-0
                                    :domain :int
                                    :inputs (arithmetic-inputs :int)
                                    :target :int
                                    :position 0
                                    :witness (app (op :- :int) (var 1 :int) (var 0 :int))
                                    :guard (lit :bool t)
                                    :certified-p t
                                    :unique-p t)
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
         ;; for an UNSEEN constant '7 using `:code-match`, `:code-bind`, `:code-subst` in the VM!
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
                         req2))))
    (clear-function-definitions)))

(deftest library-l4-continual-learning-curriculum-amortization
  (unwind-protect
       (let* ((seq-type (sequence-type :int))
              (inputs (list (cons 0 seq-type)))
              (inc-frame
                (simple-frame seq-type inputs
                              '(((()) ())
                                (((2)) (3))
                                (((5 2)) (6 3))
                                (((0 5 2)) (1 6 3)))))
              (add3-frame
                (simple-frame seq-type inputs
                              '(((()) ())
                                (((2)) (5))
                                (((5 2)) (8 5))
                                (((0 5 2)) (3 8 5)))))
              ;; Transfer task: shift-by-4(xs) = [x + 4 for x in xs]
              (shift4-frame
                (simple-frame seq-type inputs
                              '(((()) ())
                                (((2)) (6))
                                (((5 2)) (9 6))
                                (((0 5 2)) (4 9 6)))))
              ;; Context-dependent task: add-len(xs) = [x + len(xs) for x in xs]
              (add-len-frame
                (simple-frame seq-type inputs
                              '(((()) ())
                                (((5)) (6))
                                (((5 2)) (7 4))
                                (((0 5 2)) (3 8 5)))))
              (base-ops (list (op :+ :int) (op :cons :int) (op :tail :int)
                              (op :at seq-type) (op := seq-type) (op :if seq-type)))
              (len-ops (append base-ops (list (op :length :int))))
              (inc-lang (make-language :int inputs
                                       :operators base-ops
                                       :literals '(1)
                                       :constants (list (lit seq-type '()))))
              (add3-lang (make-language :int inputs
                                        :operators base-ops
                                        :literals '(3)
                                        :constants (list (lit seq-type '()))))
              (shift4-lang (make-language :int inputs
                                          :operators base-ops
                                          :literals '(4)
                                          :constants (list (lit seq-type '()))))
              (len-lang (make-language :int inputs
                                       :operators len-ops
                                       :literals '(0 1)
                                       :constants (list (lit seq-type '()))))
              (cold-inc-work 0)
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
         ;; 2. Run 1 (Cold Discovery -> Consolidation -> Persistence):
         ;;    Synthesize `:inc-list` and `:add3-list` de novo from examples, consolidate into `:map`,
         ;;    induce functorial solvers/descriptors/heuristics, synthesize `:add-len` (committing its
         ;;    UIP `:nogood-schema` and `:dip-feature`), and serialize the library.
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
             (register-knowledge-solver :+
                                        :id :int-add-solve-0
                                        :domain :int
                                        :inputs (arithmetic-inputs :int)
                                        :target :int
                                        :position 0
                                        :witness (app (op :- :int) (var 1 :int) (var 0 :int))
                                        :guard (lit :bool t)
                                        :certified-p t
                                        :unique-p t)
             (let ((report (consolidate-knowledge-library *knowledge-library*
                                                          :synthesis-jobs (list j-inc j-add3)
                                                          :library-names '(:map))))
               (check (> (getf report :after-version) (getf report :before-version)))
               (check (find-knowledge-entry :map))
               (check (find-knowledge-entry :map/descriptor))
               (check (find-knowledge-entry :map/functor))
               (check (find-knowledge-entry :map/invert-+-0))
               (check (find-knowledge-entry :default-priority-predictor)))
             ;; Synthesize `add-len` before any `:nogood-schema` or `:dip-feature` is in the library,
             ;; then commit the job to persist both into `*knowledge-library*`.
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
         ;; 3. Run 2 (Warm Synthesis after Deserialization):
         ;;    Re-run with the EXACT same languages (`inc-lang`, `shift4-lang`, `len-lang`) and
         ;;    `start-recursive-synthesis` calls, verifying strict reductions in BOTH discovery work (W)
         ;;    and description length (S, both `candidate-size` and `body-size`).
         (with-knowledge-library ((deserialize-knowledge-library serialized))
           ;; 3a. Repeated task (`inc-list`) with identical `inc-lang` and `start-recursive-synthesis`:
           (let ((warm-inc-job (start-recursive-synthesis inc-frame inc-lang 90
                                                          :self-name :inc-warm
                                                          :library *knowledge-library*)))
             (resume-synthesis warm-inc-job 120000 :stop-on-first t)
             (check (synthesis-job-best warm-inc-job))
             (let ((warm-inc-work (ledger-total (synthesis-job-ledger warm-inc-job)))
                   (warm-inc-size (candidate-size (synthesis-job-best warm-inc-job)))
                   (warm-inc-body (body-size (candidate-expression (synthesis-job-best warm-inc-job)) inputs)))
               (check (< warm-inc-work cold-inc-work))
               (check (< warm-inc-size cold-inc-size))
               (check (< warm-inc-body cold-inc-body))))
           ;; 3b. Unseen transfer task (`shift-by-4`) with identical `shift4-lang` and `start-recursive-synthesis`:
           (let ((warm-shift4-job (start-recursive-synthesis shift4-frame shift4-lang 90
                                                             :self-name :shift4-warm
                                                             :library *knowledge-library*)))
             (resume-synthesis warm-shift4-job 120000 :stop-on-first t)
             (check (synthesis-job-best warm-shift4-job))
             (let ((warm-shift4-work (ledger-total (synthesis-job-ledger warm-shift4-job)))
                   (warm-shift4-size (candidate-size (synthesis-job-best warm-shift4-job)))
                   (warm-shift4-body (body-size (candidate-expression (synthesis-job-best warm-shift4-job)) inputs)))
               ;; Strictly reduces both discovery work W and description length S (total & body bits)
               (check (< warm-shift4-work cold-shift4-work))
               (check (< warm-shift4-size cold-shift4-size))
               (check (< warm-shift4-body cold-shift4-body))
               ;; Commit `shift4-warm` back into the library and verify `:refactored-by` edge and descriptor
               (commit-synthesis-job warm-shift4-job :name :shift4-warm :library *knowledge-library*)
               (let ((s4-entry (find-knowledge-entry :shift4-warm)))
                 (check s4-entry)
                 (check (find-knowledge-entry :shift4-warm/descriptor))
                 (check (equal '(14 24 34)
                               (evaluation-value (consume-knowledge-entry s4-entry '((10 20 30))))))
                 (check (member '(:refactored-by :map)
                                (knowledge-edges-from :shift4-warm :refactored-by)
                                :test #'equal)))))
           ;; 3c. Context-dependent task (`add-len`) reusing persisted `:nogood-schema` + `:dip-feature`:
           (let ((warm-len-job (start-recursive-synthesis add-len-frame len-lang 90
                                                          :self-name :add-len-warm
                                                          :library *knowledge-library*)))
             (resume-synthesis warm-len-job 120000 :stop-on-first t)
             (check (synthesis-job-best warm-len-job))
             (let ((warm-add-len-work (ledger-total (synthesis-job-ledger warm-len-job))))
               ;; Persisted `:nogood-schema` immediately refutes unary `:map` (`:reused-nogood t`)
               ;; and persisted `:dip-feature` `(length X0)` repairs it with strictly less work.
               (check (some (lambda (m)
                              (and (eq :conflict (message-claim m))
                                   (getf (message-evidence m) :reused-nogood)))
                            (synthesis-job-messages warm-len-job)))
               (check (< warm-add-len-work cold-add-len-work))))))
    (clear-function-definitions)))
