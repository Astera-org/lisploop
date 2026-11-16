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
         (step-type (code-type (list (cons 0 pair) (cons 1 :int)) pair))
         (inputs (list (cons 0 actions-type) (cons 1 pair))))
    (define-function :scan-pair (list (cons 0 actions-type) (cons 1 pair) (cons 2 step-type)) states-type
      (lambda (self)
        (let* ((actions (var 0 actions-type)) (state (var 1 pair)) (step (var 2 step-type))
               (next (term `(code-eval ,step ,state (at ,actions 0)))))
          (term `(if (= ,actions ()) () (cons ,next (,self (tail ,actions) ,next ,step)))
                states-type))))
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
                                          :library-functions '(:scan-pair)
                                          :heuristic-budget 16000)))
        (multiple-value-bind (batch)
            (check-synthesis-resumption #'start :budget 1000000 :stop-on-first t)
          (let ((expression (candidate-expression (synthesis-job-best batch))))
            (check-synthesized-model expression frame :held-out held-out :must-call-ops '(:scan-pair))
            ;; The winning candidate was joined at the lifted node from its two slots.
            (check (some (lambda (node)
                           (and (synthesis-node-join node) (slot-satisfied-p node)))
                         (synthesis-job-nodes batch)))
            (check (expression-calls-operator-p expression :code-eval))))
        ;; Without structural proposals the same budget does not reach the step.
        (let ((job (start-heuristic-synthesis frame language 260
                                              :library-functions '(:scan-pair)
                                              :heuristic-budget 16000
                                              :structural-proposals-p nil)))
          (resume-synthesis job 1000000 :stop-on-first t)
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
