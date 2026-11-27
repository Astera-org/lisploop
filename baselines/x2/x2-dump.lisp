;;;; x2-dump.lisp -- record what the v1 milestone code finds for the eight arithmetic solvers.
;;;; It calls the milestone functions exactly as the test fixture ARITHMETIC-CONTROLS does
;;;; (tests/milestones/support.lisp:198-208): for each domain in GF(5), GF(7), :int, each operator
;;;; in + - * /, and each unknown position 0, 1.
;;;; Output: x2-solvers.txt (one block per solver) and x2-solvers.sexp (machine-readable).

(load (merge-pathnames "x2-common.lisp" (make-pathname :name nil :type nil :defaults *load-truename*)))
(in-package #:lisploop)

;;; Log what SEARCH-MEMBERSHIP-FRAME returns (the learned Boolean parts of each guard).
(defvar *membership-log* :off)
(sb-int:encapsulate
 'search-membership-frame 'x2-log
 (lambda (f &rest args)
   (let ((job (apply f args)))
     (unless (eq *membership-log* :off)
       (push (list (short (candidate-expression (search-job-best job)))
                   (length (frame-rows (search-job-frame job)))
                   (ledger-total (search-job-ledger job))
                   (if (getf (cddr args) :expressions) :replay :search))
             *membership-log*))
     job)))

(defun coverage-ranking (discovery)
  "Recompute, independently of the kernel's bookkeeping, how many frame rows each enumerated
answer term satisfies: R(k, c, q(k,c)) evaluates to T. Returns entries (model count size index mask)."
  (let* ((relation (solve-discovery-relation discovery))
         (position (solve-discovery-position discovery))
         (domain (arithmetic-relation-domain relation))
         (inputs (arithmetic-inputs domain))
         (frame (solve-discovery-frame discovery))
         (requirement (arithmetic-requirement relation position))
         (records (remove-if-not (lambda (r) (equal domain (observed-expression-type r)))
                                 (reverse (observation-job-records (solve-discovery-observations discovery))))))
    (loop for record in records for index from 0
          collect (let* ((model (observed-expression-expression record))
                         (check (instantiate requirement (list (cons 2 model)) :var))
                         (mask (loop for row in (frame-rows frame)
                                     collect (multiple-value-bind (status value)
                                                 (x2-eval check inputs (row-known row))
                                               (and (eq status :value) (eq value t))))))
                    (list model (count t mask) (description-size model inputs) index mask)))))

(defun guard-table (guard domain values)
  "Rows k, columns c: 1 where the guard is T, 0 where NIL, E where it raises an error."
  (let ((inputs (arithmetic-inputs domain)))
    (loop for k in values collect
      (format nil "~{~A~}"
              (loop for c in values collect
                (multiple-value-bind (status value) (x2-eval guard inputs (list k c))
                  (cond ((not (eq status :value)) "E") (value "1") (t "0"))))))))

(defun certificate-method (validation)
  (and validation (getf (knowledge-entry-certificate (law-validation-law validation)) :method)))

(defparameter *sexp-rows* nil)
(defparameter *grand-work* 0)
(defparameter *grand-seconds* 0d0)
(defparameter *domain-totals* nil
  "Per domain: (name all-ledger-work retained-ledger-work seconds), retained = the discovery ledger
plus the enumeration ledger, the definition the audit's empirical report used.")
(setf *print-pretty* nil)

(defun dump-domain (domain out)
  (let ((values (x2-values domain)) (literals (x2-literals domain))
        (work-before *grand-work*) (seconds-before *grand-seconds*) (retained 0))
    (dolist (name '(:+ :- :* :/))
      (let (relation relation-meter relation-seconds relation-log)
        (let ((*membership-log* nil))
          (multiple-value-setq (relation relation-meter relation-seconds)
            (call-metered (lambda () (observe-arithmetic-relation domain name values))))
          (setf relation-log (reverse *membership-log*)))
        (incf *grand-work* (meter-total relation-meter))
        (incf *grand-seconds* relation-seconds)
        (dolist (position '(0 1))
          (let (discovery d-meter d-seconds d-log v-meter v-seconds)
            (let ((*membership-log* nil))
              (multiple-value-setq (discovery d-meter d-seconds)
                (call-metered (lambda () (discover-arithmetic-solver relation position values
                                                                     :literals literals))))
              (setf d-log (reverse *membership-log*)))
            (multiple-value-setq (discovery v-meter v-seconds)
              (call-metered (lambda ()
                              (if (eq domain :int)
                                  (integer-solver-held-out discovery)
                                  (validate-arithmetic-solver discovery))
                              discovery)))
            (incf *grand-work* (+ (meter-total d-meter) (meter-total v-meter)))
            (incf *grand-seconds* (+ d-seconds v-seconds))
            (incf retained (+ (ledger-total (solve-discovery-ledger discovery))
                              (ledger-total (observation-job-ledger (solve-discovery-observations discovery)))))
            (let* ((inputs (arithmetic-inputs domain))
                   (witness (solve-discovery-witness discovery))
                   (guard (solve-discovery-guard discovery))
                   (frame (solve-discovery-frame discovery))
                   (rows (frame-rows frame))
                   (forward-rows (count-if (lambda (row) (eq :forward (first (row-key row)))) rows))
                   (query-rows (count-if (lambda (row) (eq :query (first (row-key row)))) rows))
                   (observations (solve-discovery-observations discovery))
                   (language (observation-scope-language (observation-job-scope observations)))
                   (all-records (observation-job-records observations))
                   (ranking (coverage-ranking discovery))
                   (ranked (stable-sort (copy-list ranking)
                                        (lambda (a b) (if (/= (second a) (second b)) (> (second a) (second b))
                                                          (< (third a) (third b))))))
                   (top (first ranked))
                   (same-mask (remove-if-not (lambda (e) (equal (fifth e) (fifth top))) ranking))
                   (validation (solve-discovery-validation discovery))
                   (uniqueness (solve-discovery-uniqueness discovery))
                   (certified (certified-solve-discovery-p discovery))
                   (arguments (rest (solve-discovery-solver-arguments discovery)))
                   (library (prepare-propagator-library (list discovery) (make-ledger)))
                   (rule (first (propagator-library-rules library)))
                   (entry (and rule (arithmetic-propagator-source rule)))
                   (grid (guard-table guard domain values))
                   (active (loop for line in grid sum (count #\1 line)))
                   (k-arg (- 1 position)))
              (format out "~%================================================================================~%")
              (format out "SOLVER  operator ~(~A~)   unknown = argument ~D   domain ~A~%"
                      name position (domain-name domain))
              (format out "================================================================================~%")
              (format out "equation            : ~A = c, solved for z; k is the known argument (argument ~D)~%"
                      (if (zerop position) (format nil "(~(~A~) z k)" name) (format nil "(~(~A~) k z)" name)) k-arg)
              (format out "variables           : x0 = k (known argument), x1 = c (result)~%")
              (format out "forward grid        : ~D x ~D pairs, values ~S~%" (length values) (length values) values)
              (format out "forward definedness : ~A   [learned, over x0 = argument 0, x1 = argument 1]~%"
                      (short (arithmetic-relation-guard relation)))
              (format out "forward exhaustive  : ~S~%" (arithmetic-relation-exhaustive-p relation))
              (format out "solver frame        : ~D rows = ~D forward rows (k, c observed) + ~D query rows (k, c in grid x grid)~%"
                      (length rows) forward-rows query-rows)
              (format out "answer language     : operators ~(~S~), literals ~S, variables x0 x1; body bound 16 bits (description bound ~D)~%"
                      (mapcar #'operator-name (language-operators language)) (language-literals language)
                      (header-bound inputs domain 16))
              (format out "candidates          : ~D terms enumerated (~D of the domain type); job mode ~S~%"
                      (length all-records) (length ranking) (observation-job-mode observations))
              (format out "ANSWER TERM         : ~A~%" (short witness))
              (format out "  kernel syntax     : ~A~%" (full witness))
              (format out "  size              : body ~D bits, description ~D bits~%"
                      (body-size witness inputs) (description-size witness inputs))
              (format out "GUARD               : ~A~%" (short guard))
              (format out "  kernel syntax     : ~A~%" (full guard))
              (format out "  size              : body ~D bits~%" (body-size guard inputs))
              (format out "  learned parts     :~%")
              (loop for (term nrows work mode) in d-log
                    for label in '("where the answer term is defined (over k, c)"
                                   "does the forward replay equal c (over x0 = k, x1 = c, x2 = replayed value)"
                                   "composed guard replayed against the selected support (check only)")
                    do (format out "      ~A~%        -> ~A   [~D rows, ~D work, ~(~A~)]~%" label term nrows work mode))
              (format out "  guard on grid     : true on ~D of ~D (k, c) pairs; rows k = ~S, columns c likewise~%"
                      active (* (length values) (length values)) values)
              (dolist (line grid) (format out "      ~A~%" line))
              (format out "selection           : the term satisfying most rows wins, ties by smaller description, then enumeration order~%")
              (format out "  support           : ~D of ~D rows; ~D terms share exactly this support~%"
                      (second top) (length rows) (length same-mask))
              (format out "  top of ranking    : (rows satisfied, description bits, term)~%")
              (loop for e in ranked repeat 6
                    do (format out "      ~4D ~4D  ~A~%" (second e) (third e) (short (first e))))
              (format out "  recomputed top = kernel's answer term: ~S~%" (equal (first top) witness))
              (format out "CERTIFICATION (a solver is two laws)~%")
              (format out "  witness law       : ~A~%" (short (law-statement (solve-witness-law discovery))))
              (format out "      status ~S, grade ~S, assignments ~S, active ~S~%"
                      (law-validation-status validation) (certificate-method validation)
                      (law-validation-count validation) (law-validation-active validation))
              (format out "  uniqueness law    : ~A~%" (short (law-statement (solve-uniqueness-law discovery))))
              (format out "      status ~S, grade ~S, assignments ~S, active ~S~%"
                      (law-validation-status uniqueness) (certificate-method uniqueness)
                      (law-validation-count uniqueness) (law-validation-active uniqueness))
              (when (law-validation-counterexample uniqueness)
                (format out "      counterexample (k c z) = ~S~%"
                        (getf (law-validation-counterexample uniqueness) :inputs)))
              (when (law-validation-counterexample validation)
                (format out "      witness counterexample (k c) = ~S~%"
                        (getf (law-validation-counterexample validation) :inputs)))
              (format out "  certified-solve-discovery-p : ~S~%" certified)
              (format out "  recorded as       : ~A~%"
                      (if entry
                          (format nil ":solver entry, status ~S, certificate ~S ~S, unique-p ~S, certified-p ~S, bits ~D"
                                  (knowledge-entry-status entry)
                                  (getf (knowledge-entry-certificate entry) :method)
                                  (getf (knowledge-entry-certificate entry) :obligations)
                                  (getf (knowledge-entry-metadata entry) :unique-p)
                                  (getf (knowledge-entry-metadata entry) :certified-p)
                                  (knowledge-entry-bits entry))
                          "no propagator rule (neither certified nor a current integer witness conjecture)"))
              (format out "  solver arguments  : attested-p ~S, unique-p ~S, work ~S~%"
                      (getf arguments :attested-p) (getf arguments :unique-p) (getf arguments :work))
              (format out "WORK (ledger units charged to any ledger) and wall time~%")
              (format out "  observe relation  : ~10D units, ~,4F s   (shared by both positions of ~(~A~); forward guard ~A)~%"
                      (meter-total relation-meter) relation-seconds name
                      (first (first relation-log)))
              (format out "  discover + guard  : ~10D units, ~,4F s~%" (meter-total d-meter) d-seconds)
              (format out "  validate          : ~10D units, ~,4F s   (~A)~%" (meter-total v-meter) v-seconds
                      (if (eq domain :int) "integer-solver-held-out: sampled" "validate-arithmetic-solver: exhaustive"))
              (format out "  kernel's own ledgers: discovery ledger ~D, enumeration ledger ~D~%"
                      (ledger-total (solve-discovery-ledger discovery))
                      (ledger-total (observation-job-ledger observations)))
              (format out "  discover categories: ~{~(~A~)~^, ~}~%"
                      (loop for (category . amount) in (meter-categories d-meter)
                            collect (format nil "~A ~D" category amount)))
              (push (list :domain (domain-name domain) :operator name :unknown position
                          :answer (short witness) :guard (short guard)
                          :answer-sexp (ast->sexp witness) :guard-sexp (ast->sexp guard)
                          :forward-guard (short (arithmetic-relation-guard relation))
                          :witness-law (law-validation-status validation)
                          :witness-grade (certificate-method validation)
                          :uniqueness-law (law-validation-status uniqueness)
                          :uniqueness-grade (certificate-method uniqueness)
                          :certified certified
                          :grid values
                          ;; rows k, columns c over :grid: guard 1/0/E, and the answer term's value
                          :guard-on-grid grid
                          :answer-on-grid
                          (loop for k in values collect
                            (loop for c in values collect
                              (multiple-value-bind (status value) (x2-eval witness inputs (list k c))
                                (if (eq status :value) value :error))))
                          :guard-true-on-grid active
                          :support (second top) :frame-rows (length rows)
                          :candidates (length all-records)
                          :work-relation (meter-total relation-meter)
                          :work-discover (meter-total d-meter)
                          :work-validate (meter-total v-meter)
                          :work-retained-ledgers
                          (+ (ledger-total (solve-discovery-ledger discovery))
                             (ledger-total (observation-job-ledger observations))))
                    *sexp-rows*))))))
    (push (list (domain-name domain) (- *grand-work* work-before) retained (- *grand-seconds* seconds-before))
          *domain-totals*)))

(let ((here cl-user::*x2-here*))
  (with-open-file (out (merge-pathnames "x2-solvers.txt" here) :direction :output :if-exists :supersede)
    (format out "X2 baseline: the eight arithmetic solvers found by v1/milestones/algebra-discovery.lisp~%")
    (format out "Produced by x2-dump.lisp from a private copy of v1. One block per solver and domain: 8 x 3 = 24 blocks.~%")
    (format out "Fixture: tests/milestones/support.lisp:198-208 (arithmetic-controls).~%")
    (dolist (domain (list (gf 5) (gf 7) :int))
      (dump-domain domain out))
    (format out "~%================================================================================~%")
    (format out "TOTAL over the 24 discoveries (12 relations observed, 24 solvers discovered and validated):~%")
    (format out "  ~D ledger units, ~,3F s wall (metered run; the meter adds overhead, see logs/x2-time.log)~%"
            *grand-work* *grand-seconds*)
    (format out "Per domain (8 solvers each): all ledgers | discovery ledger + enumeration ledger only | wall~%")
    (dolist (row (reverse *domain-totals*))
      (format out "  ~6A ~12D | ~10D | ~,3F s~%" (first row) (second row) (third row) (fourth row))))
  (with-open-file (out (merge-pathnames "x2-solvers.sexp" here) :direction :output :if-exists :supersede)
    (let ((*print-pretty* nil) (*print-right-margin* 100000))
      (format out ";; One plist per solver and domain, in the order found. Variables: x0 = k (known argument), x1 = c (result).~%")
      (dolist (row (reverse *sexp-rows*)) (format out "~S~%" row))))
  ;; The table a new engine is compared with: tab-separated, one row per domain, operator, unknown.
  (with-open-file (out (merge-pathnames "x2-match-table.tsv" here) :direction :output :if-exists :supersede)
    (format out "domain~Coperator~Cunknown_argument~Canswer_term~Cguard~Cwitness_law~Cuniqueness_law~Ccertified~Cguard_true_on_grid~Cframe_rows~Crows_satisfied~Ccandidates~Cwork_observe_relation~Cwork_discover~Cwork_validate~Cwork_two_retained_ledgers~%"
            #\Tab #\Tab #\Tab #\Tab #\Tab #\Tab #\Tab #\Tab #\Tab #\Tab #\Tab #\Tab #\Tab #\Tab #\Tab)
    (dolist (row (reverse *sexp-rows*))
      (format out "~A~C~(~A~)~C~D~C~A~C~A~C~(~A~)/~(~A~)~C~(~A~)/~(~A~)~C~(~A~)~C~D~C~D~C~D~C~D~C~D~C~D~C~D~C~D~%"
              (getf row :domain) #\Tab (getf row :operator) #\Tab (getf row :unknown) #\Tab
              (getf row :answer) #\Tab (getf row :guard) #\Tab
              (getf row :witness-law) (getf row :witness-grade) #\Tab
              (getf row :uniqueness-law) (getf row :uniqueness-grade) #\Tab
              (if (getf row :certified) "yes" "no") #\Tab (getf row :guard-true-on-grid) #\Tab
              (getf row :frame-rows) #\Tab (getf row :support) #\Tab (getf row :candidates) #\Tab
              (getf row :work-relation) #\Tab (getf row :work-discover) #\Tab (getf row :work-validate) #\Tab
              (getf row :work-retained-ledgers))))
  ;; GF(5) and GF(7) must agree term for term.
  (let ((rows (reverse *sexp-rows*)) (disagreements 0))
    (loop for a in (subseq rows 0 8) for b in (subseq rows 8 16)
          unless (and (equal (getf a :answer) (getf b :answer)) (equal (getf a :guard) (getf b :guard)))
            do (incf disagreements))
    (format t "~&GF(5) and GF(7) disagree on ~D of 8 solvers (answer term or guard)~%" disagreements))
  (format t "~&wrote x2-solvers.txt, x2-solvers.sexp and x2-match-table.tsv; total work ~D units, ~,3F s~%"
          *grand-work* *grand-seconds*))
