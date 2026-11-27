;;;; xref-kernel.lisp -- kernel side of the reference cross-check.  Loads the v2 kernel (the tree that
;;;; holds library/*.sexp) from the scratch copy, loads the batteries, and
;;;;  (1) compares my hand-copied spec rows with the :SPEC entries stored in v2/library/*.sexp;
;;;;  (2) evaluates the LIBRARY's own definition in the kernel VM on each of the 200 held-out inputs
;;;;      and compares with the output of my Lisp reference.
(load (merge-pathnames "kernel/v2/load.lisp" *load-truename*))
(in-package :lisploop)
(setf *print-pretty* nil *print-right-margin* 100000)

(defparameter *seq* (sequence-type :int))
(defparameter *bin* (code-type '((0 . :int) (1 . :int)) :int))
(defparameter *una* (code-type '((0 . :int)) :int))
(defparameter *prd* (code-type '((0 . :int)) :bool))
(defun bin (s) (ecase s (+ (term `(+ ,(var 0 :int) ,(var 1 :int)))) (- (term `(- ,(var 0 :int) ,(var 1 :int))))
                 (* (term `(* ,(var 0 :int) ,(var 1 :int))))))
(defun prd (s) (ecase s (pos (term `(< 0 ,(var 0 :int)))) (even (term `(= (* (/ ,(var 0 :int) 2) 2) ,(var 0 :int))))
                 (neg (term `(< ,(var 0 :int) 0)))))
(defun unbin (ast) (or (find ast '(+ - *) :key #'bin :test #'equal) (error "unknown step ~a" (ast->sexp ast))))
(defun unprd (ast) (or (find ast '(pos even) :key #'prd :test #'equal) (error "unknown predicate ~a" (ast->sexp ast))))

;; task -> (library operator, input types, converters from probe value to kernel value, [fixed extra args])
(defparameter *map*
  `(("positions" :positions (,*seq* :int)) ("scan" :scan (,*seq* :int ,*bin*)) ("shift-seq" :shift-seq (,*seq* :int))
    ("filter" :filter (,*seq* ,*prd*)) ("map-adjacent" :map-adjacent (,*seq* ,*bin*)) ("foldl" :foldl (,*seq* :int ,*bin*))
    ("last-or" :last-or (,*seq* :int)) ("seq-corr" :seq-corr (,*seq* ,*seq*))
    ("best-shift" :best-shift (,*seq* ,*seq* :int)) ("argmax-corr" :argmax-corr (,*seq* ,*seq*))))
;; the six seed-corpus functions are not library entries; they are checked as instances of the library's
;; :map and :foldr (the abstractions the bootstrap derives from exactly these six): (operator extra-args types)
(defparameter *seed*
  `(("copy" :map (,*seq* ,*una*) ,(list (var 0 :int)))
    ("inc-all" :map (,*seq* ,*una*) ,(list (term `(+ ,(var 0 :int) 1))))
    ("dbl-all" :map (,*seq* ,*una*) ,(list (term `(* ,(var 0 :int) 2))))
    ("sum-all" :foldr (,*seq* :int ,*bin*) ,(list 0 (term `(+ ,(var 0 :int) ,(var 1 :int)))))
    ("len-all" :foldr (,*seq* :int ,*bin*) ,(list 0 (term `(+ 1 ,(var 1 :int)))))
    ("prd-all" :foldr (,*seq* :int ,*bin*) ,(list 1 (term `(* ,(var 0 :int) ,(var 1 :int)))))))

(defun to-kernel (v type) (cond ((equal type *bin*) (bin v)) ((equal type *prd*) (prd v)) (t v)))
(defun call-library (opname types args)
  (let* ((inputs (loop for ty in types for i from 0 collect (cons i ty)))
         (run (evaluate (apply #'app (op opname) (loop for (i . ty) in inputs collect (var i ty))) inputs args)))
    (if (eq :value (evaluation-status run)) (evaluation-value run) (list :status (evaluation-status run)))))

(with-knowledge-library ((make-knowledge-library))
  (dolist (b '(:sequences :scans :sequence-shift)) (load-battery b))
  (let ((data (with-open-file (in (merge-pathnames "logs/xref-data.sexp" *load-truename*))
                (let ((*package* (find-package :lisploop))) (loop for form = (read in nil) while form collect form))))
        (stored (make-hash-table :test 'equal)))
    ;; (1) stored :SPEC rows, read straight from the .sexp packets
    (dolist (b '(:sequences :scans :sequence-shift))
      (dolist (entry (knowledge-library-entries (deserialize-knowledge-library (read-battery b))))
        (when (eq :spec (knowledge-entry-kind entry))
          (setf (gethash (string-downcase (subseq (symbol-name (knowledge-entry-id entry)) 5)) stored) entry))))
    (format t "=== (1) my spec rows against the :SPEC entries in v2/library/*.sexp ===~%")
    (dolist (m *map*)
      (destructuring-bind (name opname types) m
        (declare (ignore opname))
        (let* ((entry (gethash name stored))
               (rows (and entry (knowledge-entry-residual entry)))   ; deserialized: the list of ((inputs) output) rows
               (mine (getf (rest (assoc name data :test #'string=)) :spec))
               ;; a stored value is the portable form (:LIT type value); a :code value is itself a portable expression
               (theirs (flet ((raw (v) (if (and (consp v) (eq :lit (first v))) (third v) v)))
                         (loop for (ins out) in rows
                               collect (list (loop for v in ins for ty in types
                                                   collect (cond ((equal ty *bin*) (unbin (sexp->ast (raw v))))
                                                                 ((equal ty *prd*) (unprd (sexp->ast (raw v))))
                                                                 (t (raw v))))
                                             (raw out))))))
          (format t "  ~14a stored rows ~2d, mine ~2d, identical in order and content: ~a~%"
                  name (length theirs) (length mine) (if (equal theirs mine) "YES" "NO"))
          (unless (equal theirs mine) (format t "     stored: ~s~%     mine:   ~s~%" theirs mine)))))
    ;; (2) the library definition, run in the kernel VM, against my reference on the held-out inputs
    (format t "~%=== (2) library definition (kernel VM) against my Lisp reference on the 200 held-out inputs ===~%")
    (dolist (m (append *map* *seed*))
      (destructuring-bind (name opname types &optional extra) m
        (let ((rows (getf (rest (assoc name data :test #'string=)) :held-out)) (bad 0) (first-bad nil))
          (dolist (row rows)
            (destructuring-bind (ins out) row
              (let* ((args (append (loop for v in ins for ty in types collect (to-kernel v ty)) extra))
                     (got (call-library opname types args)))
                (unless (equal got out) (incf bad) (unless first-bad (setf first-bad (list ins out got)))))))
          (format t "  ~14a via library ~12a ~3d inputs, mismatches ~d~@[  first: ~s~]~%"
                  name opname (length rows) bad first-bad))))))
(finish-output)
