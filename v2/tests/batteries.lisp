(in-package #:lisploop)

;;; Batteries: bootstrapped `.sexp` knowledge-library packets in `library/`.

(defun call-with-temporary-battery (name packet-or-library thunk &key metadata)
  "Call THUNK with `*battery-directory*` bound to a fresh directory holding `NAME.sexp`."
  (let* ((directory (merge-pathnames (format nil "lisploop-batteries-~D-~D/"
                                             (get-universal-time) (random 1000000))
                                     #P"/tmp/"))
         (path (merge-pathnames (make-pathname :name (string-downcase (symbol-name name)) :type "sexp")
                                directory)))
    (ensure-directories-exist path)
    (unwind-protect
         (progn
           (if (knowledge-library-p packet-or-library)
               (save-knowledge-library path packet-or-library :metadata metadata)
               (with-open-file (stream path :direction :output :if-exists :supersede)
                 (with-standard-io-syntax
                   (let ((*print-pretty* t)
                         (*print-circle* nil))
                     (prin1 packet-or-library stream)
                     (terpri stream)))))
           (let ((*battery-directory* directory))
             (funcall thunk)))
      (when (probe-file path) (delete-file path))
      (sb-ext:delete-directory directory))))

(deftest every-battery-loads-and-passes-its-examples
  "Each `.sexp` battery in `library/` loads into an empty library by itself: its entries
type-check, its solvers over finite types certify, and every `:spec` it carries replays on
the VM. Its primary entries carry the edge that says where they came from."
  (check (equal '(:algebra :arithmetic :constructors :descriptors :functors
                  :scans :sequence-shift :sequences)
                (battery-names)))
  (dolist (name (battery-names))
    (with-clean-kernel-state
      (let ((entries (load-battery name)))
        (check entries)
        (check (every #'knowledge-entry-p entries))
        (check (same-set-p (mapcar #'knowledge-entry-id entries)
                           (mapcar #'second (knowledge-edges-to name :from-battery))))
        (dolist (entry entries)
          (check (eq entry (find-knowledge-entry (knowledge-entry-id entry))))
          (check (member (knowledge-entry-kind entry)
                         '(:function :solver :law :motif :transformer
                           :decoder-template :descriptor)))))))
  ;; All of them together, and through persistence.
  (with-clean-kernel-state
    (dolist (name (battery-names))
      (load-battery name))
    (check (find-knowledge-entry :map))
    (check (find-knowledge-entry :solve-/-1))
    (check (equal '(:shift-seq)
                  (mapcar (lambda (decoder) (operator-name (first decoder)))
                          (metric-decoders (sequence-type :int)))))
    (let* ((packet (serialize-knowledge-library))
           (restored (deserialize-knowledge-library packet)))
      (check (equal (getf (rest packet) :entries)
                    (getf (rest (serialize-knowledge-library restored)) :entries)))
      (with-knowledge-library (restored)
        (check (equal '(4 1 5 0 0)
                      (result (app (op :shift-seq) (lit (sequence-type :int) '(3 1 4 1 5))
                                   (lit :int 2)))))))))

(deftest battery-type-parameters-instantiate-and-certify
  "A battery is stated once over its type parameters. Loaded at a prime field its solvers are
certified exhaustively by the load; loaded at the integers nothing can be, and what is
taken on trust is recorded as an axiom and as nothing stronger."
  (with-clean-kernel-state
    (let* ((field (gf 5))
           (over-integers (load-battery :arithmetic))
           (over-field (load-battery :arithmetic :types (list (cons '?n field)))))
      (check (= 8 (length over-integers)))
      (check (= 8 (length over-field)))
      (check (eq (first over-integers) (find-knowledge-entry :solve-+-0)))
      (check (eq (first over-field) (find-knowledge-entry :solve-+-0/gf5)))
      (dolist (entry over-field)
        (check (equal field (knowledge-entry-domain entry)))
        (check (eq :validated (knowledge-entry-status entry)))
        (check (eq :exhaustive (getf (knowledge-entry-certificate entry) :method)))
        (check (knowledge-evidence-current-p entry :witness))
        (check (knowledge-evidence-current-p entry :uniqueness)))
      (dolist (entry over-integers)
        (check (eq :int (knowledge-entry-domain entry)))
        (check (eq :conjecture (knowledge-entry-status entry)))
        (check (not (knowledge-evidence-current-p entry :witness))))
      (dolist (id '(:solve-+-0 :solve-+-1 :solve---0 :solve---1))
        (let ((entry (find-knowledge-entry id)))
          (check (eq :trusted-axiom (getf (knowledge-entry-certificate entry) :method)))
          (check (knowledge-evidence-current-p entry :uniqueness))))
      (dolist (id '(:solve-*-0 :solve-*-1 :solve-/-0 :solve-/-1))
        (let ((entry (find-knowledge-entry id)))
          (check (null (knowledge-entry-certificate entry)))
          (check (not (getf (knowledge-entry-metadata entry) :unique-p)))))
      ;; The field's rule narrows outright; the integers' is a suggestion that keeps its fallback.
      (flet ((propagation (domain)
               (propagate-requirements
                (make-frame (make-schema :inputs nil :target domain)
                            (list (make-row :key 0 :known nil
                                            :requirement (term `(= (+ ,(var 0 domain) 2) 1) :bool))))
                *knowledge-library* (make-ledger))))
        (let ((narrowed (propagation field)))
          (check (= 1 (propagation-narrowed narrowed)))
          (check (null (propagation-fallback narrowed)))
          (check (accepts (row-requirement (first (frame-rows (propagation-frame narrowed)))) 4)))
        (let ((suggested (propagation :int)))
          (check (= 1 (propagation-suggested suggested)))
          (check (propagation-fallback suggested))
          (check (accepts (row-requirement (first (frame-rows (propagation-frame suggested)))) -1))))))
  ;; A function at another element type takes the type's slug, and calls itself by that name.
  (with-clean-kernel-state
    (let* ((field (gf 5))
           (entries (load-battery :sequences :types (list (cons '?a field)) :only '(:map))))
      (check (equal '(:map/gf5) (mapcar #'knowledge-entry-id entries)))
      (check (null (find-knowledge-entry :map)))
      (check (expression-calls-operator-p (knowledge-entry-expression (first entries)) :map/gf5))
      (check (equal '(2 3 4)
                    (result (app (op :map/gf5) (lit (sequence-type field) '(1 2 3))
                                 (lit (code-type (list (cons 0 field)) field)
                                      (term `(+ ,(var 0 field) 1))))))))))

(deftest battery-loading-is-selective-and-checked
  (with-clean-kernel-state
    ;; The entries asked for, in the battery's order whatever order they were asked in.
    (check (equal '(:map :filter)
                  (mapcar #'knowledge-entry-id (load-battery :sequences :only '(:filter :map)))))
    (check (equal '(:map :filter) *registered-function-names*))
    (check (null (find-knowledge-entry :foldr)))
    ;; Loading into a library that is not the active one leaves the active one alone.
    (let ((other (make-knowledge-library)))
      (load-battery :scans :only '(:scan) :library other)
      (check (find-knowledge-entry :scan other))
      (check (null (find-knowledge-entry :scan)))
      (check (not (defined-function-p :scan))))
    (raises (load-battery :sequences :only '(:no-such-entry)))
    (raises (load-battery :sequences :types '((?z . :int))))
    (raises (load-battery :no-such-battery))
    ;; An entry is not loaded without what it calls.
    (raises (load-battery :sequence-shift :only '(:argmax-corr)))
    (raises (load-battery :sequences :only '(:foldr=foldl/monoid))))
  (with-clean-kernel-state
    (raises (load-battery :sequences :only '(:comprehension/filter-map))))
  ;; Nothing is believed on the file's word: a wrong `:spec` example refuses the load, a wrong
  ;; type refuses it, and a claim of uniqueness that a finite check refutes is withdrawn.
  (flet ((build-scratch-packet (expected-out)
           (with-clean-kernel-state
             (let ((scratch-lib (make-knowledge-library)))
               (with-knowledge-library (scratch-lib)
                 (define-function :double '((0 . :int)) :int
                   (term `(+ ,(var 0 :int) ,(var 0 :int))))
                 (add-knowledge-edge (find-knowledge-entry :double scratch-lib)
                                     :from-battery :scratch)
                 (let ((solver (register-knowledge-solver
                                (op :+ :int)
                                :id :undo-plus
                                :domain :int
                                :position 0
                                :witness (term `(- ,(var 1 :int) ,(var 0 :int)))
                                :certified-p nil
                                :unique-p nil
                                :library scratch-lib)))
                   (add-knowledge-edge solver :from-battery :scratch))
                 (register-knowledge-spec :spec/double '((0 . :int)) :int
                                          (list (list '(3) expected-out))
                                          :target-id :double
                                          :library scratch-lib)
                 (serialize-knowledge-library
                  scratch-lib
                  :metadata '(:battery :scratch :parameters ((?n :int)))))))))
    (let ((ok-packet (build-scratch-packet 6))
          (bad-spec-packet (build-scratch-packet 7)))
      (with-clean-kernel-state
        (call-with-temporary-battery
         :scratch ok-packet
         (lambda ()
           (check (equal '(:double :undo-plus)
                         (mapcar #'knowledge-entry-id (load-battery :scratch))))
           (check (= 10 (result (app (op :double) (lit :int 5))))))))
      (with-clean-kernel-state
        (call-with-temporary-battery
         :scratch bad-spec-packet
         (lambda ()
           (raises (load-battery :scratch))
           ;; Unchecked, or at types its examples were not written for, it loads.
           (check (load-battery :scratch :check-examples-p nil))
           (check (load-battery :scratch :types (list (cons '?n (gf 5))))))))
      ;; Corrupting the serialized return type of `:double` to `:bool` fails `deserialize-knowledge-library`.
      (with-clean-kernel-state
        (let* ((corrupted (copy-tree ok-packet))
               (entries (getf (rest corrupted) :entries))
               (dbl-plist (find :double entries :key (lambda (pl) (getf pl :id)))))
          (setf (getf dbl-plist :target) :bool)
          (call-with-temporary-battery
           :scratch corrupted
           (lambda () (raises (load-battery :scratch))))))))
  ;; 0 * z = 0 has every z: claimed unique in a serialized packet, `load-battery` re-certifies
  ;; finite solvers and withdraws `:uniqueness` while certifying `:witness`.
  (let ((overclaimed-packet
          (with-clean-kernel-state
            (let* ((gf3 (gf 3))
                   (k (var 0 gf3))
                   (c (var 1 gf3))
                   (scratch-lib (make-knowledge-library)))
              (with-knowledge-library (scratch-lib)
                (let ((s (register-knowledge-solver
                          (op :* gf3)
                          :id :zero-times
                          :domain gf3
                          :position 1
                          :witness (lit gf3 0)
                          :guard (bool-and (term `(= ,k ,(lit gf3 0)))
                                           (term `(= ,c ,(lit gf3 0))))
                          :certified-p nil
                          :unique-p t
                          :library scratch-lib)))
                  (add-knowledge-edge s :from-battery :scratch))
                (serialize-knowledge-library scratch-lib :metadata '(:battery :scratch)))))))
    (with-clean-kernel-state
      (call-with-temporary-battery
       :scratch overclaimed-packet
       (lambda ()
         (let ((entry (first (load-battery :scratch))))
           (check (knowledge-evidence-current-p entry :witness))
           (check (not (knowledge-evidence-current-p entry :uniqueness)))
           (check (not (getf (knowledge-entry-metadata entry) :unique-p)))))))))

(deftest the-active-library-is-consumed-without-being-named
  "A synthesis job narrows its child frames with the solvers of the library that is active
when it starts, unless it is given another library or none. The size of the library is not
what dispatch costs: a conjunct pays for one lookup, not for every rule."
  (with-clean-kernel-state
    (let* ((frame (simple-frame :int '((0 . :int)) '(((1) 2))))
           (language (make-language :int '((0 . :int)))))
      (check (null (synthesis-job-library (start-synthesis frame language 40))))
      (load-battery :arithmetic :only '(:solve-+-0))
      (let ((rules (lambda (job) (and (synthesis-job-library job)
                                      (propagator-library-rules (synthesis-job-library job))))))
        (check (= 1 (length (funcall rules (start-synthesis frame language 40)))))
        (check (= 1 (length (funcall rules (start-heuristic-synthesis frame language 40)))))
        (check (null (funcall rules (start-synthesis frame language 40 :library nil))))
        (check (null (funcall rules (start-synthesis frame language 40
                                                     :library (make-knowledge-library)))))
        ;; A proposal that brings a rule of its own for the same entry does not have it tried twice.
        (let ((again (make-propagator-library
                      :rules (list (knowledge-entry->propagator-rule (find-knowledge-entry :solve-+-0))))))
          (check (= 1 (length (propagator-library-rules
                               (as-propagator-library (list *knowledge-library* again))))))))))
  ;; One conjunct, propagated with one rule in the library and then with every battery.
  (flet ((dispatch-work ()
           (let ((ledger (make-ledger)))
             (propagate-requirements
              (make-frame (make-schema :inputs nil :target :int)
                          (list (make-row :key 0 :known nil
                                          :requirement (term `(= (- 9 ,(var 0 :int)) 4) :bool))))
              *knowledge-library* ledger)
             (cdr (assoc :propagator-dispatch (canonical-ledger-alist ledger))))))
    (let ((alone (with-clean-kernel-state
                   (load-battery :arithmetic :only '(:solve---1))
                   (dispatch-work)))
          (among-all (with-clean-kernel-state
                       (dolist (name (battery-names)) (load-battery name))
                       (load-battery :arithmetic :types (list (cons '?n (gf 7))))
                       (check (< 16 (length (knowledge-entries-of-kind :solver))))
                       (dispatch-work))))
      (check (plusp alone))
      (check (= alone among-all)))))

(deftest a-search-keeps-its-solvers-when-the-function-table-changes
  "A job freezes the rules it will propagate with when it starts. A function defined after
that, as when the search instantiates a combinator at the types of its frame, leaves those
rules standing: their programs are prepared again for the new function table."
  (with-clean-kernel-state
    (dolist (name (battery-names))
      (load-battery name))
    (let* ((seq (sequence-type :int))
           (inputs (list (cons 0 seq)))
           (frame (simple-frame seq inputs '(((()) ()) (((2)) (5)) (((4 2)) (7 5)) (((-1 3 0)) (2 6 3)))))
           (language (make-language :int inputs :operators (list (op :+ :int)) :literals '(1 3)
                                                :constants (list (lit seq '()))))
           (job (start-heuristic-synthesis frame language 75))
           (rules (propagator-library-rules (synthesis-job-library job))))
      (check rules)
      (define-function :defined-meanwhile '((0 . :int)) :int (var 0 :int))
      (check (not (equal (vm-versions) (propagator-library-versions (synthesis-job-library job)))))
      (resume-synthesis job 400000 :stop-on-first t)
      ;; No combinator was named: the library's own `:map` is found and lifted.
      (check (synthesis-job-best job))
      (check-synthesized-model (candidate-expression (synthesis-job-best job)) frame
                               :must-call-ops '(:map)
                               :held-out '((((10 20)) (13 23))))
      (check (equal (vm-versions) (propagator-library-versions (synthesis-job-library job))))
      (check (equal rules (propagator-library-rules (synthesis-job-library job)))))))

(deftest step1-necessity-refutation-and-bounded-membership-propagation
  "Joint heterogeneous `:cons` solvers, `:necessity` refutations (including domain-guarded `:*`),
and bounded finite-set `(member ...)` (`2 <= m <= 8`) propagation maintain exact vs fallback
evidence discipline."
  (with-clean-kernel-state
    ;; 1. Joint `(0 1)` `:cons` solver with heterogeneous `(:tuple :int (:seq :int))` target.
    (let* ((seq-t (sequence-type :int))
           (pair-t (tuple-type :int seq-t))
           (c (var 0 seq-t))
           (cons-solver
             (register-knowledge-solver
              (op :cons :int)
              :id :solve-cons-01
              :position '(0 1)
              :target pair-t
              :guard (bool-not (term `(= ,c ())))
              :witness (app (op :tuple pair-t) (term `(at ,c 0)) (term `(tail ,c)))
              :trusted-p t
              :necessary-p t))
           (h (term `(at ,(var 0 pair-t) 0)))
           (tl (term `(at ,(var 0 pair-t) 1)))
           (schema (make-schema :inputs nil :target pair-t)))
      (check (knowledge-evidence-current-p cons-solver :witness))
      (check (knowledge-evidence-current-p cons-solver :uniqueness))
      (check (knowledge-evidence-current-p cons-solver :necessity))
      ;; Non-empty target narrows to `(= H '10) ^ (= T '(20))` with no fallback.
      (let* ((req-ok (term `(= (cons ,h ,tl) '(10 20))))
             (res-ok (propagate-requirements
                      (make-frame schema (list (make-row :key 0 :known nil :requirement req-ok)))
                      *knowledge-library* (make-ledger))))
        (check (= 1 (propagation-narrowed res-ok)))
        (check (null (propagation-fallback res-ok)))
        (check (equal (bool-and (term `(= ,h 10))
                                (term `(= ,tl '(20))))
                      (row-requirement (first (frame-rows (propagation-frame res-ok)))))))
      ;; Empty target `'()` is refuted directly to `'nil` with no fallback.
      (let* ((req-empty (term `(= (cons ,h ,tl) ())))
             (res-empty (propagate-requirements
                         (make-frame schema (list (make-row :key 0 :known nil :requirement req-empty)))
                         *knowledge-library* (make-ledger))))
        (check (= 1 (propagation-narrowed res-empty)))
        (check (null (propagation-fallback res-empty)))
        (check (equal (lit :bool nil)
                      (row-requirement (first (frame-rows (propagation-frame res-empty)))))))
      ;; Sampled-only `:necessity` still refutes tentatively while retaining `propagation-fallback`.
      (attest-knowledge-entry cons-solver :sampled '(:witness :uniqueness :necessity))
      (invalidate-knowledge-caches *knowledge-library*)
      (let* ((req-empty (term `(= (cons ,h ,tl) ())))
             (res-tent (propagate-requirements
                        (make-frame schema (list (make-row :key 0 :known nil :requirement req-empty)))
                        *knowledge-library* (make-ledger))))
        (check (zerop (propagation-narrowed res-tent)))
        (check (= 1 (propagation-suggested res-tent)))
        (check (frame-p (propagation-fallback res-tent)))
        (check (equal (lit :bool nil)
                      (row-requirement (first (frame-rows (propagation-frame res-tent))))))))
    ;; 2. `:*` over GF(5): without `domain-guard`, `:necessary-p` is refuted at `(0, 0)`;
    ;; with `domain-guard`, `certify-solver-entry` certifies `:necessity`, refuting `0 * Z = 3`
    ;; while leaving `0 * Z = 0` untouched.
    (let* ((gf5 (gf 5))
           (k (var 0 gf5))
           (c (var 1 gf5))
           (overclaimed (make-knowledge-solver
                         (op :* gf5)
                         :id :overclaimed-mul
                         :domain gf5
                         :position 1
                         :guard (bool-not (term `(= ,k ,(lit gf5 0))))
                         :witness (term `(/ ,c ,k))
                         :certified-p t
                         :necessary-p t)))
      (check (not (knowledge-evidence-current-p overclaimed :necessity)))
      (let ((sound-mul (register-knowledge-solver
                        (op :* gf5)
                        :id :sound-gf5-mul-1
                        :domain gf5
                        :position 1
                        :guard (bool-not (term `(= ,k ,(lit gf5 0))))
                        :domain-guard (term `(if (= ,k ,(lit gf5 0))
                                                 (= ,c ,(lit gf5 0))
                                                 t))
                        :witness (term `(/ ,c ,k))
                        :certified-p t
                        :necessary-p t))
            (schema (make-schema :inputs nil :target gf5)))
        (check (knowledge-evidence-current-p sound-mul :necessity))
        (let ((bad (propagate-requirements
                    (make-frame schema
                                (list (make-row :key 0 :known nil
                                                :requirement (term `(= (* ,(lit gf5 0) ,(var 0 gf5))
                                                                       ,(lit gf5 3))))))
                    *knowledge-library* (make-ledger)))
              (ambig (propagate-requirements
                      (make-frame schema
                                  (list (make-row :key 0 :known nil
                                                  :requirement (term `(= (* ,(lit gf5 0) ,(var 0 gf5))
                                                                         ,(lit gf5 0))))))
                      *knowledge-library* (make-ledger))))
          (check (= 1 (propagation-narrowed bad)))
          (check (null (propagation-fallback bad)))
          (check (equal (lit :bool nil)
                        (row-requirement (first (frame-rows (propagation-frame bad))))))
          (check (zerop (propagation-narrowed ambig))))))
    ;; 3. Bounded `(member ...)` (`2 <= m <= 8`) unwinds across nested GF(7) & integer solvers.
    (with-clean-kernel-state
      (load-battery :arithmetic :types (list (cons '?n (gf 7))))
      (let* ((gf7 (gf 7))
             (z (var 0 gf7))
             (schema (make-schema :inputs nil :target gf7))
             (req (term `(member (+ (* ,(lit gf7 2) ,z) ,(lit gf7 1)) '(3 5))))
             (res (propagate-requirements
                   (make-frame schema (list (make-row :key 0 :known nil :requirement req)))
                   *knowledge-library* (make-ledger)))
             (too-wide (term `(member (+ ,z ,(lit gf7 1)) '(0 1 2 3 4 5 6 0 1)))))
        (check (= 1 (propagation-narrowed res)))
        (check (null (propagation-fallback res)))
        (check (equal (term `(member ,z '(1 2)))
                      (row-requirement (first (frame-rows (propagation-frame res))))))
        ;; Deduplicated `'(0 1 2 3 4 5 6)` has length 7 <= 8 so it narrows; 9 distinct ints do not.
        (check (= 1 (propagation-narrowed
                     (propagate-requirements
                      (make-frame schema (list (make-row :key 0 :known nil :requirement too-wide)))
                      *knowledge-library* (make-ledger)))))))
    (with-clean-kernel-state
      (load-battery :arithmetic)
      (let* ((z (var 0 :int))
             (schema (make-schema :inputs nil :target :int))
             (wide (term `(member (+ ,z 1) '(0 1 2 3 4 5 6 7 8))))
             (res-wide (propagate-requirements
                        (make-frame schema (list (make-row :key 0 :known nil :requirement wide)))
                        *knowledge-library* (make-ledger))))
        (check (zerop (propagation-narrowed res-wide)))))))

(deftest the-index-list-is-a-learned-library-function
  "`:positions` gives the coordinates of a sequence from a start. It is synthesized by the
bootstrap from a spec, loads with its examples, and is total: the sequence shortens at
every call, whatever the counter does."
  (with-clean-kernel-state
    (load-battery :sequences :only '(:positions))
    (let ((seq (sequence-type :int))
          (definition (find-function-definition :positions)))
      (check (function-definition-total-p definition))
      (check (equal '(5 6 7 8) (result (app (op :positions) (lit seq '(4 4 4 4)) (lit :int 5)))))
      (check (equal '(0 1 2) (result (app (op :positions) (lit seq '(9 8 7)) (lit :int 0)))))
      (check (null (result (app (op :positions) (lit seq '()) (lit :int 3))))))))

(deftest a-read-at-an-unknown-index-narrows-to-the-positions-that-hold-the-value
  "`:solve-at-1` inverts `(at xs Z)` in its index. Its witness, synthesized by the bootstrap
from the learned `:filter` and `:positions`, lists every position of xs that holds the value,
so the requirement becomes membership in that list, an equation when there is one position,
and false when there is none. Its evidence is sampled, so each narrowing keeps its fallback."
  (with-clean-kernel-state
    (load-battery :sequences)
    (let ((seq (sequence-type :int))
          (solver (find-knowledge-entry :solve-at-1))
          (z (var 0 :int)))
      (check (getf (knowledge-entry-metadata solver) :set-valued-p))
      (check (eq :int (knowledge-entry-target solver)))
      (check (knowledge-evidence-tested-p solver :witness))
      (check (not (knowledge-evidence-current-p solver :witness)))
      (flet ((narrowed (xs value)
               (let ((propagation
                       (propagate-requirements
                        (make-frame (make-schema :inputs '((0 . :int)) :target :int)
                                    (list (make-row :key 0 :known '(0)
                                                    :requirement (term `(= (at ,(lit seq xs) ,z) ,value)))))
                        *knowledge-library* (make-ledger))))
                 (check (= 1 (propagation-suggested propagation)))
                 (check (zerop (propagation-narrowed propagation)))
                 (check (propagation-fallback propagation))
                 (row-requirement (first (frame-rows (propagation-frame propagation)))))))
        (let ((two (narrowed '(5 6 7 5) 5)))
          (check (accepts two 0))
          (check (accepts two 3))
          (check (not (accepts two 1))))
        (check (equal (term `(= ,z 1)) (narrowed '(5 6 7 5) 6)))
        (check (equal (lit :bool nil) (narrowed '(5 6 7 5) 9)))))))

(deftest step1-rank-environment-totality-and-terminating-recursions
  "Rank-environment static totality certifies nested-tail lookahead (`:map-adjacent`),
integer countdowns (`(< 0 n)` -> `(- n 1)`), and multi-argument lexicographic recursions,
while rejecting unguarded or non-decreasing calls."
  (with-clean-kernel-state
    (load-battery :sequences)
    (let* ((def (find-function-definition :map-adjacent))
           (seq-t (sequence-type :int))
           (step-t (code-type '((0 . :int) (1 . :int)) :int))
           (diff-code (lit step-t (term `(- ,(var 0 :int) ,(var 1 :int)))))
           (call (app (op :map-adjacent) (var 0 seq-t) diff-code)))
      (check (equal '(1) (function-definition-conditional-code-params def)))
      (check (provably-total-p call)))
    ;; Integer countdown recursion is total; unguarded countdown and upward step are not.
    (define-function :countdown-sum '((0 . :int)) :int
      (lambda (self)
        (let ((n (var 0 :int)))
          (term `(if (< 0 ,n) (+ ,n (,self (- ,n 1))) 0)))))
    (check (function-definition-total-p (find-function-definition :countdown-sum)))
    (define-function :unguarded-countdown '((0 . :int)) :int
      (lambda (self)
        (let ((n (var 0 :int)))
          (term `(+ ,n (,self (- ,n 1)))))))
    (check (not (function-definition-total-p (find-function-definition :unguarded-countdown))))
    (define-function :upward-step '((0 . :int)) :int
      (lambda (self)
        (let ((n (var 0 :int)))
          (term `(if (< 0 ,n) (+ ,n (,self (+ ,n 1))) 0)))))
    (check (not (function-definition-total-p (find-function-definition :upward-step))))
    ;; Two-sequence lexicographic merge is total; parameter-swapping recursion is not.
    (let* ((seq-t (sequence-type :int))
           (inputs (list (cons 0 seq-t) (cons 1 seq-t)))
           (xs (var 0 seq-t))
           (ys (var 1 seq-t)))
      (define-function :lex-merge inputs seq-t
        (lambda (self)
          (term `(if (= ,xs ())
                     ,ys
                     (if (= ,ys ())
                         ,xs
                         (if (< (at ,xs 0) (at ,ys 0))
                             (cons (at ,xs 0) (,self (tail ,xs) ,ys))
                             (cons (at ,ys 0) (,self ,xs (tail ,ys)))))))))
      (check (function-definition-total-p (find-function-definition :lex-merge)))
      (define-function :swap-loop inputs seq-t
        (lambda (self)
          (term `(if (= ,xs ())
                     ,ys
                     (if (= ,ys ())
                         ,xs
                         (,self (tail ,ys) ,xs))))))
      (check (not (function-definition-total-p (find-function-definition :swap-loop)))))))

(deftest step1-unified-entry-templates-shared-descriptors-and-triggers
  "Constraint-based `instantiate-entry-template` retypes solvers, laws (preserving `:int`
indices/lengths), and descriptors cleanly; shared polymorphic `:descriptor` entries evaluate
across types and isolate per-function necessity snapshots; and `knowledge-entry-trigger`
gates `:decoder-template` proposals."
  (with-clean-kernel-state
    (dolist (name (battery-names))
      (load-battery name))
    ;; 1. Shared `:DESC/LEN-EQ` has no per-function duplicates and evaluates polymorphically.
    (let ((len-eq (find-knowledge-entry :DESC/LEN-EQ)))
      (check len-eq)
      (check (null (remove-if-not
                    (lambda (e)
                      (and (not (eq e len-eq))
                           (search "DESC/LEN-EQ" (symbol-name (knowledge-entry-id e)))))
                    (knowledge-entries-of-kind :descriptor))))
      (let ((seq-t (sequence-type :int)))
        (define-function :id-seq (list (cons 0 seq-t)) seq-t
          (lambda (self)
            (let ((xs (var 0 seq-t)))
              (term `(if (= ,xs ()) () (cons (at ,xs 0) (,self (tail ,xs)))))))))
      (check (entry-descriptor-necessary-p :map :DESC/LEN-EQ))
      (check (entry-descriptor-necessary-p :id-seq :DESC/LEN-EQ))
      (check (not (entry-descriptor-necessary-p :scan :DESC/LEN-EQ)))
      (let ((gf5-seq (sequence-type (gf 5)))
            (tup-seq (sequence-type (tuple-type :int :bool))))
        (check (eq :satisfied
                   (evaluate-descriptor-entry-on-frame
                    len-eq '(:seq-out) gf5-seq gf5-seq '(((1 4) . (2 0))) (make-ledger))))
        (check (eq :violated
                   (evaluate-descriptor-entry-on-frame
                    len-eq '(:seq-out) tup-seq tup-seq '((((1 t) (2 nil)) . ((3 t)))) (make-ledger))))))
    ;; Redefining `:map` invalidates `:map`'s necessity snapshot without touching `:id-seq`.
    (let* ((seq-t (sequence-type :int))
           (xs (var 0 seq-t)))
      (setf (function-definition-body (find-function-definition :map))
            (term `(if (= ,xs ()) () (tail ,xs))))
      (check (not (entry-descriptor-necessary-p :map :DESC/LEN-EQ)))
      (check (entry-descriptor-necessary-p :id-seq :DESC/LEN-EQ))))
  ;; 2. `instantiate-entry-template` on `:solver` and `:law` (preserving `:int` `:length`).
  (with-clean-kernel-state
    (load-battery :arithmetic :only '(:solve-+-0))
    (let* ((int-solver (find-knowledge-entry :solve-+-0))
           (gf5 (gf 5))
           (gf5-solver (instantiate-entry-template int-solver
                                                   :id :gf5-solve-+-0
                                                   :domain gf5
                                                   :input-types (list gf5 gf5)
                                                   :target gf5
                                                   :register-p t))
           (back-int (instantiate-entry-template gf5-solver
                                                 :id :back-int-solve-+-0
                                                 :domain :int
                                                 :input-types '(:int :int)
                                                 :target :int)))
      (check (knowledge-evidence-current-p gf5-solver :witness))
      (check (eq :exhaustive (getf (knowledge-entry-certificate gf5-solver) :method)))
      (check (not (knowledge-evidence-current-p back-int :witness)))
      (check (eq :conjecture (knowledge-entry-status back-int))))
    (let* ((seq-int (sequence-type :int))
           (xs (var 0 seq-int))
           (x (var 1 :int))
           (law-entry (make-law :int (list (cons 0 seq-int) (cons 1 :int))
                                (term `(at (cons ,x ,xs) 0))
                                x
                                :guard (term `(< 0 (length (cons ,x ,xs))))))
           (gf5 (gf 5))
           (seq-gf5 (sequence-type gf5))
           (inst-law (instantiate-entry-template law-entry
                                                 :id :gf5-at-cons-law
                                                 :domain gf5
                                                 :input-types (list seq-gf5 gf5))))
      ;; `:at` index `0` and `:length` comparison `(< 0 ...)` stay `:int` while elements become `(gf 5)`!
      (check (eq :bool (knowledge-entry-target inst-law)))
      (check (equal (list (cons 0 seq-gf5) (cons 1 gf5))
                    (knowledge-entry-inputs inst-law)))
      (check (eq t (eval-expr-value (knowledge-entry-expression inst-law)
                                    (knowledge-entry-inputs inst-law)
                                    '((1 4) 3))))
      (check (eq t (eval-expr-value (knowledge-entry-guard inst-law)
                                    (knowledge-entry-inputs inst-law)
                                    '((1 4) 3))))))
  ;; 3. `knowledge-entry-trigger` gates `learned-decoder-decompositions`.
  (with-clean-kernel-state
    (let* ((seq-t (sequence-type :int))
           (xs (var 0 seq-t))
           (ys (var 1 seq-t))
           (tmpl (register-knowledge-entry
                  (make-knowledge-entry
                   :id :grow-by-1-decoder
                   :kind :decoder-template
                   :domain :int
                   :inputs (list (cons 0 seq-t) (cons 1 :int))
                   :target seq-t
                   :expression (app (op :cons :int) (var 1 :int) xs)
                   :trigger (term `(= (+ (length ,xs) 1) (length ,ys)))
                   :status :empirical
                   :metadata (list :child-id 1 :bindings :identity))))
           (inputs (list (cons 0 seq-t)))
           (lang (make-language :int inputs :operators (list (op :+ :int)) :literals '(0 1)))
           (match-frame (simple-frame seq-t inputs '(((()) (9)) (((2 3)) (9 2 3)))))
           (miss-frame (simple-frame seq-t inputs '(((()) ()) (((2 3)) (3 4))))))
      (declare (ignore tmpl))
      (check (= 1 (length (learned-decoder-decompositions
                           match-frame lang 60 *knowledge-library* (make-ledger)))))
      (check (null (learned-decoder-decompositions
                    miss-frame lang 60 *knowledge-library* (make-ledger)))))))

(deftest step2-spec-synthesis-and-verification
  "First-class `:spec` entries persist homoiconically (including `:code` literal inputs),
drive de novo recursive synthesis (`synthesize-spec-entry`), and reject mismatched functions
and solvers (`verify-entry-against-spec`)."
  (with-clean-kernel-state
    (let* ((seq-t (sequence-type :int))
           (pred-t (code-type '((0 . :int)) :bool))
           (pos-pred (term `(< 0 ,(var 0 :int))))
           (spec (register-knowledge-spec
                  :spec/keep-matching
                  (list (cons 0 seq-t) (cons 1 pred-t))
                  seq-t
                  (list (list (list '() pos-pred) '())
                        (list (list '(4) pos-pred) '(4))
                        (list (list '(-3 4) pos-pred) '(4))
                        (list (list '(2 -3 4) pos-pred) '(2 4))
                        (list (list '() (lit :bool nil)) '())
                        (list (list '(4) (lit :bool nil)) '()))
                  :target-id :keep-matching
                  :operators (list (op :cons :int) (op :tail :int) (op :at seq-t)
                                   (op := seq-t) (op :if seq-t) (op :code-eval pred-t))
                  :constants (list (lit seq-t '()))))
           (fn-entry (synthesize-spec-entry spec)))
      (check (eq :function (knowledge-entry-kind fn-entry)))
      (check (equal '(1) (function-definition-conditional-code-params
                          (find-function-definition :keep-matching))))
      (check (provably-total-p (app (op :keep-matching) (var 0 seq-t) (lit pred-t pos-pred))))
      (check (equal '(5 7)
                    (result (app (op :keep-matching)
                                 (lit seq-t '(-1 5 0 7))
                                 (lit pred-t pos-pred)))))
      ;; Round-trip persistence preserves `:spec` rows without uninterned symbols.
      (let* ((packet (serialize-knowledge-library))
             (restored (deserialize-knowledge-library packet)))
        (with-knowledge-library (restored)
          (check (verify-entry-against-spec :keep-matching (find-knowledge-entry :spec/keep-matching)))))
      ;; Breaking `:keep-matching` makes `verify-entry-against-spec` raise.
      (setf (function-definition-body (find-function-definition :keep-matching))
            (lit seq-t '()))
      (raises (verify-entry-against-spec :keep-matching spec)))))

(deftest step2-conditional-and-law-solver-induction
  "`induce-conditional-solvers` discovers exact witnesses, uniqueness guards, and domain-range
guards (`:necessity`) over finite fields without hand-coded templates; `induce-law-solvers`
derives witnesses and `:uniqueness` from right-inverse / left-cancellation / involution laws."
  ;; 1. Exhaustive fiber solver induction over GF(5) for `:+` and `:*` (including `:domain-guard`).
  (with-clean-kernel-state
    (let* ((gf5 (gf 5))
           (solvers (induce-conditional-solvers (list (op :+ gf5) (op :* gf5))
                                                :domain gf5 :positions '(0 1)))
           (mul-1 (find-if (lambda (s)
                             (and (eq :* (getf (knowledge-entry-metadata s) :operator-name))
                                  (eql 1 (getf (knowledge-entry-metadata s) :position))))
                           solvers))
           (schema (make-schema :inputs nil :target gf5)))
      (check (= 4 (length solvers)))
      (dolist (s solvers)
        (check (knowledge-evidence-current-p s :witness))
        (check (knowledge-evidence-current-p s :uniqueness)))
      ;; `:*` at position 1 has `multi-rows` `(0, 0)` and `empty-rows` `(0, 1..4)` -> `:necessity` certified!
      (check (knowledge-entry-auxiliary-code mul-1))
      (check (knowledge-evidence-current-p mul-1 :necessity))
      (let ((impossible (propagate-requirements
                         (make-frame schema
                                     (list (make-row :key 0 :known nil
                                                     :requirement (term `(= (* ,(lit gf5 0) ,(var 0 gf5))
                                                                            ,(lit gf5 2))))))
                         *knowledge-library* (make-ledger))))
        (check (= 1 (propagation-narrowed impossible)))
        (check (null (propagation-fallback impossible)))
        (check (equal (lit :bool nil)
                      (row-requirement (first (frame-rows (propagation-frame impossible)))))))))
  ;; 2. `induce-law-solvers`: right-inverse + left-cancellation over GF(5), plus unary involution.
  (with-clean-kernel-state
    (let* ((gf5 (gf 5))
           (inps (list (cons 0 gf5) (cons 1 gf5)))
           (k (var 0 gf5))
           (z (var 1 gf5)))
      (register-knowledge-law
       (validate-law (make-law gf5 inps (term `(+ (- ,z ,k) ,k)) z) 100000 nil nil)
       :id :gf5/right-inv)
      (register-knowledge-law
       (validate-law (make-law gf5 inps (term `(- (+ ,z ,k) ,k)) z) 100000 nil nil)
       :id :gf5/left-can)
      (define-function :neg-gf5 (list (cons 0 gf5)) gf5
        (term `(- ,(lit gf5 0) ,(var 0 gf5))))
      (register-knowledge-law
       (validate-law (make-law gf5 (list (cons 0 gf5))
                               (app (op :neg-gf5) (app (op :neg-gf5) (var 0 gf5)))
                               (var 0 gf5))
                     100000 nil nil)
       :id :gf5/neg-involution)
      (let ((derived (induce-law-solvers *knowledge-library*)))
        (check (<= 2 (length derived)))
        (let ((add-solver (find-if (lambda (s)
                                     (eq :+ (getf (knowledge-entry-metadata s) :operator-name)))
                                   derived))
              (inv-solver (find-if (lambda (s)
                                     (eq :neg-gf5 (getf (knowledge-entry-metadata s) :operator-name)))
                                   derived)))
          (check add-solver)
          (check (knowledge-evidence-current-p add-solver :witness))
          (check (knowledge-evidence-current-p add-solver :uniqueness))
          (check inv-solver)
          (check (knowledge-evidence-current-p inv-solver :witness))
          (check (knowledge-evidence-current-p inv-solver :uniqueness)))))))

(deftest step2-multi-hole-decoder-templates-and-functor-transformers
  "The `:comprehension/filter-map` multi-hole `:decoder-template` solves filter-map comprehensions
over `:int` and polymorphically over `(:gf 5)`; and `functors.sexp` `:transformer` entries execute
in the VM via `induce-functorial-solvers`."
  ;; 1. Polymorphic `:comprehension/filter-map` over `(:gf 5)` with zero host filter-map code.
  (with-clean-kernel-state
    (load-battery :arithmetic :types (list (cons '?n (gf 5))))
    (load-battery :sequences :only '(:map :filter :comprehension/filter-map))
    (let* ((gf5 (gf 5))
           (seq-gf5 (sequence-type gf5))
           (inputs (list (cons 0 seq-gf5)))
           ;; Keep non-zero elements in GF(5) and add 1 mod 5.
           (frame (simple-frame seq-gf5 inputs
                                '(((()) ())
                                  (((0 2 0 4)) (3 0))
                                  (((1 0 3)) (2 4))
                                  (((0 0)) ()))))
           (lang (make-language gf5 inputs
                                :operators (list (op :+ gf5) (op := gf5))
                                :literals '(0 1)
                                :constants (list (lit seq-gf5 '()) (lit :bool t) (lit :bool nil))))
           (job (start-heuristic-synthesis frame lang 90)))
      (resume-synthesis job 250000 :stop-on-first t)
      (check (synthesis-job-best job))
      (check-synthesized-model (candidate-expression (synthesis-job-best job)) frame
                               :held-out '((((4 0 1 2)) (0 2 3))))))
  ;; 2. `functors.sexp` `:transformer` execution via `induce-functorial-solvers`.
  (with-clean-kernel-state
    (load-battery :arithmetic :only '(:solve-+-0 :solve-+-1))
    (load-battery :functors)
    (load-battery :sequences :only '(:map))
    (let ((seq-solvers (induce-functorial-solvers *knowledge-library*)))
      (check seq-solvers)
      (let* ((seq-t (sequence-type :int))
             (xs (var 0 seq-t))
             (step-t (code-type '((0 . :int)) :int))
             (inc2 (lit step-t (term `(+ ,(var 0 :int) 2))))
             (schema (make-schema :inputs nil :target seq-t))
             (res (propagate-requirements
                   (make-frame schema
                               (list (make-row :key 0 :known nil
                                               :requirement (term `(= (:map ,xs ,inc2) '(12 15))))))
                   *knowledge-library* (make-ledger))))
        (check (= 1 (propagation-suggested res)))
        (check (frame-p (propagation-fallback res)))
        (check (accepts (row-requirement (first (frame-rows (propagation-frame res))))
                        '(10 13)))))))
