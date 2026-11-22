(in-package #:lisploop)

;;; Stage 0 (E0a + E0b): Soundness/sandbox regression tests and battery load-bearing switches.

(deftest stage0-e0a-retype-laws-and-consolidation-samples
  "Consolidating validated finite-field laws to `:int` without explicit `:samples` supplies
default sample assignments, keeping sound ring laws as `:conjecture` and refuting modular
wrap-around coincidences instead of discarding all retyped laws as `:vacuous`."
  (with-clean-kernel-state
    (let* ((gf3 (gf 3))
           (in1 (list (cons 0 gf3)))
           (in2 (list (cons 0 gf3) (cons 1 gf3)))
           (a (var 0 gf3))
           (b (var 1 gf3))
           (comm-val (resume-law-validation
                      (start-law-validation
                       (make-law gf3 in2 (term `(+ ,a ,b)) (term `(+ ,b ,a))))
                      50000))
           (wrap-val (resume-law-validation
                      (start-law-validation
                       (make-law gf3 in1 (term `(+ (+ ,a ,a) ,a)) (lit gf3 0)))
                      50000))
           (lib (make-knowledge-library)))
      (check (eq :validated (law-validation-status comm-val)))
      (check (eq :validated (law-validation-status wrap-val)))
      (let ((report (consolidate-knowledge-library lib
                                                   :law-validations (list comm-val wrap-val)
                                                   :retype-domains '(:int)
                                                   :condense-heuristic-p nil)))
        (check (getf report :fixed-point-p))
        (let ((int-laws (remove-if-not (lambda (e) (eq :int (knowledge-entry-domain e)))
                                       (knowledge-entries-of-kind :law lib))))
          ;; Commutativity survives `:int` sampling; `x + x + x = 0` is refuted on `:int`!
          (check (= 1 (length int-laws)))
          (check (eq :conjecture (knowledge-entry-status (first int-laws))))
          (check (knowledge-evidence-tested-p (first int-laws) :equivalence))
          (check (not (knowledge-evidence-current-p (first int-laws) :equivalence))))))))

(deftest stage0-e0a-row-satisfaction-and-observation-unresolved
  "`row-satisfaction` treats `:unresolved` oracle calls in either candidate or requirement
evaluation as `:unknown` (never `nil` or `:refuted`), and `observation-job` never marks
`:unresolved` or `:cutoff` expressions as `:complete` when `retain-outcomes` is enabled."
  (with-clean-kernel-state
    (define-function :partial-oracle '((0 . :int)) :int nil
      :oracle-table '(((1) . 10)))
    (let* ((inputs '((0 . :int)))
           (x (var 0 :int))
           (call-expr (app (op :partial-oracle) x))
           (row-hit (make-row :key 0 :known '(1) :requirement (singleton-requirement :int 10)))
           (row-miss-oracle (make-row :key 1 :known '(2) :requirement (singleton-requirement :int 20)))
           (row-unres-req (make-row :key 2 :known '(1)
                                    :requirement (term `(= ,(var 0 :int) (partial-oracle 99))))))
      (check (eq :satisfied (row-satisfaction row-hit call-expr inputs)))
      (check (eq :unknown (row-satisfaction row-miss-oracle call-expr inputs)))
      (check (eq :unknown (row-satisfaction row-unres-req (lit :int 10) inputs)))
      ;; `observation-job` with `retain-outcomes` on an unresolved row keeps status `:unresolved`.
      (let* ((frame (probe-frame :int inputs '((1) (2))))
             (lang (make-language :int inputs :operators (list (op :partial-oracle))))
             (scope (make-observation-scope frame lang))
             (obs (start-observation-search scope :expressions (list call-expr) :retain-outcomes t)))
        (resume-observation-search obs 80 10000)
        (let ((rec (find-observation obs call-expr)))
          (check rec)
          (check (eq :unresolved (observed-expression-status rec)))
          (check (null (observation-job-buckets obs))))))))

(deftest stage0-e0a-node-search-rewrites-with-active-laws
  "Prepared synthesis nodes pass active certified rewrite laws into `start-search`, refresh
their `rewrite-library` across function definitions, skip `:code`-typed scopes safely, and
respect `:library nil`."
  (with-clean-kernel-state
    (load-battery :algebra)
    (let* ((inputs '((0 . :int) (1 . :int)))
           (frame (simple-frame :int inputs '(((2 5) 2) ((7 -3) 7) ((0 4) 0))))
           (lang (make-language :int inputs :operators (list (op :+ :int) (op :- :int))))
           (job (start-synthesis frame lang 60))
           (isolated (start-synthesis frame lang 60 :library nil)))
      ;; Root preparation & opening attaches the `:int` rewrite library when active, none when `:library nil`.
      (resume-synthesis job 500 :stop-on-first t)
      (resume-synthesis isolated 500 :stop-on-first t)
      (let ((root-search (synthesis-node-search (synthesis-job-root job)))
            (iso-search (synthesis-node-search (synthesis-job-root isolated))))
        (check root-search)
        (check (rewrite-library-p (lisploop::search-job-library root-search)))
        (check (null (lisploop::search-job-library iso-search))))
      ;; Defining a new function bumps `*function-library-version*`; child nodes refresh cleanly.
      (define-function :helper-id '((0 . :int)) :int (var 0 :int))
      (resume-synthesis job 20000 :stop-on-first t)
      (check (synthesis-job-best job))
      (check (equal (var 0 :int) (candidate-expression (synthesis-job-best job)))))))

(deftest stage0-e0a-universal-row-fuel-and-sandbox-safety
  "Diverging recursive calls and crashing child bindings are bounded per row across `start-search`,
`start-observation-search`, `propagate-requirements`, and `prepare-synthesis-node`."
  (with-clean-kernel-state
    (define-function :spin '((0 . :int)) :int
      (lambda (self) (app self (var 0 :int))))
    (let* ((*default-row-budget* 250)
           (*propagation-eval-budget* 250)
           (inputs '((0 . :int)))
           (x (var 0 :int))
           (frame (simple-frame :int inputs '(((3) 4) ((5) 6))))
           (lang (make-language :int inputs :operators (list (op :spin) (op :+ :int)) :literals '(1))))
      ;; 1. `start-search` cuts off `(spin X0)` in 250 steps and still finds `(+ X0 1)` well within 15k work.
      (let ((sjob (start-search frame lang)))
        (resume-search sjob 45 15000)
        (check (search-job-best sjob))
        (check (= 8 (result (candidate-expression (search-job-best sjob)) inputs '(7)))))
      ;; 2. `start-observation-search` cuts off `(spin X0)` with `:cutoff` and buckets `(+ X0 1)`.
      (let* ((pframe (probe-frame :int inputs '((3) (5))))
             (obs (start-observation-search (make-observation-scope pframe lang)
                                            :row-budget 250
                                            :expressions (list (app (op :spin) x)
                                                               (term `(+ ,x 1)))
                                            :retain-outcomes t)))
        (resume-observation-search obs 60 15000)
        (check (eq :cutoff (observed-expression-status (find-observation obs (app (op :spin) x)))))
        (check (eq :complete (observed-expression-status (find-observation obs (term `(+ ,x 1)))))))
      ;; 3. Diverging solver witness in `propagate-requirements` cuts off safely without crashing.
      (register-knowledge-solver (op :+ :int)
                                 :id :bad-spin-solver :domain :int :position 1
                                 :witness (app (op :spin) (var 0 :int))
                                 :certified-p nil :unique-p nil)
      (let* ((ledger (make-ledger))
             (prop (propagate-requirements
                    (make-frame (make-schema :inputs nil :target :int)
                                (list (make-row :key 0 :known nil
                                                :requirement (term `(= (+ 2 ,(var 0 :int)) 5)))))
                    *knowledge-library* ledger)))
        (check (= 1 (propagation-retained prop)))
        (check (< (ledger-total ledger) 2000)))
      ;; 4. Partial child binding crashing on an empty sequence row closes child node cleanly as `:conflict`.
      (let* ((seq-t (sequence-type :int))
             (s-in (list (cons 0 seq-t)))
             (s-frame (simple-frame :int s-in '(((()) 0) (((4 5)) 4))))
             (s-lang (make-language :int s-in :literals '(0)))
             (bad-prop (make-decomposition
                        :name :crash-head
                        :decoder (var 9 :int)
                        :child-id 9 :child-type :int
                        :bindings (list (cons 0 (term `(at ,(var 0 seq-t) 0))))
                        :language (make-language :int '((0 . :int)) :literals '(0))
                        :bound 30))
             (job (start-synthesis s-frame s-lang 40 :decompositions (list bad-prop))))
        (resume-synthesis job 5000)
        (let ((child (second (synthesis-job-nodes job))))
          (check (eq :done (lisploop::synthesis-node-phase child))))))))

(deftest stage0-e0a-coupled-nogood-keys-and-branch-safe-filter-lift
  "Distinct coupled fallback occurrences do not collide on `:coupled` in nogood clauses, and
`flatten-lifted-conjuncts` refutes impossible duplicate-element `:filter` branches while
preserving ambiguous `:filter` branches without hallucinating positive hits."
  (with-clean-kernel-state
    (load-battery :sequences :only '(:filter))
    (let* ((seq-t (sequence-type :int))
           (inputs (list (cons 0 seq-t)))
           (xs (var 0 seq-t))
           (pred-t (code-type '((0 . :int)) :bool))
           (z (var 1 pred-t)))
      ;; 1. Impossible duplicate-element row: `(filter '(1 2 1 3) Z) = '(1 3)` has NO valid predicate `Z`!
      (let* ((bad-frame (simple-frame seq-t inputs '((((1 2 1 3)) (1 3)))))
             (lifted (lift-frame bad-frame (app (op :filter) xs z) 1 pred-t)))
        (check (nth-value 0 (frame-conflict-p lifted))))
      ;; 2. Ambiguous non-injective outer wrapper: `(= (length (filter '(1 2) Z)) 1)` + `(= (filter '(3) Z) '(3))`.
      ;;    True solution `(< 1 X0)` has `Z(1) = nil, Z(2) = t`; old code hallucinated `Z(1) = t, Z(2) = nil`!
      (let* ((ambig-frame
               (make-frame (make-schema :inputs inputs :target seq-t)
                           (list (make-row :key 0 :known '((1 2))
                                           :requirement (term `(= (length ,(var 0 seq-t)) 1)))
                                 (make-row :key 1 :known '((3))
                                           :requirement (singleton-requirement seq-t '(3))))))
             (lang (make-language :int inputs
                                  :operators (list (op :filter) (op :< :int))
                                  :literals '(1)
                                  :constants (list (lit seq-t '())))))
        (multiple-value-bind (lifted coupled)
            (lift-frame ambig-frame (app (op :filter) xs z) 1 pred-t)
          (check (null (nth-value 0 (frame-conflict-p lifted))))
          (check (= 1 (length coupled))))
        (let ((job (start-heuristic-synthesis ambig-frame lang 70)))
          (resume-synthesis job 30000 :stop-on-first t)
          (check (synthesis-job-best job))
          (let ((expr (candidate-expression (synthesis-job-best job))))
            (check (equal '(2 5) (result expr inputs '((1 2 0 5))))))))
      ;; 3. Distinct `:coupled` fallback occurrence keys never trick `build-nogood-clause` into `parent-incompatible-p`.
      (let* ((parent (make-synthesis-node
                      :id 0
                      :frame (simple-frame seq-t inputs '((((1 2)) (2)) (((3 4)) (4))))))
             (prop (make-decomposition :name :flt :decoder (app (op :filter) xs z)
                                       :child-id 1 :child-type pred-t :lift-p t))
             (conflict (lisploop::incompatible-rows-conflict
                        (list (list 0 (cons :coupled 0)) (list 1 (cons :coupled 1)))
                        '(1)))
             (clause (lisploop::build-nogood-clause parent prop conflict)))
        (check (not (nogood-clause-parent-incompatible-p clause)))))))

(deftest stage0-e0b-constructor-and-descriptor-switches
  "Gating `*enable-host-cons-folds*` and `*enable-host-descriptor-synthesis*` isolates host
fold rules and matches preloaded `descriptors.sexp` entries without host prototype search."
  (with-clean-kernel-state
    (let* ((seq-t (sequence-type :int))
           (term-eq (term `(= (cons ,(var 0 :int) ,(var 1 seq-t)) '(3 4)))))
      (check (not (equal term-eq (fold-constants term-eq :contract :necessary))))
      (let ((*enable-host-cons-folds* nil))
        (check (equal term-eq (fold-constants term-eq :contract :necessary))))))
  ;; With `descriptors.sexp` loaded and `*enable-host-descriptor-synthesis*` NIL, `:map` and `:filter`
  ;; acquire accurate necessary/empirical profiles from the library's descriptors at tiny work cost.
  (with-clean-kernel-state
    (load-battery :descriptors)
    (let ((*enable-host-descriptor-synthesis* nil)
          (ledger (make-ledger)))
      (load-battery :sequences :only '(:map :filter :map-adjacent) :ledger ledger)
      (check (entry-descriptor-necessary-p :map :DESC/LEN-EQ))
      (check (find :DESC/LEN-LE (knowledge-entry-descriptor-profile (find-knowledge-entry :filter))
                   :key #'descriptor-clause-id))
      (check (find :DESC/LEN-DEC-1 (knowledge-entry-descriptor-profile (find-knowledge-entry :map-adjacent))
                   :key #'descriptor-clause-id))
      (let* ((seq-t (sequence-type :int))
             (flt-frame (simple-frame seq-t (list (cons 0 seq-t))
                                      '(((()) ()) (((1 2 3)) (2))))))
        (check (not (library-function-descriptor-compatible-p flt-frame 0 :map ledger)))
        (check (library-function-descriptor-compatible-p flt-frame 0 :filter ledger))))))
