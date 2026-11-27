;;; x1-baseline.lisp -- record the baseline for gate X1 on a copy of the v1 kernel.
;;; Environment: X1_V1 = directory of the kernel copy, X1_OUT = directory for output files.
(load (concatenate 'string (sb-ext:posix-getenv "X1_V1") "/load.lisp"))
(load (concatenate 'string (sb-ext:posix-getenv "X1_OUT") "/x1-lib.lisp"))
(in-package #:lisploop)

(defparameter *huge* 1000000000000)

;;; name, variables, operators, literals, body slack, work limit: bootstrap/build-batteries.lisp:127-150
(defparameter *shipped*
  '(("obs1"  1 (:+ :*) (0 1) 20 20000)
    ("obs2"  2 (:+ :*) nil   24 40000)
    ("obs3+" 3 (:+)    nil   44 80000)
    ("obs3*" 3 (:*)    nil   44 80000)))

(defun write-observed (r path)
  "Every record of the job in order of observation, with the class it joined."
  (let* ((job (x1-result-job r))
         (class-of (make-hash-table :test #'eq)))
    (loop for (bucket . members) in (bucket-list job) for i from 0
          do (dolist (m members) (setf (gethash m class-of) i)))
    (with-open-file (s path :direction :output :if-exists :supersede)
      (format s "# job ~A: index <tab> leaves <tab> body-bits <tab> status <tab> class-index <tab> values-on-rows <tab> term~%"
              (x1-result-name r))
      (loop for rec in (reverse (observation-job-records job)) for i from 0
            for e = (observed-expression-expression rec)
            do (format s "~D~C~D~C~D~C~A~C~A~C~{~D~}~C~A~%"
                       i #\Tab (count-leaves e) #\Tab (body-size e (x1-result-inputs r)) #\Tab
                       (observed-expression-status rec) #\Tab (gethash rec class-of) #\Tab
                       (observed-expression-values rec) #\Tab (short e))))))

(format t "~&===== 0. Sizes and tariffs the configuration rests on =====~%")
(let* ((gf3 (gf 3)))
  (dolist (n '(1 2 3))
    (let ((inputs (make-inputs n gf3)))
      (format t "vars=~D header-size=~D var-body-bits=~{~D~^,~} literal-body-bits=~D app-overhead(+)=~D app-overhead(*)=~D~%"
              n (header-size inputs gf3)
              (loop for i below n collect (body-size (var i gf3) inputs))
              (body-size (lit gf3 0) inputs)
              (application-overhead (op :+ gf3)) (application-overhead (op :* gf3)))
      (format t "   syntax-work: vars=~{~D~^,~} literal=~D operator-symbol(+)=~D ; validation-work of x0 on one row=~D ; value-work=~D type-work=~D~%"
              (loop for i below n collect (syntax-work (var i gf3)))
              (syntax-work (lit gf3 0)) (syntax-work (op :+ gf3))
              (validation-work (var 0 gf3) inputs (make-list n :initial-element 0))
              (value-work 0 gf3) (type-work gf3))))
  (format t "encoding-version=~D tariff-version=~D simulator-version=~D closure-evaluation=~S~%"
          +encoding-version+ +tariff-version+ +simulator-version+ *closure-evaluation*)
  (format t "row order for 2 vars (x0 x1): ~S~%" (all-rows (make-inputs 2 gf3))))

(format t "~&===== A. The four observation jobs exactly as the bootstrap runs them =====~%")
(let ((all-lines nil) (by-job nil) (all-laws nil) (total-work 0) (total-wall 0)
      (total-records 0) (total-classes 0) (total-trees 0) (typed nil))
  (when (probe-file (out-path "x1-classes.txt")) (delete-file (out-path "x1-classes.txt")))
  (dolist (spec *shipped*)
    (destructuring-bind (name nvars ops lits slack work) spec
      (let* ((r (report-result (run-config name nvars ops lits slack work)))
             (lines (equation-lines r))
             (facts (remove-if-not #'law-operator-fact (x1-result-laws r))))
        (format t "   pass-law-operator-fact=~D : ~{~A~^ ; ~}~%" (length facts) (mapcar #'law-line facts))
        (format t "   certification of all ~D: ~S~%" (length lines) (certify-all (x1-result-laws r)))
        (write-classes r (out-path "x1-classes.txt") :append t)
        (write-observed r (out-path (format nil "x1-observed-~A.txt" (file-tag name))))
        (dolist (law (x1-result-laws r))
          (push (format nil "~A~C~A" name #\Tab (law-line law)) by-job)
          (push (with-standard-io-syntax
                  (let ((*print-readably* nil) (*print-pretty* nil))
                    (format nil "~S" (list name (ast->sexp (knowledge-entry-expression law))))))
                typed))
        (setf all-lines (append all-lines lines)
              all-laws (append all-laws (x1-result-laws r)))
        (incf total-work (ledger-total (observation-job-ledger (x1-result-job r))))
        (incf total-wall (x1-result-wall-us r))
        (incf total-records (length (observation-job-records (x1-result-job r))))
        (incf total-classes (length (observation-job-buckets (x1-result-job r))))
        (incf total-trees (enumerator-tree-count (observation-job-enumerator (x1-result-job r)))))))
  (write-lines (out-path "x1-equations.txt") (sorted all-lines))
  (write-lines (out-path "x1-equations-by-job.txt") (nreverse by-job))
  (write-lines (out-path "x1-equations-typed.sexp") (nreverse typed))
  (write-lines (out-path "x1-equations-distinct.txt")
               (sorted (remove-duplicates all-lines :test #'string=)))
  (format t "~&TOTAL shipped: equations=~D distinct=~D kept-by-shape-filter=~D work=~D wall-us=~D records=~D classes=~D trees-kept=~D~%"
          (length all-lines) (length (remove-duplicates all-lines :test #'string=))
          (count-if #'law-operator-fact all-laws) total-work total-wall
          total-records total-classes total-trees))

(format t "~&===== A2. Wall time of the four shipped jobs, 50 repetitions each =====~%")
(let ((sum-min 0) (sum-median 0))
  (dolist (spec *shipped*)
    (destructuring-bind (name nvars ops lits slack work) spec
      (let* ((domain (gf 3)) (inputs (make-inputs nvars domain))
             (bound (header-bound inputs domain slack))
             (times (sort (loop repeat 50
                                collect (let* ((job (make-obs domain inputs ops lits))
                                               (t0 (now-ns)))
                                          (resume-observation-search job bound work)
                                          (wall-us t0 (now-ns))))
                          #'<)))
        (incf sum-min (first times)) (incf sum-median (nth 25 times))
        (format t "[~A] wall-us min=~D median=~D max=~D~%" name (first times) (nth 25 times)
                (car (last times))))))
  (format t "TOTAL shipped wall-us: sum of minima=~D sum of medians=~D~%" sum-min sum-median))

(format t "~&===== B. The same four grammars and bit bounds, run to exhaustion (no work cutoff) =====~%")
(dolist (spec *shipped*)
  (destructuring-bind (name nvars ops lits slack work) spec
    (declare (ignore work))
    (let* ((tag (format nil "~A-exhausted" name))
           (r (report-result (run-config tag nvars ops lits slack *huge*))))
      (write-lines (out-path (format nil "x1-exhausted-~A.equations.txt" (file-tag name))) (sorted (equation-lines r)))
      (write-classes r (out-path (format nil "x1-exhausted-~A.classes.txt" (file-tag name))))
      (format t "   pass-law-operator-fact=~D~%" (count-if #'law-operator-fact (x1-result-laws r))))))

(format t "~&===== C. Neighbouring bit bounds, each run to exhaustion (counts only) =====~%")
(dolist (sweep '(("obs1"  1 (:+ :*) (0 1) (8 10 12 14 16 18 20 22 24 26))
                 ("obs2"  2 (:+ :*) nil   (12 20 21 24 29 30))
                 ("obs3+" 3 (:+)    nil   (14 23 24 33 34 43 44))
                 ("obs3*" 3 (:*)    nil   (14 23 24 33 34 43 44))))
  (destructuring-bind (name nvars ops lits slacks) sweep
    (dolist (slack slacks)
      (let* ((r (run-config (format nil "~A@~D" name slack) nvars ops lits slack *huge*))
             (job (x1-result-job r)))
        (format t "[~A slack=~D] records=~D classes=~D equations=~D work=~D wall-us=~D facts=~D~%"
                name slack (length (observation-job-records job))
                (length (observation-job-buckets job)) (length (x1-result-laws r))
                (ledger-total (observation-job-ledger job)) (x1-result-wall-us r)
                (count-if #'law-operator-fact (x1-result-laws r)))
        ;; The two 3-variable jobs at the bounds that end on a whole number of leaves.
        (when (and (= nvars 3) (member slack '(24 34)))
          (let ((stem (format nil "x1-bound~D-~A" slack (file-tag name))))
            (write-lines (out-path (format nil "~A.equations.txt" stem)) (sorted (equation-lines r)))
            (write-classes r (out-path (format nil "~A.classes.txt" stem)))))))))

(format t "~&===== D. Work-limit sensitivity of the two cut-off jobs =====~%")
(dolist (spec (cddr *shipped*))
  (destructuring-bind (name nvars ops lits slack work) spec
    (declare (ignore work slack))
    ;; Thresholds up to the end of the 3-leaf terms (24 body bits) are enough to bracket 80,000.
    (let ((thresholds (record-thresholds nvars ops lits 24)))
      (format t "[~A] ledger total when record k is finished (k from 1), terms of at most 24 body bits:~%" name)
      (loop for (w . e) in thresholds for k from 1
            do (format t "   k=~D work=~D ~A~%" k w (short e))))))
(dolist (limit '(20000 40000 60000 70000 79000 80000 81000 82000 90000 100000 120000 160000 320000 1000000))
  (dolist (spec (cddr *shipped*))
    (destructuring-bind (name nvars ops lits slack work) spec
      (declare (ignore work))
      (let* ((r (run-config name nvars ops lits slack limit))
             (job (x1-result-job r)))
        (format t "[~A work-limit=~D] claim=~S records=~D classes=~D equations=~D facts=~D~%"
                name limit (message-claim (x1-result-message r))
                (length (observation-job-records job)) (length (observation-job-buckets job))
                (length (x1-result-laws r)) (count-if #'law-operator-fact (x1-result-laws r)))))))

(format t "~&===== E. Distributivity: 3 variables, {+,*}, no literals, GF(3) =====~%")
(let* ((gf3 (gf 3))
       (in3 (make-inputs 3 gf3))
       (a (var 0 gf3)) (b (var 1 gf3)) (c (var 2 gf3))
       (lhs (term `(* ,a (+ ,b ,c))))
       (rhs (term `(+ (* ,a ,b) (* ,a ,c)))))
  (format t "body bits: ~A = ~D ; ~A = ~D~%" (short lhs) (body-size lhs in3) (short rhs) (body-size rhs in3))
  (dolist (slack '(24 33 34 44))
    (let* ((name (format nil "dist~D" slack))
           (r (report-result (run-config name 3 '(:+ :*) nil slack *huge*)))
           (job (x1-result-job r))
           (l (find-observation job lhs)) (rr (find-observation job rhs)))
      (format t "   lhs-observed=~S rhs-observed=~S same-class=~S pass-law-operator-fact=~D~%"
              (not (null l)) (not (null rr)) (and l rr (observed-agreement-p l rr) t)
              (count-if #'law-operator-fact (x1-result-laws r)))
      (when (<= slack 34)
        (write-lines (out-path (format nil "x1-~A.equations.txt" name)) (sorted (equation-lines r)))
        (write-classes r (out-path (format nil "x1-~A.classes.txt" name))))
      (when (= slack 44)
        (write-classes r (out-path (format nil "x1-~A.classes-reps.txt" name)) :max-members 1))
      (when (and l rr (observed-agreement-p l rr))
        (let* ((entry (find-if (lambda (x) (member l (cdr x))) (bucket-list job)))
               (members (cdr entry)))
          (format t "   class of ~A: ~D members, representative ~A~%   members: ~{~A~^ ; ~}~%"
                  (short lhs) (length members)
                  (short (observed-expression-expression (first members)))
                  (mapcar (lambda (m) (short (observed-expression-expression m))) members))
          (format t "   equation proposed: ~A~%"
                  (find-if (lambda (line) (search (short rhs) line)) (equation-lines r)))
          (when (= slack 34)
            (format t "   certification of all ~D equations at this bound: ~S~%"
                    (length (x1-result-laws r)) (certify-all (x1-result-laws r) 1000000))))))))
;; The bootstrap's own budget for a 3-variable job, applied to this grammar.
(let* ((r (run-config "dist34@80000" 3 '(:+ :*) nil 34 80000)) (job (x1-result-job r)))
  (format t "[dist34 work-limit=80000] claim=~S records=~D classes=~D equations=~D~%"
          (message-claim (x1-result-message r)) (length (observation-job-records job))
          (length (observation-job-buckets job)) (length (x1-result-laws r))))

(format t "~&===== F. The enumerator alone at the same bounds (no evaluation) =====~%")
(defun enumerator-only (nvars ops literals slack &key (p 3))
  (let* ((domain (gf p)) (inputs (make-inputs nvars domain))
         (language (make-language domain inputs
                                  :operators (mapcar (lambda (n) (op n domain)) ops)
                                  :literals literals))
         (enumerator (make-enumerator language))
         (steps 0) (candidates 0) (construction 0)
         (t0 (now-ns)))
    (loop
      (multiple-value-bind (expression event) (enumeration-step enumerator)
        (incf steps)
        (case event
          (:candidate (incf candidates) (incf construction (syntax-work expression))
           (index-expression enumerator expression))
          (:bound (when (>= (1- (enumerator-size enumerator)) slack) (return))))))
    ;; Retained bytes of the enumerator's store are in x1-memory.log ("enumerator-only").
    (list :enumeration-steps steps :candidates candidates :construction-work construction
          :work (+ steps construction) :trees-kept (enumerator-tree-count enumerator)
          :wall-us (wall-us t0 (now-ns)))))
(dolist (spec '(("obs1" 1 (:+ :*) (0 1) 20) ("obs2" 2 (:+ :*) nil 24)
                ("obs3+" 3 (:+) nil 24) ("obs3+" 3 (:+) nil 34) ("obs3+" 3 (:+) nil 44)
                ("obs3*" 3 (:*) nil 44)
                ("dist" 3 (:+ :*) nil 24) ("dist" 3 (:+ :*) nil 34) ("dist" 3 (:+ :*) nil 44)))
  (destructuring-bind (name nvars ops lits slack) spec
    (format t "[~A slack=~D] ~S~%" name slack (enumerator-only nvars ops lits slack))))

(format t "~&===== G. Certification entry points, shown on single laws =====~%")
(let* ((gf3 (gf 3)) (in2 (make-inputs 2 gf3)) (a (var 0 gf3)) (b (var 1 gf3)))
  (flet ((show (title law &rest args)
           (let ((val (apply #'resume-law-validation (start-law-validation law) args)))
             (format t "~A~%   status=~S work=~D ledger=~S~%   certificate=~S~%   counterexample=~S~%"
                     title (law-validation-status val)
                     (ledger-total (law-validation-ledger val))
                     (ledger-alist (law-validation-ledger val))
                     (let ((cert (law-validation-certificate val)))
                       (and cert (list :method (getf cert :method) :obligations (getf cert :obligations)
                                       :assignments (getf cert :assignments) :active (getf cert :active)
                                       :work (getf cert :work))))
                     (law-validation-counterexample val))
             (format t "   current-evidence=~S tested-evidence=~S entry-status=~S~%"
                     (and (knowledge-evidence-current-p (law-validation-law val) :equivalence) t)
                     (and (knowledge-evidence-tested-p (law-validation-law val) :equivalence) t)
                     (knowledge-entry-status (law-validation-law val)))
             val)))
    (show "true law (+ x1 x0) = (+ x0 x1), work limit 100000"
          (make-law gf3 in2 (term `(+ ,b ,a)) (term `(+ ,a ,b))) 100000)
    (show "false law (+ x0 x1) = (* x0 x1), work limit 100000"
          (make-law gf3 in2 (term `(+ ,a ,b)) (term `(* ,a ,b))) 100000)
    (show "true law, work limit 50 (too small to finish)"
          (make-law gf3 in2 (term `(+ ,b ,a)) (term `(+ ,a ,b))) 50)
    (let* ((cube (make-law gf3 (make-inputs 1 gf3) (term `(* ,a (* ,a ,a))) a))
           (val (show "GF(3)-only law (* x0 (* x0 x0)) = x0, exhaustive on GF(3)" cube 100000))
           (retyped (retype-law (law-validation-law val) :int))
           (samples (residue-assignments (mapcar #'cdr (knowledge-entry-inputs retyped)) '(-3 -1 0 1 2 5)))
           (ival (validate-law retyped 100000 t samples)))
      (format t "the same law retyped to :int and sampled on ~D assignments: status=~S counterexample=~S~%"
              (length samples) (law-validation-status ival) (law-validation-counterexample ival)))))
(format t "~&===== H. The ledger does not depend on how terms are evaluated or how the run is sliced =====~%")
(dolist (spec *shipped*)
  (destructuring-bind (name nvars ops lits slack work) spec
    (let* ((domain (gf 3)) (inputs (make-inputs nvars domain))
           (bound (header-bound inputs domain slack)))
      (flet ((run-one (closures quantum)
               (let* ((*closure-evaluation* closures)
                      (job (make-obs domain inputs ops lits))
                      (t0 (now-ns)))
                 (resume-observation-search job bound work :quantum quantum)
                 (list :work (ledger-total (observation-job-ledger job))
                       :ledger (ledger-alist (observation-job-ledger job))
                       :records (length (observation-job-records job))
                       :equations (mapcar #'law-line (propose-observed-laws job))
                       :wall-us (wall-us t0 (now-ns))))))
        (let ((a (run-one t nil)) (b (run-one nil nil)) (c (run-one t 7)))
          (format t "[~A] closures: work=~D wall-us=~D | interpreter: work=~D wall-us=~D | closures, quantum 7: work=~D~%"
                  name (getf a :work) (getf a :wall-us) (getf b :work) (getf b :wall-us) (getf c :work))
          (format t "   same ledger, records and equations in all three: ~S~%"
                  (and (equal (getf a :ledger) (getf b :ledger)) (equal (getf a :ledger) (getf c :ledger))
                       (= (getf a :records) (getf b :records) (getf c :records))
                       (equal (getf a :equations) (getf b :equations))
                       (equal (getf a :equations) (getf c :equations)))))))))
(format t "~&===== done =====~%")
