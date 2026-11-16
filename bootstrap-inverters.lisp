(in-package #:lisploop)

;;; Supplied structural inverter proposals. These constructors are not learned
;;; theories; generated witnesses require independent evidence or forward replay.

(defun map-like-combinator-signature (fdef)
  "If FDEF is a higher-order list-mapping combinator taking `(X0 : (:seq elem))` and
`(X1 : (:code ((0 . elem)) elem))` and returning `(:seq elem)` via `function-body-length-preserving-p`,
return `(VALUES elem-type seq-type code-type)`."
  (when (and (function-definition-p fdef)
             (function-definition-body fdef)
             (= 2 (length (function-definition-inputs fdef))))
    (let* ((inps (function-definition-inputs fdef))
           (t0 (cdr (first inps)))
           (t1 (cdr (second inps)))
           (ret (function-definition-return-type fdef)))
      (when (and (seq-type-p t0)
                 (equal t0 ret)
                 (code-type-p t1)
                 (= 1 (length (code-inputs t1)))
                 (eql 0 (caar (code-inputs t1)))
                 (equal (second t0) (cdar (code-inputs t1)))
                 (equal (second t0) (code-sort t1))
                 (function-body-length-preserving-p (function-definition-name fdef)
                                                    (function-definition-body fdef)))
        (values (second t0) t0 t1)))))

(defun build-functorial-map-inverter (map-name elem-type seq-type src-ctype elem-solver)
  "Construct a second-order VM guard, witness, and code-inverter AST for inverting
`(:map z 'code) = c` at position 0 using binary element solver ELEM-SOLVER. Also returns
the name of the element operator and the position ELEM-SOLVER solves it at."
  (let* ((meta (knowledge-entry-metadata elem-solver))
         (op-name (operator-name (sexp->ast (getf meta :operator))))
         (elem-pos (getf meta :position))
         (pat-ctype (code-type (list (cons 0 elem-type) (cons 1 elem-type)) elem-type))
         (pattern (lit pat-ctype (app (op op-name elem-type) (var 0 elem-type) (var 1 elem-type))))
         (known-code (var 0 src-ctype))
         (element (lit src-ctype (var 0 elem-type))) ; the code that returns its argument
         (b0 (term `(code-bind ,pattern ,known-code 0) src-ctype))
         (b1 (term `(code-bind ,pattern ,known-code 1) src-ctype))
         (var-part (if (zerop elem-pos) b0 b1))
         (const-part (if (zerop elem-pos) b1 b0))
         (inverse (term `(code-subst ,(lit pat-ctype (knowledge-entry-expression elem-solver))
                                     (tuple ,const-part ,element))
                        src-ctype)))
    (values (term `(if (code-match ,pattern ,known-code)
                       ,(bool-and (term `(= ,var-part ,element))
                                  (bool-and (term `(= (code-kind ,const-part) 1))
                                            (term `(code-total ,inverse))))
                       nil))
            (app (op map-name) (var 1 seq-type) inverse)
            inverse op-name elem-pos)))

(defun build-pointwise-sequence-inverter (map-name elem-type seq-type src-ctype elem-solver)
  "Witness and guard that solve `(fn xs p) = ys` for xs from `(p ys)`, where fn applies a
binary scalar operator to each element of xs and p, and ELEM-SOLVER inverts that operator
at the element's position: MAP-NAME maps the element witness, with p bound, over ys."
  (let* ((bin-ctype (code-type (list (cons 0 elem-type) (cons 1 elem-type)) elem-type))
         (parameter (var 0 elem-type))
         ;; The element witness reads (known target); as mapped code it reads (target known).
         (swapped (instantiate (knowledge-entry-expression elem-solver)
                               (list (cons 0 (var 1 elem-type)) (cons 1 (var 0 elem-type))) :var))
         (inverse (term `(code-subst ,(lit bin-ctype swapped)
                                     (tuple ,(lit src-ctype (var 0 elem-type)) ,parameter))
                        src-ctype))
         (guard (knowledge-entry-guard elem-solver)))
    (values (app (op map-name) (var 1 seq-type) inverse)
            ;; A scalar guard that reads the target would have to hold of every output
            ;; element; it is omitted, which is one reason the result stays a conjecture.
            (if (member 1 (free-vars guard)) (lit :bool t) guard))))

(defun build-pointwise-parameter-inverter (seq-type elem-solver)
  "Witness and guard that solve `(fn xs p) = ys` for the scalar p from `(xs ys)`: ELEM-SOLVER,
which inverts the scalar operator at the parameter's position, applied to the heads of xs
and ys when both are nonempty and of equal length."
  (let* ((xs (var 0 seq-type))
         (ys (var 1 seq-type))
         (heads (list (cons 0 (term `(at ,xs 0))) (cons 1 (term `(at ,ys 0))))))
    (values (instantiate (knowledge-entry-expression elem-solver) heads :var)
            (term `(if (< 0 (length ,xs))
                       (if (= (length ,xs) (length ,ys))
                           ,(instantiate (knowledge-entry-guard elem-solver) heads :var)
                           nil)
                       nil)))))

(defun extract-pointwise-binary-step (src-entry elem-type seq-type)
  "If `:function` entry SRC-ENTRY has signature `((0 . seq-type) (1 . elem-type)) -> seq-type`
and applies a binary scalar operator `(op elem param)` or `(op param elem)` to each element
of `X0` with parameter `X1` (either via `:map` + `:code-subst` or direct structural recursion),
return (VALUES op-name elem-pos param-pos)."
  (let ((expr (knowledge-entry-expression src-entry))
        (aux (knowledge-entry-auxiliary-code src-entry))
        (v0 (var 0 elem-type))
        (v1 (var 1 elem-type)))
    (flet ((binary-step (step element parameter)
             (when (and (app-p step) (operator-p (first step)) (= 2 (length (rest step))))
               (cond ((and (equal (second step) element) (equal (third step) parameter))
                      (list (operator-name (first step)) 0 1))
                     ((and (equal (second step) parameter) (equal (third step) element))
                      (list (operator-name (first step)) 1 0))))))
      (when (and (equal (knowledge-entry-inputs src-entry)
                        (list (cons 0 seq-type) (cons 1 elem-type)))
                 (equal seq-type (knowledge-entry-target src-entry)))
        (values-list
         (or (and aux (binary-step aux v0 v1))
             (and (app-p expr) (= 2 (length (rest expr)))
                  (app-of-p (third expr) :code-subst)
                  (lit-p (second (third expr)))
                  (binary-step (ast-value (second (third expr))) v0 v1))
             (and (app-of-p expr :if)
                  (app-of-p (fourth expr) :cons)
                  (binary-step (second (fourth expr)) (term `(at ,(var 0 seq-type) 0)) v1))))))))

