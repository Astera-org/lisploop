;;;; bootstrap/build-batteries.lisp
;;;; Cold-bootstraps all `library/*.sexp` knowledge-library battery packets from an empty
;;;; kernel library using `:spec` synthesis, higher-order anti-unification, template
;;;; instantiation, observational law discovery, and conditional/law solver induction.

(let* ((here (make-pathname :name nil :type nil :defaults *load-truename*))
       (root (merge-pathnames "../" here)))
  (load (merge-pathnames "load.lisp" root))
  (load (merge-pathnames "recursion-schemas.lisp" here)))

(in-package #:lisploop)

(defun synthesize-battery-function (spec &rest keys)
  "`synthesize-spec-entry` on SPEC with the curriculum's recursion schemas on offer."
  (apply #'synthesize-spec-entry spec :expanders (list (recursion-schema-expander)) keys))

(defparameter *bootstrap-output-directory*
  (merge-pathnames "library/"
                   (merge-pathnames "../"
                                    (make-pathname :name nil :type nil :defaults *load-truename*))))

(defun battery-output-path (name)
  (merge-pathnames (make-pathname :name (string-downcase (symbol-name name)) :type "sexp")
                   *bootstrap-output-directory*))

(defun save-clean-battery (name primary-ids source-library &key parameters (ledger (make-ledger)))
  "Extract PRIMARY-IDS (and any `:spec` entries specifying them) from SOURCE-LIBRARY into a
minimal, clean `knowledge-library`, attach `(:from-battery NAME)` to each primary entry,
verify round-trip loading, and write `library/<name>.sexp`."
  (let* ((bname (canonical-op-name name))
         (wanted (mapcar #'canonical-op-name primary-ids))
         (out-lib (make-knowledge-library))
         (specs (loop for sp in (knowledge-entries-of-kind :spec source-library)
                      for edge = (first (knowledge-edges-from sp :specifies source-library))
                      when (and edge (member (second edge) wanted :test #'eq))
                        collect sp)))
    (with-knowledge-library (out-lib)
      ;; Pre-declare function signatures so mutually/forward referenced ASTs install cleanly.
      (dolist (id wanted)
        (let ((src (find-knowledge-entry id source-library)))
          (assert src () "Missing primary battery entry ~S while saving ~S" id bname)
          (when (eq :function (knowledge-entry-kind src))
            (setf (gethash id *function-definitions*)
                  (%make-function-definition :name id
                                             :inputs (copy-tree (knowledge-entry-inputs src))
                                             :return-type (copy-tree (knowledge-entry-target src))))
            (pushnew id *registered-function-names* :test #'eq))))
      (setf *registered-function-names* (nreverse *registered-function-names*))
      ;; Install in kind-priority order, then restore exact `wanted` + `specs` chronological order.
      (let* ((primary-entries (mapcar (lambda (id) (find-knowledge-entry id source-library)) wanted))
             (all-src (append specs primary-entries))
             (installed (make-hash-table :test #'eq)))
        (dolist (src (stable-sort (copy-list all-src) #'<
                                  :key (lambda (e) (knowledge-kind-priority (knowledge-entry-kind e)))))
          (let ((id (knowledge-entry-id src))
                (kind (knowledge-entry-kind src)))
            (if (eq kind :function)
                (progn
                  (define-function id (knowledge-entry-inputs src) (knowledge-entry-target src)
                    (lambda (self)
                      (rename-function-calls (knowledge-entry-expression src) id self)))
                  (let ((fn-ent (find-knowledge-entry id out-lib)))
                    (setf (knowledge-entry-work fn-ent) (knowledge-entry-work src))
                    (add-knowledge-edge fn-ent :from-battery bname)
                    (setf (gethash id installed) fn-ent)))
                (let ((copy (copy-knowledge-entry src)))
                  (when (eq kind :descriptor)
                    (let ((meta (copy-list (knowledge-entry-metadata copy))))
                      (remf meta :necessary-for)
                      (setf (knowledge-entry-metadata copy) meta
                            (knowledge-entry-edges copy)
                            (remove :describes (knowledge-entry-edges copy) :key #'first))))
                  (let ((reg (register-knowledge-entry copy :library out-lib :ledger ledger))
                        (metric-edge (and (eq kind :solver)
                                          (first (knowledge-edges-from src :metric-decoder source-library)))))
                    (unless (eq kind :spec)
                      (add-knowledge-edge reg :from-battery bname))
                    (when metric-edge
                      (register-metric-decoder reg :library out-lib :tag-bits (fourth metric-edge)))
                    (setf (gethash id installed) reg))))))
        ;; Keep only the explicitly requested entries + specs in canonical order (dropping auto side-effects).
        (dolist (ent (copy-list (knowledge-library-entries out-lib)))
          (unless (gethash (knowledge-entry-id ent) installed)
            (remove-knowledge-entry (knowledge-entry-id ent) out-lib)))
        (setf (knowledge-library-entries out-lib)
              (loop for src in (append primary-entries specs)
                    collect (gethash (knowledge-entry-id src) installed)))))
    (let ((path (battery-output-path bname))
          (meta (append (list :battery bname)
                        (when parameters (list :parameters parameters)))))
      (ensure-directories-exist path)
      (save-knowledge-library path out-lib :metadata meta)
      (format t "~&[bootstrap] Saved ~20A -> ~A (~D entries, ~D specs)~%"
              bname (namestring path) (length wanted) (length specs))
      path)))

;;; ============================================================================
;;; 1. `library/algebra.sexp` — Integer Ring Axioms, Discovered Laws & Fold Motif
;;; ============================================================================

(defun build-algebra-battery ()
  (let ((lib (make-knowledge-library))
        (ledger (make-ledger)))
    (with-knowledge-library (lib)
      ;; 1a. Minimal integer additive cancellation ring axioms (trusted axioms; witnesses stay uncertified).
      (let ((k (var 0 :int))
            (z (var 1 :int))
            (inps '((0 . :int) (1 . :int))))
        (flet ((add-axiom (id lhs)
                 (let ((law (make-law :int inps lhs z :origin :integer-ring-axiom)))
                   (setf (knowledge-entry-id law) id)
                   (attest-knowledge-entry law :trusted-axiom '(:equivalence))
                   (register-knowledge-entry law :library lib :ledger ledger))))
          (add-axiom :int/cancel-+-0 (term `(- (+ ,z ,k) ,k)))
          (add-axiom :int/cancel-+-1 (term `(- (+ ,k ,z) ,k)))
          (add-axiom :int/cancel---0 (term `(+ ,k (- ,z ,k))))
          (add-axiom :int/cancel---1 (term `(- ,k (- ,k ,z))))))

      ;; 1b. Observational algebraic law discovery over GF(3), retyped & sample-validated on :int.
      (let* ((gf3 (gf 3))
             (in1 (list (cons 0 gf3)))
             (in2 (list (cons 0 gf3) (cons 1 gf3)))
             (in3 (list (cons 0 gf3) (cons 1 gf3) (cons 2 gf3)))
             (rows1 (loop for i below 3 collect (law-assignment in1 i)))
             (rows2 (loop for i below 9 collect (law-assignment in2 i)))
             (rows3 (loop for i below 27 collect (law-assignment in3 i)))
             (obs1 (start-observation-search
                    (make-observation-scope (probe-frame gf3 in1 rows1)
                                            (make-language gf3 in1
                                                           :operators (list (op :+ gf3) (op :* gf3))
                                                           :literals '(0 1)))))
             (obs2 (start-observation-search
                    (make-observation-scope (probe-frame gf3 in2 rows2)
                                            (make-language gf3 in2
                                                           :operators (list (op :+ gf3) (op :* gf3))
                                                           :literals nil))))
             (obs3+ (start-observation-search
                     (make-observation-scope (probe-frame gf3 in3 rows3)
                                             (make-language gf3 in3
                                                            :operators (list (op :+ gf3))
                                                            :literals nil))))
             (obs3* (start-observation-search
                     (make-observation-scope (probe-frame gf3 in3 rows3)
                                             (make-language gf3 in3
                                                            :operators (list (op :* gf3))
                                                            :literals nil)))))
        (resume-observation-search obs1 (header-bound in1 gf3 20) 20000)
        (resume-observation-search obs2 (header-bound in2 gf3 24) 40000)
        (resume-observation-search obs3+ (header-bound in3 gf3 44) 80000)
        (resume-observation-search obs3* (header-bound in3 gf3 44) 80000)
        (let ((gf-lib (make-knowledge-library)))
          (with-knowledge-library (gf-lib)
            (dolist (obs (list obs1 obs2 obs3+ obs3*))
              (dolist (law (propose-observed-laws obs :ledger ledger))
                (when (law-operator-fact law)
                  (let ((val (resume-law-validation (start-law-validation law) 100000)))
                    (when (eq :validated (law-validation-status val))
                      (register-knowledge-law val :library gf-lib :ledger ledger))))))
            (dolist (src-law (copy-list (knowledge-entries-of-kind :law gf-lib)))
              (let* ((retyped (retype-law src-law :int))
                     (samples (residue-assignments (mapcar #'cdr (knowledge-entry-inputs retyped))
                                                   '(-3 -1 0 1 2 5)))
                     (val (validate-law retyped 100000 t samples))
                     (e (and (eq :conjecture (law-validation-status val))
                             (law-validation-law val))))
                (when (and e (law-operator-fact e))
                  (let* ((fact (law-operator-fact e))
                         (law-id (ecase (first fact)
                                   (:commutative (keyword-id "INT/COMM-~A" (second fact)))
                                   (:associative (keyword-id "INT/ASSOC-~A" (second fact)))
                                   (:identity (keyword-id "INT/ID-~A-~A" (second fact) (fourth fact))))))
                    (unless (find-knowledge-entry law-id lib)
                      (register-knowledge-law val :id law-id :library lib :ledger ledger)))))))))
      (let ((ids (mapcar #'knowledge-entry-id (knowledge-entries-of-kind :law lib))))
        (save-clean-battery :algebra ids lib :parameters '((?n :int)) :ledger ledger)))))

;;; ============================================================================
;;; 2. `library/arithmetic.sexp` — Induced Arithmetic Solvers + Axiomatic Uniqueness
;;; ============================================================================

(defun build-arithmetic-battery ()
  (let ((lib (make-knowledge-library))
        (ledger (make-ledger)))
    (with-knowledge-library (lib)
      ;; Load integer cancellation axioms from `algebra.sexp` so `induce-law-solvers` derives uniqueness.
      (let ((*battery-directory* *bootstrap-output-directory*))
        (load-battery :algebra :library lib :ledger ledger))
      (let* ((inps '((0 . :int) (1 . :int)))
             (specs
               (list
                (register-knowledge-spec
                 :spec/solve-+-0 inps :int '(((2 5) 3) ((4 1) -3) ((-3 7) 10))
                 :target-id :solve-+-0 :target-kind :solver
                 :metadata (list :inverts (ast->sexp (op :+ :int)) :position 0
                                 :unique-p nil :certified-p nil)
                 :library lib :ledger ledger)
                (register-knowledge-spec
                 :spec/solve-+-1 inps :int '(((2 5) 3) ((4 1) -3) ((-3 7) 10))
                 :target-id :solve-+-1 :target-kind :solver
                 :metadata (list :inverts (ast->sexp (op :+ :int)) :position 1
                                 :unique-p nil :certified-p nil)
                 :library lib :ledger ledger)
                (register-knowledge-spec
                 :spec/solve---0 inps :int '(((2 5) 7) ((4 -1) 3) ((-3 6) 3))
                 :target-id :solve---0 :target-kind :solver
                 :metadata (list :inverts (ast->sexp (op :- :int)) :position 0
                                 :unique-p nil :certified-p nil)
                 :library lib :ledger ledger)
                (register-knowledge-spec
                 :spec/solve---1 inps :int '(((7 5) 2) ((4 9) -5) ((-2 3) -5))
                 :target-id :solve---1 :target-kind :solver
                 :metadata (list :inverts (ast->sexp (op :- :int)) :position 1
                                 :unique-p nil :certified-p nil)
                 :library lib :ledger ledger)
                (register-knowledge-spec
                 :spec/solve-*-0 inps :int '(((3 12) 4) ((-2 6) -3) ((5 0) 0) ((0 5) :none) ((0 0) :none))
                 :target-id :solve-*-0 :target-kind :solver
                 :metadata (list :inverts (ast->sexp (op :* :int)) :position 0
                                 :unique-p nil :finite-unique-p t :certified-p nil)
                 :library lib :ledger ledger)
                (register-knowledge-spec
                 :spec/solve-*-1 inps :int '(((3 12) 4) ((-2 6) -3) ((5 0) 0) ((0 5) :none) ((0 0) :none))
                 :target-id :solve-*-1 :target-kind :solver
                 :metadata (list :inverts (ast->sexp (op :* :int)) :position 1
                                 :unique-p nil :finite-unique-p t :certified-p nil)
                 :library lib :ledger ledger)
                (register-knowledge-spec
                 :spec/solve-/-0 inps :int '(((3 4) 12) ((-2 5) -10) ((4 0) 0) ((0 4) :none) ((0 0) :none))
                 :target-id :solve-/-0 :target-kind :solver
                 :metadata (list :inverts (ast->sexp (op :/ :int)) :position 0
                                 :unique-p nil :finite-unique-p t :certified-p nil)
                 :library lib :ledger ledger)
                (register-knowledge-spec
                 :spec/solve-/-1 inps :int '(((12 4) 3) ((15 3) 5) ((-12 3) -4)
                                             ((0 4) :none) ((12 0) :none) ((0 0) :none))
                 :target-id :solve-/-1 :target-kind :solver
                 :metadata (list :inverts (ast->sexp (op :/ :int)) :position 1
                                 :unique-p nil :finite-unique-p t :certified-p nil)
                 :library lib :ledger ledger))))
        (induce-conditional-solvers specs :library lib :ledger ledger)
        ;; Derive axiomatic uniqueness on addition & subtraction solvers from integer cancellation axioms.
        (induce-law-solvers lib :ledger ledger)
        (save-clean-battery :arithmetic
                            '(:solve-+-0 :solve-+-1 :solve---0 :solve---1
                              :solve-*-0 :solve-*-1 :solve-/-0 :solve-/-1)
                            lib
                            :parameters '((?n :int))
                            :ledger ledger)))))

;;; ============================================================================
;;; 3. `library/constructors.sexp` — Induced `:cons` Solvers & Destructor Laws
;;; ============================================================================

(defun build-constructors-battery ()
  (let ((lib (make-knowledge-library))
        (ledger (make-ledger))
        (seq-t (sequence-type :int)))
    (with-knowledge-library (lib)
      (let* ((tup-t (tuple-type :int seq-t))
             (specs
               (list
                (register-knowledge-spec
                 :spec/solve-cons-0 (list (cons 0 seq-t) (cons 1 seq-t)) :int
                 '((((2 3) (1 2 3)) 1)
                   ((() (7)) 7)
                   (((5) (4 5)) 4)
                   (((2 3) ()) :none)
                   ((() ()) :none)
                   (((9) (1 2)) :none)
                   (((2) (7)) :none))
                 :target-id :solve-cons-0 :target-kind :solver
                 :operators (list (op :at seq-t) (op :tail :int))
                 :constants (list (lit seq-t '()))
                 :metadata (list :inverts (ast->sexp (op :cons :int)) :position 0
                                 :guard-operators (mapcar #'ast->sexp
                                                          (list (op :tail :int) (op := seq-t)))
                                 :unique-p t :certified-p nil)
                 :library lib :ledger ledger)
                (register-knowledge-spec
                 :spec/solve-cons-1 (list (cons 0 :int) (cons 1 seq-t)) seq-t
                 '(((1 (1 2 3)) (2 3))
                   ((7 (7)) ())
                   ((4 (4 5)) (5))
                   ((1 ()) :none)
                   ((0 ()) :none)
                   ((9 (1 2)) :none)
                   ((2 (7)) :none))
                 :target-id :solve-cons-1 :target-kind :solver
                 :operators (list (op :at seq-t) (op :tail :int))
                 :constants (list (lit seq-t '()))
                 :metadata (list :inverts (ast->sexp (op :cons :int)) :position 1
                                 :guard-operators (mapcar #'ast->sexp
                                                          (list (op :at seq-t) (op := seq-t) (op := :int)))
                                 :unique-p t :certified-p nil)
                 :library lib :ledger ledger)
                (register-knowledge-spec
                 :spec/solve-cons-01 (list (cons 0 seq-t)) tup-t
                 '((((1 2 3)) (1 (2 3)))
                   (((7)) (7 ()))
                   (((4 5)) (4 (5)))
                   ((()) :none))
                 :target-id :solve-cons-01 :target-kind :solver
                 :operators (list (op :tuple tup-t) (op :at seq-t) (op :tail :int))
                 :constants (list (lit seq-t '()))
                 :metadata (list :inverts (ast->sexp (op :cons :int)) :position '(0 1)
                                 :guard-operators (mapcar #'ast->sexp (list (op := seq-t)))
                                 :unique-p t :certified-p nil)
                 :library lib :ledger ledger))))
        (induce-conditional-solvers specs :library lib :ledger ledger)
        ;; Validate & register `:cons` destructor laws on sampled sequence assignments.
        (let ((inps (list (cons 0 :int) (cons 1 seq-t)))
              (samples '((1 ()) (3 (4)) (-2 (5 6)) (0 (1 2 3)))))
          (flet ((reg-cons-law (id lhs rhs)
                   (let ((val (validate-law (make-law :int inps lhs rhs :origin :constructor-destructor)
                                            100000 t samples)))
                     (register-knowledge-law val :id id :library lib :ledger ledger))))
            (reg-cons-law :cons/head (term `(at (cons ,(var 0 :int) ,(var 1 seq-t)) 0)) (var 0 :int))
            (reg-cons-law :cons/tail (term `(tail (cons ,(var 0 :int) ,(var 1 seq-t)))) (var 1 seq-t))
            (reg-cons-law :cons/non-empty
                          (term `(= (cons ,(var 0 :int) ,(var 1 seq-t)) ,(lit seq-t '())))
                          (lit :bool nil))))
        (save-clean-battery :constructors
                            '(:solve-cons-0 :solve-cons-1 :solve-cons-01
                              :cons/head :cons/tail :cons/non-empty)
                            lib
                            :parameters '((?a :int))
                            :ledger ledger)))))

;;; ============================================================================
;;; 4. `library/functors.sexp` — Polymorphic Second-Order `:transformer` Programs
;;; ============================================================================

(defun build-functors-battery ()
  (let* ((lib (make-knowledge-library))
         (ledger (make-ledger))
         (elem-t :int)
         (seq-t (sequence-type elem-t))
         (src-c (code-type (list (cons 0 elem-t)) elem-t))
         (pat-c (code-type (list (cons 0 elem-t) (cons 1 elem-t)) elem-t))
         (guard-p-c (code-type (list (cons 0 elem-t) (cons 1 elem-t)) :bool))
         (map-inps (list (cons 0 src-c) (cons 1 seq-t)))
         (map-fn-c (code-type map-inps (list :fn (list seq-t src-c) seq-t)))
         (unary-fn-c (code-type (list (cons 0 seq-t)) (list :fn (list seq-t src-c) seq-t)))
         (pseq-inps (list (cons 0 elem-t) (cons 1 seq-t)))
         (pseq-fn-c (code-type pseq-inps (list :fn (list seq-t src-c) seq-t)))
         (pparam-inps (list (cons 0 seq-t) (cons 1 seq-t))))
    (with-knowledge-library (lib)
      ;; Reference `:map` solely to produce concrete verification examples for `:spec` replay.
      (define-function :ref-map (list (cons 0 seq-t) (cons 1 src-c)) seq-t
        (lambda (self)
          (term `(if (= ,(var 0 seq-t) ()) ()
                     (cons (code-eval ,(var 1 src-c) (at ,(var 0 seq-t) 0))
                           (,self (tail ,(var 0 seq-t)) ,(var 1 src-c)))))))
      (flet ((reg-tr (id inputs target expr sample-known sample-expected &optional (persist-spec-p t))
               (register-knowledge-entry
                (make-knowledge-entry
                 :id id :kind :transformer :domain elem-t
                 :inputs inputs :target target :expression expr
                 :status :validated
                 :metadata (list :origin :bootstrap-functor-transformer)
                 :library lib)
                :library lib :ledger ledger)
               (let ((sp (register-knowledge-spec
                          (keyword-id "SPEC/~A" id) inputs target
                          (list (list sample-known sample-expected))
                          :target-id id :target-kind :transformer
                          :library lib :ledger ledger)))
                 (verify-entry-against-spec id sp :library lib :ledger ledger)
                 (unless persist-spec-p
                   (remove-knowledge-entry (knowledge-entry-id sp) lib)))))
        (let* ((ex-pat (term `(+ ,(var 0 elem-t) ,(var 1 elem-t))))
               (ex-wit (term `(- ,(var 1 elem-t) ,(var 0 elem-t))))
               (id-code (lit src-c (var 0 elem-t))))
          ;; 4a & 4b. Map-inverse step & guard & witness transformers (pos 0 and pos 1)
          (dolist (pos '(0 1))
            (let* ((inv-scope (list (cons 0 pat-c) (cons 1 pat-c) (cons 2 src-c)))
                   (inv-out (code-type (list (cons 0 src-c)) src-c))
                   (b0 (term `(code-bind ,(var 0 pat-c) ,(var 2 src-c) 0) src-c))
                   (b1 (term `(code-bind ,(var 0 pat-c) ,(var 2 src-c) 1) src-c))
                   (const-p (if (zerop pos) b1 b0))
                   (inv-tpl (lit (code-type inv-scope src-c)
                                 (term `(code-subst ,(var 1 pat-c) (tuple ,const-p ,id-code)) src-c)))
                   (inv-expr
                     (term `(code-subst ,inv-tpl
                                        (tuple ,(var 0 pat-c) ,(var 1 pat-c)
                                               ,(lit inv-out (var 0 src-c))))
                           inv-out))
                   (ex-const (term `(code-bind ,(lit pat-c ex-pat) ,(var 0 src-c) ,(if (zerop pos) 1 0)) src-c))
                   (ex-inv (term `(code-subst ,(lit pat-c ex-wit) (tuple ,ex-const ,id-code)) src-c)))
              (reg-tr (if (zerop pos) :functor/map-inverse-0 :functor/map-inverse-1)
                      (list (cons 0 pat-c) (cons 1 pat-c)) inv-out inv-expr
                      (list ex-pat ex-wit) ex-inv)
              ;; Guard transformer: `((0 . pat-c) (1 . pat-c)) -> (:code map-inps :bool)`
              (let* ((g-out (code-type map-inps :bool))
                     (gb0 (term `(code-bind ,(var 0 pat-c) ,(var 2 src-c) 0) src-c))
                     (gb1 (term `(code-bind ,(var 0 pat-c) ,(var 2 src-c) 1) src-c))
                     (gvar (if (zerop pos) gb0 gb1))
                     (gcst (if (zerop pos) gb1 gb0))
                     (ginv (term `(code-subst ,(var 1 pat-c) (tuple ,gcst ,id-code)) src-c))
                     (g-tpl (lit (code-type inv-scope :bool)
                                 (term `(if (code-match ,(var 0 pat-c) ,(var 2 src-c))
                                            ,(bool-and (term `(= ,gvar ,id-code))
                                                       (bool-and (term `(= (code-kind ,gcst) 1))
                                                                 (term `(code-total ,ginv))))
                                            nil))))
                     (g-expr
                       (term `(code-subst ,g-tpl
                                          (tuple ,(var 0 pat-c) ,(var 1 pat-c)
                                                 ,(lit (code-type map-inps src-c) (var 0 src-c))))
                             g-out))
                     (ex-var (term `(code-bind ,(lit pat-c ex-pat) ,(var 0 src-c) ,pos) src-c))
                     (ex-g (term `(if (code-match ,(lit pat-c ex-pat) ,(var 0 src-c))
                                      ,(bool-and (term `(= ,ex-var ,id-code))
                                                 (bool-and (term `(= (code-kind ,ex-const) 1))
                                                           (term `(code-total ,ex-inv))))
                                      nil))))
                (reg-tr (if (zerop pos) :functor/map-guard-0 :functor/map-guard-1)
                        (list (cons 0 pat-c) (cons 1 pat-c)) g-out g-expr
                        (list ex-pat ex-wit) ex-g))
              ;; Witness transformer: `((0 . map-fn-c) (1 . pat-c) (2 . pat-c)) -> (:code map-inps seq-t)`
              (let* ((w-out (code-type map-inps seq-t))
                     (inv-map-out (code-type map-inps src-c))
                     (w-inv (term `(code-subst ,inv-tpl
                                               (tuple ,(var 1 pat-c) ,(var 2 pat-c)
                                                      ,(lit inv-map-out (var 0 src-c))))
                                  inv-map-out))
                     (w-expr (term `(code-apply ,(var 0 map-fn-c)
                                                (tuple ,(lit w-out (var 1 seq-t)) ,w-inv))
                                   w-out))
                     (ex-w (app (op :ref-map) (var 1 seq-t) ex-inv)))
                (reg-tr (if (zerop pos) :functor/map-witness-0 :functor/map-witness-1)
                        (list (cons 0 map-fn-c) (cons 1 pat-c) (cons 2 pat-c)) w-out w-expr
                        (list (op :ref-map) ex-pat ex-wit) ex-w nil))))
          ;; 4c. Unary refactored map witness: `((0 . unary-fn-c) (1 . src-c)) -> (:code ((0 . seq-t)) seq-t)`
          (let* ((u-out (code-type (list (cons 0 seq-t)) seq-t))
                 (u-lit-tpl (lit (code-type (list (cons 0 src-c)) src-c) (var 0 src-c)))
                 (u-code-arg (term `(code-subst ,u-lit-tpl (tuple ,(var 1 src-c)))
                                   (code-type (list (cons 0 seq-t)) src-c)))
                 (u-expr (term `(code-apply ,(var 0 unary-fn-c)
                                            (tuple ,(lit u-out (var 0 seq-t)) ,u-code-arg))
                               u-out))
                 (ex-step (term `(- ,(var 0 elem-t) 1))))
            (reg-tr :functor/unary-map-witness
                    (list (cons 0 unary-fn-c) (cons 1 src-c)) u-out u-expr
                    (list (op :ref-map) ex-step)
                    (app (op :ref-map) (var 0 seq-t) (lit src-c ex-step))
                    nil))
          ;; 4d. Pointwise sequence witness: `((0 . pseq-fn-c) (1 . pat-c)) -> (:code pseq-inps seq-t)`
          (let* ((ps-out (code-type pseq-inps seq-t))
                 (swapped (term `(code-subst ,(var 1 pat-c)
                                             (tuple ,(lit pat-c (var 1 elem-t))
                                                    ,(lit pat-c (var 0 elem-t))))
                                pat-c))
                 (ps-tpl (lit (code-type (list (cons 0 pat-c) (cons 1 elem-t)) src-c)
                              (term `(code-subst ,(var 0 pat-c)
                                                 (tuple ,id-code ,(var 1 elem-t)))
                                    src-c)))
                 (ps-inv (term `(code-subst ,ps-tpl
                                            (tuple ,swapped
                                                   ,(lit (code-type pseq-inps elem-t) (var 0 elem-t))))
                               (code-type pseq-inps src-c)))
                 (ps-expr (term `(code-apply ,(var 0 pseq-fn-c)
                                             (tuple ,(lit ps-out (var 1 seq-t)) ,ps-inv))
                                ps-out))
                 (ex-swapped (term `(- ,(var 0 elem-t) ,(var 1 elem-t)))))
            (reg-tr :functor/pointwise-seq-witness
                    (list (cons 0 pseq-fn-c) (cons 1 pat-c)) ps-out ps-expr
                    (list (op :ref-map) ex-wit)
                    (app (op :ref-map) (var 1 seq-t)
                         (term `(code-subst ,(lit pat-c ex-swapped)
                                            (tuple ,id-code ,(var 0 elem-t)))
                               src-c))
                    nil))
          ;; 4e. Pointwise parameter witness (synthesized via `learn-knowledge-transformer`!) & guard
          (let* ((pp-out (code-type pparam-inps elem-t))
                 (head0 (lit pp-out (term `(at ,(var 0 seq-t) 0))))
                 (head1 (lit pp-out (term `(at ,(var 1 seq-t) 0))))
                 (pp-inps (list (cons 0 pat-c)))
                 (pp-frame (simple-frame pp-out pp-inps
                                         (list (list (list ex-wit)
                                                     (term `(- (at ,(var 1 seq-t) 0)
                                                               (at ,(var 0 seq-t) 0)))))))
                 (pp-lang (make-language :int pp-inps
                                         :operators (list (op :code-subst
                                                              (tuple-type pat-c
                                                                          (tuple-type pp-out pp-out)
                                                                          pp-out))
                                                          (op :tuple (tuple-type pp-out pp-out)))
                                         :literals nil
                                         :constants (list head0 head1)))
                 (learned (learn-knowledge-transformer pp-frame pp-lang
                                                       (header-bound pp-inps pp-out 300) 50000
                                                       :id :functor/pointwise-param-witness
                                                       :library lib)))
            (assert learned () "Failed to learn :functor/pointwise-param-witness")
            (register-knowledge-spec
             :spec/functor/pointwise-param-witness pp-inps pp-out
             (list (list (list ex-wit) (term `(- (at ,(var 1 seq-t) 0) (at ,(var 0 seq-t) 0)))))
             :target-id :functor/pointwise-param-witness :target-kind :transformer
             :library lib :ledger ledger)
            ;; Pointwise parameter guard transformer
            (let* ((pg-out (code-type pparam-inps :bool))
                   (g-head (term `(code-subst ,(var 0 guard-p-c) (tuple ,head0 ,head1)) pg-out))
                   (pg-wrap (lit (code-type (list (cons 0 seq-t) (cons 1 seq-t) (cons 2 :bool)) :bool)
                                 (term `(if (< 0 (length ,(var 0 seq-t)))
                                            (if (= (length ,(var 0 seq-t)) (length ,(var 1 seq-t)))
                                                ,(var 2 :bool)
                                                nil)
                                            nil))))
                   (pg-expr (term `(code-subst ,pg-wrap
                                               (tuple ,(lit (code-type pparam-inps seq-t) (var 0 seq-t))
                                                      ,(lit (code-type pparam-inps seq-t) (var 1 seq-t))
                                                      ,g-head))
                                  pg-out))
                   (ex-eg (bool-not (term `(= ,(var 0 elem-t) 0)))))
              (reg-tr :functor/pointwise-param-guard
                      (list (cons 0 guard-p-c)) pg-out pg-expr
                      (list ex-eg)
                      (term `(if (< 0 (length ,(var 0 seq-t)))
                                 (if (= (length ,(var 0 seq-t)) (length ,(var 1 seq-t)))
                                     ,(bool-not (term `(= (at ,(var 0 seq-t) 0) 0)))
                                     nil)
                                 nil)))))))
      (save-clean-battery :functors
                          '(:functor/map-inverse-0 :functor/map-inverse-1
                            :functor/map-guard-0 :functor/map-guard-1
                            :functor/map-witness-0 :functor/map-witness-1
                            :functor/unary-map-witness
                            :functor/pointwise-seq-witness
                            :functor/pointwise-param-witness
                            :functor/pointwise-param-guard)
                          lib
                          :parameters '((?a :int))
                          :ledger ledger))))

;;; ============================================================================
;;; 5. `library/sequences.sexp` & `library/descriptors.sexp`
;;; ============================================================================

(defun build-sequences-and-descriptors-batteries ()
  (let* ((corpus-lib (make-knowledge-library))
         (seq-lib (make-knowledge-library))
         (ledger (make-ledger))
         (seq-t (sequence-type :int))
         (seq2-t (sequence-type seq-t))
         (unary-t (code-type '((0 . :int)) :int))
         (pred-t (code-type '((0 . :int)) :bool))
         (bin-t (code-type '((0 . :int) (1 . :int)) :int)))
    ;; 5a. Synthesize the 6 first-order recursive list functions de novo and discover `:map` & `:foldr`!
    (with-knowledge-library (corpus-lib)
      (let ((in1 (list (cons 0 seq-t)))
            (s-ops (list (op :cons :int) (op :tail :int) (op :at seq-t) (op := seq-t)
                         (op :if seq-t) (op :+ :int) (op :* :int)))
            (i-ops (list (op :tail :int) (op :at seq-t) (op := seq-t)
                         (op :if :int) (op :+ :int) (op :* :int))))
        (flet ((synth1 (id ret rows ops lits)
                 (synthesize-battery-function
                  (register-knowledge-spec
                   (keyword-id "SPEC/~A" id) in1 ret rows
                   :target-id id :operators ops :literals lits :constants (list (lit seq-t '()))
                   :library corpus-lib :ledger ledger)
                  :library corpus-lib :bound 90 :budget 80000 :ledger ledger)))
          (synth1 :copy seq-t '(((()) ()) (((3)) (3)) (((1 3)) (1 3)) (((4 1 3)) (4 1 3))) s-ops nil)
          (synth1 :inc-all seq-t '(((()) ()) (((3)) (4)) (((1 3)) (2 4)) (((4 1 3)) (5 2 4))) s-ops '(1))
          (synth1 :dbl-all seq-t '(((()) ()) (((3)) (6)) (((1 3)) (2 6)) (((4 1 3)) (8 2 6))) s-ops '(2))
          (synth1 :sum-all :int '(((()) 0) (((3)) 3) (((2 3)) 5) (((4 2 3)) 9)) i-ops '(0))
          (synth1 :len-all :int '(((()) 0) (((3)) 1) (((2 3)) 2) (((4 2 3)) 3)) i-ops '(0 1))
          (synth1 :prd-all :int '(((()) 1) (((3)) 3) (((2 3)) 6) (((4 2 3)) 24)) i-ops '(1))))
      (let* ((defs (mapcar #'find-function-definition
                           '(:copy :inc-all :dbl-all :sum-all :len-all :prd-all)))
             (accepted (discover-library-abstractions defs :register-p nil :ledger ledger))
             (map-abs (find seq-t accepted :key #'library-abstraction-return-type :test #'equal))
             (fold-abs (find :int accepted :key #'library-abstraction-return-type :test #'equal)))
        (assert (and map-abs fold-abs) () "Failed to discover :map and :foldr via anti-unification")
        ;; Install discovered `:map` & `:foldr` into `seq-lib`, plus synthesize `:foldl`, `:filter`, `:map-adjacent`!
        (with-knowledge-library (seq-lib)
          (define-function :map (library-abstraction-inputs map-abs) seq-t
            (lambda (self)
              (rename-function-calls (library-abstraction-body map-abs)
                                     (library-abstraction-name map-abs) self)))
          (define-function :foldr (library-abstraction-inputs fold-abs) :int
            (lambda (self)
              (rename-function-calls (library-abstraction-body fold-abs)
                                     (library-abstraction-name fold-abs) self)))
          (let ((pos-pred (term `(< 0 ,(var 0 :int))))
                (even-pred (term `(= (* (/ ,(var 0 :int) 2) 2) ,(var 0 :int))))
                (sub-step (term `(- ,(var 0 :int) ,(var 1 :int))))
                (add-step (term `(+ ,(var 0 :int) ,(var 1 :int))))
                (id-fn (var 0 :int))
                (inc-fn (term `(+ ,(var 0 :int) 1))))
            ;; Attach verification specs to `:map` and `:foldr`
            (verify-entry-against-spec
             :map
             (register-knowledge-spec
              :spec/map (list (cons 0 seq-t) (cons 1 unary-t)) seq-t
              (list (list (list '() id-fn) '())
                    (list (list '(1 2 3) inc-fn) '(2 3 4)))
              :target-id :map :library seq-lib :ledger ledger)
             :library seq-lib :ledger ledger)
            (verify-entry-against-spec
             :foldr
             (register-knowledge-spec
              :spec/foldr (list (cons 0 seq-t) (cons 1 :int) (cons 2 bin-t)) :int
              (list (list (list '() 7 sub-step) 7)
                    (list (list '(1 2 3) 10 sub-step) -8))
              :target-id :foldr :library seq-lib :ledger ledger)
             :library seq-lib :ledger ledger)
            ;; Synthesize `:foldl`, `:filter`, `:map-adjacent` de novo from pure `:spec`s!
            (synthesize-battery-function
             (register-knowledge-spec
              :spec/foldl (list (cons 0 seq-t) (cons 1 :int) (cons 2 bin-t)) :int
              (list (list (list '() 7 sub-step) 7)
                    (list (list '() 9 sub-step) 9)
                    (list (list '() 6 sub-step) 6)
                    (list (list '(3) 9 sub-step) 6)
                    (list (list '(2 3) 11 sub-step) 6)
                    (list (list '(1 2 3) 12 sub-step) 6)
                    (list (list '() 10 sub-step) 10)
                    (list (list '(4) 10 sub-step) 6)
                    (list (list '(1 4) 11 sub-step) 6))
              :target-id :foldl
              :operators (list (op :tail :int) (op :at seq-t) (op := seq-t) (op :if :int) (op :code-eval bin-t))
              :constants (list (lit seq-t '()))
              :library seq-lib :ledger ledger)
             :library seq-lib :ledger ledger)
            (synthesize-battery-function
             (register-knowledge-spec
              :spec/filter (list (cons 0 seq-t) (cons 1 pred-t)) seq-t
              (list (list (list '() pos-pred) '())
                    (list (list '(3) pos-pred) '(3))
                    (list (list '(-2 3) pos-pred) '(3))
                    (list (list '(4 -2 3) pos-pred) '(4 3))
                    (list (list '() even-pred) '())
                    (list (list '(3) even-pred) '())
                    (list (list '(4 3) even-pred) '(4)))
              :target-id :filter
              :operators (list (op :cons :int) (op :tail :int) (op :at seq-t) (op := seq-t)
                               (op :if seq-t) (op :code-eval pred-t))
              :constants (list (lit seq-t '()))
              :library seq-lib :ledger ledger)
             :library seq-lib :ledger ledger)
            (synthesize-battery-function
             (register-knowledge-spec
              :spec/map-adjacent (list (cons 0 seq-t) (cons 1 bin-t)) seq-t
              (list (list (list '() sub-step) '())
                    (list (list '(9) sub-step) '())
                    (list (list '(4 9) sub-step) '(5))
                    (list (list '(1 4 9) sub-step) '(3 5))
                    (list (list '() add-step) '())
                    (list (list '(5) add-step) '())
                    (list (list '(2 5) add-step) '(7))
                    (list (list '(1 2 5) add-step) '(3 7)))
              :target-id :map-adjacent
              :operators (list (op :cons :int) (op :tail :int) (op :at seq-t) (op := seq-t)
                               (op :if seq-t) (op :code-eval bin-t))
              :constants (list (lit seq-t '()))
              :library seq-lib :ledger ledger)
             :library seq-lib :ledger ledger)
            ;; The index list of a sequence, counted from a start: the coordinates a positional
            ;; rule is written over, as in `(map (positions xs 0) ...)`. Every recursive call the
            ;; definition makes on these rows is itself a row.
            (synthesize-battery-function
             (register-knowledge-spec
              :spec/positions (list (cons 0 seq-t) (cons 1 :int)) seq-t
              '(((() 0) ()) ((() 1) ()) ((() 2) ()) ((() 3) ()) ((() 4) ())
                (((7) 2) (2)) (((4) 3) (3)) (((7) 0) (0))
                (((6 7) 1) (1 2)) (((9 4) 2) (2 3)) (((5 6 7) 0) (0 1 2)))
              :target-id :positions
              :operators (list (op :cons :int) (op :tail :int) (op :at seq-t) (op := seq-t)
                               (op :if seq-t) (op :+ :int))
              :literals '(0 1)
              :constants (list (lit seq-t '()))
              :library seq-lib :ledger ledger)
             :library seq-lib :ledger ledger)
            ;; The inverter of a read at an unknown index: `(= (at xs Z) c)` holds of every
            ;; position of xs that holds c, so the solver's witness is that list of positions and
            ;; not one of them (`:set-valued-p`). The witness is synthesized over (xs, c, the
            ;; index list of xs); the curriculum then writes the index list as `(positions xs 0)`.
            (let* ((with-index (list (cons 0 seq-t) (cons 1 :int) (cons 2 seq-t)))
                   (fibers '((((5 6 7 5) 5) (0 3)) (((5 6 7 5) 6) (1)) (((5 6 7 5) 9) ()) ((() 3) ())
                             (((4 4 4) 4) (0 1 2)) (((1 2) 2) (1)) (((3 1 3) 3) (0 2)) (((3 1 3) 1) (1))))
                   (job (start-heuristic-synthesis
                         (simple-frame seq-t with-index
                                       (loop for (known positions) in fibers
                                             collect (list (append known
                                                                   (list (loop for i below (length (first known))
                                                                               collect i)))
                                                           positions)))
                         (make-language :int with-index
                                        :operators (list (op :at seq-t) (op := :int))
                                        :literals '(0) :constants (list (lit seq-t '())))
                         170 :max-depth 3 :heuristic-budget 8000 :library-functions '(:filter))))
              (resume-synthesis job 500000 :stop-on-first t)
              (charge ledger :synthesis (ledger-total (synthesis-job-ledger job)))
              (assert (synthesis-job-best job) () "Failed to synthesize the witness of :at in its index")
              (let* ((xs (var 0 seq-t))
                     (witness (instantiate (candidate-expression (synthesis-job-best job))
                                           (list (cons 2 (term `(positions ,xs 0))))
                                           :var))
                     (solver (register-knowledge-solver
                              (op :at seq-t) :id :solve-at-1 :domain :int :position 1 :target :int
                              :witness witness :certified-p nil :unique-p t :necessary-p t
                              :metadata (list :set-valued-p t)
                              :library seq-lib :ledger ledger)))
                ;; Evidence by sample: on every row the witness is the whole list of positions.
                (assert (loop for (known positions) in fibers
                              always (multiple-value-bind (value ok)
                                         (eval-expr-value witness (knowledge-entry-inputs solver) known ledger)
                                       (and ok (equal positions value)))))
                (attest-knowledge-entry solver :sampled '(:witness :uniqueness :necessity))))
            ;; Register `:comprehension/filter-map` multi-hole `:decoder-template`!
            (let* ((fm-expr (app (op :map)
                                 (app (op :filter) (var 0 seq-t) (var 1 pred-t))
                                 (var 2 unary-t)))
                   (fm-trig (bool-not (term `(< (length ,(var 0 seq-t)) (length ,(var 1 seq-t)))))))
              (register-knowledge-entry
               (make-knowledge-entry
                :id :comprehension/filter-map
                :kind :decoder-template
                :domain :int
                :inputs (list (cons 0 seq-t) (cons 1 pred-t) (cons 2 unary-t))
                :target seq-t
                :expression fm-expr
                :trigger fm-trig
                :status :validated
                :metadata (list :child-ids '(1 2)
                                :child-id 2
                                :bindings :identity
                                :lift-p t
                                :strict-contraction-p t
                                :policy-score -18
                                :dependencies (expression-dependencies (list fm-expr)))
                :library seq-lib)
               :library seq-lib :ledger ledger))
            ;; Discover `:FOLDR=:FOLDL/MONOID` motif in a scratch workspace with `algebra.sexp`!
            (let ((motif-lib (make-knowledge-library)))
              (with-knowledge-library (motif-lib)
                (let ((*battery-directory* *bootstrap-output-directory*))
                  (load-battery :algebra :library motif-lib :ledger ledger))
                (dolist (fid '(:foldr :foldl))
                  (let ((src (find-knowledge-entry fid seq-lib)))
                    (define-function fid (knowledge-entry-inputs src) (knowledge-entry-target src)
                      (lambda (self)
                        (rename-function-calls (knowledge-entry-expression src) fid self)))))
                (define-function :sum-m (list (cons 0 seq-t)) :int
                  (app (op :foldr) (var 0 seq-t) (lit :int 0)
                       (lit bin-t (term `(+ ,(var 0 :int) ,(var 1 :int))))))
                (add-knowledge-edge :sum-m :refactored-by :foldr)
                (define-function :prod-m (list (cons 0 seq-t)) :int
                  (app (op :foldr) (var 0 seq-t) (lit :int 1)
                       (lit bin-t (term `(* ,(var 0 :int) ,(var 1 :int))))))
                (add-knowledge-edge :prod-m :refactored-by :foldr)
                (induce-fold-motifs motif-lib :ledger ledger))
              (let ((motif (copy-knowledge-entry (find-knowledge-entry :foldr=foldl/monoid motif-lib))))
                (setf (knowledge-entry-edges motif)
                      (remove :instance (knowledge-entry-edges motif) :key #'first))
                (register-knowledge-entry motif :library seq-lib :ledger ledger)))
            ;; Also trigger `:DESC/OUTER-SHAPE-2D` via a transient 2D map instantiation before harvesting descriptors.
            (retype-function-definition :map seq-t :new-name :tmp-map-2d)
            (let ((desc-ids (mapcar #'knowledge-entry-id
                                    (knowledge-entries-of-kind :descriptor seq-lib))))
              (save-clean-battery :descriptors desc-ids seq-lib
                                  :parameters '((?a :int)) :ledger ledger))
            (save-clean-battery :sequences
                                '(:map :foldr :foldl :filter :map-adjacent :positions :solve-at-1
                                  :comprehension/filter-map :foldr=foldl/monoid)
                                seq-lib
                                :parameters '((?a :int))
                                :ledger ledger)))))))

;;; ============================================================================
;;; 6. `library/scans.sexp` — `:scan` (Synthesized) & `:scan-pair` (Instantiated)
;;; ============================================================================

(defun build-scans-battery ()
  (let* ((lib (make-knowledge-library))
         (ledger (make-ledger))
         (seq-t (sequence-type :int))
         (tup-t (tuple-type :int :int))
         (seq-tup-t (sequence-type tup-t))
         (bin-t (code-type '((0 . :int) (1 . :int)) :int))
         (pair-step-t (code-type (list (cons 0 tup-t) (cons 1 :int)) tup-t))
         (add-step (term `(+ ,(var 0 :int) ,(var 1 :int))))
         (sub-step (term `(- ,(var 0 :int) ,(var 1 :int)))))
    (with-knowledge-library (lib)
      (synthesize-battery-function
       (register-knowledge-spec
        :spec/scan (list (cons 0 seq-t) (cons 1 :int) (cons 2 bin-t)) seq-t
        (list (list (list '() 4 add-step) '())
              (list (list '() 5 add-step) '())
              (list (list '() 2 add-step) '())
              (list (list '(3) 2 add-step) '(5))
              (list (list '(-1 3) 3 add-step) '(2 5))
              (list (list '(2 -1 3) 1 add-step) '(3 2 5))
              (list (list '() 6 sub-step) '())
              (list (list '(4) 10 sub-step) '(6))
              (list (list '(1 4) 11 sub-step) '(10 6)))
        :target-id :scan
        :operators (list (op :cons :int) (op :tail :int) (op :at seq-t)
                         (op := seq-t) (op :if seq-t) (op :code-eval bin-t))
        :constants (list (lit seq-t '()))
        :library lib :ledger ledger)
       :library lib :ledger ledger)
      ;; Polymorphically instantiate `:scan-pair` from `:scan`!
      (instantiate-entry-template :scan
                                  :input-types (list seq-t tup-t pair-step-t)
                                  :target seq-tup-t
                                  :id :scan-pair
                                  :register-p t
                                  :library lib
                                  :ledger ledger)
      (let ((pair-step (term `(tuple (+ (at ,(var 0 tup-t) 0) ,(var 1 :int))
                                     (+ (at ,(var 0 tup-t) 1) ,(var 1 :int))))))
        (verify-entry-against-spec
         :scan-pair
         (register-knowledge-spec
          :spec/scan-pair (list (cons 0 seq-t) (cons 1 tup-t) (cons 2 pair-step-t)) seq-tup-t
          (list (list (list '(1 1) '(0 10) pair-step) '((1 11) (2 12))))
          :target-id :scan-pair :library lib :ledger ledger)
         :library lib :ledger ledger))
      (save-clean-battery :scans '(:scan :scan-pair) lib :ledger ledger))))

;;; ============================================================================
;;; 7. `library/sequence-shift.sexp` — Synthesized Shift/Correlation Metric Battery
;;; ============================================================================

(defun build-sequence-shift-battery ()
  (let* ((lib (make-knowledge-library))
         (ledger (make-ledger))
         (seq-t (sequence-type :int))
         (tup-t (tuple-type :int :int)))
    (with-knowledge-library (lib)
      ;; 7a. `:shift-seq`
      (synthesize-battery-function
       (register-knowledge-spec
        :spec/shift-seq (list (cons 0 seq-t) (cons 1 :int)) seq-t
        '(((() 0) ()) ((() 1) ()) ((() 2) ())
          (((5) 0) (5)) (((1 5) 0) (1 5)) (((4 1 5) 0) (4 1 5))
          (((5) 1) (0)) (((1 5) 1) (5 0)) (((4 1 5) 1) (1 5 0))
          (((1 5) 2) (0 0)) (((4 1 5) 2) (5 0 0))
          (((3 1 4 1 5) 0) (3 1 4 1 5))
          (((3 1 4 1 5) 2) (4 1 5 0 0)))
        :target-id :shift-seq
        :operators (list (op :concat :int) (op :cons :int) (op :cons seq-t)
                         (op :tail :int) (op := seq-t) (op :< :int) (op :- :int) (op :if seq-t))
        :literals '(0 1)
        :constants (list (lit seq-t '()) (lit (sequence-type seq-t) (list '(0))))
        :library lib :ledger ledger)
       :library lib :ledger ledger)
      ;; 7b. `:seq-corr`
      (synthesize-battery-function
       (register-knowledge-spec
        :spec/seq-corr (list (cons 0 seq-t) (cons 1 seq-t)) :int
        '(((() ()) 0) ((() (5)) 0) (((3) ()) 0)
          (((3) (5)) 15) (((2 3) (4 5)) 23) (((1 2 3) (2 4 5)) 25)
          (((2 3) (5)) 10))
        :target-id :seq-corr
        :operators (list (op :+ :int) (op :* :int) (op :tail :int)
                         (op :at seq-t) (op := seq-t) (op :if :int))
        :literals '(0)
        :constants (list (lit seq-t '()))
        :library lib :ledger ledger)
       :library lib :ledger ledger)
      ;; 7c. `:best-shift`
      (synthesize-battery-function
       (register-knowledge-spec
        :spec/best-shift (list (cons 0 seq-t) (cons 1 seq-t) (cons 2 :int)) tup-t
        '(((() (4 1) 3) (0 3)) ((() (4 1) 2) (0 2)) ((() (4 1) 1) (0 1))
          (((1) (4 1) 2) (4 2)) (((4 1) (4 1) 1) (17 1)) (((3 4 1) (4 1) 0) (17 1))
          ((() (5 0) 2) (0 2)) (((2) (5 0) 1) (10 1)) (((5 2) (5 0) 0) (25 0)))
        :target-id :best-shift
        :operators (list (op :seq-corr) (op :tuple tup-t) (op :at (tuple-type tup-t :int))
                         (op :tail :int) (op := seq-t) (op :< :int) (op :+ :int) (op :if tup-t))
        :literals '(0 1)
        :constants (list (lit seq-t '()))
        :library lib :ledger ledger)
       :library lib :ledger ledger)
      ;; 7d. `:argmax-corr`
      (synthesize-battery-function
       (register-knowledge-spec
        :spec/argmax-corr (list (cons 0 seq-t) (cons 1 seq-t)) :int
        '((((3 4 1) (4 1)) 1)
          (((5 2) (5 0)) 0)
          (((3 1 4 1 5) (4 1 5 0 0)) 2))
        :target-id :argmax-corr
        :operators (list (op :best-shift) (op :at (tuple-type tup-t :int)))
        :literals '(0 1)
        :library lib :ledger ledger)
       :library lib :recursive-p nil :ledger ledger)
      ;; 7e. `:last-or`
      (synthesize-battery-function
       (register-knowledge-spec
        :spec/last-or (list (cons 0 seq-t) (cons 1 :int)) :int
        '(((() 7) 7) ((() 9) 9) (((4) 7) 4) (((1 4) 7) 4)
          (((3 1 4) 7) 4) (((8) 2) 8) (((5 8) 2) 8))
        :target-id :last-or
        :operators (list (op :tail :int) (op :at seq-t) (op := seq-t) (op :if :int))
        :constants (list (lit seq-t '()))
        :library lib :ledger ledger)
       :library lib :ledger ledger)
      ;; 7f. `:solve-shift-seq-by-correlation` (witness + guard induced from `:spec`, registered as metric!)
      (let ((solver-spec
              (register-knowledge-spec
               :spec/solve-shift-seq-by-correlation
               (list (cons 0 seq-t) (cons 1 seq-t)) :int
               '((((3 1 4 1 5) (4 1 5 0 0)) 2)
                 (((3 1 4 1 5) (3 1 4 1 5)) 0)
                 (((1 5) (5 0)) 1)
                 (((4 1) (4 1)) 0)
                 ((() ()) 0)
                 (((3 1 4 1 5) (4 1 5 9 2)) :none)
                 (((3 1 4 1 5) (4 1 5 0)) :none)
                 (((1 2) (1 2 0)) :none)
                 (((1 2) (9 9)) :none)
                 (((5) (7)) :none)
                 ((() (0)) :none)
                 (((1) ()) :none))
               :target-id :solve-shift-seq-by-correlation
               :target-kind :solver
               :operators (list (op :argmax-corr))
               :literals '(0)
               :constants (list (lit seq-t '()))
               :metadata (list :inverts (ast->sexp (op :shift-seq))
                               :position 1
                               :guard-operators (mapcar #'ast->sexp
                                                        (list (op :last-or) (op :length :int)
                                                              (op := seq-t) (op := :int)))
                               :unique-p nil
                               :metric-p t
                               :certified-p nil)
               :library lib :ledger ledger)))
        (induce-conditional-solvers (list solver-spec) :library lib :ledger ledger))
      (save-clean-battery :sequence-shift
                          '(:shift-seq :seq-corr :best-shift :argmax-corr :last-or
                            :solve-shift-seq-by-correlation)
                          lib
                          :ledger ledger))))

(let ((t0 (get-internal-real-time)))
  (format t "~&=== Cold-bootstrapping library/*.sexp batteries ===~%")
  (build-algebra-battery)
  (build-arithmetic-battery)
  (build-constructors-battery)
  (build-functors-battery)
  (build-sequences-and-descriptors-batteries)
  (build-scans-battery)
  (build-sequence-shift-battery)
  (format t "~&=== Bootstrap complete in ~,2F s ===~%"
          (/ (- (get-internal-real-time) t0) internal-time-units-per-second)))
