;;; Gate X2 (plan_v2c.md section 11.2): reorientation.
;;;
;;;   sbcl --script gates/x2.lisp
;;;
;;; Find the eight arithmetic solvers and their guards from operator tables alone: no spec rows,
;;; and no language for the answer terms beyond the operators in scope. The gate is the same
;;; answer terms and guards that the present kernel's milestone code finds, as recorded in
;;; ../baselines/x2/x2-solvers.sexp: eight solvers on each of GF(5), GF(7) and the integers.
;;;
;;; How "the same" is judged. An answer term is compared as text, with the baseline's x0 and x1
;;; written k and c; where the text differs only in the order of the arguments of a commutative
;;; operator, the two are also compared by value. A guard is compared by its truth table over
;;; every pair of grid values, which the baseline records, because the two kernels write
;;; Boolean terms differently: the baseline has IF only, and this kernel has TRY as well.

(load (merge-pathnames "common.lisp" (make-pathname :name nil :type nil :defaults *load-truename*)))
(in-package #:lisploop2)

(defun baseline-records () (read-forms (baseline-path "x2/x2-solvers.sexp")))

(defun rename (sexp)
  "The baseline's variables x0 (the known argument) and x1 (the result), as this kernel's k and c."
  (cond ((eq sexp 'x0) 'k) ((eq sexp 'x1) 'c)
        ((consp sexp) (mapcar #'rename sexp))
        (t sexp)))

(defun domain-type (name)
  (cond ((string= name "INT") :int)
        (t (gf (parse-integer name :start 3 :end (1- (length name)))))))

(defun solve-record (record)
  "Run reorientation for the operator, position and domain of a baseline RECORD."
  (let* ((type (domain-type (getf record :domain)))
         (name (intern (symbol-name (getf record :operator)) '#:lisploop2))
         (position (getf record :unknown))
         (grid (getf record :grid)))
    (if (eq type :int)
        ;; the rows solved on have the unknown in the baseline's grid; uniqueness is judged on a
        ;; range twice as wide, because a finite table creates false dependencies at its edge
        (let* ((reach (reduce #'max grid))
               (wide (loop for v from (* -2 reach) to (* 2 reach) collect v)))
          (reorient name (list type type) position
                    :ranges (if (= position 0) (list wide grid) (list grid wide))
                    :inner grid :op-names '(+ - * / mod < = if) :constants '((:int 0 1))
                    :max-size 7 :budget 20000000))
        (reorient name (list type type) position
                  :op-names '(+ - * / = if) :constants `((,type 0 1))))))

(defun guard-table (solver grid)
  "The solver's guard over every pair of grid values, in the baseline's layout: one string for
each value of the known argument, one character for each value of the result."
  (loop for k in grid
        collect (map 'string (lambda (c) (if (eq t (run-term (solver-guard solver) `((k . ,k) (c . ,c)))) #\1 #\0))
                     grid)))

(defun answers-agree-p (solver record)
  "True when, wherever the baseline's guard holds, this kernel's answer has the baseline's value."
  (let ((grid (getf record :grid)))
    (loop for k in grid for guard-row in (getf record :guard-on-grid)
          for answer-row in (getf record :answer-on-grid)
          always (loop for c in grid for flag across guard-row for theirs in answer-row
                       always (or (char= flag #\0)
                                  (eql theirs (run-term (solver-answer solver) `((k . ,k) (c . ,c)))))))))

(format t "Gate X2: reorientation~%")
(let ((records (baseline-records)) (t0 (get-internal-real-time))
      (answers-same 0) (guards-same 0) (total-work 0) (total-candidates 0) (failures '()))
  (format t "~%~7a ~3a ~3a  ~12a ~6a ~7a  ~26a ~9a ~9a ~10a~%" "domain" "op" "arg" "answer" "text" "values"
          "uniqueness guard (extra)" "guard" "work" "baseline")
  (dolist (record records)
    (let* ((solver (solve-record record))
           (grid (getf record :grid))
           (theirs (rename (let ((*package* (find-package '#:lisploop2)))
                             (read-from-string (getf record :answer)))))
           (mine (and (solver-answer solver) (term->sexp (solver-answer solver))))
           (text (equal mine theirs))
           (by-value (and mine (answers-agree-p solver record)))
           (guard (and mine (equal (guard-table solver grid) (getf record :guard-on-grid)))))
      (when (or text by-value) (incf answers-same))
      (when guard (incf guards-same))
      (unless (and (or text by-value) guard)
        (push (list (getf record :domain) (getf record :operator) (getf record :unknown)) failures))
      (incf total-work (solver-work solver))
      (incf total-candidates (solver-candidates solver))
      (format t "~7a ~3a ~3d  ~12a ~6a ~7a  ~26a ~9a ~9:d ~10:d~%"
              (getf record :domain) (symbol-name (getf record :operator)) (getf record :unknown)
              mine (if text "same" "differs") (if by-value "same" "DIFFER")
              (cond ((null (solver-unique-guard solver)) (format nil "none found (share ~,2f)" (solver-share solver)))
                    ((eq (solver-unique-guard solver) (true)) "always")
                    (t (solver-unique-guard solver)))
              (if guard "same" "DIFFERS") (solver-work solver)
              (+ (getf record :work-relation) (getf record :work-discover) (getf record :work-validate)))))
  (format t "~%answer terms the same as the baseline's: ~d of ~d~%" answers-same (length records))
  (format t "guards with the baseline's truth table over the grid: ~d of ~d~%" guards-same (length records))
  (format t "work: ~:d cells and ~:d candidates for all ~d, in ~,2f s. The baseline spent ~:d ledger units by the same count (relation, discovery and validation), in units that are not cells.~%"
          total-work total-candidates (length records) (seconds-since t0)
          (reduce #'+ records :key (lambda (r) (+ (getf r :work-relation) (getf r :work-discover)
                                                  (getf r :work-validate)))))

  ;; certification on the fields: the whole domain, not the table
  (format t "~%Certification on the two fields, over every pair (k, c) and every value of the unknown:~%")
  (dolist (p '(5 7))
    (let ((type (gf p)) (sound 0) (exact 0))
      (dolist (name '(+ - * /))
        (dotimes (position 2)
          (let* ((solver (reorient name (list type type) position :op-names '(+ - * / = if)
                                                                   :constants `((,type 0 1))))
                 (report (certify-solver solver)))
            (when (getf report :sound) (incf sound))
            (when (getf report :exact) (incf exact)))))
      (format t "  GF(~d): ~d of 8 solvers sound (where the guard holds, the answer is a solution); ~d of 8 exact (the guard and the uniqueness guard hold together exactly where one solution exists)~%"
              p sound exact)))

  ;; the two composite cases of section 10, risk 2: reported, not gated
  (format t "~%The two composite cases (reported, not gated). Each is solved from its own table.~%")
  (flet ((range (lo hi) (loop for v from lo to hi collect v)))
    (let* ((env '((a . :int) (b . :int) (x . :int)))
           (inner (range -4 4)) (wide (range -8 8)))
      (dolist (case (list (list "a*x + b = c, for x" '(+ (* a x) b) (list inner wide inner)
                                (list (range -5 5) (range -60 60) (range -5 5)) (range -20 20) '((:int 0 1)))
                          (list "x + x = c, for x" '(+ x x) (list wide)
                                (list (range -60 60)) (range -30 30) '((:int 0 1)))))
        (destructuring-bind (label sexp ranges check-ranges check-results constants) case
          (let* ((start (get-internal-real-time))
                 (solver (reorient-term (parse-term sexp env) (var 'x :int)
                                        :ranges ranges :inner inner
                                        :op-names '(+ - * / mod < = if) :constants constants
                                        :max-size 7 :budget 50000000))
                 (report (and (solver-guard solver) (check-solver solver check-ranges check-results))))
            (format t "  ~a~%     answer ~a~%     guard ~a~%     uniqueness guard ~a~%     on a wider grid: sound ~a, exact ~a; work ~:d cells, ~,2f s~%"
                    label (solver-answer solver) (solver-guard solver) (solver-unique-guard solver)
                    (getf report :sound) (getf report :exact) (solver-work solver) (seconds-since start)))))))

  (format t "~%GATE X2~%")
  (format t "  the same answer terms: ~d of ~d~%  the same guards: ~d of ~d~%" answers-same (length records)
          guards-same (length records))
  (format t "  including the unknown-divisor solver and the integer divisibility guard: ~a~%"
          (if (notany (lambda (f) (or (equal f '("INT" :* 0)) (equal f '("INT" :* 1)) (equal (cdr f) '(:/ 1))))
                      failures)
              "yes" "NO"))
  (format t "  ~:[FAILED: ~a~;passed~]~%" (null failures) (reverse failures)))