(defun induce-involution-solvers (library &key (ledger (make-ledger)))
  "Scan `:law` entries in LIBRARY for involution identities `(= (f (f X0)) X0)` over a unary
function or operator `f : tau -> tau` and induce `:unary` `:solver` entries `(f X0)`."
  (let ((induced nil))
    (dolist (law-entry (knowledge-entries-of-kind :law library) (nreverse induced))
      (let ((eq-expr (knowledge-entry-expression law-entry))
            (inputs (knowledge-entry-inputs law-entry)))
        (when (and (= 1 (length inputs)) (app-of-p eq-expr :=))
          (let* ((tau (cdar inputs))
                 (x0 (var (caar inputs) tau))
                 (nested (cond ((equal (third eq-expr) x0) (second eq-expr))
                               ((equal (second eq-expr) x0) (third eq-expr)))))
            (when (and nested
                       (app-p nested)
                       (operator-p (first nested))
                       (= 1 (length (rest nested)))
                       (let ((inner (second nested)))
                         (and (app-p inner)
                              (equal (first nested) (first inner))
                              (= 1 (length (rest inner)))
                              (equal (second inner) x0))))
              (let* ((fn-op (first nested))
                     (solver-id (keyword-id "~A/INVOLUTION-INVERTER" (operator-name fn-op)))
                     (cert-p (knowledge-evidence-current-p law-entry :equivalence))
                     (guard (instantiate (knowledge-entry-guard law-entry)
                                         (list (cons (caar inputs) (var 0 tau))) :var)))
                (unless (find-knowledge-entry solver-id library)
                  (push (register-knowledge-solver
                         fn-op :id solver-id :library library
                         :domain (or (knowledge-entry-domain law-entry) tau)
                         :inputs (list (cons 0 tau)) :target tau :position :unary
                         :witness (app fn-op (var 0 tau)) :guard guard
                         :certified-p cert-p
                         :unique-p (and cert-p (equal guard (lit :bool t)))
                         :edges (list (list :induced-by (knowledge-entry-id law-entry)))
                         :ledger ledger)
                        induced))))))))))

