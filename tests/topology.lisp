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
  "A schema may preorder its columns. A model of the target reads only the columns strictly
before it (`tau(X_i) < tau(Y)`), whatever they are called; a column at the target's own rank,
later, or incomparable is withheld, and search refuses an unoriented frame."
  (dolist (ids '((0 1) (7 3)))
    (destructuring-bind (early late) ids
      (let* ((inputs (list (cons early :int) (cons late :int)))
             ;; The other column shares the target's rank and happens to equal the target:
             ;; read, it would be the whole model.
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
        (raises (start-heuristic-search frame language))
        (let ((job (start-search oriented oriented-language)))
          (resume-search job (header-bound oriented-inputs :int 16) 100000)
          (check (= 13 (result (candidate-expression (search-job-best job)) oriented-inputs '(12)))))
        ;; An invariant may still be sought across every column.
        (check (make-observation-scope frame language))
        ;; An equal index is not earlier; a column without one precedes every ranked target.
        (check (null (available-inputs (make-schema :inputs inputs :target :int
                                                    :availability (list (cons early 1) (cons late 1))
                                                    :target-availability 1))))
        (check (equal inputs (available-inputs (make-schema :inputs inputs :target :int
                                                            :target-availability 0))))
        (check (null (available-inputs (make-schema :inputs inputs :target :int
                                                    :target-availability :bottom))))
        ;; Symbolic DAG preorders withhold columns at the target's own rank, strictly later
        ;; ones, and incomparable ones.
        (let* ((dag-inputs (list (cons early :int) (cons late :int) (cons 98 :int) (cons 99 :int)))
               (dag-schema (make-schema :inputs dag-inputs :target :int
                                        :availability (list :ranks (list (cons early :past)
                                                                         (cons late :future)
                                                                         (cons 98 :present)
                                                                         (cons 99 :side-branch))
                                                            :target :present
                                                            :le '((:past . :present)
                                                                  (:present . :future))))))
          (check (equal (list (cons early :int)) (available-inputs dag-schema)))
          (check (expression-respects-availability-p (var early :int) dag-schema))
          (check (not (expression-respects-availability-p (var 98 :int) dag-schema))))
        ;; Strict precedence: reflexivity and cycles of the order do not count.
        (check (rank-lt-p 0 1))
        (check (not (rank-lt-p 1 1)))
        (check (rank-lt-p :bottom 0))
        (check (not (rank-lt-p :bottom :bottom)))
        (check (rank-lt-p :a :c '((:a . :b) (:b . :c))))
        (check (not (rank-lt-p :a :b '((:a . :b) (:b . :a)))))
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

(deftest symbolic-unwinding-respects-availability-and-multi-probe-sensitivity
  "Symbolic unwinding auto-selects the maximal-availability column when `:target-id :auto` is
requested, refuses closed forms that read unavailable later columns, detects target sensitivity
across synthetic probes when sample rows collide, and preserves frame topology across propagation
and row shuffles."
  (with-clean-kernel-state
    (let* ((library (kernel-propagator-library :int))
           (inputs '((0 . :int) (1 . :int) (2 . :int)))
           (x0 (var 0 :int)) (x1 (var 1 :int)) (x2 (var 2 :int)))
      ;; 1. `:target-id :auto` unwinds the unique maximal-availability column (`x2` at rank 2).
      (let* ((schema (make-schema :inputs inputs :target :int
                                  :availability '((0 . 0) (1 . 1) (2 . 2))))
             (rows (loop for (a b c) in '((1 3 4) (2 5 7) (-1 4 3)) for k from 0
                         collect (make-row :key k :known (list a b c) :requirement (lit :bool t))))
             (frame (make-frame schema rows))
             (conserved (term `(- ,x2 (+ ,x0 ,x1)))))
        (multiple-value-bind (model kind)
            (orient-conserved-quantity frame :auto conserved 0 :library library)
          (check (eq :symbolic kind))
          (check (= 15 (result model inputs '(6 9 0))))))
      ;; 2. Unwinding `x1` (rank 1) from `(- (+ x1 x2) 10) = 0` when `x2` has rank 2 > 1 refuses
      ;;    the unavailable `:symbolic` closed form `(- 10 x2)` and strips `x2` from `:numeric`.
      (let* ((schema (make-schema :inputs inputs :target :int
                                  :availability '((0 . 0) (1 . 1) (2 . 2))))
             (rows (loop for (a b c) in '((0 3 7) (1 4 6) (2 8 2)) for k from 0
                         collect (make-row :key k :known (list a b c) :requirement (lit :bool t))))
             (frame (make-frame schema rows)))
        (multiple-value-bind (fallback kind)
            (orient-conserved-quantity frame 1 (term `(- (+ ,x1 ,x2) 10)) 0 :library library)
          (check (eq :numeric kind))
          (check (equal '((0 . :int)) (schema-inputs (frame-schema fallback)))))))
    ;; 3. Multi-probe sensitivity: `1^2 = 4^2 = 1 (mod 5)` collides on rows `(1, 1)` and `(2, 4)`,
    ;;    yet synthetic probes still detect sensitivity of `(* X (* Y Y))` to `Y`.
    (let* ((field (gf 5))
           (f-inputs (list (cons 0 field) (cons 1 field)))
           (fx (var 0 field)) (fy (var 1 field))
           (colliding (probe-frame field f-inputs '((1 1) (2 4)))))
      (check (target-sensitive-p (term `(* ,fx (* ,fy ,fy)) field) 1 colliding)))
    ;; 4. `propagate-requirements` preserves `frame-edges` and `child-scope-signature` is shuffle-invariant.
    (let* ((inputs '((0 . :int)))
           (z (var 0 :int))
           (rows (list (make-row :key :a :known '(1) :requirement (term `(= (+ ,z 1) 6)))
                       (make-row :key :b :known '(2) :requirement (term `(= (+ ,z 2) 7)))
                       (make-row :key :c :known '(3) :requirement (term `(= (+ ,z 3) 9)))))
           (frame (make-frame (make-schema :inputs inputs :target :int) rows
                              :pairs '((:a :b)) :anchors '(:b :c)
                              :edges '((:equal :a :b) (:persistence :b :c))))
           (lang (make-language :int inputs :operators (list (op :+ :int)) :literals '(0 1)))
           (prop (propagate-requirements frame (kernel-propagator-library :int) (make-ledger))))
      (check (equal (frame-edges frame) (frame-edges (propagation-frame prop))))
      (check (equal (child-scope-signature frame lang)
                    (child-scope-signature (shuffle-frame-rows frame '(2 0 1)) lang)))
      ;; The signature names rows by their place, not their key: the same frame under other
      ;; keys has the same one. A pair's direction is priced, so reversing it is another scope.
      (flet ((relinked (keys pairs)
               (destructuring-bind (a b c) keys
                 (make-frame (make-schema :inputs inputs :target :int)
                             (loop for row in rows for key in keys
                                   collect (make-row :key key :known (row-known row)
                                                     :requirement (row-requirement row)))
                             :pairs pairs :anchors (list b c)
                             :edges (list (list :equal a b) (list :persistence b c))))))
        (check (equal (child-scope-signature frame lang)
                      (child-scope-signature (relinked '(:p :q :r) '((:p :q))) lang)))
        (check (equal (child-scope-signature frame lang)
                      (child-scope-signature (relinked '((:row 2) (:row 0) (:row 1)) '(((:row 2) (:row 0)))) lang)))
        (check (not (equal (child-scope-signature frame lang)
                           (child-scope-signature (relinked '(:a :b :c) '((:b :a))) lang)))))
      ;; A pair is a two-element list of row keys.
      (raises (make-frame (make-schema :inputs inputs :target :int) rows :pairs '((:a . :b)))))))

(deftest truncating-integer-division-does-not-lift-from-prime-fields
  "Multiplication's prime-field inverse `(/ y c)` does not replay over the integers because `/`
truncates (`(/ 7 2) = 3` while `3 * 2 /= 7`), so `lift-field-solvers` rejects `:*` while keeping
sound lifts; archived field solvers are ignored as well."
  (with-clean-kernel-state
    (dolist (prime '(5 7))
      (register-kernel-arithmetic-solver (gf prime) :* 0)
      (register-kernel-arithmetic-solver (gf prime) :+ 0))
    (let ((lifted (lift-field-solvers *knowledge-library*)))
      (check (= 1 (length lifted)))
      (check (eq :+ (getf (knowledge-entry-metadata (first lifted)) :operator-name)))))
  (with-clean-kernel-state
    (dolist (prime '(5 7))
      (let ((entry (register-kernel-arithmetic-solver (gf prime) :+ 0)))
        (when (= prime 7)
          (setf (getf (knowledge-entry-metadata entry) :active-p) nil))))
    (check (null (lift-field-solvers *knowledge-library*)))))

(deftest availability-orders-compose-and-reach-their-first-column
  "Real and symbolic ranks order one another through the pairs that relate them, in either
direction; a malformed availability is refused, not read as none; and a target that nothing
precedes is oriented onto no inputs at all, where its model is a constant."
  ;; 1. A path may pass from a real rank to a greater one and along an order pair, in any order.
  (check (rank-le-p 0 :present '((1 . :present))))
  (check (rank-lt-p 0 :present '((1 . :present))))
  (check (rank-le-p :a :b '((:a . 1) (2 . :b))))
  (check (not (rank-le-p :b :a '((:a . 1) (2 . :b)))))
  (check (not (rank-le-p 2 :present '((1 . :present)))))
  (let* ((inputs '((0 . :int) (1 . :int) (2 . :int)))
         (schema (make-schema :inputs inputs :target :int
                              :availability (list :ranks '((0 . 0) (1 . 1) (2 . :later))
                                                  :target :present
                                                  :le '((1 . :present) (:present . :later))))))
    (check (equal '((0 . :int) (1 . :int)) (available-inputs schema)))
    (check (eql 2 (schema-maximal-availability-id schema)))
    ;; 2. Neither a misspelt key nor an input ranked twice passes for an availability.
    (raises (make-schema :inputs inputs :target :int :availability '(:rank ((0 . 1)) :target 1)))
    (raises (make-schema :inputs inputs :target :int :availability '((0 . 1) (0 . 2)))))
  ;; 3. Every input is later than the target: the oriented frame has none, and is searched.
  (let* ((inputs '((0 . :int) (1 . :int)))
         (frame (make-frame (make-schema :inputs inputs :target :int
                                         :availability '((0 . 1) (1 . 2)) :target-availability 0)
                            (loop for (x y) in '((1 2) (5 6) (9 10)) for key from 0
                                  collect (make-row :key key :known (list x y)
                                                    :requirement (singleton-requirement :int 7)))))
         (oriented (orient-available frame))
         (constants (make-language :int nil :operators nil :literals '(7))))
    (check (null (schema-inputs (frame-schema oriented))))
    (check (equal '(nil nil nil) (mapcar #'row-known (frame-rows oriented))))
    (check (eq oriented (orient-available oriented)))
    (let ((job (start-search oriented constants)))
      (resume-search job (header-bound nil :int 16) 10000)
      (check (= 7 (result (candidate-expression (search-job-best job))))))
    ;; 4. A column the schema does not rank is at the bottom of an order that ranks others:
    ;;    predicting it from the columns that come later is refused, however the frame's own
    ;;    target is ranked.
    (with-clean-kernel-state
      (let* ((library (kernel-propagator-library :int))
             (inputs '((0 . :int) (1 . :int) (2 . :int)))
             (rows (loop for (a b c) in '((4 1 3) (7 2 5) (3 4 -1)) for key from 0
                         collect (make-row :key key :known (list a b c) :requirement (lit :bool t))))
             (conserved (term `(- ,(var 0 :int) (+ ,(var 1 :int) ,(var 2 :int))))))
        (dolist (target-rank '(nil 1 9))
          (let ((frame (make-frame (make-schema :inputs inputs :target :int
                                                :availability '((1 . 1) (2 . 2))
                                                :target-availability target-rank)
                                   rows)))
            (multiple-value-bind (oriented kind) (orient-conserved-quantity frame 0 conserved 0 :library library)
              (check (eq :numeric kind))
              (check (null (schema-inputs (frame-schema oriented)))))))))))

(deftest a-claim-of-uniqueness-authorises-nothing-without-evidence
  "A solver's :unique-p is a claim. Symbolic unwinding uses a rule only when the uniqueness
has evidence, of whatever grade; a certification that refutes the claim withdraws it; a
solver lifted from prime fields carries the record of the samples it survived, which lets
it unwind an equation as a conjecture and never drops a requirement; and lifting neither
fails on a solver of another type nor passes one the samples refute."
  (with-clean-kernel-state
    (let* ((k (var 0 :int)) (c (var 1 :int))
           (y (var 0 :int)) (x (var 1 :int))
           (equation (term `(+ ,y ,x)))
           (claimed (register-knowledge-solver :+ :domain :int :position 0
                                               :witness (term `(- ,c ,k)) :unique-p t)))
      (flet ((solve ()
               (clrhash (knowledge-library-propagator-libraries *knowledge-library*))
               (multiple-value-list
                (solve-equality-symbolically equation (lit :int 3) 0 :library *knowledge-library*))))
        ;; 1. The flag alone: no evidence, no unwinding.
        (check (getf (knowledge-entry-metadata claimed) :unique-p))
        (check (null (knowledge-entry-certificate claimed)))
        (check (null (first (solve))))
        ;; 2. A sample test of the uniqueness, once recorded, licenses a conjecture.
        (attest-knowledge-entry claimed :sampled '(:uniqueness))
        (check (knowledge-evidence-tested-p claimed :uniqueness))
        (check (not (knowledge-evidence-current-p claimed :uniqueness)))
        (destructuring-bind (solution guards certified-p) (solve)
          (check (= 1 (result solution '((0 . :int) (1 . :int)) '(0 2))))
          (check (null guards))
          (check (not certified-p)))
        ;; 3. The record is of the statement tested: change the statement and it lapses.
        (setf (knowledge-entry-expression claimed) (term `(+ ,c ,k)))
        (check (not (knowledge-evidence-tested-p claimed :uniqueness)))
        (check (null (first (solve)))))))
  ;; 4. A certification that finds a second solution withdraws the claim and keeps the witness.
  (with-clean-kernel-state
    (let* ((field (gf 5))
           (k (var 0 field)) (c (var 1 field))
           (entry (register-knowledge-solver
                   :* :domain field :position 0
                   ;; At k = 0 and c = 0 every value solves (* z 0) = 0.
                   :witness (term `(if (= ,k 0) ,(lit field 0) (/ ,c ,k)) field)
                   :guard (term `(if (= ,k 0) (= ,c 0) ,(lit :bool t)))
                   :certified-p t :unique-p t)))
      (check (not (getf (knowledge-entry-metadata entry) :unique-p)))
      (check (knowledge-evidence-current-p entry :witness))
      (check (not (knowledge-evidence-tested-p entry :uniqueness)))
      (check (null (solve-equality-symbolically (term `(* ,(var 0 field) ,(var 1 field))) (lit field 0) 0
                                                :library *knowledge-library*)))))
  ;; 5. What lifting records, and what the record is good for.
  (with-clean-kernel-state
    (dolist (prime '(5 7))
      (register-kernel-arithmetic-solver (gf prime) :+ 0)
      (register-kernel-arithmetic-solver (gf prime) :/ 0))
    (let* ((lifted (lift-field-solvers *knowledge-library*))
           (sum (find :+ lifted :key (lambda (entry) (getf (knowledge-entry-metadata entry) :operator-name))))
           (quotient (find :/ lifted :key (lambda (entry) (getf (knowledge-entry-metadata entry) :operator-name)))))
      (check (= 2 (length lifted)))
      (dolist (entry lifted)
        (check (eq :sampled (getf (knowledge-entry-certificate entry) :method)))
        (check (plusp (getf (knowledge-entry-certificate entry) :active)))
        (check (knowledge-evidence-tested-p entry :witness))
        (check (not (knowledge-evidence-current-p entry :witness))))
      ;; Addition has one solution at every offset tried; (z / k) = c has several.
      (check (getf (knowledge-entry-metadata sum) :unique-p))
      (check (knowledge-evidence-tested-p sum :uniqueness))
      (check (not (getf (knowledge-entry-metadata quotient) :unique-p)))
      (check (not (knowledge-evidence-tested-p quotient :uniqueness)))
      (let ((y (var 0 :int)) (x (var 1 :int)))
        (multiple-value-bind (solution guards certified-p)
            (solve-equality-symbolically (term `(+ ,y ,x)) (lit :int 10) 0 :library *knowledge-library*)
          (check (= 6 (result solution '((0 . :int) (1 . :int)) '(0 4))))
          (check (null guards))
          (check (not certified-p)))
        (check (null (solve-equality-symbolically (term `(/ ,y ,x)) (lit :int 3) 0
                                                  :library *knowledge-library*))))
      ;; The evidence survives persistence, and an archived solver proposes nothing.
      (let ((restored (deserialize-knowledge-library (serialize-knowledge-library *knowledge-library*))))
        (check (knowledge-evidence-tested-p (find-knowledge-entry (knowledge-entry-id sum) restored)
                                            :uniqueness)))
      (let* ((z (var 0 :int))
             (frame (make-frame (make-schema :inputs nil :target :int)
                                (list (make-row :key 0 :known nil :requirement (term `(= (+ ,z 4) 10)))))))
        (check (= 1 (propagation-suggested (propagate-requirements frame *knowledge-library* (make-ledger)))))
        (setf (getf (knowledge-entry-metadata sum) :active-p) nil)
        (check (zerop (propagation-suggested (propagate-requirements frame *knowledge-library* (make-ledger))))))))
  ;; 6. A solver of a Boolean unknown is replayed as one, and lifted.
  (with-clean-kernel-state
    (dolist (prime '(5 7))
      (let* ((field (gf prime)) (a (var 0 field)) (b (var 1 field)) (c (var 2 field)))
        ;; (if z a b) = c with a /= b and c one of them: z = (c = a).
        (register-knowledge-solver
         (op :if field) :domain field :position 0
         :witness (term `(= ,c ,a))
         :guard (term `(if (= ,a ,b) ,(lit :bool nil) (if (= ,c ,a) ,(lit :bool t) (= ,c ,b))))
         :certified-p t :unique-p t)))
    (let ((lifted (lift-field-solvers *knowledge-library*)))
      (check (= 1 (length lifted)))
      (check (eq :bool (knowledge-entry-target (first lifted))))
      (check (knowledge-evidence-tested-p (first lifted) :uniqueness))
      (check (getf (consolidate-knowledge-library *knowledge-library*) :library)))))

(deftest row-order-keys-are-read-off-compound-inputs-by-the-enumerator
  "A key that is a component of a tuple input is found beside an unrelated integer column:
the kernel's enumerator writes the accessors and the VM evaluates them, for work that is
charged. A key the library already keeps for these inputs is a candidate as well."
  (with-clean-kernel-state
    (let* ((pair (tuple-type :int :int))
           (inputs (list (cons 0 pair) (cons 1 :int)))
           ;; ((time other) noise): 24 rows stored out of order, whose target drifts with
           ;; time by steps small enough for the chain to repay a key that costs an accessor.
           (times (loop for index below 24 collect (1+ (mod (* 7 index) 24))))
           (frame (make-frame (make-schema :inputs inputs :target :int)
                              (loop for time in times for key from 0
                                    collect (make-row :key key
                                                      :known (list (list time (mod (* 5 key) 11))
                                                                   (mod (* 3 key) 7))
                                                      :requirement (singleton-requirement
                                                                    :int (+ 1000 (* 37 time)))))))
           (ledger (make-ledger))
           (key (induce-row-order frame :ledger ledger)))
      (check (equal (term `(at ,(var 0 pair) 0)) key))
      (check (plusp (ledger-total ledger)))
      ;; The accessors are a language like any other: nothing but what the inputs' types offer.
      (check (equal (list (op :at pair)) (language-operators (projection-language inputs))))
      (check (null (projection-language '((0 . :int) (1 . :bool)))))
      ;; Remembered, the key is offered again without being searched for.
      (multiple-value-bind (ordered ordered-key) (with-induced-row-order frame :library *knowledge-library*)
        (check (equal key ordered-key))
        (check (equal (loop for time from 1 to 24 collect time)
                      (mapcar (lambda (row) (first (first (row-known row)))) (frame-rows ordered)))))
      (check (equal (list key) (mapcar #'car (stored-row-keys frame *knowledge-library* nil))))
      (let ((*projection-key-work* 1))
        (check (equal key (induce-row-order frame)))))))

