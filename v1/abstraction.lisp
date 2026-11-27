(in-package #:lisploop)

;;; Higher-order library abstraction over function bodies, and the :function kind.

(declaim (ftype function compute-entry-descriptor-profile))

(defun normalize-trees-with-library (trees inputs rewrite-library &key (budget 100000) ledger)
  "Normalize each tree in TREES using validated REWRITE-LIBRARY (or a `knowledge-library`) in the metered VM."
  (let* ((norm-inputs (input-alist inputs))
         (library (as-rewrite-library rewrite-library
                                      :domain (infer-domain-from-types (mapcar #'cdr norm-inputs)))))
    (if (null library)
        trees
        (mapcar (lambda (tree)
                  (let ((state (start-rewriting tree norm-inputs library)))
                    (advance-rewriting state budget)
                    (charge ledger :rewriting (rewriting-work state))
                    (if (eq :complete (rewriting-status state))
                        (rewriting-value state)
                        tree)))
                trees))))

;;; Homoiconic Higher-Order Library Learning via Top-Down Anti-Unification (Phase 4 / R5)
(defstruct library-abstraction
  name
  program-inputs
  inputs
  return-type
  body
  definition
  pattern
  programs
  refactored-bodies
  refactored-definitions
  (original-bits 0 :type fixnum)
  (library-bits 0 :type fixnum)
  (refactored-call-bits 0 :type fixnum)
  (work 0 :type fixnum))

(defun library-abstraction-refactored-bits (abs)
  "Size of the corpus after refactoring: the library body plus the calls that replace the programs."
  (+ (library-abstraction-library-bits abs) (library-abstraction-refactored-call-bits abs)))

(defun library-abstraction-gain (abs)
  "Bits saved by refactoring the programs of ABS through its library body."
  (- (library-abstraction-original-bits abs) (library-abstraction-refactored-bits abs)))

(defun price-library-abstraction (abs)
  "Set the sizes of the library body of ABS and of its refactored calls from the bodies it holds."
  (setf (library-abstraction-library-bits abs)
        (body-size (library-abstraction-body abs) (library-abstraction-inputs abs))
        (library-abstraction-refactored-call-bits abs)
        (loop for call in (library-abstraction-refactored-bodies abs)
              sum (body-size call (library-abstraction-program-inputs abs))))
  abs)

(defun extract-var-literal-equality (guard)
  "When GUARD is `(= Xi 'c)` or `(= 'c Xi)`, return `(VALUES var-node lit-node)`."
  (when (app-of-p guard :=)
    (let ((lhs (second guard))
          (rhs (third guard)))
      (cond
        ((and (var-p lhs) (lit-p rhs)) (values lhs rhs))
        ((and (lit-p lhs) (var-p rhs)) (values rhs lhs))
        (t (values nil nil))))))

(defun normalize-guarded-equalities (expr)
  "In `(if (= Xi 'c) then else)` (or `(= 'c Xi)`), canonicalize the guard to `(= Xi 'c)`
and replace occurrences of `Xi` inside `then` with `'c`."
  (map-ast (lambda (node meta)
             (when (and (eq :app (ast-meta-kind meta)) (eq :if (ast-meta-id meta)))
               (destructuring-bind (operator guard then else) node
                 (multiple-value-bind (variable literal) (extract-var-literal-equality guard)
                   (when variable
                     (app operator
                          (app (first guard) variable literal)
                          (replace-subexpression then variable literal)
                          else))))))
           expr))

(defun infer-self-operator-name (expr inputs return-type &optional declared-name)
  "Determine the recursive self-call operator name in EXPR matching `(inputs -> return-type)`."
  (let* ((norm-inputs (input-alist inputs))
         (kdecl (when declared-name (canonical-op-name declared-name)))
         (expected-sig (list :fn (mapcar #'cdr norm-inputs) return-type)))
    (if (and kdecl (term-references-bound-or-self-p expr nil kdecl))
        kdecl
        (labels ((find-self (node)
                   (when (app-p node)
                     (let ((head (first node)))
                       (or (and (operator-p head)
                                (not (member (operator-name head) +operator-names+))
                                (equal (operator-type head) expected-sig)
                                (operator-name head))
                           (some #'find-self (rest node)))))))
          (or (find-self expr) kdecl)))))

(defun anti-unify-for-library (sources inputs &key self-name ledger)
  "Top-down typed anti-unification for higher-order :code library learning.
Preserves shared recursive control spines (:if guards, self-calls, and constructors
wrapping self-calls) while collapsing diverging element/step computations into expression
holes suitable for positional :code abstraction."
  (let* ((norm-inputs (input-alist inputs))
         (bound-vars (mapcar #'car norm-inputs))
         (eff-self (when self-name (canonical-op-name self-name))))
    (anti-unify sources norm-inputs ledger
                :operator-holes-p nil
                :keep-application-p
                (lambda (arguments terms)
                  (let ((op-name (ast-id (first terms)))
                        (shared (remove-if #'hole-p arguments))) ; arguments with common structure
                    (or (and (eq op-name :if) (not (hole-p (first arguments))))
                        (and eff-self (eq op-name eff-self) shared)
                        (some (lambda (argument)
                                (term-references-bound-or-self-p argument nil eff-self))
                              shared)
                        (and shared
                             (notany (lambda (term)
                                       (term-references-bound-or-self-p term bound-vars eff-self))
                                     terms))))))))

(defun call-with-temporary-function-names (temp-names thunk)
  "Ensure TEMP-NAMES are registered at the front of `*registered-function-names*` during THUNK
(matching `:fa`/`:fb` opcode bit width) and remove any newly added temporary names afterward."
  (let ((added nil))
    (dolist (name (reverse temp-names))
      (let ((kname (canonical-op-name name)))
        (unless (member kname *registered-function-names*)
          (push kname added)
          (push kname *registered-function-names*))))
    (unwind-protect
         (funcall thunk)
      (dolist (kname added)
        (setf *registered-function-names*
              (remove kname *registered-function-names* :test #'eq))))))

(defun finalize-library-abstraction (abs target-name &key register-p)
  "Rename the candidate combinator operator in ABS to TARGET-NAME, optionally
registering it in `*function-definitions*` via `define-function`."
  (let ((ktarget (canonical-op-name target-name))
        (cand-name (library-abstraction-name abs))
        (cand-body (library-abstraction-body abs))
        (lib-inputs (library-abstraction-inputs abs))
        (return-type (library-abstraction-return-type abs)))
    (flet ((retarget (target-op body definition)
             (setf (library-abstraction-name abs) ktarget
                   (library-abstraction-body abs) body
                   (library-abstraction-definition abs) definition
                   (library-abstraction-refactored-bodies abs)
                   (mapcar (lambda (call) (rename-function-calls call cand-name target-op))
                           (library-abstraction-refactored-bodies abs)))
             (price-library-abstraction abs)))
      (cond
        (register-p
         (let ((def (define-function ktarget lib-inputs return-type
                      (lambda (self) (rename-function-calls cand-body cand-name self)))))
           (retarget (op ktarget) (function-definition-body def) def)))
        ((eq ktarget cand-name) abs)
        (t
         ;; A dry run: the target name is registered and its definition hidden only
         ;; for the dynamic extent of the renaming.
         (let* ((lib-ctype (code-type lib-inputs return-type))
                (saved-def (gethash ktarget *function-definitions*))
                (pool-key (list :op ktarget lib-ctype))
                (had-pool-key-p (nth-value 1 (gethash pool-key *typed-symbol-pool*)))
                (*registered-function-names*
                  (if (member ktarget *registered-function-names*)
                      *registered-function-names*
                      (append *registered-function-names* (list ktarget)))))
           (unwind-protect
                (progn
                  (remhash ktarget *function-definitions*)
                  (let ((target-op (op ktarget lib-ctype)))
                    (retarget target-op (rename-function-calls cand-body cand-name target-op) nil)))
             (if saved-def
                 (setf (gethash ktarget *function-definitions*) saved-def)
                 (remhash ktarget *function-definitions*))
             (unless had-pool-key-p
               (remhash pool-key *typed-symbol-pool*)))))))))

(defun abstraction-parameters (pattern substitutions norm-inputs ledger)
  "The parameters that the holes of PATTERN add to a library combinator, as three lists in
hole order: the (id . type) of each parameter, the (hole-id . expression) that stands for
the hole in the library body, and the arguments each program passes for it. Fillers that
mention neither an input nor the recursive call are passed as first-order values. Other
fillers are closed over a shared subterm cover into :code literals, which the library body
evaluates on that cover. Returns nil unless every hole can be abstracted and one needs code."
  (let ((bound-vars (mapcar #'car norm-inputs))
        (next-id (next-child-id norm-inputs))
        (code-p nil)
        (parameters nil) (replacements nil) (arguments nil))
    (flet ((add-parameter (hole-id type replacement fillers)
             (push (cons next-id type) parameters)
             (push (cons hole-id (funcall replacement (var next-id type))) replacements)
             (push fillers arguments)
             (incf next-id)))
      (loop for (hole-id . sort) in (pattern-holes pattern)
            for fillers = (mapcar (lambda (substitution) (cdr (assoc hole-id substitution)))
                                  substitutions)
            do (cond
                 ((or (function-sort-p sort) (some #'null fillers))
                  (return-from abstraction-parameters nil))
                 ((notany (lambda (filler)
                            (term-references-bound-or-self-p filler bound-vars :__au_self__))
                          fillers)
                  (add-parameter hole-id sort #'identity fillers))
                 (t
                  (let ((cover (shared-subterm-cover fillers norm-inputs :bound-vars bound-vars
                                                                         :self-name :__au_self__))
                        (common-type nil) ; the one code type of all the fillers
                        (literals nil))
                    (unless cover
                      (return-from abstraction-parameters nil))
                    (dolist (filler fillers)
                      (multiple-value-bind (literal type)
                          (abstract-over-subterms filler cover norm-inputs ledger
                                                  :self-name :__au_self__)
                        (unless (and literal (or (null common-type) (equal common-type type)))
                          (return-from abstraction-parameters nil))
                        (setf common-type type)
                        (push literal literals)))
                    (setf code-p t)
                    (add-parameter hole-id common-type
                                   (lambda (parameter)
                                     (term `(code-eval ,parameter ,@cover)))
                                   (nreverse literals))))))
      (when code-p
        (values (nreverse parameters) (nreverse replacements) (nreverse arguments))))))

(defun abstract-function-bodies (bodies inputs return-type
                                 &key self-names program-names (target-name :fa)
                                      rewrite-library register-p ledger)
  "Anti-unify recursive BODIES of signature `(inputs -> return-type)` after normalizing
self-calls (and optional REWRITE-LIBRARY), factor diverging subexpressions into first-order
value parameters or closed positional `:code` literals via `shared-subterm-cover` +
`abstract-over-subterms`, and return a `library-abstraction` (or NIL when no valid
recursive combinator exists)."
  (let* ((ledger (or ledger (make-ledger)))
         (start-work (ledger-total ledger))
         (norm-inputs (input-alist inputs)))
    (when (and (>= (length bodies) 2)
               (every (lambda (body) (equal return-type (expression-type body norm-inputs))) bodies))
      (let* ((inferred-snames
               (loop for body in bodies
                     for i from 0
                     collect (infer-self-operator-name
                              body norm-inputs return-type
                              (if (consp self-names) (nth i self-names) self-names))))
             (candidate
               (call-with-temporary-function-names
                (remove-duplicates (append '(:__au_self__ :__lib_cand__) (remove nil inferred-snames)))
                (lambda ()
                  (let ((active-bodies (if rewrite-library
                                           (normalize-trees-with-library bodies norm-inputs rewrite-library
                                                                         :ledger ledger)
                                           bodies))
                        (canon-self-op (op :__au_self__ (code-type norm-inputs return-type))))
                    (abstract-normalized-bodies
                     (loop for body in active-bodies
                           for sname in inferred-snames
                           collect (normalize-guarded-equalities
                                    (rename-function-calls body sname canon-self-op)))
                     bodies norm-inputs return-type program-names ledger))))))
        (when candidate
          (setf (library-abstraction-work candidate) (- (ledger-total ledger) start-work))
          (finalize-library-abstraction candidate target-name :register-p register-p))))))

(defun abstract-normalized-bodies (norm-bodies bodies norm-inputs return-type program-names ledger)
  "The candidate `library-abstraction` named :__lib_cand__ for BODIES, given NORM-BODIES, the
same bodies with their recursive calls renamed to :__au_self__. Returns nil unless every body
recurses, the bodies share structure, every difference can be made a parameter, and the
resulting combinator is recursive and total given total code arguments."
  (when (every (lambda (body) (term-references-bound-or-self-p body nil :__au_self__)) norm-bodies)
    (multiple-value-bind (pattern substitutions)
        (anti-unify-for-library norm-bodies norm-inputs :self-name :__au_self__ :ledger ledger)
      (multiple-value-bind (new-params hole-replacements call-arguments)
          (and (not (hole-p pattern))
               (abstraction-parameters pattern substitutions norm-inputs ledger))
        (when new-params
          (let* ((lib-inputs (append (copy-tree norm-inputs) new-params))
                 (cand-op (op :__lib_cand__ (code-type lib-inputs return-type)))
                 (lib-body (rename-function-calls
                            (instantiate pattern hole-replacements :hole) :__au_self__ cand-op
                            (loop for (id . type) in new-params collect (var id type)))))
            (charge ledger :construction (syntax-work lib-body))
            (when (and (equal return-type (expression-type lib-body lib-inputs))
                       (term-references-bound-or-self-p lib-body nil :__lib_cand__)
                       (multiple-value-bind (total-p conditional-params)
                           (analyze-function-body-totality :__lib_cand__ lib-inputs lib-body)
                         (or total-p conditional-params)))
              (let ((program-vars (loop for (id . type) in norm-inputs collect (var id type))))
                (price-library-abstraction
                 (make-library-abstraction
                  :name :__lib_cand__
                  :program-inputs (copy-tree norm-inputs)
                  :inputs lib-inputs
                  :return-type (copy-tree return-type)
                  :body lib-body
                  :pattern pattern
                  :programs (or (copy-list program-names)
                                (loop for i below (length bodies) collect i))
                  :refactored-bodies
                  (loop for i below (length bodies)
                        for call = (apply #'app cand-op
                                          (append program-vars
                                                  (mapcar (lambda (per-program) (nth i per-program))
                                                          call-arguments)))
                        do (charge ledger :construction (syntax-work call))
                        collect call)
                  :original-bits (loop for body in bodies sum (body-size body norm-inputs))))))))))))

(defstruct (corpus-entry (:constructor make-corpus-entry (index definition self-name body)))
  "A function of the corpus that `discover-library-abstractions` works on: its position, its
`function-definition`, the name its body recurses through, and its body, which may be
replaced by a normal form."
  index definition self-name body)

(defun normalize-corpus-definition-entry (entry index)
  "Normalize a `function-definition`, function name symbol, or plist
`(:name name :inputs inputs :return-type return-type :body body :self-name sname)` into a
`corpus-entry` at INDEX."
  (cond
    ((function-definition-p entry)
     (let ((body (function-definition-body entry)))
       (make-corpus-entry index entry
                          (infer-self-operator-name body (function-definition-inputs entry)
                                                    (function-definition-return-type entry)
                                                    (function-definition-name entry))
                          body)))
    ((and (symbolp entry) (not (null entry)))
     (let ((def (find-function-definition entry)))
       (assert def () "Unknown function definition ~S" entry)
       (normalize-corpus-definition-entry def index)))
    ((consp entry)
     (destructuring-bind (&key name inputs return-type body self-name &allow-other-keys) entry
       (let* ((name (canonical-op-name (or name (de-novo-function-name index))))
              (inputs (copy-tree (input-alist inputs)))
              (return-type (copy-tree (or return-type (expression-type body inputs)))))
         (make-corpus-entry index
                            (%make-function-definition :name name :inputs inputs
                                                       :return-type return-type :body body
                                                       :total-p (provably-total-p body))
                            (infer-self-operator-name body inputs return-type (or self-name name))
                            body))))
    (t (error "Invalid corpus definition entry: ~S" entry))))

(defun greedy-subset-search (items evaluate key improves-p better-p)
  "Search the subsets of ITEMS for candidates. EVALUATE maps a subset, sorted by KEY, to a
candidate or nil, and is called at most once per subset. The whole of ITEMS is tried, then
every pair; a pair with a candidate grows one item at a time, each time by the BETTER-P one
of the extensions that IMPROVES-P on it, until none does. Both predicates compare
(subset . candidate) pairs. Returns such a pair for every candidate found, latest first."
  (let ((seen (make-hash-table :test #'equal))
        (found nil))
    (flet ((try (subset)
             (let* ((ordered (sort (copy-list subset) #'< :key key))
                    (id (mapcar key ordered)))
               (multiple-value-bind (cached present-p) (gethash id seen)
                 (if present-p
                     cached
                     (let* ((candidate (funcall evaluate ordered))
                            (pair (and candidate (cons ordered candidate))))
                       (when pair (push pair found))
                       (setf (gethash id seen) pair)))))))
      (try items)
      (loop for (a . others) on items do
        (dolist (b others)
          (let ((current (try (list a b))))
            (loop while current do
              (let ((best nil))         ; the best improving extension of CURRENT by one item
                (dolist (c items)
                  (unless (member c (car current) :test #'eq)
                    (let ((grown (try (cons c (car current)))))
                      (when (and grown (funcall improves-p grown current)
                                 (or (null best) (funcall better-p grown best)))
                        (setf best grown)))))
                (setf current best))))))
      found)))

(defun discover-library-abstractions (definitions &key (register-p t) (min-gain 0)
                                                       library-names rewrite-library ledger)
  "Discover higher-order recursive library combinators (:map, :foldr, ...) across DEFINITIONS
using top-down homoiconic anti-unification (`anti-unify-for-library`) and positional `:code`
extraction (`shared-subterm-cover` + `abstract-over-subterms`).
Accepts a candidate combinator only when it strictly improves description length above MIN-GAIN:
  gain = sum_i S(p_i) - (S(L) + sum_i S(p_i | L)) > min-gain.
Returns `(VALUES accepted-abstractions refactored-definitions all-candidates ledger)`."
  (let* ((ledger (or ledger (make-ledger)))
         (entries (loop for definition in definitions
                        for index from 0
                        collect (normalize-corpus-definition-entry definition index)))
         ;; Candidates are found as (subset . abstraction) pairs and ranked by these keys.
         (rank (list (list :desc (lambda (found) (library-abstraction-gain (cdr found))))
                     (list :desc (lambda (found) (length (car found))))
                     (lambda (found) (library-abstraction-library-bits (cdr found)))))
         (all-candidates nil)
         (accepted nil))
    (flet ((inputs (entry) (function-definition-inputs (corpus-entry-definition entry)))
           (return-type (entry) (function-definition-return-type (corpus-entry-definition entry)))
           (gain (found) (library-abstraction-gain (cdr found))))
      ;; 1. Optionally normalize corpus bodies once upfront with REWRITE-LIBRARY
      (when rewrite-library
        (call-with-temporary-function-names
         (remove-duplicates (loop for entry in entries
                                  for sname = (corpus-entry-self-name entry)
                                  when sname collect (canonical-op-name sname)))
         (lambda ()
           (dolist (entry entries)
             (setf (corpus-entry-body entry)
                   (first (normalize-trees-with-library (list (corpus-entry-body entry))
                                                        (inputs entry) rewrite-library
                                                        :ledger ledger)))))))
      ;; 2. Within each signature group, in corpus order, accept the best candidate over the
      ;;    remaining functions until none clears MIN-GAIN.
      (dolist (signature (remove-duplicates
                          (mapcar (lambda (entry) (cons (inputs entry) (return-type entry))) entries)
                          :test #'equal :from-end t))
        (let ((remaining (remove-if-not (lambda (entry)
                                          (and (equal (car signature) (inputs entry))
                                               (equal (cdr signature) (return-type entry))))
                                        entries)))
          (loop while (>= (length remaining) 2) do
            (let* ((found (greedy-subset-search
                           remaining
                           (lambda (subset)
                             (abstract-function-bodies
                              (mapcar #'corpus-entry-body subset) (car signature) (cdr signature)
                              :self-names (mapcar #'corpus-entry-self-name subset)
                              :program-names (mapcar (lambda (entry)
                                                       (function-definition-name
                                                        (corpus-entry-definition entry)))
                                                     subset)
                              :target-name :__lib_cand__
                              :ledger ledger))
                           #'corpus-entry-index
                           (lambda (grown current) (> (gain grown) (gain current)))
                           (lambda (a b) (apply #'lex< a b rank))))
                   (best (apply #'best-by found rank)))
              (setf all-candidates (append (mapcar #'cdr found) all-candidates))
              (unless (and best (> (gain best) min-gain))
                (return))
              (push best accepted)
              (setf remaining (set-difference remaining (car best) :test #'eq)))))))
    (setf accepted (nreverse accepted))
    ;; 3. Assign library names (:fa, :fb, ... or LIBRARY-NAMES), register when REGISTER-P,
    ;;    and construct the refactored definitions corpus.
    (let ((refactored (mapcar (lambda (entry) (copy-function-definition (corpus-entry-definition entry)))
                              entries)))
      (loop for (subset . candidate) in accepted
            for index from 0
            do (finalize-library-abstraction
                candidate
                (canonical-op-name (or (nth index library-names) (de-novo-function-name index)))
                :register-p register-p)
               (setf (library-abstraction-refactored-definitions candidate)
                     (loop for entry in subset
                           for body in (library-abstraction-refactored-bodies candidate)
                           for definition = (nth (corpus-entry-index entry) refactored)
                           do (setf (function-definition-body definition) body
                                    (function-definition-oracle-table definition) nil
                                    (function-definition-total-p definition) (provably-total-p body)
                                    (function-definition-conditional-code-params definition) nil)
                           collect definition)))
      (values (mapcar #'cdr accepted) refactored (nreverse all-candidates) ledger))))

(defun consolidate-library-functions (library &key
                                                entries
                                                (ledger (make-ledger))
                                                (min-gain 0)
                                                (register-p t)
                                                library-names
                                                rewrite-library)
  "Discover MDL-positive higher-order combinators across :FUNCTION entries in LIBRARY,
recording :REFACTORED-BY and :ABSTRACTS relational edges and refreshing descriptors."
  (let* ((fn-entries (or entries (knowledge-entries-of-kind :function library)))
         (fdefs (loop for e in fn-entries
                      for fdef = (or (gethash (knowledge-entry-id e) (knowledge-library-functions library))
                                     (find-function-definition (knowledge-entry-id e)))
                      when (and fdef
                                (function-definition-body fdef)
                                (null (function-definition-oracle-table fdef))
                                ;; Exclude already-abstracted higher-order combinators and functions already refactored
                                (not (some (lambda (spec) (code-type-p (cdr spec)))
                                           (function-definition-inputs fdef)))
                                (null (knowledge-edges-from e :refactored-by library)))
                        collect fdef)))
    (when (>= (length fdefs) 2)
      (multiple-value-bind (accepted refactored-defs all-candidates updated-ledger)
          (discover-library-abstractions fdefs
                                         :ledger ledger
                                         :min-gain min-gain
                                         :register-p register-p
                                         :library-names library-names
                                         :rewrite-library (or rewrite-library library))
        (declare (ignore all-candidates))
        (when (and register-p accepted)
          ;; Redefining a refactored function re-installs its entry, which records the
          ;; :REFACTORED-BY and :ABSTRACTS edges and the code it passes to the combinator.
          (loop for orig-def in fdefs
                for ref-def in refactored-defs
                for fname = (function-definition-name orig-def)
                unless (equal (function-definition-body orig-def)
                              (function-definition-body ref-def))
                  do (define-function fname
                                      (function-definition-inputs ref-def)
                                      (function-definition-return-type ref-def)
                                      (function-definition-body ref-def)))
          (dolist (cand accepted)
            (let ((lib-entry (find-knowledge-entry (library-abstraction-name cand) library)))
              (when lib-entry
                (setf (knowledge-entry-gain lib-entry) (library-abstraction-gain cand)
                      (knowledge-entry-work lib-entry) (library-abstraction-work cand))))))
        (values accepted refactored-defs updated-ledger)))))

(defun combinator-call-code-args (call)
  "The bodies of the code literals that CALL passes to its operator."
  (when (app-p call)
    (loop for argument in (rest call)
          when (and (lit-p argument) (code-type-p (ast-type argument)))
            collect (ast-value argument))))

(defun sync-function-definition (entry)
  "Make the function table agree with the :function ENTRY and return the definition."
  (let* ((kname (knowledge-entry-id entry))
         (inputs (knowledge-entry-inputs entry))
         (target (knowledge-entry-target entry))
         (body (knowledge-entry-expression entry))
         (oracle (getf (knowledge-entry-metadata entry) :oracle-table))
         (existing (find-function-definition kname)))
    (if (and existing
             (equal inputs (function-definition-inputs existing))
             (equal target (function-definition-return-type existing))
             (equal body (function-definition-body existing))
             (equal oracle (function-definition-oracle-table existing)))
        existing
        (let ((*syncing-knowledge-library-p* t))
          (define-function kname inputs target body :oracle-table oracle)))))

(defun record-combinator-call (entry library ledger)
  "When the body of the :function ENTRY is a call passing code to another library function,
link the two with :REFACTORED-BY and :ABSTRACTS edges, keep the code as the entry's auxiliary
code if there is just one, and refresh the descriptors of the function called."
  (let* ((kname (knowledge-entry-id entry))
         (body (knowledge-entry-expression entry))
         (comb-name (and (app-p body) (ast-id body)))
         (comb-entry (and (not (eq comb-name kname)) (find-knowledge-entry comb-name library)))
         (code-args (combinator-call-code-args body)))
    (when (and comb-entry (eq :function (knowledge-entry-kind comb-entry)) code-args)
      (when (and (null (rest code-args)) (null (knowledge-entry-auxiliary-code entry)))
        (setf (knowledge-entry-auxiliary-code entry) (first code-args)))
      (let ((already-abstracts-p
              (some (lambda (edge) (member kname (rest edge)))
                    (knowledge-edges-from comb-entry :abstracts library))))
        (add-knowledge-edge entry :refactored-by comb-name)
        (add-knowledge-edge comb-entry :abstracts kname)
        (unless already-abstracts-p
          (compute-entry-descriptor-profile comb-entry library ledger))))))

(define-knowledge-kind :function
  (:priority 10)
  (:validate (entry library)
    (declare (ignore library))
    (when (knowledge-entry-expression entry)
      ;; A recursive body calls the entry's own name, which may not be registered yet.
      (let* ((kname (knowledge-entry-id entry))
             (*registered-function-names*
               (if (or (defined-function-p kname) (member kname *registered-function-names*))
                   *registered-function-names*
                   (append *registered-function-names* (list kname)))))
        (assert-entry-expression-type entry))))
  (:install (entry library ledger)
    (sync-function-definition entry)
    (record-combinator-call entry library ledger)
    (unless (knowledge-entry-descriptor-profile entry)
      (compute-entry-descriptor-profile entry library ledger)))
  (:consolidate (entries library ledger)
    (mapcar #'library-abstraction-name
            (consolidate-library-functions library :entries entries :ledger ledger
                                           :min-gain (getf *consolidation-options* :min-gain 0)
                                           :library-names (getf *consolidation-options* :library-names)))))
