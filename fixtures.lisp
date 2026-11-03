(in-package #:lisploop)

(defun report-ledger (label ledger)
  (format t "~A: work=~D ~S~%" label (ledger-total ledger) (ledger-counts ledger)))

(defun report-size (label expression inputs)
  (let* ((total (description-size expression inputs))
         (header (header-size inputs (expression-type expression inputs))))
    (format t "~A: S=~D bits = ~D header + ~D body.~%"
            label total header (- total header))))

(defun code-transform-fixture (domain)
  "Supplied structural context for learning which child to retain, with nonmatches
and partial terms. No transform program or selector is supplied to the child search."
  (let* ((scope (list (cons 99 domain))) (code (code-type scope domain))
         (x (var 99 domain)) (zero (lit domain 0)) (one (lit domain 1))
         (plus (op :+ domain)) (mul (op :* domain))
         (partial (app (op :/ domain) one zero))
         (positive (list x (lit domain 2) (app mul x one)))
         (negative (list x zero (app mul x zero) (app plus x one) (app plus partial zero)))
         (rows (append (loop for term in positive collect (list (app plus term zero) term))
                       (loop for term in negative collect (list term term))))
         (pattern-type (code-type (list (cons 7 domain)) domain))
         (pattern (lit pattern-type (app plus (var 7 domain) zero)))
         (source (var 0 code))
         (child (app (op :code-child (tuple-type code code)) source (var 1 :int)))
         (decoder (app (op :if code)
                       (app (op :code-match (tuple-type pattern-type code)) pattern source)
                       (app (op :if code) (app (op :code-total code) child) child source) source)))
    (values (make-frame (make-schema :inputs (list (cons 0 code)) :target code)
                        (loop for (source target) in rows for i from 0 collect
                          (make-row :key i :known (list source) :requirement (set-requirement code (list target)))))
            decoder scope)))

(defun gf5-fixture (&optional ledger)
  "The oracle generates observations only; neither its syntax nor sketch enters search."
  (let* ((field (gf 5))
         (inputs (list (cons 0 field) (cons 1 field)))
         (oracle (app (op :+ field) (var 0 field)
                      (app (op :* field) (lit field 2) (var 1 field))))
         (records
           (loop for a below 5 append
             (loop for b below 5 for key from (* a 5) collect
               (let ((run (evaluate oracle inputs (list a b) :ledger ledger)))
                 (assert (eq (evaluation-status run) :value))
                 (list key a b (evaluation-value run)))))))
    (values (orient-observations (list field field field) records '(0 1) '(2)
                                  :lookup-p t :ledger ledger)
            oracle records)))

(defun replay-model (expression frame &optional ledger)
  "Decode a fresh model, pass declared values only, and separately check each output."
  (multiple-value-bind (model inputs)
      (decode-model (encode-model expression (schema-inputs (frame-schema frame))))
    (assert (equal inputs (schema-inputs (frame-schema frame))))
    (let ((target-type (schema-target (frame-schema frame))))
      (loop for row in (frame-rows frame) sum
        (let ((run (evaluate model inputs (row-known row) :ledger ledger)))
          (assert (eq (evaluation-status run) :value))
          (let ((check (check-requirement (row-requirement row) (evaluation-value run)
                                          :ledger ledger :type target-type)))
            (assert (and (eq (evaluation-status check) :value) (evaluation-value check))))
          (evaluation-work run))))))

(defun additive-transition-fixture (domain starts steps shift-b key-prefix ledger)
  "Record forward transitions T(a,b)=(a+1,b+SHIFT-B). Return the frame and start keys.
The transition is supplied fixture machinery; no invariant sketch enters search."
  (assert (and (integerp steps) (plusp steps)))
  (let* ((field domain) (state-type (tuple-type field field))
         (inputs (list (cons 0 field) (cons 1 field)))
         (transition (app (op :tuple state-type)
                          (app (op :+ field) (var 0 field) (lit field 1))
                          (app (op :+ field) (var 1 field) (lit field shift-b))))
         (rows nil) (anchors nil))
    (loop for start in starts for orbit from 0 do
      (let ((state start))
        (dotimes (step steps)
          (let* ((key (list key-prefix orbit step))
                 (run (evaluate transition inputs state :ledger ledger)))
            (assert (eq (evaluation-status run) :value))
            (when (zerop step) (push (list key :before) anchors))
            (push (make-row :key key :known state
                            :requirement (set-requirement state-type (list (evaluation-value run)))) rows)
            (setf state (evaluation-value run))))))
    (values (make-frame (make-schema :inputs inputs :target state-type) (nreverse rows))
            (nreverse anchors))))

(defun gf5-transition-fixture (&key (starts '((0 0) (0 1))) (steps 5)
                                  (shift-b 4) (key-prefix :training) ledger)
  (additive-transition-fixture (gf 5) starts steps shift-b key-prefix ledger))

(defun integer-transition-fixture (&key (starts '((-3 1) (0 0) (2 3))) (steps 3)
                                       (shift-b -1) (key-prefix :integer-training) ledger)
  (additive-transition-fixture :int starts steps shift-b key-prefix ledger))

(defun integer-held-out-starts ()
  "Exact cancellation, adjacent large integers, and positive/negative large outputs."
  (let ((n (ash 1 256)))
    (list (list n (- n)) (list (1+ n) (- n))
          (list (- n) n) (list (- (1+ n)) n)
          (list n n) (list (- n) (- n)))))

(defun integer-linear-fixture (&key (starts (loop for a from -2 to 2 append
                                            (loop for b from -2 to 2 collect (list a b)))) ledger)
  "Generate integer y=a+2b observations through the same metered simulator."
  (let* ((inputs '((0 . :int) (1 . :int)))
         (oracle (app (op :+ :int) (var 0 :int) (app (op :* :int) (lit :int 2) (var 1 :int))))
         (records (loop for values in starts for key from 0 collect
                    (let ((run (evaluate oracle inputs values :ledger ledger)))
                      (assert (eq :value (evaluation-status run)))
                      (list key (first values) (second values) (evaluation-value run))))))
    (values (orient-observations '(:int :int :int) records '(0 1) '(2) :lookup-p t :ledger ledger)
            oracle records)))

(defun gf7-iota-conversion (t-expr &key (steps 7) ledger)
  "Declared, metered conversion \\iota(t) from :int index T-EXPR into GF(7)."
  (assert (and (integerp steps) (plusp steps)))
  (let* ((field (gf 7))
         (key-type (tuple-type :int))
         (entry-type (tuple-type key-type field))
         (entries (loop for step below steps
                        collect (list (list step) (mod step 7))))
         (expr (app (op :lookup entry-type)
                    (app (op :tuple key-type) t-expr)
                    (lit (sequence-type entry-type) entries))))
    (charge ledger :construction (syntax-work expr))
    expr))

(defun gf7-lifting-fixture (&key (offsets '(1 3)) (steps 7) (repetitions 1) schedule ledger)
  "Generate indexed GF(7) sequences y_{j,t} = a_j + \\iota(t) with explicit occurrence
coordinate r (:int) and index t (:int). Returns:
  (values frame decoder r-to-j-map row-labels records)"
  (assert (and (integerp steps) (plusp steps)))
  (assert (and (integerp repetitions) (plusp repetitions)))
  (let* ((field (gf 7))
         (seq-tags (or schedule
                       (loop repeat repetitions
                             append (loop for idx below (length offsets) collect idx))))
         (iota-t (gf7-iota-conversion (var 1 :int) :steps steps :ledger ledger))
         (decoder (app (op :+ field) iota-t (var 9 field)))
         (oracle-inputs (list (cons 0 field) (cons 1 :int)))
         (oracle (app (op :+ field) (var 0 field)
                      (gf7-iota-conversion (var 1 :int) :steps steps :ledger ledger)))
         (records nil)
         (row-labels nil))
    (charge ledger :construction (syntax-work decoder))
    (loop for tag in seq-tags
          for r from 0
          for offset = (nth tag offsets)
          do (dotimes (step steps)
               (let* ((key (list :seq r step))
                      (run (evaluate oracle oracle-inputs (list offset step) :ledger ledger)))
                 (assert (eq :value (evaluation-status run)))
                 (push tag row-labels)
                 (push (list key r step (evaluation-value run)) records))))
    (setf records (nreverse records)
          row-labels (nreverse row-labels))
    (let* ((frame (orient-observations (list :int :int field) records '(0 1) '(2)
                                       :lookup-p t :ledger ledger))
           (label-frame (context-label-frame frame row-labels
                                             :bindings (list (cons 0 (var 0 :int)))
                                             :label-type field
                                             :ledger ledger))
           (r-to-j (lookup-model label-frame ledger)))
      (values frame decoder r-to-j row-labels records))))

(defun integer-lifting-fixture (&key (offsets '(1 3)) (steps 7) (repetitions 1) schedule ledger)
  "Generate indexed integer sequences y_{j,t} = a_j + t with explicit occurrence
coordinate r (:int) and index t (:int). Returns:
  (values frame decoder r-to-j-map row-labels records)"
  (assert (and (integerp steps) (plusp steps)))
  (assert (and (integerp repetitions) (plusp repetitions)))
  (let* ((domain :int)
         (seq-tags (or schedule
                       (loop repeat repetitions
                             append (loop for idx below (length offsets) collect idx))))
         (decoder (app (op :+ domain) (var 1 domain) (var 9 domain)))
         (oracle-inputs (list (cons 0 domain) (cons 1 domain)))
         (oracle (app (op :+ domain) (var 0 domain) (var 1 domain)))
         (records nil)
         (row-labels nil))
    (charge ledger :construction (syntax-work decoder))
    (loop for tag in seq-tags
          for r from 0
          for offset = (nth tag offsets)
          do (dotimes (step steps)
               (let* ((key (list :seq r step))
                      (run (evaluate oracle oracle-inputs (list offset step) :ledger ledger)))
                 (assert (eq :value (evaluation-status run)))
                 (push tag row-labels)
                 (push (list key r step (evaluation-value run)) records))))
    (setf records (nreverse records)
          row-labels (nreverse row-labels))
    (let* ((frame (orient-observations (list domain domain domain) records '(0 1) '(2)
                                       :lookup-p t :ledger ledger))
           (label-frame (context-label-frame frame row-labels
                                             :bindings (list (cons 0 (var 0 domain)))
                                             :label-type domain
                                             :ledger ledger))
           (r-to-j (lookup-model label-frame ledger)))
      (values frame decoder r-to-j row-labels records))))

(defun planted-abstraction-fixture (&key (domain :int) (repetitions 1) include-unrelated-p ledger)
  "Construct whole trees T_i = W_i[p[\\theta_i]] from a hidden planted template p,
substitutions \\theta_i, and varied outer wrappers W_i at distinct occurrence paths.
Returns (VALUES trees inputs hidden-oracle)."
  (let* ((inputs (list (cons 0 domain) (cons 1 domain)))
         (x0 (var 0 domain))
         (x1 (var 1 domain))
         (plus (op :+ domain))
         (mul (op :* domain))
         (sub (op :- domain))
         ;; Shared inner anchor: (+ (* X0 '2) (+ (* X1 '3) (* (+ X0 X1) '5)))
         (anchor (app plus
                      (app mul x0 (lit domain 2))
                      (app plus
                           (app mul x1 (lit domain 3))
                           (app mul (app plus x0 x1) (lit domain 5)))))
         ;; Planted template p: (+ (* ?0 anchor) (* ?0 anchor))
         ;; Has a repeated hole ?0 AND two copies of the 31-bit fixed anchor expression.
         (branch (app mul (hole 0 domain) anchor))
         (pattern (app plus branch branch))
         (ctx-hole (hole 999 domain))
         (base-wrappers-and-paths
           (list (cons ctx-hole nil)
                 (cons (app plus (lit domain 1) ctx-hole) '(1))
                 (cons (app mul ctx-hole (lit domain 2)) '(0))
                 (cons (app sub (lit domain 4) (app plus ctx-hole x1)) '(1 0))))
         (trees nil)
         (subtrees nil)
         (paths nil)
         (wrappers nil)
         (substs nil)
         (idx 0))
    (dotimes (rep repetitions)
      (loop for (wrapper . path) in base-wrappers-and-paths
            for k = (+ 2 idx)
            for arg = (case (mod idx 4)
                        (0 (if (evenp rep) x0 x1))
                        (1 (app plus x1 (lit domain k)))
                        (2 (app mul x0 (lit domain k)))
                        (otherwise (app sub (app plus x0 x1) (lit domain k))))
            for subst = (list (cons 0 arg))
            for sub-term = (instantiate pattern subst)
            for whole-tree = (instantiate wrapper (list (cons 999 sub-term)))
            do (incf idx)
               (charge ledger :construction (+ (syntax-work sub-term) (syntax-work whole-tree)))
               (push whole-tree trees)
               (push sub-term subtrees)
               (push path paths)
               (push wrapper wrappers)
               (push subst substs)))
    (when include-unrelated-p
      (let ((unrelated-1 (app plus x0 (lit domain 0)))
            (unrelated-2 (app mul x1 (lit domain 1))))
        (charge ledger :construction (+ (syntax-work unrelated-1) (syntax-work unrelated-2)))
        (push unrelated-1 trees)
        (push nil subtrees)
        (push :none paths)
        (push nil wrappers)
        (push nil substs)
        (push unrelated-2 trees)
        (push nil subtrees)
        (push :none paths)
        (push nil wrappers)
        (push nil substs)))
    (values (nreverse trees)
            inputs
            (list :pattern pattern
                  :substitutions (nreverse substs)
                  :subtrees (nreverse subtrees)
                  :paths (nreverse paths)
                  :wrappers (nreverse wrappers)))))

(defun randomized-planted-abstraction-fixture (&key (domain :int) (state 424242) (count 4) include-unrelated-p ledger)
  "Deterministic LCG-generated planted templates, substitutions, and wrapper paths.
Returns (VALUES trees inputs hidden-oracle next-state)."
  (labels ((next-int (bound)
             (setf state (mod (+ (* state 1103515245) 12345) #x7fffffff))
             (mod (ash state -8) bound)))
    (let* ((inputs (list (cons 0 domain) (cons 1 domain)))
           (vars (list (var 0 domain) (var 1 domain)))
           (ops (list (op :+ domain) (op :* domain) (op :- domain)))
           (sig (operator-type (first ops)))
           (const-val (1+ (next-int 4)))
           (template-choice (next-int 3))
           (pattern
             (ecase template-choice
               (0 ;; (?op (?op2 ?x 'c) (?op2 ?x 'c))
                (let ((sub (app (first ops) (hole 1 domain) (lit domain const-val))))
                  (app (hole 0 sig) sub sub)))
               (1 ;; (+ (* ?x ?y) (* ?x ?y))
                (let ((sub (app (second ops) (hole 0 domain) (hole 1 domain))))
                  (app (first ops) sub sub)))
               (2 ;; (?op (+ ?x 'c) (* ?x ?y))
                (app (hole 0 sig)
                     (app (first ops) (hole 1 domain) (lit domain const-val))
                     (app (second ops) (hole 1 domain) (hole 2 domain))))))
           (holes (pattern-holes pattern))
           (ctx-hole (hole 999 domain))
           (trees nil)
           (subtrees nil)
           (paths nil)
           (wrappers nil)
           (substs nil))
      (dotimes (i count)
        (let* ((subst
                 (loop for (hid . hsort) in holes
                       collect (cons hid
                                     (if (function-sort-p hsort)
                                         (nth (next-int (length ops)) ops)
                                         (ecase (next-int 3)
                                           (0 (nth (next-int (length vars)) vars))
                                           (1 (lit domain (1+ (next-int 4))))
                                           (2 (app (nth (next-int (length ops)) ops)
                                                   (nth (next-int (length vars)) vars)
                                                   (lit domain (1+ (next-int 3))))))))))
               (wrapper-choice (next-int 4))
               (w-const (lit domain (1+ (next-int 4))))
               (w-var (nth (next-int (length vars)) vars))
               (wrapper-and-path
                 (ecase wrapper-choice
                   (0 (cons ctx-hole nil))
                   (1 (cons (app (first ops) w-const ctx-hole) '(1)))
                   (2 (cons (app (second ops) ctx-hole w-const) '(0)))
                   (3 (cons (app (third ops) w-var (app (first ops) ctx-hole w-const)) '(1 0)))))
               (wrapper (car wrapper-and-path))
               (path (cdr wrapper-and-path))
               (sub-term (instantiate pattern subst))
               (whole-tree (instantiate wrapper (list (cons 999 sub-term)))))
          (charge ledger :construction (+ (syntax-work sub-term) (syntax-work whole-tree)))
          (push whole-tree trees)
          (push sub-term subtrees)
          (push path paths)
          (push wrapper wrappers)
          (push subst substs)))
      (when include-unrelated-p
        (let ((u (app (first ops) (first vars) (lit domain 0))))
          (charge ledger :construction (syntax-work u))
          (push u trees)
          (push nil subtrees)
          (push :none paths)
          (push nil wrappers)
          (push nil substs)))
      (values (nreverse trees)
              inputs
              (list :pattern pattern
                    :substitutions (nreverse substs)
                    :subtrees (nreverse subtrees)
                    :paths (nreverse paths)
                    :wrappers (nreverse wrappers))
              state))))

(defun locality-abstraction-fixture (&key (domain :int) (mode :co-local) ledger)
  "Construct a 6-tree AST corpus in which planted instances of a shared template p
are arranged according to MODE:
  :CO-LOCAL    — 2 planted trees placed adjacent at indices (3, 4), surrounded by 4 distractors.
  :DISTANT     — 2 planted trees placed at opposite ends (0, 5), separated by 4 distractors.
  :INTERLEAVED — 3 planted trees placed at even indices (0, 2, 4), interleaved with 3 odd distractors.
Returns (VALUES trees inputs hidden-oracle)."
  (assert (member mode '(:co-local :distant :interleaved)))
  (let* ((inputs (list (cons 0 domain) (cons 1 domain)))
         (x0 (var 0 domain))
         (x1 (var 1 domain))
         (plus (op :+ domain))
         (mul (op :* domain))
         (sub (op :- domain))
         (anchor (app plus
                      (app mul x0 (lit domain 2))
                      (app plus
                           (app mul x1 (lit domain 3))
                           (app mul (app plus x0 x1) (lit domain 5)))))
         (branch (app mul (hole 0 domain) anchor))
         (pattern (app plus branch branch))
         (planted-args (list x0
                             (app plus x1 (lit domain 2))
                             (app mul x0 (lit domain 3))))
         (planted-trees
           (mapcar (lambda (arg)
                     (instantiate pattern (list (cons 0 arg))))
                   planted-args))
         (distractors
           (list (app plus x0 (lit domain 1))
                 (app plus x1 (lit domain 2))
                 (app plus (app sub x0 (lit domain 3)) x1)
                 (app plus x0 (app sub x1 (lit domain 4)))))
         (trees
           (ecase mode
             (:co-local
              (list (first distractors)
                    (second distractors)
                    (third distractors)
                    (first planted-trees)
                    (second planted-trees)
                    (fourth distractors)))
             (:distant
              (list (first planted-trees)
                    (first distractors)
                    (second distractors)
                    (third distractors)
                    (fourth distractors)
                    (second planted-trees)))
             (:interleaved
              (list (first planted-trees)
                    (first distractors)
                    (second planted-trees)
                    (second distractors)
                    (third planted-trees)
                    (third distractors)))))
         (planted-indices
           (ecase mode
             (:co-local '(3 4))
             (:distant '(0 5))
             (:interleaved '(0 2 4)))))
    (dolist (tree trees)
      (charge ledger :construction (syntax-work tree)))
    (values trees
            inputs
            (list :pattern pattern
                  :mode mode
                  :planted-indices planted-indices))))
