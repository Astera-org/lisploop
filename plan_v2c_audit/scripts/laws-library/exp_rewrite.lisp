;;; Read-only experiment 3: what the law-driven rewrite filter in `start-search :laws` buys.
;;; Same frame (y = a + 2b over GF(5), 25 rows), same language (+,*, all literals), same bound.
(load "/home/tlh24/lisploop/load.lisp")
(in-package #:lisploop)

(defun ticks () (get-internal-real-time))
(defun secs (t0) (/ (float (- (get-internal-real-time) t0) 1d0) internal-time-units-per-second))

(let* ((field (gf 5))
       (inputs (list (cons 0 field) (cons 1 field)))
       (a (var 0 field)) (b (var 1 field))
       (plus (op :+ field)) (mul (op :* field))
       (oracle (app plus a (app mul (lit field 2) b)))
       (records (loop for x below 5 append
                  (loop for y below 5 for key from (* x 5)
                        collect (list key x y (evaluation-value (evaluate oracle inputs (list x y)))))))
       (frame (orient-observations (list field field field) records '(0 1) '(2) :lookup-p t))
       (language (make-language field inputs))
       (bound (description-size oracle inputs))
       ;; Laws: everything observational discovery proposes on the full GF(5) grid at a small bound,
       ;; exhaustively validated (as tests/laws.lisp does), plus hand-stated comm/assoc for + and *.
       (rows (loop for x below 5 append (loop for y below 5 collect (list x y))))
       (obs (start-observation-search (make-observation-scope (probe-frame field inputs rows) language)))
       (obs-bound (+ (header-size inputs field) (application-overhead plus)
                     (* 2 (body-size (lit field 0) inputs)))))
  (resume-observation-search obs obs-bound 100000000)
  (let* ((proposed (propose-observed-laws obs))
         (validated (loop for law in proposed
                          for v = (resume-law-validation (start-law-validation law) 10000000)
                          when (eq :validated (law-validation-status v)) collect v))
         (identity-only (remove-if-not
                         (lambda (v) (let ((s (rest (knowledge-entry-expression (law-validation-law v)))))
                                       (or (equal s (list (app plus a (lit field 0)) a))
                                           (equal (reverse s) (list (app plus a (lit field 0)) a)))))
                         validated)))
    (format t "~&observational laws proposed at depth-1 bound: ~D, validated: ~D~%" (length proposed) (length validated))
    (flet ((run (name laws)
             (let* ((job (if laws (start-search frame language :laws laws) (start-search frame language)))
                    (t0 (ticks))
                    (msg (resume-search job bound 2000000000))
                    (dt (secs t0))
                    (ledger (search-job-ledger job)))
               (format t "~&[~A] claim=~S results=~D rejected=~D reused-rejections=~D total-work=~D wall=~,2Fs~%   ledger=~S~%"
                       name (message-claim msg) (length (search-job-results job)) (search-job-rejected job)
                       (search-job-reused-rejections job) (ledger-total ledger) dt
                       (sort (copy-list (ledger-counts ledger)) #'> :key #'cdr)))))
      (format t "bound=~D bits (oracle ~A)~%" bound (ast->sexp oracle))
      (run "plain, no laws" nil)
      (run "1 law: x+0=x" identity-only)
      (run (format nil "all ~D validated depth-1 laws" (length validated)) validated))))
