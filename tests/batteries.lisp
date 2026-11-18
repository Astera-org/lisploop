(in-package #:lisploop)

;;; Batteries: library sources that ship with the kernel (batteries.lisp, library/).

(defun call-with-temporary-battery (name text thunk)
  "Call THUNK with `*battery-directory*` a fresh directory holding battery NAME, whose
source is TEXT."
  (let* ((directory (merge-pathnames (format nil "lisploop-batteries-~D-~D/"
                                             (get-universal-time) (random 1000000))
                                     #P"/tmp/"))
         (path (merge-pathnames (make-pathname :name (string-downcase (symbol-name name)) :type "lisp")
                                directory)))
    (ensure-directories-exist path)
    (unwind-protect
         (progn
           (with-open-file (stream path :direction :output :if-exists :supersede)
             (write-string text stream))
           (let ((*battery-directory* directory))
             (funcall thunk)))
      (when (probe-file path) (delete-file path))
      (sb-ext:delete-directory directory))))

(deftest every-battery-loads-and-passes-its-examples
  "Each battery in library/ loads into an empty library by itself: its entries type-check,
its solvers over finite types certify, and every example it carries replays on the VM. Its
entries carry the edge that says where they came from."
  (check (subsetp '(:arithmetic :scans :sequence-shift :sequences) (battery-names)))
  (dolist (name (battery-names))
    (with-clean-kernel-state
      (let ((entries (load-battery name)))
        (check entries)
        (check (every #'knowledge-entry-p entries))
        (check (same-set-p (mapcar #'knowledge-entry-id entries)
                           (mapcar #'second (knowledge-edges-to name :from-battery))))
        (dolist (entry entries)
          (check (eq entry (find-knowledge-entry (knowledge-entry-id entry))))
          (check (member (knowledge-entry-kind entry) '(:function :solver)))))))
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
    (raises (load-battery :sequence-shift :only '(:argmax-corr))))
  ;; Nothing is believed on the file's word: a wrong example refuses the load, a wrong type
  ;; refuses it, and a claim of uniqueness that a finite check refutes is withdrawn.
  (flet ((source (example)
           (format nil "(:battery :scratch :parameters ((?n :int)))
(:function :double ((x ?n)) ?n (+ x x) :examples (~A))
(:solver :undo-plus :inverts :+ :at 0 :over ?n :given (k c) :witness (- c k))"
                   example)))
    (with-clean-kernel-state
      (call-with-temporary-battery
       :scratch (source "((3) => 6)")
       (lambda ()
         (check (equal '(:double :undo-plus) (mapcar #'knowledge-entry-id (load-battery :scratch))))
         (check (= 10 (result (app (op :double) (lit :int 5))))))))
    (with-clean-kernel-state
      (call-with-temporary-battery
       :scratch (source "((3) => 7)")
       (lambda ()
         (raises (load-battery :scratch))
         ;; Unchecked, or at types its examples were not written for, it loads.
         (check (load-battery :scratch :check-examples-p nil))
         (check (load-battery :scratch :types (list (cons '?n (gf 5))))))))
    (with-clean-kernel-state
      (call-with-temporary-battery
       :scratch "(:battery :scratch)
(:function :wrong ((x :int)) :bool (+ x 1))"
       (lambda () (raises (load-battery :scratch))))))
  ;; 0 * z = 0 has every z: claimed unique, the solver is certified for its witness only.
  (with-clean-kernel-state
    (call-with-temporary-battery
     :scratch "(:battery :scratch)
(:solver :zero-times :inverts :* :at 1 :over (:gf 3) :given (k c)
  :witness 0 :guard (and (= k 0) (= c 0)) :unique t)"
     (lambda ()
       (let ((entry (first (load-battery :scratch))))
         (check (knowledge-evidence-current-p entry :witness))
         (check (not (knowledge-evidence-current-p entry :uniqueness)))
         (check (not (getf (knowledge-entry-metadata entry) :unique-p))))))))

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

(defun add-three-search (setup)
  "Search for the map that adds 3 to every element, in a language that names no combinator,
after SETUP has filled a clean library. Returns the job."
  (with-clean-kernel-state
    (funcall setup)
    (let* ((seq (sequence-type :int))
           (inputs (list (cons 0 seq)))
           (frame (simple-frame seq inputs '(((()) ()) (((2)) (5)) (((4 2)) (7 5)) (((-1 3 0)) (2 6 3)))))
           (language (make-language :int inputs :operators (list (op :+ :int)) :literals '(1 3)
                                                :constants (list (lit seq '()))))
           (job (start-heuristic-synthesis frame language 75)))
      (resume-synthesis job 400000 :stop-on-first t)
      (check (synthesis-job-best job))
      (check (expression-calls-operator-p (candidate-expression (synthesis-job-best job)) :map))
      job)))

(deftest carrying-the-library-costs-a-search-little
  "A search that needs one combinator pays little for the rest of the library, and the same
whatever order the library was loaded in. Two things keep it so. Lifts that the descriptors
score alike are prepared function by function, the smaller call first, so a map is tried
before scans from guessed states. And the shift metric's solver is guarded by what a shift
must look like, so a sequence that is no shift of the prediction does not run its
correlation."
  (flet ((work (job) (ledger-total (synthesis-job-ledger job)))
         (lifts (job)
           (loop for node in (synthesis-job-nodes job)
                 for proposal = (synthesis-node-proposal node)
                 when (and proposal (decomposition-lift-p proposal))
                   collect (ast-id (decomposition-decoder proposal))))
         (everything ()
           (dolist (name (battery-names)) (load-battery name))
           (dolist (prime '(5 7)) (load-battery :arithmetic :types (list (cons '?n (gf prime)))))))
    (let ((alone (add-three-search (lambda () (load-battery :sequences :only '(:map)))))
          (scans-last (add-three-search (lambda () (load-battery :sequences) (load-battery :scans))))
          (scans-first (add-three-search (lambda () (load-battery :scans) (load-battery :sequences))))
          (shift (add-three-search (lambda () (load-battery :sequences :only '(:map))
                                     (load-battery :sequence-shift))))
          (all (add-three-search #'everything)))
      ;; The map is materialized first whichever battery was registered last.
      (check (eq :map (first (lifts scans-last))))
      (check (eq :map (first (lifts scans-first))))
      (check (member :scan (lifts scans-last)))
      (check (= (work scans-last) (work scans-first)))
      ;; No correlation is run on targets that are no shift of anything.
      (check (metric-decoders (sequence-type :int) (synthesis-job-knowledge shift)))
      (check (null (assoc :heuristic-metric (ledger-counts (synthesis-job-ledger shift)))))
      ;; The whole library costs under half as much again as the one function needed.
      (dolist (job (list scans-last shift all))
        (check (< (work job) (* 3/2 (work alone)))))))
  ;; The order itself: by policy score, then function by function, each function's own
  ;; proposals and every proposal that is not a lift keeping their places.
  (with-clean-kernel-state
    (load-battery :sequences :only '(:map))
    (load-battery :scans :only '(:scan))
    (let* ((seq (sequence-type :int))
           (unary (code-type '((0 . :int)) :int))
           (binary (code-type '((0 . :int) (1 . :int)) :int))
           (inputs (list (cons 0 seq)))
           (xs (var 0 seq)))
      (flet ((lift (name decoder child-type &optional (score 0))
               (make-decomposition :name name :decoder decoder :child-id 1 :child-type child-type
                                   :lift-p t :policy-score score))
             (scan-from (state) (app (op :scan) xs (lit :int state) (var 1 binary))))
        (let* ((scan-7 (lift :scan-7 (scan-from 7) binary))
               (scan-0 (lift :scan-0 (scan-from 0) binary))
               (other (make-decomposition :name :other :decoder (var 1 seq) :child-id 1 :child-type seq))
               (map (lift :map (app (op :map) xs (var 1 unary)) unary))
               (better (lift :better (scan-from 7) binary -5))
               (ordered (order-proposals (list scan-7 scan-0 other map better) inputs)))
          (check (equal '(:better :map :scan-7 :other :scan-0)
                        (mapcar #'decomposition-name ordered))))))))
