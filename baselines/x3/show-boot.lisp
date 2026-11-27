;;;; show-boot.lisp -- print, for each of the sixteen records of boot-specs.sexp, the keys the bootstrap
;;;; passed, the functions in its library at that moment, the bits and work of the result, and whether the
;;;; harness's own copy of the spec (collect-bootstrap-function-specs) equals the bootstrap's.
(load (merge-pathnames "x3-common.lisp" (make-pathname :name nil :type nil :defaults *load-truename*)))
(in-package #:lisploop)

(let ((items (collect-bootstrap-function-specs))
      (boot (read-boot-specs)))
  (format t "~&harness order: ~(~{~A~^ ~}~)~%" (mapcar (lambda (it) (getf it :id)) items))
  (format t "bootstrap order: ~(~{~A~^ ~}~)~%" (mapcar (lambda (r) (getf r :id)) boot))
  (dolist (r boot)
    (let* ((id (getf r :id))
           (item (find id items :key (lambda (it) (getf it :id))))
           (spec (getf item :spec))
           (hmeta (knowledge-entry-metadata spec))
           (bmeta (getf r :spec-metadata)))
      (format t "~&~(~A~): keys ~S; library before ~(~A~); bits ~D; work ~D~%"
              id (getf r :keys) (getf r :functions-in-library-before) (getf r :bits) (getf r :work))
      (format t "    harness copy equals bootstrap: inputs ~A, target ~A, rows ~A, operators ~A, literals ~A, constants ~A~%"
              (equal (knowledge-entry-inputs spec) (getf r :inputs))
              (equal (knowledge-entry-target spec) (getf r :target))
              (equal (knowledge-entry-residual spec) (getf r :rows))
              (equal (getf hmeta :operators) (getf bmeta :operators))
              (equal (getf hmeta :literals) (getf bmeta :literals))
              (equal (getf hmeta :constants) (getf bmeta :constants)))
      ;; the library's stored definition, for the ten that are stored
      (unless (eq :seed-corpus (getf item :battery))
        (let* ((lib (deserialize-knowledge-library (read-battery (getf item :battery))))
               (ent (find-knowledge-entry id lib)))
          (format t "    stored in battery ~(~A~): expression equals the bootstrap's ~A; bits ~D; work ~D~%"
                  (getf item :battery)
                  (equal (ast->sexp (knowledge-entry-expression ent)) (getf r :expression))
                  (knowledge-entry-bits ent) (knowledge-entry-work ent)))))))
