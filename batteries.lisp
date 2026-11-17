(in-package #:lisploop)

;;; Batteries: knowledge that ships with the kernel as library source, in library/, and not
;;; as host code. A battery is a file of forms that are read and never evaluated:
;;;
;;;   (:battery NAME &key parameters)
;;;       The first form. PARAMETERS lists (?variable default-type): a type written with a
;;;       variable takes what the load binds the variable to, or its default.
;;;   (:function NAME ((parameter type) ...) return-type body &key examples)
;;;       A function definition. An example is ((argument ...) => value).
;;;   (:solver NAME &key inverts at over given witness guard unique axioms metric examples)
;;;       A solver for the operator or function INVERTS at argument position AT (default
;;;       :unary), OVER the type that parameterises a primitive. GIVEN names what it reads,
;;;       the known arguments and then the target. UNIQUE is t, nil, or :finite for a
;;;       witness that is the only solution where every type involved is finite. AXIOMS are
;;;       obligations taken on trust where no check certifies them. METRIC marks the solver
;;;       of a metric decoder. An example is ((given-value ...) => witness), or => :none
;;;       where the guard rejects.
;;;
;;; Bodies, witnesses, guards and the parts of an example are in the surface syntax of `term`.
;;; A parameter name stands for its variable; (code ((parameter type) ...) sort body) is
;;; quoted code over parameters of its own; (not e) and (and e ...) are the :if encodings.
;;;
;;; Nothing here is trusted on the file's word. Types are checked as an entry is built, a
;;; solver over finite types is certified exhaustively, and every example is run on the VM:
;;; a function's against its value, a solver's forward through the operator it inverts.
;;; Examples are written at the default types and are run when the battery is loaded at them.

(defparameter *battery-directory*
  (merge-pathnames (make-pathname :directory '(:relative "library"))
                   (make-pathname :name nil :type nil
                                  :defaults (or *load-truename* *default-pathname-defaults*)))
  "The directory of battery sources, one file per battery.")

(defvar *battery-sources* (make-hash-table :test #'equal)
  "Battery sources already read: namestring -> (write-date header forms).")

(defun battery-names ()
  "The names of the batteries in `*battery-directory*`, in alphabetical order."
  (sort (mapcar (lambda (path) (keyword-id "~:@(~A~)" (pathname-name path)))
                (directory (merge-pathnames (make-pathname :name :wild :type "lisp")
                                            *battery-directory*)))
        #'string< :key #'symbol-name))

(defun read-battery (name)
  "The source of battery NAME as (VALUES header forms): the property list of its :battery
form and its entry forms in file order. The file is read once and again when it changes."
  (let* ((path (merge-pathnames (make-pathname :name (string-downcase (symbol-name name)) :type "lisp")
                                *battery-directory*))
         (date (and (probe-file path) (file-write-date path)))
         (cached (gethash (namestring path) *battery-sources*)))
    (assert date () "No battery ~S at ~A" name path)
    (unless (and cached (eql date (first cached)))
      (with-open-file (stream path)
        (let* ((*package* (find-package '#:lisploop))
               (*read-eval* nil)
               (forms (loop for form = (read stream nil stream)
                            until (eq form stream) collect form))
               (header (first forms)))
          (assert (and (consp header) (eq :battery (first header))
                       (eq (canonical-op-name name) (second header)))
                  () "~A does not begin with (:battery ~S ...)" path name)
          (setf cached (list date (cddr header) (rest forms))
                (gethash (namestring path) *battery-sources*) cached))))
    (values (second cached) (third cached))))

(defun battery-scope (parameters)
  "PARAMETERS, a list of (name type), as (VALUES inputs scope): the input schema that
numbers them from 0, and the variable each name stands for."
  (loop for (name type) in parameters
        for id from 0
        collect (cons id type) into inputs
        collect (cons name (var id type)) into scope
        finally (return (values inputs scope))))

(defun battery-term (form scope renames &optional expected)
  "FORM, battery source, as a typed AST of type EXPECTED. SCOPE maps the names in scope to
their variables and RENAMES the battery's entry names to the ids they are loaded under."
  (labels ((named-p (head name) (and (symbolp head) (string= name (symbol-name head))))
           (truth (part) (battery-term part scope renames :bool))
           (walk (form)
             (cond ((and form (symbolp form) (assoc form scope)) (cdr (assoc form scope)))
                   ((atom form) form)
                   ((eq 'quote (first form)) form)
                   ((named-p (first form) "CODE")
                    (destructuring-bind (parameters sort body) (rest form)
                      (multiple-value-bind (inputs inner) (battery-scope parameters)
                        (lit (code-type inputs sort) (battery-term body inner renames sort)))))
                   ((named-p (first form) "NOT") (bool-not (truth (second form))))
                   ((named-p (first form) "AND") (reduce #'bool-and (mapcar #'truth (rest form))
                                                         :from-end t))
                   (t (let ((head (first form)))
                        (cons (or (and (symbolp head) (cdr (assoc (canonical-op-name head) renames)))
                                  head)
                              (mapcar #'walk (rest form))))))))
    (term (walk form) expected)))

(defun check-battery-example (name example actual expected ledger)
  "Run the closed expressions ACTUAL and EXPECTED on the VM; they must have one value."
  (let ((got (evaluate actual nil nil :ledger ledger))
        (want (evaluate expected nil nil :ledger ledger)))
    (assert (and (eq :value (evaluation-status got))
                 (eq :value (evaluation-status want))
                 (equal (evaluation-value got) (evaluation-value want)))
            () "Battery entry ~S fails its example ~S" name example)))

(defun load-battery-function (form id renames examples-p ledger)
  "Define the :function FORM as ID in the active library and return its entry."
  (destructuring-bind (name parameters return-type body &key examples) (rest form)
    (multiple-value-bind (inputs scope) (battery-scope parameters)
      (define-function id inputs return-type
        (lambda (self)
          (declare (ignore self))       ; the body names the function, as it names any other
          (battery-term body scope renames return-type)))
      (when examples-p
        (loop for example in examples
              for (arguments nil value) = example
              do (check-battery-example
                  name example
                  (apply #'app (op id)
                         (loop for argument in arguments
                               for (nil . type) in inputs
                               collect (battery-term argument nil renames type)))
                  (battery-term value nil renames return-type)
                  ledger)))
      (find-knowledge-entry id))))

(defun load-battery-solver (form id battery renames examples-p ledger)
  "Register the :solver FORM as ID in the active library and return its entry."
  (destructuring-bind (name &key inverts (at :unary) over given witness (guard t) (unique t)
                                 axioms metric examples)
      (rest form)
    (let* ((inverted (or (cdr (assoc (canonical-op-name inverts) renames)) (canonical-op-name inverts)))
           (operator (if (defined-function-p inverted) (op inverted) (op inverted over)))
           (context-map (solver-context-map operator at))
           (inputs (solver-context-types operator context-map))
           (unknowns (mapcar (lambda (position) (nth position (second (operator-type operator))))
                             (solver-positions at)))
           (target (if (rest unknowns) (cons :tuple unknowns) (first unknowns)))
           (scope (loop for name in given
                        for (id . type) in inputs
                        collect (cons name (var id type))))
           (finite-p (every #'finite-type-p (cons target (mapcar #'cdr inputs))))
           (entry (make-knowledge-solver
                   operator :id id :domain over :position at
                   :witness (battery-term witness scope renames target)
                   :guard (battery-term guard scope renames :bool)
                   :certified-p finite-p
                   :unique-p (if (eq unique :finite) finite-p unique)
                   :edges (list (list :from-battery battery))
                   :ledger ledger)))
      (assert (= (length given) (length inputs)) ()
              "Solver ~S reads ~D values and names ~D" name (length inputs) (length given))
      ;; An axiom stands in only where no check has left its own certificate.
      (when (and axioms (null (knowledge-entry-certificate entry)))
        (attest-knowledge-entry entry :trusted-axiom axioms))
      (register-knowledge-entry entry :ledger ledger)
      (when metric (register-metric-decoder entry))
      (when examples-p
        (flet ((value-of (part type)
                 (let ((run (evaluate (battery-term part nil renames type) nil nil :ledger ledger)))
                   (assert (eq :value (evaluation-status run)) ()
                           "Battery entry ~S has an example without a value: ~S" name part)
                   (evaluation-value run))))
          (loop for example in examples
                for (context nil value) = example
                for known = (loop for part in context
                                  for (nil . type) in inputs
                                  collect (value-of part type))
                for solved = (evaluate-guarded-entry entry known ledger)
                do (if (eq value :none)
                       (assert (null solved) () "Battery entry ~S fails its example ~S" name example)
                       (let ((found (value-of value target)))
                         (assert (and solved (eq :value (evaluation-status solved))) ()
                                 "Battery entry ~S fails its example ~S" name example)
                         ;; The witness is the one named, and it replays through the operator.
                         (check-battery-example name example
                                                (lit target (evaluation-value solved))
                                                (lit target found) ledger)
                         (check-battery-example
                          name example
                          (solver-forward-expression operator at context-map known found)
                          (lit (cdr (nth (position :target context-map) inputs))
                               (nth (position :target context-map) known))
                          ledger))))))
      entry)))

(defun load-battery (name &key types only (library *knowledge-library*) ledger (check-examples-p t))
  "Register in LIBRARY the entries of battery NAME and return them in file order. TYPES is an
alist from the battery's type parameters to types, for those that are not to take their
defaults; an entry loaded at other than the defaults has the types' slugs appended to its
name, as `retype-function-definition` names an instance. ONLY names the entries to load, the
others being left out; what an entry calls must be loaded with it or be there already.
Each entry is built by the kernel's own constructors, so it is typed, certified and
described as any other, and carries the edge (:from-battery NAME). Its examples are run
when CHECK-EXAMPLES-P and the battery is at its default types; LEDGER, when given, is
charged for that and for the entries' installation."
  (multiple-value-bind (header forms) (read-battery name)
    (let* ((battery (canonical-op-name name))
           (parameters (getf header :parameters))
           (bindings (loop for (parameter default) in parameters
                           for given = (assoc (symbol-name parameter) types
                                              :key #'symbol-name :test #'string=)
                           collect (cons parameter (if given (cdr given) default))))
           (slugs (loop for (nil default) in parameters
                        for (nil . type) in bindings
                        unless (equal type default) collect (type-slug type)))
           (renames (loop for form in forms
                          for source = (canonical-op-name (second form))
                          collect (cons source (if slugs
                                                   (keyword-id "~A/~{~A~^-~}" source slugs)
                                                   source))))
           (wanted (mapcar #'canonical-op-name only))
           (examples-p (and check-examples-p (null slugs))))
      (assert (every (lambda (binding)
                       (find (symbol-name (car binding)) parameters
                             :key (lambda (parameter) (symbol-name (first parameter))) :test #'string=))
                     types)
              () "Battery ~S has parameters ~S, not ~S" name (mapcar #'first parameters) types)
      (assert (subsetp wanted (mapcar #'car renames)) ()
              "Battery ~S has no entry ~S" name (set-difference wanted (mapcar #'car renames)))
      (with-knowledge-library (library)
        (loop for form in (sublis bindings forms)
              for (source . id) in renames
              when (or (null only) (member source wanted))
                collect (ecase (first form)
                          (:function
                           (let ((entry (load-battery-function form id renames examples-p ledger)))
                             (add-knowledge-edge entry :from-battery battery)
                             entry))
                          (:solver
                           (load-battery-solver form id battery renames examples-p ledger))))))))
