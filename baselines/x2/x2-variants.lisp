;;;; x2-variants.lisp -- which of the 24 baseline results depend on the caller's choices?
;;;; Re-runs the milestone discovery with one choice changed at a time: the grid, the query rows,
;;;; the literals, the body bound, the operators of the answer language, the field.
;;;; Each line gives the answer term and guard, and marks a difference from the baseline fixture.
(load (merge-pathnames "x2-common.lisp" (make-pathname :name nil :type nil :defaults *load-truename*)))
(in-package #:lisploop)
(setf *print-pretty* nil)

(defvar *baseline* (make-hash-table :test #'equal)
  "(domain-class operator position) -> (answer guard), domain-class being :field or :int.")

(defun domain-class (domain) (if (eq domain :int) :int :field))

(defun one (domain name position &key (values (x2-values domain)) (query-values values)
                                      (literals (x2-literals domain))
                                      (operators '(:+ :- :* :/)) (body-bound 16)
                                      (work-limit +completion-work+))
  "(values answer guard work seconds candidates) as strings/numbers, or an error string."
  (handler-case
      (multiple-value-bind (result meter seconds)
          (call-metered
           (lambda ()
             (let* ((relation (observe-arithmetic-relation domain name values))
                    (discovery (discover-arithmetic-solver relation position query-values
                                                           :operators operators :literals literals
                                                           :body-bound body-bound :work-limit work-limit)))
               discovery)))
        (values (short (solve-discovery-witness result)) (short (solve-discovery-guard result))
                (meter-total meter) seconds
                (length (observation-job-records (solve-discovery-observations result)))))
    (error (c)
      (let ((text (substitute #\Space #\Newline (princ-to-string c))))
        (values :error (subseq text 0 (min 90 (length text))) 0 0 0)))))

(defun variant (label domain &rest keys)
  (format t "~%-- ~A  [~A]~%" label (domain-name domain))
  (let ((differences 0))
    (dolist (name '(:+ :- :* :/))
      (dolist (position '(0 1))
        (multiple-value-bind (answer guard work seconds candidates) (apply #'one domain name position keys)
          (let* ((base (gethash (list (domain-class domain) name position) *baseline*))
                 (same (and base (equal (first base) answer) (equal (second base) guard))))
            (unless same (incf differences))
            (format t "   ~A ~D  ~12A  ~A~60T ~A  cand ~5D  work ~10D  ~,3F s~%"
                    (string-downcase name) position answer guard
                    (cond ((null base) "") (same "same") (t "DIFFERS"))
                    candidates work seconds)
            (finish-output)))))
    (format t "   => ~D of 8 differ from the baseline~%" differences)))

;;; Baseline: the fixture's own settings. GF(5) and GF(7) give the same terms; both are recorded.
(format t "~&===== Baseline (the fixture's settings) =====~%")
(dolist (domain (list (gf 5) (gf 7) :int))
  (format t "~%-- baseline  [~A]~%" (domain-name domain))
  (dolist (name '(:+ :- :* :/))
    (dolist (position '(0 1))
      (multiple-value-bind (answer guard work seconds candidates) (one domain name position)
        (let ((key (list (domain-class domain) name position)))
          (when (and (gethash key *baseline*) (not (equal (gethash key *baseline*) (list answer guard))))
            (format t "   !! GF(5) and GF(7) disagree on ~S~%" key))
          (setf (gethash key *baseline*) (list answer guard)))
        (format t "   ~A ~D  ~12A  ~A~60T cand ~5D  work ~10D  ~,3F s~%"
                (string-downcase name) position answer guard candidates work seconds)))))

(format t "~%===== V1. Other fields (whole field as the grid, literals :all, bound 16) =====~%")
(dolist (p '(2 3 11 13))
  (variant (format nil "field GF(~D)" p) (gf p)))

(format t "~%===== V2. Integer grid (literals -1 0 1, bound 16) =====~%")
(dolist (grid (list '(-2 -1 0 1 2) '(-3 -2 -1 0 1 2 3) '(-6 -5 -4 -3 -2 -1 0 1 2 3 4 5 6)
                    '(0 1 2 3 4) '(1 2 3 4 5) '(-7 -3 0 2 5 11)))
  (variant (format nil "integer grid ~S" grid) :int :values grid))

(format t "~%===== V3. No query rows: the operator's own table only =====~%")
(variant "integer, grid -4..4, query rows none" :int :query-values nil)
(variant "GF(5), query rows none" (gf 5) :query-values nil)
(variant "GF(7), query rows none" (gf 7) :query-values nil)

(format t "~%===== V4. Integer literals of the answer language (grid -4..4, bound 16) =====~%")
(variant "literals none" :int :literals nil)
(variant "literals (0 1)" :int :literals '(0 1))
(variant "literals (-1 0 1 2)" :int :literals '(-1 0 1 2))
(variant "literals :all (every integer that fits the bound)" :int :literals :all)

(format t "~%===== V5. Body bound of the answer language =====~%")
(dolist (bound '(12 14 18 20 22 24))
  (variant (format nil "integer, body bound ~D" bound) :int :body-bound bound))
(dolist (bound '(12 14 18 20 22))
  (variant (format nil "GF(5), body bound ~D" bound) (gf 5) :body-bound bound))

(format t "~%===== V6. Operators of the answer language =====~%")
(variant "integer, operators + - * / mod, bound 16" :int :operators '(:+ :- :* :/ :mod))
(variant "integer, operators + - * / mod, bound 28" :int :operators '(:+ :- :* :/ :mod) :body-bound 28)
(variant "integer, operators + * only, bound 24 (as tests/milestones/algebra.lisp:57-73 does for +)" :int
         :operators '(:+ :*) :body-bound 24)
(variant "GF(5), operators + * only, bound 24" (gf 5) :operators '(:+ :*) :body-bound 24)
(variant "integer, operators + - * only, bound 16" :int :operators '(:+ :- :*))
(variant "GF(5), operators + - * only, bound 16" (gf 5) :operators '(:+ :- :*))