(defun induce-combinator-solvers (library ledger map-name elem-type seq-type src-ctype elem-solvers)
  "Register the `:functor` theory of the map-like combinator MAP-NAME and the solvers that
lift ELEM-SOLVERS, the binary scalar solvers over ELEM-TYPE, through it. Returns the new
entries in registration order."
  (let ((functor-id (keyword-id "~A/FUNCTOR" map-name))
        (map-inputs (list (cons 0 src-ctype) (cons 1 seq-type)))
        (induced nil))
    (labels
        ((new-p (id) (null (find-knowledge-entry id library)))
         (induce (id function esolver &rest fields)
           ;; Shape recognition and scalar certification do not certify a sequence
           ;; transformation: the scalar guard and the combinator's semantics need proofs.
           ;; So every lifted solver is registered as a conjecture, which keeps forward
           ;; verification and the fallback lane.
           (push (apply #'register-knowledge-solver function
                        :id id :library library :ledger ledger
                        :unique-p (getf (knowledge-entry-metadata esolver) :unique-p t)
                        :edges (list (list :induced-by functor-id (knowledge-entry-id esolver)))
                        fields)
                 induced))
         (element-solver (operator position)
           (find-if (lambda (solver)
                      (let ((meta (knowledge-entry-metadata solver)))
                        (and (eq operator (getf meta :operator-name))
                             (eql position (getf meta :position)))))
                    elem-solvers))
         (map-inverter (esolver)
           "Invert `(MAP-NAME z 'code) = c` for z, then every unary function known to be
MAP-NAME applied to a fixed step."
           (multiple-value-bind (guard witness inverse op-name elem-pos)
               (build-functorial-map-inverter map-name elem-type seq-type src-ctype esolver)
             (let ((id (keyword-id "~A/INVERT-~A-~D" map-name op-name elem-pos)))
               (when (new-p id)
                 (induce id map-name esolver :domain elem-type :inputs map-inputs
                         :target seq-type :position 0 :witness witness :guard guard)))
             (dolist (edge (knowledge-edges-from map-name :abstracts library))
               (dolist (src-fn (rest edge))
                 (refactored-inverter src-fn esolver guard inverse)))))
         (refactored-inverter (src-fn esolver guard inverse)
           "Invert the unary SRC-FN, whose auxiliary code is its step under MAP-NAME, by
mapping the step's inverse; GUARD and INVERSE are the map inverter's, run on that step."
           (let* ((src-entry (find-knowledge-entry src-fn library))
                  (step (and src-entry
                             (= 1 (length (knowledge-entry-inputs src-entry)))
                             (knowledge-entry-auxiliary-code src-entry)))
                  (id (keyword-id "~A/INVERTER" src-fn)))
             (when (and step (new-p id))
               (let ((grun (evaluate guard map-inputs (list step nil) :ledger ledger)))
                 (when (and (eq :value (evaluation-status grun)) (evaluation-value grun))
                   (let ((irun (evaluate inverse (list (cons 0 src-ctype)) (list step)
                                         :ledger ledger)))
                     (when (eq :value (evaluation-status irun))
                       (induce id src-fn esolver :domain elem-type
                               :inputs (list (cons 0 seq-type)) :target seq-type :position :unary
                               :witness (app (op map-name) (var 0 seq-type)
                                             (lit src-ctype (evaluation-value irun)))))))))))
         (pointwise-inverters (src-entry)
           "Invert `(fn xs param) = ys`, where fn applies a binary scalar operator to each
element of xs and param, for the sequence xs and for the scalar param."
           (multiple-value-bind (operator elem-pos param-pos)
               (extract-pointwise-binary-step src-entry elem-type seq-type)
             (when operator
               (let* ((src-fn (knowledge-entry-id src-entry))
                      (seq-solver (element-solver operator elem-pos))
                      (seq-id (keyword-id "~A/INVERT-0" src-fn))
                      (param-solver (element-solver operator param-pos))
                      (param-id (keyword-id "~A/INVERT-1" src-fn)))
                 (when (and seq-solver (new-p seq-id))
                   (multiple-value-bind (witness guard)
                       (build-pointwise-sequence-inverter map-name elem-type seq-type src-ctype
                                                          seq-solver)
                     (induce seq-id src-fn seq-solver :domain seq-type
                             :inputs (list (cons 0 elem-type) (cons 1 seq-type)) :target seq-type
                             :position 0 :witness witness :guard guard)))
                 (when (and param-solver (new-p param-id))
                   (multiple-value-bind (witness guard)
                       (build-pointwise-parameter-inverter seq-type param-solver)
                     (induce param-id src-fn param-solver :domain seq-type
                             :inputs (list (cons 0 seq-type) (cons 1 seq-type)) :target elem-type
                             :position 1 :witness witness :guard guard))))))))
      (when (new-p functor-id)
        (push (register-knowledge-entry
               (make-knowledge-entry
                :id functor-id :kind :functor :domain elem-type
                :inputs map-inputs :target seq-type
                :expression (app (op map-name) (var 1 seq-type) (var 0 src-ctype))
                :status :conjecture
                :metadata (list :origin :bootstrap-structural :combinator map-name)
                :edges (list (list :lifts-inverter map-name))
                :library library)
               :library library :ledger ledger)
              induced))
      ;; Registration order is the order propagation tries rules in: the pointwise solvers
      ;; follow the first element solver's inverters and precede those of the rest.
      (map-inverter (first elem-solvers))
      (mapc #'pointwise-inverters (knowledge-entries-of-kind :function library))
      (mapc #'map-inverter (rest elem-solvers))
      (nreverse induced))))

(defun induce-functorial-solvers (library &key (ledger (make-ledger)))
  "Traverse higher-order `:abstracts` / `:refactored-by` edges, element `:solver` entries, and
involution `:law` entries in LIBRARY to induce second-order `:functor` theories and concrete
`:solver` propagators for:
1. Higher-order combinators `(map z 'code) = c` (using `:code-match`, `:code-bind`, `:code-subst` in the VM),
2. First-order unary functions refactored through those combinators `(fn z) = c`,
3. Parameterized binary sequence functions `(fn xs param) = c` at both position 0 (`xs`) and position 1 (`param`), and
4. Involution functions satisfying `(= (f (f X0)) X0)`."
  (let ((induced nil))
    (dolist (fn-entry (knowledge-entries-of-kind :function library))
      (let ((map-name (knowledge-entry-id fn-entry)))
        (multiple-value-bind (elem-type seq-type src-ctype)
            (map-like-combinator-signature
             (or (gethash map-name (knowledge-library-functions library))
                 (find-function-definition map-name)))
          (let ((elem-solvers
                  (and elem-type
                       (remove-if-not
                        (lambda (s)
                          (and (equal elem-type (knowledge-entry-domain s))
                               (equal elem-type (knowledge-entry-target s))
                               (equal (knowledge-entry-inputs s)
                                      (list (cons 0 elem-type) (cons 1 elem-type)))
                               (member (getf (knowledge-entry-metadata s) :position) '(0 1))))
                        (knowledge-entries-of-kind :solver library)))))
            (when elem-solvers
              (setf induced
                    (nconc induced
                           (induce-combinator-solvers library ledger map-name elem-type seq-type
                                                      src-ctype elem-solvers))))))))
    (nconc induced
           (induce-involution-solvers library :ledger ledger)
           (induce-solvers-from-transformers library ledger))))

(define-knowledge-kind :functor
  (:priority 40)
  (:validate (entry library)
    (declare (ignore library))
    (assert-entry-expression-type entry))
  (:consolidate (entries library ledger)
    (declare (ignore entries))
    (induce-functorial-solvers library :ledger ledger)))

;;; A supplied metric decoder for sequences: the delay between a prediction and its target.

(defun install-sequence-shift-metric (&key (library *knowledge-library*) ledger)
  "Define in LIBRARY the decoder `:shift-seq`, which advances an integer sequence by k
places and fills the end with zeros, and a heuristic solver for k, `:argmax-corr`: the
advance at which the prediction correlates best with the target. Register the pair as a
metric decoder of `(:seq :int)`. The solver is a conjecture and not unique: a delta counts
only where it replays through the decoder, and a narrowing by it keeps the original
requirement as a fallback. Returns the solver entry."
  (with-knowledge-library (library)
    (let* ((seq (sequence-type :int))
           (pair (tuple-type :int :int))
           (xs (var 0 seq)) (ys (var 1 seq)) (k (var 1 :int)) (index (var 2 :int))
           ;; (let ((rest r) (here c)) (if (< c (at r 0)) r (tuple c k))), an earlier place winning ties
           (pick-type (code-type (list (cons 0 pair) (cons 1 :int) (cons 2 :int)) pair))
           (pick (lit pick-type
                      (term `(if (< ,(var 1 :int) (at ,(var 0 pair) 0))
                                 ,(var 0 pair)
                                 (tuple ,(var 1 :int) ,(var 2 :int)))
                            pair))))
      (define-function :shift-seq (list (cons 0 seq) (cons 1 :int)) seq
        (lambda (self)
          (term `(if (= ,xs ()) ()
                     (if (< 0 ,k)
                         (concat (cons (,self (tail ,xs) (- ,k 1)) (cons (cons 0 ()) ())))
                         ,xs))
                seq)))
      (define-function :seq-corr (list (cons 0 seq) (cons 1 seq)) :int
        (lambda (self)
          (term `(if (= ,xs ()) 0
                     (if (= ,ys ()) 0
                         (+ (* (at ,xs 0) (at ,ys 0)) (,self (tail ,xs) (tail ,ys)))))
                :int)))
      ;; The best correlation of a suffix of X0 with X1 and the place it starts, counted from X2.
      (define-function :best-shift (list (cons 0 seq) (cons 1 seq) (cons 2 :int)) pair
        (lambda (self)
          (term `(if (= ,xs ()) (tuple ,(lit :int 0) ,index)
                     (code-eval ,pick
                                (,self (tail ,xs) ,ys (+ ,index 1))
                                (seq-corr ,xs ,ys)
                                ,index))
                pair)))
      (define-function :argmax-corr (list (cons 0 seq) (cons 1 seq)) :int
        (term `(at (best-shift ,xs ,ys 0) 1) :int))
      (register-metric-decoder
       (register-knowledge-solver :shift-seq
                                  :id :solve-shift-seq-by-correlation
                                  :position 1
                                  :witness (term `(argmax-corr ,xs ,ys))
                                  :unique-p nil
                                  :library library :ledger ledger)
       :library library))))

