(in-package #:lisploop)

;;; ===========================================================================
;;; Plan 8 / P8.1: let-sharing, product slots, Constructor-AU, and feature-pair guards
;;; ===========================================================================

(defun inline-composition (decoder child-id child-model bindings)
  "The composition by substitution alone, which every shared form must agree with."
  (instantiate decoder (list (cons child-id (instantiate child-model bindings :var))) :var))

(deftest let-sharing-is-smaller-and-preserves-definedness
  "A value that a composed model would compute more than once is bound once under a
`:code-eval` let, when that is smaller and can neither add nor hide an error."
  (let* ((inputs '((0 . :int) (1 . :int)))
         (x0 (var 0 :int)) (x1 (var 1 :int))
         (v0 (var 0 :int)) (v1 (var 1 :int))
         (z (var 9 :int))
         (valuations '((0 0) (1 0) (0 3) (6 3) (-7 2) (12 -5)))
         (big (term `(+ (* ,x0 ,x1) (* (+ ,x0 ,x1) (+ ,x0 ,x1)))))
         (partial (term `(/ (+ ,x0 ,x1) (* ,x1 ,x1)))))
    (flet ((agrees-p (model reference)
             (every (lambda (values)
                      (equal (outcome-signature model inputs values)
                             (outcome-signature reference inputs values)))
                    valuations))
           (shared-p (model)
             (app-of-p model :code-eval)))
      ;; 1. A total binding used twice is shared, is smaller, and unfolds back to the substitution.
      (let* ((child (term `(* ,v0 ,v0)))
             (bindings (list (cons 0 big)))
             (inline (inline-composition z 9 child bindings))
             (model (compose-model z 9 child bindings nil inputs)))
        (check (shared-p model))
        (check (< (description-size model inputs) (description-size inline inputs)))
        (check (provably-total-p model))
        (check (agrees-p model inline))
        (check-codec-roundtrip model inputs)
        (check (equal inline (fold-constants model)))
        ;; Without a scope the variables of the result stand in for it.
        (check (shared-p (compose-model z 9 child bindings))))
      ;; 2. A partial binding that every path demands is shared, error included.
      (let* ((child (term `(+ ,v0 (* ,v0 ,v0))))
             (bindings (list (cons 0 partial)))
             (inline (inline-composition z 9 child bindings))
             (model (compose-model z 9 child bindings nil inputs)))
        (check (shared-p model))
        (check (agrees-p model inline))
        (check (equal '(:error nil) (outcome-signature model inputs '(1 0)))))
      ;; 3. A partial binding that a branch may skip stays where the branch guards it.
      (let* ((child (term `(if (= ,v1 0) 0 (+ ,v0 (* ,v0 ,v0)))))
             (bindings (list (cons 0 partial) (cons 1 x1)))
             (inline (inline-composition z 9 child bindings))
             (model (compose-model z 9 child bindings nil inputs)))
        (check (equal inline model))
        (check (equal '(:value 0) (outcome-signature model inputs '(1 0)))))
      ;; 4. A body that is not total by itself is not quoted: its totality may rest on its context.
      (let* ((child (term `(/ ,v0 ,v0)))
             (bindings (list (cons 0 big))))
        (check (null (let-call child bindings)))
        (check (equal (inline-composition z 9 child bindings)
                      (compose-model z 9 child bindings nil inputs))))
      ;; 5. A child the decoder mentions several times is bound once around the decoder.
      (let* ((decoder (term `(+ (* ,z ,z) (* ,z ,x0))))
             (inline (inline-composition decoder 9 big nil))
             (model (compose-model decoder 9 big nil nil inputs)))
        (check (shared-p model))
        (check (< (description-size model inputs) (description-size inline inputs)))
        (check (agrees-p model inline)))
      ;; 6. Nothing used twice: composition is plain substitution, as before.
      (dolist (child (list v0 (term `(+ ,v0 1)) (lit :int 4)))
        (let ((bindings (list (cons 0 big))))
          (check (equal (inline-composition (term `(+ ,x1 ,z)) 9 child bindings)
                        (compose-model (term `(+ ,x1 ,z)) 9 child bindings nil inputs)))))
      ;; 7. A leaf used twice costs less to repeat than to bind.
      (check (equal (term `(* ,x1 ,x1))
                    (compose-model z 9 (term `(* ,v0 ,v0)) (list (cons 0 x1)) nil inputs))))))

(deftest product-slot-frames-are-galois-sound
  "The slot frames of a product reject no slot of a valid product, and through an injective
constructor they accept exactly the valid ones."
  (let* ((pair (tuple-type :int :int))
         (inputs '((0 . :int) (1 . :int)))
         (parent (simple-frame pair inputs '(((1 2) (3 2)) ((4 1) (5 4)) ((0 7) (7 0)))))
         (slots '((5 . :int) (6 . :int)))
         (bindings (identity-bindings inputs))
         (decoder (term `(tuple ,(var 5 :int) ,(var 6 :int))))
         (candidates (reference-typed-trees (list (var 0 :int) (var 1 :int) (lit :int 0))
                                            (list (op :+ :int) (op :* :int)) 1 inputs)))
    ;; 1. An injective constructor: every row pins each slot, and nothing couples them.
    (multiple-value-bind (frame-0 coupled-0) (product-slot-frame parent decoder slots 5 bindings)
      (multiple-value-bind (frame-1 coupled-1) (product-slot-frame parent decoder slots 6 bindings)
        (check (and (null coupled-0) (null coupled-1)))
        (check (equal '(3 5 7) (mapcar #'row-singleton-value (frame-rows frame-0))))
        (check (equal '(2 4 0) (mapcar #'row-singleton-value (frame-rows frame-1))))
        (check (equal (mapcar #'row-known (frame-rows parent)) (mapcar #'row-known (frame-rows frame-0))))
        (dolist (left candidates)
          (dolist (right candidates)
            (let ((model (compose-product-model decoder (list (cons 5 left) (cons 6 right))
                                                bindings nil inputs)))
              (check (eq (frame-satisfied-by-p model parent)
                         (and (frame-satisfied-by-p left frame-0)
                              (frame-satisfied-by-p right frame-1)))))))))
    ;; 2. A decoder that is not injective couples its slots; each slot frame is weakened, never wrong.
    (let* ((sum-parent (simple-frame :int inputs '(((1 2) 3) ((4 1) 5))))
           (sum-decoder (term `(+ ,(var 5 :int) ,(var 6 :int)))))
      (multiple-value-bind (frame coupled) (product-slot-frame sum-parent sum-decoder slots 5 bindings)
        (check (= 2 (length coupled)))
        (check (notany #'constrained-row-p (frame-rows frame)))))
    ;; 3. A set of whole tuples is not split into marginal sets.
    (let ((set-parent (make-frame (make-schema :inputs inputs :target pair)
                                  (list (make-row :key 0 :known '(1 2)
                                                  :requirement (set-requirement pair '((0 1) (1 0))))))))
      (multiple-value-bind (frame coupled) (product-slot-frame set-parent decoder slots 5 bindings)
        (check (= 1 (length coupled)))
        (check (notany #'constrained-row-p (frame-rows frame)))))
    ;; 4. A slot the decoder repeats must agree with itself: (tuple Z Z) cannot make (2 3).
    (let* ((diagonal (term `(tuple ,(var 5 :int) ,(var 5 :int))))
           (frame (product-slot-frame parent diagonal '((5 . :int)) 5 bindings)))
      (check (frame-conflict-p frame)))
    ;; 5. Bindings give the slots their inputs: tuple components, whatever ids the inputs carry.
    (dolist (ids '((0 1) (7 3)))
      (let* ((tuple-inputs (list (cons (first ids) pair) (cons (second ids) :int)))
             (bindings (component-bindings tuple-inputs))
             (rows-parent (simple-frame pair tuple-inputs '((((1 2) 3) (4 2)) (((5 0) 1) (6 0)))))
             (slots (list (cons 8 :int) (cons 9 :int)))
             (decoder (term `(tuple ,(var 8 :int) ,(var 9 :int))))
             (frame (product-slot-frame rows-parent decoder slots 8 bindings)))
        (check (equal '((0 . :int) (1 . :int) (2 . :int)) (schema-inputs (frame-schema frame))))
        (check (equal '((1 2 3) (5 0 1)) (mapcar #'row-known (frame-rows frame))))
        (check (frame-satisfied-by-p (term `(+ ,(var 0 :int) ,(var 2 :int))) frame))
        ;; The joined product binds the projections once, around both slots.
        (let ((model (compose-product-model
                      decoder
                      (list (cons 8 (term `(+ ,(var 0 :int) ,(var 2 :int))))
                            (cons 9 (term `(* (+ ,(var 0 :int) ,(var 1 :int))
                                              (+ ,(var 0 :int) ,(var 1 :int))))))
                      bindings nil tuple-inputs)))
          (check (app-of-p model :code-eval))
          (check (provably-total-p model))
          (check-codec-roundtrip model tuple-inputs)
          (check (equal '(4 9) (result model tuple-inputs '((1 2) 3)))))))))

(deftest constructor-au-slots-agree-with-the-substitution-frame
  "The holes of an anti-unifier are the slots of a product whose decoder rebuilds the tree:
their frames are the coordinates of `au-substitutions-frame`."
  (let* ((scope '((0 . :int)))
         (code (code-type scope :int))
         (x (var 0 :int))
         (trees (list (term `(- 1 ,x)) (term `(- ,x 2)) (term `(- 3 (+ ,x ,x)))))
         (inputs (list (cons 4 :int)))
         (known '((10) (20) (30)))
         (parent (make-frame (make-schema :inputs inputs :target code)
                             (loop for tree in trees for row-known in known for key from 0
                                   collect (make-row :key key :known row-known
                                                     :requirement (singleton-requirement code tree))))))
    (multiple-value-bind (pattern substitutions) (anti-unify trees scope nil :operator-holes-p nil)
      (check (= 2 (length (pattern-holes pattern))))
      (multiple-value-bind (constructor parameters) (compile-au-constructor pattern scope)
        (let* ((slots (loop for (nil . type) in parameters for id from 7 collect (cons id type)))
               (decoder (instantiate constructor
                                     (loop for (hole . type) in parameters for (id . nil) in slots
                                           collect (cons hole (var id type)))
                                     :var))
               (joint (au-substitutions-frame pattern substitutions :inputs scope
                                              :known known :schema-inputs inputs)))
          (check (equal (mapcar #'row-known (frame-rows parent)) (mapcar #'row-known (frame-rows joint))))
          (loop for (id . nil) in slots
                for position from 0
                do (multiple-value-bind (frame coupled)
                       (product-slot-frame parent decoder slots id (identity-bindings inputs))
                     (check (null coupled))
                     (check (equal (mapcar (lambda (row) (nth position (row-singleton-value row)))
                                           (frame-rows joint))
                                   (mapcar #'row-singleton-value (frame-rows frame))))))
          ;; A tree the pattern does not match refutes its row in every slot.
          (let* ((odd (make-frame (frame-schema parent)
                                  (list (make-row :key :odd :known '(40)
                                                  :requirement (singleton-requirement
                                                                code (term `(* ,x ,x)))))))
                 (frame (product-slot-frame odd decoder slots (car (first slots))
                                            (identity-bindings inputs))))
            (check (frame-conflict-p frame))))))))

(defun conditional-tuple-scan-fixture ()
  "Plan 8 probe 5: a scan whose step keeps one slot of its state unless the other reaches it.
Returns the frame, the language, and held-out cases."
  (let* ((pair (tuple-type :int :int))
         (actions-type (sequence-type :int))
         (states-type (sequence-type pair))
         (inputs (list (cons 0 actions-type) (cons 1 pair))))
    ;; `:scan-pair` is from the `scans` battery (library/scans.lisp).
    (load-battery :scans :only '(:scan-pair))
    (values (simple-frame states-type inputs
                          '((((1 1) (0 2)) ((1 2) (2 3)))
                            (((1 1) (0 3)) ((1 3) (2 3)))
                            (((-1 -1) (4 2)) ((3 2) (2 1)))))
            (make-language :int inputs
                           :operators (list (op :+ :int) (op :- :int) (op := :int) (op :if :int)
                                            (op :tuple pair) (op :at pair) (op :scan-pair))
                           :literals '(0 1))
            '((((1 1 1) (0 3)) ((1 3) (2 3) (3 4)))
              (((2) (5 7)) ((7 9)))
              ((() (1 1)) ())))))

(deftest product-join-solves-the-conditional-tuple-scan
  "A tuple-valued step is found slot by slot over the components of its state: one slot
directly, the other as a Stage B exception whose guard compares two Stage A features, and
the joined product binds the projections once. The monolithic step is out of reach."
  (with-clean-kernel-state
    (multiple-value-bind (frame language held-out) (conditional-tuple-scan-fixture)
      (flet ((start ()
               (start-heuristic-synthesis frame language 260
                                          :library-functions '(:scan-pair))))
        (multiple-value-bind (batch)
            (check-synthesis-resumption #'start :budget 800000 :stop-on-first t)
          (let ((expression (candidate-expression (synthesis-job-best batch))))
            (check (< (ledger-total (synthesis-job-ledger batch)) 800000))
            (check-synthesized-model expression frame :held-out held-out :must-call-ops '(:scan-pair))
            ;; The winning candidate was joined at the lifted node from its two slots.
            (check (some (lambda (node)
                           (and (synthesis-node-join node) (slot-satisfied-p node)))
                         (synthesis-job-nodes batch)))
            (check (expression-calls-operator-p expression :code-eval))))
        ;; Without structural proposals the same budget does not reach the step.
        (let ((job (start-heuristic-synthesis frame language 260
                                              :library-functions '(:scan-pair)
                                              :structural-proposals-p nil)))
          (resume-synthesis job 800000 :stop-on-first t)
          (check (null (synthesis-job-best job))))))))

(deftest constructor-au-product-solves-a-symbolic-rewrite
  "Target trees that share a skeleton are rebuilt from it, each hole being synthesized from
the source tree by itself; renaming the input changes nothing."
  (let* ((scope '((0 . :int)))
         (code (code-type scope :int))
         (x (var 0 :int))
         (examples (list (list (term `(- ,x 1)) (term `(- 1 ,x)))
                         (list (term `(- 2 ,x)) (term `(- ,x 2)))
                         (list (term `(- (+ ,x ,x) 3)) (term `(- 3 (+ ,x ,x))))))
         (held-out (list (term `(- (* ,x ,x) 7)) (term `(- 7 (* ,x ,x)))))
         (results nil))
    (dolist (id '(0 5))
      (let* ((inputs (list (cons id code)))
             (frame (make-frame (make-schema :inputs inputs :target code)
                                (loop for (source target) in examples for key from 0
                                      collect (make-row :key key :known (list source)
                                                        :requirement (singleton-requirement code target)))))
             (language (make-language :int inputs
                                      :operators (list (op :code-child (tuple-type code code)))
                                      :literals '(0 1))))
        (flet ((start () (start-heuristic-synthesis frame language 220)))
          (multiple-value-bind (batch) (check-synthesis-resumption #'start :budget 200000 :stop-on-first t)
            (let ((expression (candidate-expression (synthesis-job-best batch))))
              (check-synthesized-model expression frame :require-total-p nil)
              (check (expression-calls-operator-p expression :code-apply))
              (check (equal (second held-out) (result expression inputs (list (first held-out)))))
              (push (description-size expression inputs) results))))))
    ;; The header names the input, the body does not: the two models differ by the id alone.
    (check (= (- (first results) (second results))
              (- (header-size (list (cons 5 code)) code) (header-size (list (cons 0 code)) code))))))

(deftest feature-pair-guards-reuse-stage-a-observations
  "When the guard grammar holds no exact separator within its bound, a comparison of two
features that Stage A already evaluated separates the exceptions without running anything."
  (let* ((inputs '((0 . :int) (1 . :int) (2 . :int)))
         (frame (make-frame
                 (make-schema :inputs inputs :target :int)
                 (loop for (s0 s1 a) in '((0 2 1) (1 2 1) (2 3 1) (3 4 -1) (2 4 -1) (5 2 -1) (3 2 -1))
                       for key from 0
                       collect (make-row :key key :known (list s0 s1 a)
                                         :requirement (singleton-requirement
                                                       :int (if (= (+ s0 a) s1) (+ s1 a) s1))))))
         (language (make-language :int inputs
                                  :operators (list (op :+ :int) (op :- :int) (op := :int) (op :if :int))
                                  :literals '(0 1)))
         (model (condense-heuristic frame language :work-limit 30000))
         (hits (heuristic-hit-mask frame model))
         (guard-language (default-guard-language frame language))
         (guard-bound (header-bound inputs :bool 20)))
    (check (equal (var 1 :int) (heuristic-program model)))
    (flet ((find-guard (buckets)
             (let ((ledger (make-ledger)))
               (multiple-value-bind (guard invert-p)
                   (find-sound-exception-guard frame hits guard-language guard-bound 20000 ledger
                                               :buckets buckets)
                 (values guard invert-p ledger))))
           (separates-p (guard invert-p)
             (loop for row in (frame-rows frame)
                   for hit-p in hits
                   always (eq (not (null hit-p))
                              (not (eq invert-p (result guard inputs (row-known row))))))))
      ;; The grammar alone finds at most a partial guard within 20 body bits.
      (multiple-value-bind (guard invert-p grammar-ledger) (find-guard nil)
        (check (not (and guard (separates-p guard invert-p))))
        (multiple-value-bind (guard invert-p ledger) (find-guard (heuristic-buckets model))
          (check (and guard (separates-p guard invert-p)))
          (check (<= (body-size guard inputs) *feature-guard-bits*))
          (check (< (header-bound inputs :bool 20) (description-size guard inputs)))
          ;; The comparisons cost one unit each and no evaluation.
          (let ((comparisons (- (ledger-total ledger) (ledger-total grammar-ledger))))
            (check (plusp comparisons))
            (check (= comparisons
                      (- (cdr (assoc :guard-search (ledger-counts ledger)))
                         (cdr (assoc :guard-search (ledger-counts grammar-ledger)))))))))
      ;; A feature comparison names its row values without evaluating: they are the buckets' own.
      (dolist (entry (feature-pair-predicates (heuristic-buckets model) inputs
                                              (length (frame-rows frame)) *feature-guard-bits* nil))
        (check (equal (cdr entry)
                      (mapcar (lambda (row) (result (car entry) inputs (row-known row)))
                              (frame-rows frame))))))
    ;; When the grammar does hold an exact guard, the features are not consulted.
    (let* ((easy (simple-frame :int '((0 . :int)) '(((0) 0) ((1) 1) ((2) 2) ((3) 9))))
           (easy-language (make-language :int '((0 . :int)) :operators (list (op :+ :int)) :literals '(0 3)))
           (easy-model (condense-heuristic easy easy-language :work-limit 5000))
           (easy-hits (heuristic-hit-mask easy easy-model)))
      (flet ((guard-work (buckets)
               (let ((ledger (make-ledger)))
                 (list (multiple-value-list
                        (find-sound-exception-guard easy easy-hits (default-guard-language easy easy-language)
                                                    (header-bound '((0 . :int)) :bool 20) 20000 ledger
                                                    :buckets buckets))
                       (ledger-total ledger)))))
        (check (equal (guard-work nil) (guard-work (heuristic-buckets easy-model))))))))

(deftest let-call-canonicalizes-ids-and-inlines-closed-singletons
  "Let-sharing renumbers bound variables to `0 .. k-1` in first-occurrence order so alpha-renamed
child ids produce identical ASTs, inlines closed single-use total bindings, and projects both
heterogeneous and homogeneous tuple inputs in `component-bindings`."
  (let* ((inputs '((0 . :int)))
         (x0 (var 0 :int))
         (big (term `(+ ,x0 (* (+ ,x0 1) (+ ,x0 1))))))
    ;; 1. Child ids 9 and 99 produce the exact same canonicalized `:code-eval` AST.
    (let ((from-9 (let-call (term `(+ ,(var 9 :int) ,(var 9 :int))) (list (cons 9 big))))
          (from-99 (let-call (term `(+ ,(var 99 :int) ,(var 99 :int))) (list (cons 99 big)))))
      (check (app-of-p from-9 :code-eval))
      (check (equal from-9 from-99)))
    ;; 2. A closed 1-use total binding is inlined while a 2-use binding is shared at parameter 0.
    (let* ((body (term `(+ (+ ,(var 5 :int) ,(var 5 :int)) ,(var 8 :int))))
           (shared (let-call body (list (cons 5 big) (cons 8 (lit :int 7))))))
      (check (app-of-p shared :code-eval))
      (check (= 2 (length (rest shared))))
      (check (= (result shared inputs '(3)) (+ (* 2 (+ 3 (* 4 4))) 7))))
    ;; 3. Heterogeneous and homogeneous non-empty tuple inputs project to typed components; empty tuples stay whole.
    (let* ((mixed-inputs (list (cons 0 (tuple-type :int :bool))
                               (cons 1 (tuple-type :int :int))
                               (cons 2 (tuple-type))))
           (bindings (component-bindings mixed-inputs)))
      (check (= 5 (length bindings)))
      (check (equal '(:int :bool :int :int (:tuple))
                    (mapcar (lambda (b) (expression-type (cdr b) mixed-inputs)) bindings))))))

(deftest constructor-au-handles-operator-holes-and-lowered-literals
  "Constructor-AU synthesizes `:fn` operator holes when target trees share arguments across
varying operators, and lowers constant `:code` literal holes to scalar slots when outer inputs
are first-order scalars."
  ;; 1. `:fn` operator hole: selector chooses `:+` vs `:*` inside `(<op> x 2)`.
  (let* ((scope '((0 . :int)))
         (code (code-type scope :int))
         (x (var 0 :int))
         (inputs '((0 . :int)))
         (frame (simple-frame code inputs
                              (list (list '(0) (term `(+ ,x 2)))
                                    (list '(1) (term `(* ,x 2))))))
         (language (make-language :int inputs
                                  :operators (list (op := :int) (op :if :int) (op :+ :int) (op :* :int))
                                  :literals '(0 1))))
    (let ((job (start-heuristic-synthesis frame language 180)))
      (resume-synthesis job 150000 :stop-on-first t)
      (check (synthesis-job-best job))
      (let ((expr (candidate-expression (synthesis-job-best job))))
        (check-synthesized-model expr frame)
        (check (equal (term `(+ ,x 2)) (result expr inputs '(0))))
        (check (equal (term `(* ,x 2)) (result expr inputs '(1)))))))
  ;; 2. Value-literal lowering: scalar input `a` fills literal hole in `(+ x <lit>)`.
  (let* ((scope '((0 . :int)))
         (code (code-type scope :int))
         (x (var 0 :int))
         (inputs '((0 . :int)))
         (frame (simple-frame code inputs
                              (list (list '(3) (term `(+ ,x 3)))
                                    (list '(5) (term `(+ ,x 5)))
                                    (list '(-2) (term `(+ ,x -2))))))
         (language (make-language :int inputs :operators (list (op :+ :int)) :literals '(0 1))))
    (let ((job (start-heuristic-synthesis frame language 160)))
      (resume-synthesis job 120000 :stop-on-first t)
      (check (synthesis-job-best job))
      (let ((expr (candidate-expression (synthesis-job-best job))))
        (check-synthesized-model expr frame
                                 :held-out (list (list '(11) (term `(+ ,x 11)))))))))

(deftest feature-guards-templates-and-coupled-products-stay-sound
  "Feature-pair guards obey the guard language's operators; product proposals do not pollute
decoder templates while single-difference templates anti-unify; and coupled non-Cartesian
product slots explore multiple slot candidates until a valid tuple combination joins."
  ;; 1. Guard language with `:<` offers `<` predicates; without `:<` it offers only `=`.
  (let* ((inputs '((0 . :int) (1 . :int)))
         (buckets (list (cons (var 0 :int) '(1 4 2))
                        (cons (var 1 :int) '(2 3 5))))
         (eq-only (make-language :int inputs :operators (list (op := :int)) :literals nil))
         (with-lt (make-language :int inputs :operators (list (op := :int) (op :< :int)) :literals nil)))
    (check (notany (lambda (entry) (app-of-p (car entry) :<))
                   (feature-pair-predicates buckets inputs 3 *feature-guard-bits* nil eq-only)))
    (check (some (lambda (entry) (app-of-p (car entry) :<))
                 (feature-pair-predicates buckets inputs 3 *feature-guard-bits* nil with-lt))))
  ;; 2. Product-slot proposals are skipped by `remember-decoder-template`, whereas two ordinary
  ;;    templates that differ in one place are anti-unified, at consolidation, into a template
  ;;    the library keeps.
  (with-clean-kernel-state
    (let* ((pair (tuple-type :int :int))
           (inputs '((0 . :int)))
           (prod-frame (simple-frame pair inputs '(((1) (2 3)) ((4) (5 6)))))
           (prod-lang (make-language :int inputs :operators (list (op :+ :int) (op :tuple pair)) :literals '(1 2)))
           (prod-proposals (structural-decompositions prod-frame prod-lang 60)))
      (check prod-proposals)
      (dolist (p prod-proposals)
        (check (null (remember-decoder-template p inputs))))
      (check (null (knowledge-entries-of-kind :decoder-template))))
    (let* ((inputs '((0 . :int)))
           (frame (simple-frame :int inputs '(((1) 13) ((2) 23) ((3) 33))))
           (lang (make-language :int inputs :operators (list (op :+ :int) (op :* :int)) :literals '(3 10)))
           (x (var 0 :int)) (z (var 9 :int)))
      (flet ((remember (branch)
               (remember-decoder-template
                (make-decomposition :name (list :branch branch)
                                    :decoder (term `(if (= ,x 0) ,branch 10) :int)
                                    :child-id 9 :child-type :int
                                    :bindings (identity-bindings inputs)
                                    :language lang :bound 40)
                inputs))
             (retrieved ()
               (mapcar (lambda (proposal) (second (decomposition-name proposal)))
                       (learned-decoder-decompositions frame lang 40 nil nil))))
        (let ((sources (list (remember (term `(+ ,z 1))) (remember (term `(* ,z 3))))))
          (check (every #'identity sources))
          ;; Nothing is generalised while templates are being retrieved: that is consolidation's.
          (check (= 2 (length (retrieved))))
          (let* ((added (generalize-decoder-templates *knowledge-library*))
                 (general (first added)))
            ;; The shared decoder becomes a template of its own, whose child is what differed,
            ;; linked to the two it came from.
            (check (= 1 (length added)))
            (check (eq :template-generalization (getf (knowledge-entry-metadata general) :origin)))
            (check (equal (term `(if (= ,(var 1 :int) 0) ,(var 0 :int) 10) :int)
                          (knowledge-entry-expression general)))
            (check (equal (list (cons :generalizes (mapcar #'knowledge-entry-id sources)))
                          (knowledge-edges-from general :generalizes)))
            ;; It is retrieved like any other template, once, and a second pass adds nothing.
            (check (= 1 (count (knowledge-entry-id general) (retrieved))))
            (check (= 3 (length (retrieved))))
            (check (null (generalize-decoder-templates *knowledge-library*)))
            (consolidate-knowledge-library *knowledge-library*)
            (check (= 3 (length (knowledge-entries-of-kind :decoder-template))))
            ;; It survives persistence with its origin and its sources.
            (let ((restored (deserialize-knowledge-library (serialize-knowledge-library *knowledge-library*))))
              (check (= 3 (length (knowledge-entries-of-kind :decoder-template restored))))
              (check (knowledge-edges-from (find-knowledge-entry (knowledge-entry-id general) restored)
                                           :generalizes restored)))))
        ;; A template whose child already stands where the others differ is that decoder:
        ;; generalising over it would only repeat it.
        (with-knowledge-library ((make-knowledge-library))
          (remember z)
          (remember (term `(+ ,z 1)))
          (check (null (generalize-decoder-templates *knowledge-library*)))))))
  ;; 3. Coupled non-Cartesian product join: `(member Y '((0 1) (1 0)))` rejects `(0 0)` (each
  ;;    slot's first literal) and joins once a second candidate (`1`) arrives.
  (let* ((pair (tuple-type :int :int))
         (slots '((0 . :int) (1 . :int)))
         (frame (make-frame (make-schema :inputs nil :target pair)
                            (list (make-row :key 0 :known nil
                                            :requirement (set-requirement pair '((0 1) (1 0)))))))
         (slot-lang (make-language :int nil :operators nil :literals '(0 1)))
         (empty-root-lang (make-language :int nil :operators nil :literals nil))
         (decomps (product-decompositions :coupled-pair
                                          (term `(tuple ,(var 0 :int) ,(var 1 :int)))
                                          slots nil slot-lang 20))
         (job (start-synthesis frame empty-root-lang 40 :decompositions decomps)))
    (resume-synthesis job 50000 :stop-on-first t)
    (check (synthesis-job-best job))
    (check (member (result (candidate-expression (synthesis-job-best job)))
                   '((0 1) (1 0)) :test #'equal))))

(deftest coupled-product-join-is-complete-filtered-and-bounded
  "Where a requirement couples two slots of a product, the join combines the models the slots
have pooled whichever slot reports last, a slot the coupling does not name included; a
combination that falsifies the coupling is dropped at the join and never verified at the
root; the join's work is charged once; and a product stops combining at its bound."
  (let* ((triple (tuple-type :int :int :int))
         (y (var 0 triple))
         (slots '((0 . :int) (1 . :int) (2 . :int)))
         ;; z0 + z1 = 1 couples slots 0 and 1; slot 2 stands alone and must be 2.
         (requirement (term `(if (= (+ (at ,y 0) (at ,y 1)) 1) (= (at ,y 2) 2) ,(lit :bool nil)) :bool))
         (frame (make-frame (make-schema :inputs nil :target triple)
                            (list (make-row :key 0 :known nil :requirement requirement))))
         (literals (make-language :int nil :operators nil :literals '(0 1)))
         ;; Slot 2 has to build its 2, so it is the last slot to report a model.
         (sums (make-language :int nil :operators (list (op :+ :int)) :literals '(1)))
         (root-language (make-language :int nil :operators nil :literals nil))
         (decoder (term `(tuple ,(var 0 :int) ,(var 1 :int) ,(var 2 :int)))))
    (flet ((start ()
             (start-synthesis frame root-language 60
                              :decompositions (product-decompositions
                                               :coupled decoder slots nil literals 24
                                               :slot-languages (list literals literals sums)))))
      (let ((job (check-synthesis-resumption #'start :budget 100000 :stop-on-first t)))
        (check (synthesis-job-best job))
        (check (member (result (candidate-expression (synthesis-job-best job)))
                       '((0 1 2) (1 0 2)) :test #'equal))
        ;; (0 0 2) and (1 1 2) falsify the coupling: neither reached the root.
        (check (null (remove :rejected (synthesis-job-messages job) :key #'message-claim :test-not #'eq))))))
  ;; The only model is the last of the sixteen combinations of two pools of four.
  (let* ((pair (tuple-type :int :int))
         (slots '((0 . :int) (1 . :int)))
         (frame (make-frame (make-schema :inputs nil :target pair)
                            (list (make-row :key 0 :known nil
                                            :requirement (set-requirement pair '((3 3) (9 9)))))))
         (literals (make-language :int nil :operators nil :literals '(0 1 2 3)))
         (root-language (make-language :int nil :operators nil :literals nil)))
    (flet ((run ()
             (let ((job (start-synthesis frame root-language 60
                                         :decompositions (product-decompositions
                                                          :coupled (term `(tuple ,(var 0 :int) ,(var 1 :int)))
                                                          slots nil literals 24))))
               (resume-synthesis job 100000 :stop-on-first t)
               job)))
      (let ((job (run)))
        (check (equal '(3 3) (result (candidate-expression (synthesis-job-best job)))))
        ;; Fifteen combinations were dropped at the join and one was verified.
        (check (= 16 (product-join-examined (synthesis-node-join (second (synthesis-job-nodes job))))))
        (check (null (remove :rejected (synthesis-job-messages job) :key #'message-claim :test-not #'eq)))
        (check (= 1 (length (synthesis-job-results job)))))
      (let ((*max-coupled-combinations* 4))
        (let ((job (run)))
          (check (null (synthesis-job-best job)))
          (check (synthesis-finished-p job))
          (check (= 4 (product-join-examined (synthesis-node-join (second (synthesis-job-nodes job)))))))))))

(deftest constructor-au-proposes-operator-and-expression-holes-without-losing-either
  "A product with an operator slot beside another slot is priced and solved: a slot that has
no model yet is stood in for by an operator of its signature. An operator hole whose
operators the slot could neither quote nor read off an input is not proposed, and where the
anti-unifier with operator holes and the one without differ both are, so that adding an
operator to the language does not take a solution away."
  (let* ((scope '((0 . :int)))
         (code (code-type scope :int))
         (x (var 0 :int)))
    ;; 1. `(+ x 0)` and `(* x 1)`: an operator slot and a lowered literal slot.
    (let ((binary (code-type scope '(:fn (:int :int) :int))))
      (check (operator-p (default-value-for-type binary)))
      (check (equal '(:fn (:int :int) :int) (operator-type (default-value-for-type binary)))))
    (let* ((inputs '((0 . :int)))
           (frame (simple-frame code inputs (list (list '(0) (term `(+ ,x 0)))
                                                  (list '(1) (term `(* ,x 1))))))
           (language (make-language :int inputs
                                    :operators (list (op := :int) (op :if :int) (op :+ :int) (op :* :int))
                                    :literals '(0 1)))
           (job (start-heuristic-synthesis frame language 200)))
      (check (= 2 (length (remove :constructor-au-operators
                                  (structural-decompositions frame language 200)
                                  :key (lambda (proposal) (first (decomposition-name proposal)))
                                  :test-not #'eq))))
      (resume-synthesis job 200000 :stop-on-first t)
      (check (synthesis-job-best job))
      (check-synthesized-model (candidate-expression (synthesis-job-best job)) frame))
    ;; 2. Source trees whose operators the language cannot all quote: the operator slot is
    ;;    not proposed, the expression slot is, and it is read off the input as before.
    (let* ((inputs (list (cons 0 code)))
           (examples (list (list (term `(- (+ ,x 1) 5)) (term `(* (+ ,x 1) 2)))
                           (list (term `(- (* ,x 1) 5)) (term `(* (* ,x 1) 2)))
                           (list (term `(- (- ,x 1) 5)) (term `(* (- ,x 1) 2)))))
           (frame (make-frame (make-schema :inputs inputs :target code)
                              (loop for (source target) in examples for key from 0
                                    collect (make-row :key key :known (list source)
                                                      :requirement (singleton-requirement code target))))))
      (dolist (operators (list (list (op :code-child (tuple-type code code)))
                               (list (op :code-child (tuple-type code code)) (op :* :int))))
        (let* ((language (make-language :int inputs :operators operators :literals '(0 1)))
               (job (start-heuristic-synthesis frame language 220)))
          (check (equal '(:constructor-au)
                        (remove-duplicates
                         (mapcar (lambda (proposal) (first (decomposition-name proposal)))
                                 (structural-decompositions frame language 220)))))
          (resume-synthesis job 200000 :stop-on-first t)
          (check (synthesis-job-best job))
          (check-synthesized-model (candidate-expression (synthesis-job-best job)) frame
                                   :require-total-p nil))))))

(deftest repeated-subterms-are-shared-and-tuple-memberships-fold-by-place
  "A composed model computes a subterm it repeats once, under a let, when that is smaller,
though no single subterm repays the let; and a membership of a tuple in a set that is the
product of its places folds into one membership per place."
  (let* ((pair (tuple-type :int :int))
         (inputs (list (cons 0 pair) (cons 1 :int)))
         (x0 (var 0 pair)) (x1 (var 1 :int)) (z (var 9 :int))
         (second-part (term `(at ,x0 1)))
         (decoder (term `(tuple ,z (if (= ,z ,second-part) (+ ,second-part ,x1) ,second-part)) pair))
         (child (term `(+ (at ,x0 0) ,x1)))
         (inline (instantiate decoder (list (cons 9 child)) :var))
         (model (compose-model decoder 9 child (identity-bindings inputs) nil inputs)))
    (check (app-of-p model :code-eval))
    (check (< (description-size model inputs) (description-size inline inputs)))
    (dolist (values '(((1 2) 1) ((0 5) 3) ((-4 -4) 0)))
      (check (equal (result inline inputs values) (result model inputs values))))
    ;; Each subterm alone costs more under a let than it saves.
    (let ((width (reference-width inputs inline)))
      (dolist (subterm (list child second-part))
        (let ((alone (let-call (map-ast (lambda (node meta)
                                          (declare (ignore meta))
                                          (and (equal node subterm) (var 20 (ast-type node))))
                                        inline :root-first t)
                               (acons 20 subterm (identity-bindings inputs)))))
          (check (> (scoped-bits alone width) (scoped-bits inline width)))))))
  (let* ((a (var 0 :int)) (b (var 1 :int))
         (tuple (term `(tuple ,a ,b))))
    (flet ((folded (set) (fold-constants (term `(member ,tuple ',set))))
           (same-set-p (expression set)
             ;; EXPRESSION accepts exactly the pairs of SET.
             (loop for x from -1 to 6
                   always (loop for y from -1 to 6
                                always (eq (and (member (list x y) set :test #'equal) t)
                                           (result expression '((0 . :int) (1 . :int)) (list x y)))))))
      (dolist (set '(((0 4) (0 5) (1 4) (1 5)) ((3 4) (3 5) (3 4)) ((2 2))))
        (let ((expression (folded set)))
          (check (same-set-p expression set))
          ;; One requirement on each place: the tuple is gone.
          (check (not (expression-calls-operator-p expression :tuple)))
          (check (equal '((0) (1)) (mapcar #'free-vars (extract-conjuncts expression))))))
      ;; A set that ties its places together is left whole.
      (let ((expression (folded '((0 1) (1 0)))))
        (check (same-set-p expression '((0 1) (1 0))))
        (check (app-of-p expression :member))
        (check (equal tuple (second expression)))))))

