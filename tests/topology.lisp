(in-package #:lisploop)

;;; ===========================================================================
;;; Plan 8 / P8.3: symbolic equation unwinding, hard frame edges, induced row order,
;;; and availability preorders
;;; ===========================================================================

(deftest symbolic-unwinding-turns-a-conservation-into-a-closed-form
  "A conserved quantity that is sensitive to the target is unwound by unique solvers, applied
to expressions rather than to row values, into the target's closed form; one that only
cancels the target is refused, and one without unique solvers falls back to solving each row."
  (with-clean-kernel-state
    (let* ((library (kernel-propagator-library :int))
           (inputs '((0 . :int) (1 . :int) (2 . :int)))
           (j (var 0 :int)) (last (var 1 :int)) (index (var 2 :int))
           ;; Records (j, n-1, I) of reversing '(10 20 30) and '(40 50): I + j - (n-1) = 0.
           (reversal (probe-frame :int inputs '((0 2 2) (1 2 1) (2 2 0) (0 1 1) (1 1 0))))
           (conserved (term `(- (+ ,index ,j) ,last))))
      ;; 1. The closed form of the index, directly from the equation.
      (multiple-value-bind (solution guards certified-p)
          (solve-equality-symbolically conserved (lit :int 0) 2 :library library)
        (check solution)
        (check (null guards))
        ;; Integer rules are conjectures with unique witnesses: the form must be replayed.
        (check (not certified-p))
        (check (not (member 2 (free-vars solution))))
        (dolist (row (frame-rows reversal))
          (destructuring-bind (j-value last-value index-value) (row-known row)
            (check (= index-value (result solution inputs (list j-value last-value 0))))))
        ;; Held out: position 3 of a sequence of 10 reverses to position 6.
        (check (= 6 (result solution inputs '(3 9 0)))))
      (multiple-value-bind (model kind) (orient-conserved-quantity reversal 2 conserved 0 :library library)
        (check (eq :symbolic kind))
        (check (= 4 (result model inputs '(5 9 0)))))
      ;; 2. Numeric inversion of the same equation only restates each row's own value.
      (let* ((pulled (conserved-quantity-frame reversal 2 conserved 0))
             (narrowed (nth-value 1 (frame-conflict-p
                                     (propagation-frame (propagate-requirements pulled library (make-ledger)))))))
        (check (equal '(2 1 0 1 0) (mapcar #'row-singleton-value (frame-rows narrowed)))))
      ;; 3. A quantity that mentions the target only to cancel it is conserved and says nothing.
      (let ((vacuous (term `(- ,index ,index))))
        (check (not (target-sensitive-p vacuous 2 reversal)))
        (check (target-sensitive-p conserved 2 reversal))
        (check (not (target-sensitive-p (term `(- ,j ,j)) 2 reversal)))
        (check (null (orient-conserved-quantity reversal 2 vacuous 0 :library library))))
      ;; 4. The target on both sides of an operator, or under one with no unique inverse, is not unwound.
      (check (null (solve-equality-symbolically (term `(+ ,index ,index)) (lit :int 4) 2 :library library)))
      (check (null (solve-equality-symbolically (term `(/ ,index ,last)) (lit :int 1) 2 :library library)))
      (let ((halves (probe-frame :int inputs '((0 2 4) (0 2 5) (0 3 6) (0 3 9)))))
        (multiple-value-bind (frame kind)
            (orient-conserved-quantity halves 2 (term `(- (/ ,index ,last) 2)) 0 :library library)
          (check (eq :numeric kind))
          (check (frame-p frame))))
      ;; 5. A closed form that the rows refute is not returned: here the constant is wrong.
      (check (eq :numeric (nth-value 1 (orient-conserved-quantity reversal 2 conserved 1 :library library)))))
    ;; 6. Over a finite field the rules are certified, and their guards come with the solution.
    (let* ((field (gf 5))
           (library (kernel-propagator-library field))
           (x (var 0 field)) (y (var 1 field)))
      (multiple-value-bind (solution guards certified-p)
          (solve-equality-symbolically (term `(+ (* ,x ,y) ,x)) (lit field 3) 1 :library library)
        (check certified-p)
        (check (= 1 (length guards)))
        (let ((scope (list (cons 0 field) (cons 1 field))))
          (dolist (x-value '(1 2 3 4))
            (let ((y-value (result solution scope (list x-value 0))))
              (check (= 3 (mod (+ (* x-value y-value) x-value) 5)))
              (check (eq t (result (first guards) scope (list x-value 0))))))
          (check (null (result (first guards) scope '(0 0)))))))))

(deftest hard-frame-edges-are-enforced-by-exact-search
  "An :equal edge makes two rows share a value and a :distinct edge makes them differ. Exact
search rejects a candidate that every row accepts when it breaks an edge, in whatever order
the rows are stored, and a composed candidate is held to the root's edges."
  (let* ((inputs '((0 . :int)))
         (rows (list (make-row :key :a :known '(1) :requirement (set-requirement :int '(1 5)))
                     (make-row :key :b :known '(2) :requirement (set-requirement :int '(2 5)))
                     (make-row :key :c :known '(3) :requirement (set-requirement :int '(3 5 6)))))
         (schema (make-schema :inputs inputs :target :int))
         (language (make-language :int inputs :operators nil :literals '(5 6)))
         (bound (header-bound inputs :int 12))
         (free (make-frame schema rows))
         (tied (make-frame schema rows :edges '((:equal :a :b) (:equal :b :c))))
         (split (make-frame schema rows :edges '((:distinct :a :c)))))
    (flet ((models (frame)
             (let ((job (start-search frame language)))
               (resume-search job bound 100000)
               (values (mapcar #'candidate-expression (reverse (search-job-results job)))
                       (and (search-job-best job) (candidate-expression (search-job-best job)))
                       job))))
      ;; Row by row the identity is the smallest model; tied rows must agree, so it is not one.
      (check (equal (var 0 :int) (nth-value 1 (models free))))
      (check (equal (list (lit :int 5)) (models tied)))
      ;; Rows that must differ exclude the constant instead.
      (check (equal (list (var 0 :int)) (models split)))
      (dolist (permutation '((0 1 2) (2 0 1) (1 2 0)))
        (check (equal (list (lit :int 5)) (models (shuffle-frame-rows tied permutation)))))
      (check-search-resumption (lambda () (start-search tied language)) bound :exhaustive-p t)
      ;; A rejection for an edge is reported like any other counterexample.
      (let ((job (start-search tied language :diagnostics t)))
        (resume-search job bound 100000)
        (check (find-if (lambda (message)
                          (and (eq :counterexample (message-claim message))
                               (getf (message-evidence message) :edge)))
                        (search-job-messages job))))
      ;; An edge to a row a candidate leaves unresolved is not judged.
      (let ((partial (make-frame schema (list (first rows)
                                              (make-row :key :b :known '(:unresolved)
                                                        :requirement (set-requirement :int '(2 5)))
                                              (third rows))
                                 :edges '((:equal :a :b)))))
        (check (find (var 0 :int) (models partial) :test #'equal))))
    ;; Synthesis verifies every composed candidate against the root's edges.
    (let* ((proposal (make-decomposition :name :offset :decoder (term `(+ ,(var 0 :int) ,(var 9 :int)))
                                         :child-id 9 :child-type :int :bindings nil
                                         :language (make-language :int nil :operators nil :literals '(0))
                                         :bound (header-bound nil :int 8)))
           (job (start-synthesis tied language bound :decompositions (list proposal))))
      (resume-synthesis job 100000)
      (check (equal (lit :int 5) (candidate-expression (synthesis-job-best job))))
      (check (notany (lambda (candidate) (equal (term `(+ ,(var 0 :int) 0)) (candidate-expression candidate)))
                     (synthesis-job-results job))))
    ;; Edges relate target values: only the identity decoder hands them to a child.
    (check (frame-edges (snapshot-frame tied)))
    (check (frame-edges (pullback-frame tied (var 9 :int) 9 :int (identity-bindings inputs))))
    (check (null (frame-edges (pullback-frame tied (term `(+ ,(var 0 :int) ,(var 9 :int))) 9 :int
                                              (identity-bindings inputs)))))
    (check (not (equal (child-scope-signature free language) (child-scope-signature tied language))))
    (raises (make-frame schema rows :edges '((:near :a :b))))))

(deftest availability-preorder-withholds-later-inputs
  "A schema may order its columns. A model of the target reads only the columns before it,
whatever they are called; the orientation is explicit and search refuses a frame without it."
  (dolist (ids '((0 1) (7 3)))
    (destructuring-bind (early late) ids
      (let* ((inputs (list (cons early :int) (cons late :int)))
             ;; The later column happens to equal the target: read, it would be the whole model.
             (schema (make-schema :inputs inputs :target :int
                                  :availability (list (cons early 0) (cons late 1))
                                  :target-availability 1))
             (frame (make-frame schema
                                (loop for (x y) in '((1 2) (5 6) (9 10)) for key from 0
                                      collect (make-row :key key :known (list x y)
                                                        :requirement (singleton-requirement :int y)))))
             (oriented (orient-available frame))
             (oriented-inputs (schema-inputs (frame-schema oriented)))
             (language (make-language :int inputs :operators (list (op :+ :int)) :literals '(1)))
             (oriented-language (derive-language language :inputs oriented-inputs)))
        (check (equal (list (cons early :int)) (available-inputs schema)))
        (check (equal (list (cons early :int)) oriented-inputs))
        (check (equal '((1) (5) (9)) (mapcar #'row-known (frame-rows oriented))))
        (raises (start-search frame language))
        (raises (start-synthesis frame language 60))
        (let ((job (start-search oriented oriented-language)))
          (resume-search job (header-bound oriented-inputs :int 16) 100000)
          (check (= 13 (result (candidate-expression (search-job-best job)) oriented-inputs '(12)))))
        ;; An invariant may still be sought across every column.
        (check (make-observation-scope frame language))
        ;; An equal index is not earlier; a column without one is always available.
        (check (null (available-inputs (make-schema :inputs inputs :target :int
                                                    :availability (list (cons early 1) (cons late 1))
                                                    :target-availability 1))))
        (check (equal inputs (available-inputs (make-schema :inputs inputs :target :int
                                                            :target-availability 0))))
        ;; The order belongs to this target: a child with another target starts unordered.
        (check (null (schema-target-availability
                      (frame-schema (pullback-frame oriented (term `(if ,(var 9 :bool) ,(var early :int) 0) :int)
                                                    9 :bool (identity-bindings oriented-inputs))))))))))

(deftest induced-row-order-is-found-and-does-not-depend-on-storage
  "A key along which the target varies little is induced from the rows' own values; the same
key and chain come back however the rows are stored, and a table without such a key gets none."
  (with-clean-kernel-state
    (let* ((inputs '((0 . :int) (1 . :int)))
           (schema (make-schema :inputs inputs :target :int))
           ;; (time, noise) -> a target that drifts with time; stored out of order.
           (table '((5 17 1061) (1 40 1013) (8 3 1096) (2 29 1024) (7 11 1085) (3 8 1035) (6 35 1070) (4 22 1049)))
           (noise '((5 17 91) (1 40 5120) (8 3 7) (2 29 33000) (7 11 640) (3 8 12) (6 35 2900) (4 22 77000)))
           (frame (make-frame schema
                              (loop for (time other target) in table for key from 0
                                    collect (make-row :key (list :row key) :known (list time other)
                                                      :requirement (singleton-requirement :int target)))))
           (control (make-frame schema
                                (loop for (time other target) in noise for key from 0
                                      collect (make-row :key (list :row key) :known (list time other)
                                                        :requirement (singleton-requirement :int target))))))
      (multiple-value-bind (key edges chain-bits baseline-bits) (induce-row-order frame)
        (check (equal (var 0 :int) key))
        (check (< chain-bits baseline-bits))
        (check (= 7 (count :persistence edges :key #'first)))
        (check (equal '((:distinct (:row 1) (:row 2))) (remove :persistence edges :key #'first)))
        (dolist (permutation '((7 6 5 4 3 2 1 0) (3 0 6 1 7 4 2 5) (1 3 5 7 0 2 4 6)))
          (check (equal (list key edges chain-bits baseline-bits)
                        (multiple-value-list (induce-row-order (shuffle-frame-rows frame permutation))))))
        ;; The rows are stored along the chain, and the key is remembered for later.
        (multiple-value-bind (ordered ordered-key) (with-induced-row-order frame :library *knowledge-library*)
          (check (equal key ordered-key))
          (check (equal '(1 2 3 4 5 6 7 8) (mapcar (lambda (row) (first (row-known row))) (frame-rows ordered))))
          (check (equal edges (frame-edges ordered)))
          (check (null (hard-edges frame)))
          (check (equal (list key) (mapcar #'knowledge-entry-expression
                                           (knowledge-entries-of-kind :locality-key))))
          ;; Its :distinct edge is hard: the ordered frame refuses a constant model.
          (let ((job (start-search ordered (make-language :int inputs :operators nil :literals '(1061)))))
            (resume-search job (header-bound inputs :int 30) 100000)
            (check (null (search-job-results job))))))
      ;; A feature Stage A evaluated can be the key; here twice the time orders as time does, at a higher price.
      (let* ((doubled (term `(+ ,(var 0 :int) ,(var 0 :int))))
             (buckets (list (cons doubled (mapcar (lambda (row) (* 2 (first (row-known row)))) (frame-rows frame))))))
        (check (equal (var 0 :int) (induce-row-order frame :buckets buckets))))
      ;; No key explains the control: nothing is induced, and the frame is returned as it is.
      (check (null (induce-row-order control)))
      (check (eq control (with-induced-row-order control))))))

(deftest field-solvers-that-read-alike-lift-to-integer-conjectures
  "Solvers of one operator and position over two prime fields, alike once their field is
erased, give the integers the same solver as a conjecture: it is replayed, it never drops
the original requirement, and consolidating again adds nothing (plan 8, P8.4)."
  (with-clean-kernel-state
    (dolist (prime '(5 7))
      (dolist (name '(:+ :/))
        (register-kernel-arithmetic-solver (gf prime) name 0)))
    ;; One field alone lifts nothing.
    (register-kernel-arithmetic-solver (gf 5) :- 1)
    (let ((before (length (knowledge-library-entries *knowledge-library*)))
          (lifted (lift-field-solvers *knowledge-library*)))
      (check (= 2 (length lifted)))
      (check (= (+ 2 before) (length (knowledge-library-entries *knowledge-library*))))
      (dolist (entry lifted)
        (check (eq :int (knowledge-entry-domain entry)))
        (check (eq :conjecture (knowledge-entry-status entry)))
        (check (not (knowledge-evidence-current-p entry :witness)))
        (check (not (knowledge-evidence-current-p entry :uniqueness)))
        (check (knowledge-edges-from entry :lifted-from)))
      (check (null (lift-field-solvers *knowledge-library*)))
      (consolidate-knowledge-library *knowledge-library*)
      (check (= (+ 2 before) (length (knowledge-library-entries *knowledge-library*))))
      ;; The lifted rules narrow integer requirements by replay, and keep the fallback.
      (let* ((z (var 0 :int))
             (frame (make-frame (make-schema :inputs nil :target :int)
                                (list (make-row :key :sum :known nil :requirement (term `(= (+ ,z 4) 10)))
                                      (make-row :key :quotient :known nil :requirement (term `(= (/ ,z 2) 3))))))
             (propagation (propagate-requirements frame *knowledge-library* (make-ledger))))
        (check (= 2 (propagation-suggested propagation)))
        (check (= 2 (propagation-ambiguous propagation)))
        (check (propagation-fallback propagation))
        (check (equal '(6 6) (mapcar #'row-singleton-value (frame-rows (propagation-frame propagation)))))
        ;; 7 / 2 is 3 as well: the fallback is what keeps it.
        (check (accepts (row-requirement (second (frame-rows (propagation-fallback propagation)))) 7))))
    ;; Witnesses that differ once the field is erased are not lifted.
    (with-knowledge-library ((make-knowledge-library))
      (dolist (prime '(5 7))
        (let ((field (gf prime)))
          (register-knowledge-solver :+ :domain field :position 0
                                        :witness (term `(+ (- ,(var 1 field) ,(var 0 field)) ,(1- prime)) field)
                                        :unique-p nil)))
      (check (null (lift-field-solvers *knowledge-library*))))))

