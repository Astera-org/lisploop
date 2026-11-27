(:KNOWLEDGE-LIBRARY :ENCODING-VERSION 7 :VERSION 55 :METADATA
 (:BATTERY :SEQUENCES :PARAMETERS ((LISPLOOP::?A :INT))) :FUNCTION-NAMES
 (:MAP :FOLDR :FOLDL :FILTER :MAP-ADJACENT :POSITIONS) :DE-NOVO-COUNTER 0
 :ENTRY-COUNTER 1 :ENTRIES
 ((:ID :MAP :KIND :FUNCTION :DOMAIN :INT :INPUTS
   ((0 :SEQ :INT) (1 :CODE ((0 . :INT)) :INT)) :TARGET (:SEQ :INT) :EXPRESSION
   (:APP (:OP :IF (:SEQ :INT))
    (:APP (:OP := (:SEQ :INT)) (:VAR 0 (:SEQ :INT)) (:LIT (:SEQ :INT) NIL))
    (:LIT (:SEQ :INT) NIL)
    (:APP (:OP :CONS :INT)
     (:APP (:OP :CODE-EVAL (:CODE ((0 . :INT)) :INT))
      (:VAR 1 (:CODE ((0 . :INT)) :INT))
      (:APP (:OP :AT (:SEQ :INT)) (:VAR 0 (:SEQ :INT)) (:LIT :INT 0)))
     (:APP
      (:OP :MAP
       (:CODE ((0 :SEQ :INT) (1 :CODE ((0 . :INT)) :INT)) (:SEQ :INT)))
      (:APP (:OP :TAIL :INT) (:VAR 0 (:SEQ :INT)))
      (:VAR 1 (:CODE ((0 . :INT)) :INT)))))
   :GUARD (:LIT :BOOL T) :TRIGGER
   (:APP (:OP :IF :BOOL)
    (:APP (:OP :IF :BOOL)
     (:APP (:OP := (:SEQ :INT)) (:VAR 0 (:SEQ :INT)) (:LIT (:SEQ :INT) NIL))
     (:APP (:OP := (:SEQ :INT)) (:VAR 1 (:SEQ :INT)) (:LIT (:SEQ :INT) NIL))
     (:LIT :BOOL T))
    (:APP (:OP := :INT) (:APP (:OP :LENGTH :INT) (:VAR 0 (:SEQ :INT)))
     (:APP (:OP :LENGTH :INT) (:VAR 1 (:SEQ :INT))))
    (:LIT :BOOL NIL))
   :RESIDUAL NIL :AUXILIARY-CODE NIL :STATUS :VALIDATED :CERTIFICATE NIL :BITS
   127 :GAIN 0 :WORK 64 :EDGES
   ((:DESCRIBED-BY :DESC/LEN-EQ) (:DESCRIBED-BY :DESC/EMPTY->EMPTY)
    (:DESCRIBED-BY :DESC/POINTWISE-MAP) (:FROM-BATTERY :SEQUENCES))
   :METADATA
   (:COMPOSITIONAL-NAME :FUNCTION/HO-SEQ->SEQ/LEN-EQ/EMPTY->EMPTY/POINTWISE-MAP
    :DESCRIPTOR-PROFILE
    ((:ID :DESC/HO-SEQ->SEQ :FACET :TYPE :TIER 1 :STATUS :NECESSARY
      :WEIGHT-BITS 2 :WORK-COST 1)
     (:ID :DESC/LEN-EQ :FACET :SHAPE-DELTA :TIER 1 :STATUS :NECESSARY
      :WEIGHT-BITS 6 :WORK-COST 2 :SNAPSHOT
      ((:SEMANTICS (6 7) :KIND :FUNCTION :DOMAIN :INT :INPUTS
        ((0 :SEQ :INT) (1 :CODE ((0 . :INT)) :INT)) :TARGET (:SEQ :INT) :CODE
        ((:APP (:OP :IF (:SEQ :INT))
          (:APP (:OP := (:SEQ :INT)) (:VAR 0 (:SEQ :INT))
           (:LIT (:SEQ :INT) NIL))
          (:LIT (:SEQ :INT) NIL)
          (:APP (:OP :CONS :INT)
           (:APP (:OP :CODE-EVAL (:CODE ((0 . :INT)) :INT))
            (:VAR 1 (:CODE ((0 . :INT)) :INT))
            (:APP (:OP :AT (:SEQ :INT)) (:VAR 0 (:SEQ :INT)) (:LIT :INT 0)))
           (:APP
            (:OP :MAP
             (:CODE ((0 :SEQ :INT) (1 :CODE ((0 . :INT)) :INT)) (:SEQ :INT)))
            (:APP (:OP :TAIL :INT) (:VAR 0 (:SEQ :INT)))
            (:VAR 1 (:CODE ((0 . :INT)) :INT)))))
         (:LIT :BOOL T)
         (:APP (:OP :IF :BOOL)
          (:APP (:OP :IF :BOOL)
           (:APP (:OP := (:SEQ :INT)) (:VAR 0 (:SEQ :INT))
            (:LIT (:SEQ :INT) NIL))
           (:APP (:OP := (:SEQ :INT)) (:VAR 1 (:SEQ :INT))
            (:LIT (:SEQ :INT) NIL))
           (:LIT :BOOL T))
          (:APP (:OP := :INT) (:APP (:OP :LENGTH :INT) (:VAR 0 (:SEQ :INT)))
           (:APP (:OP :LENGTH :INT) (:VAR 1 (:SEQ :INT))))
          (:LIT :BOOL NIL))
         NIL)
        :CONTEXT (NIL NIL NIL NIL NIL) :DEPENDENCIES
        ((:MAP ((0 :SEQ :INT) (1 :CODE ((0 . :INT)) :INT)) (:SEQ :INT)
          (:APP (:OP :IF (:SEQ :INT))
           (:APP (:OP := (:SEQ :INT)) (:VAR 0 (:SEQ :INT))
            (:LIT (:SEQ :INT) NIL))
           (:LIT (:SEQ :INT) NIL)
           (:APP (:OP :CONS :INT)
            (:APP (:OP :CODE-EVAL (:CODE ((0 . :INT)) :INT))
             (:VAR 1 (:CODE ((0 . :INT)) :INT))
             (:APP (:OP :AT (:SEQ :INT)) (:VAR 0 (:SEQ :INT)) (:LIT :INT 0)))
            (:APP
             (:OP :MAP
              (:CODE ((0 :SEQ :INT) (1 :CODE ((0 . :INT)) :INT)) (:SEQ :INT)))
             (:APP (:OP :TAIL :INT) (:VAR 0 (:SEQ :INT)))
             (:VAR 1 (:CODE ((0 . :INT)) :INT)))))
          NIL)))
       ((:MAP ((0 :SEQ :INT) (1 :CODE ((0 . :INT)) :INT)) (:SEQ :INT)
         (:APP (:OP :IF (:SEQ :INT))
          (:APP (:OP := (:SEQ :INT)) (:VAR 0 (:SEQ :INT))
           (:LIT (:SEQ :INT) NIL))
          (:LIT (:SEQ :INT) NIL)
          (:APP (:OP :CONS :INT)
           (:APP (:OP :CODE-EVAL (:CODE ((0 . :INT)) :INT))
            (:VAR 1 (:CODE ((0 . :INT)) :INT))
            (:APP (:OP :AT (:SEQ :INT)) (:VAR 0 (:SEQ :INT)) (:LIT :INT 0)))
           (:APP
            (:OP :MAP
             (:CODE ((0 :SEQ :INT) (1 :CODE ((0 . :INT)) :INT)) (:SEQ :INT)))
            (:APP (:OP :TAIL :INT) (:VAR 0 (:SEQ :INT)))
            (:VAR 1 (:CODE ((0 . :INT)) :INT)))))
         NIL))
       (:SEMANTICS (6 7) :KIND :DESCRIPTOR :DOMAIN :INT :INPUTS
        ((0 :SEQ :INT) (1 :SEQ :INT)) :TARGET :BOOL :CODE
        ((:APP (:OP := :INT) (:APP (:OP :LENGTH :INT) (:VAR 0 (:SEQ :INT)))
          (:APP (:OP :LENGTH :INT) (:VAR 1 (:SEQ :INT))))
         (:LIT :BOOL T) NIL
         (:APP (:OP :IF :BOOL)
          (:APP (:OP := (:SEQ :INT)) (:VAR 0 (:SEQ :INT))
           (:LIT (:SEQ :INT) NIL))
          (:LIT :BOOL NIL) (:LIT :BOOL T)))
        :META ((:SEQ-OUT) NIL :VIOLATED) :DEPENDENCIES NIL)))
     (:ID :DESC/EMPTY->EMPTY :FACET :BOUNDARY :TIER 1 :STATUS :NECESSARY
      :WEIGHT-BITS 4 :WORK-COST 2 :SNAPSHOT
      ((:SEMANTICS (6 7) :KIND :FUNCTION :DOMAIN :INT :INPUTS
        ((0 :SEQ :INT) (1 :CODE ((0 . :INT)) :INT)) :TARGET (:SEQ :INT) :CODE
        ((:APP (:OP :IF (:SEQ :INT))
          (:APP (:OP := (:SEQ :INT)) (:VAR 0 (:SEQ :INT))
           (:LIT (:SEQ :INT) NIL))
          (:LIT (:SEQ :INT) NIL)
          (:APP (:OP :CONS :INT)
           (:APP (:OP :CODE-EVAL (:CODE ((0 . :INT)) :INT))
            (:VAR 1 (:CODE ((0 . :INT)) :INT))
            (:APP (:OP :AT (:SEQ :INT)) (:VAR 0 (:SEQ :INT)) (:LIT :INT 0)))
           (:APP
            (:OP :MAP
             (:CODE ((0 :SEQ :INT) (1 :CODE ((0 . :INT)) :INT)) (:SEQ :INT)))
            (:APP (:OP :TAIL :INT) (:VAR 0 (:SEQ :INT)))
            (:VAR 1 (:CODE ((0 . :INT)) :INT)))))
         (:LIT :BOOL T)
         (:APP (:OP :IF :BOOL)
          (:APP (:OP :IF :BOOL)
           (:APP (:OP := (:SEQ :INT)) (:VAR 0 (:SEQ :INT))
            (:LIT (:SEQ :INT) NIL))
           (:APP (:OP := (:SEQ :INT)) (:VAR 1 (:SEQ :INT))
            (:LIT (:SEQ :INT) NIL))
           (:LIT :BOOL T))
          (:APP (:OP := :INT) (:APP (:OP :LENGTH :INT) (:VAR 0 (:SEQ :INT)))
           (:APP (:OP :LENGTH :INT) (:VAR 1 (:SEQ :INT))))
          (:LIT :BOOL NIL))
         NIL)
        :CONTEXT (NIL NIL NIL NIL NIL) :DEPENDENCIES
        ((:MAP ((0 :SEQ :INT) (1 :CODE ((0 . :INT)) :INT)) (:SEQ :INT)
          (:APP (:OP :IF (:SEQ :INT))
           (:APP (:OP := (:SEQ :INT)) (:VAR 0 (:SEQ :INT))
            (:LIT (:SEQ :INT) NIL))
           (:LIT (:SEQ :INT) NIL)
           (:APP (:OP :CONS :INT)
            (:APP (:OP :CODE-EVAL (:CODE ((0 . :INT)) :INT))
             (:VAR 1 (:CODE ((0 . :INT)) :INT))
             (:APP (:OP :AT (:SEQ :INT)) (:VAR 0 (:SEQ :INT)) (:LIT :INT 0)))
            (:APP
             (:OP :MAP
              (:CODE ((0 :SEQ :INT) (1 :CODE ((0 . :INT)) :INT)) (:SEQ :INT)))
             (:APP (:OP :TAIL :INT) (:VAR 0 (:SEQ :INT)))
             (:VAR 1 (:CODE ((0 . :INT)) :INT)))))
          NIL)))
       ((:MAP ((0 :SEQ :INT) (1 :CODE ((0 . :INT)) :INT)) (:SEQ :INT)
         (:APP (:OP :IF (:SEQ :INT))
          (:APP (:OP := (:SEQ :INT)) (:VAR 0 (:SEQ :INT))
           (:LIT (:SEQ :INT) NIL))
          (:LIT (:SEQ :INT) NIL)
          (:APP (:OP :CONS :INT)
           (:APP (:OP :CODE-EVAL (:CODE ((0 . :INT)) :INT))
            (:VAR 1 (:CODE ((0 . :INT)) :INT))
            (:APP (:OP :AT (:SEQ :INT)) (:VAR 0 (:SEQ :INT)) (:LIT :INT 0)))
           (:APP
            (:OP :MAP
             (:CODE ((0 :SEQ :INT) (1 :CODE ((0 . :INT)) :INT)) (:SEQ :INT)))
            (:APP (:OP :TAIL :INT) (:VAR 0 (:SEQ :INT)))
            (:VAR 1 (:CODE ((0 . :INT)) :INT)))))
         NIL))
       (:SEMANTICS (6 7) :KIND :DESCRIPTOR :DOMAIN :INT :INPUTS
        ((0 :SEQ :INT) (1 :SEQ :INT)) :TARGET :BOOL :CODE
        ((:APP (:OP := (:SEQ :INT)) (:VAR 1 (:SEQ :INT))
          (:LIT (:SEQ :INT) NIL))
         (:APP (:OP := (:SEQ :INT)) (:VAR 0 (:SEQ :INT))
          (:LIT (:SEQ :INT) NIL))
         NIL NIL)
        :META (NIL NIL :VIOLATED) :DEPENDENCIES NIL)))
     (:ID :DESC/POINTWISE-MAP :FACET :SAMPLED-CONTENT :TIER 2 :STATUS
      :EMPIRICAL :WEIGHT-BITS 5 :WORK-COST 6))
    :TOTAL-P NIL :CONDITIONAL-CODE-PARAMS (1)))
  (:ID :FOLDR :KIND :FUNCTION :DOMAIN :INT :INPUTS
   ((0 :SEQ :INT) (1 . :INT) (2 :CODE ((0 . :INT) (1 . :INT)) :INT)) :TARGET
   :INT :EXPRESSION
   (:APP (:OP :IF :INT)
    (:APP (:OP := (:SEQ :INT)) (:VAR 0 (:SEQ :INT)) (:LIT (:SEQ :INT) NIL))
    (:VAR 1 :INT)
    (:APP (:OP :CODE-EVAL (:CODE ((0 . :INT) (1 . :INT)) :INT))
     (:VAR 2 (:CODE ((0 . :INT) (1 . :INT)) :INT))
     (:APP (:OP :AT (:SEQ :INT)) (:VAR 0 (:SEQ :INT)) (:LIT :INT 0))
     (:APP
      (:OP :FOLDR
       (:CODE ((0 :SEQ :INT) (1 . :INT) (2 :CODE ((0 . :INT) (1 . :INT)) :INT))
        :INT))
      (:APP (:OP :TAIL :INT) (:VAR 0 (:SEQ :INT))) (:VAR 1 :INT)
      (:VAR 2 (:CODE ((0 . :INT) (1 . :INT)) :INT)))))
   :GUARD (:LIT :BOOL T) :TRIGGER NIL :RESIDUAL NIL :AUXILIARY-CODE NIL :STATUS
   :VALIDATED :CERTIFICATE NIL :BITS 133 :GAIN 0 :WORK 70 :EDGES
   ((:DESCRIBED-BY :DESC/SCALAR-REDUCTION) (:FROM-BATTERY :SEQUENCES))
   :METADATA
   (:COMPOSITIONAL-NAME :FUNCTION/HO-SEQ->SCALAR/ANY/ANY/SCALAR-REDUCTION
    :DESCRIPTOR-PROFILE
    ((:ID :DESC/HO-SEQ->SCALAR :FACET :TYPE :TIER 1 :STATUS :NECESSARY
      :WEIGHT-BITS 2 :WORK-COST 1)
     (:ID :DESC/SCALAR-REDUCTION :FACET :SAMPLED-CONTENT :TIER 2 :STATUS
      :EMPIRICAL :WEIGHT-BITS 5 :WORK-COST 6))
    :TOTAL-P NIL :CONDITIONAL-CODE-PARAMS (2)))
  (:ID :FOLDL :KIND :FUNCTION :DOMAIN :INT :INPUTS
   ((0 :SEQ :INT) (1 . :INT) (2 :CODE ((0 . :INT) (1 . :INT)) :INT)) :TARGET
   :INT :EXPRESSION
   (:APP (:OP :IF :INT)
    (:APP (:OP := (:SEQ :INT)) (:VAR 0 (:SEQ :INT)) (:LIT (:SEQ :INT) NIL))
    (:VAR 1 :INT)
    (:APP
     (:OP :FOLDL
      (:CODE ((0 :SEQ :INT) (1 . :INT) (2 :CODE ((0 . :INT) (1 . :INT)) :INT))
       :INT))
     (:APP (:OP :TAIL :INT) (:VAR 0 (:SEQ :INT)))
     (:APP (:OP :CODE-EVAL (:CODE ((0 . :INT) (1 . :INT)) :INT))
      (:VAR 2 (:CODE ((0 . :INT) (1 . :INT)) :INT)) (:VAR 1 :INT)
      (:APP (:OP :AT (:SEQ :INT)) (:VAR 0 (:SEQ :INT)) (:LIT :INT 0)))
     (:VAR 2 (:CODE ((0 . :INT) (1 . :INT)) :INT))))
   :GUARD (:LIT :BOOL T) :TRIGGER NIL :RESIDUAL NIL :AUXILIARY-CODE NIL :STATUS
   :VALIDATED :CERTIFICATE NIL :BITS 133 :GAIN 0 :WORK 81333 :EDGES
   ((:DESCRIBED-BY :DESC/SCALAR-REDUCTION) (:FROM-BATTERY :SEQUENCES))
   :METADATA
   (:COMPOSITIONAL-NAME :FUNCTION/HO-SEQ->SCALAR/ANY/ANY/SCALAR-REDUCTION
    :DESCRIPTOR-PROFILE
    ((:ID :DESC/HO-SEQ->SCALAR :FACET :TYPE :TIER 1 :STATUS :NECESSARY
      :WEIGHT-BITS 2 :WORK-COST 1)
     (:ID :DESC/SCALAR-REDUCTION :FACET :SAMPLED-CONTENT :TIER 2 :STATUS
      :EMPIRICAL :WEIGHT-BITS 5 :WORK-COST 6))
    :TOTAL-P NIL :CONDITIONAL-CODE-PARAMS (2)))
  (:ID :FILTER :KIND :FUNCTION :DOMAIN :INT :INPUTS
   ((0 :SEQ :INT) (1 :CODE ((0 . :INT)) :BOOL)) :TARGET (:SEQ :INT) :EXPRESSION
   (:APP (:OP :IF (:SEQ :INT))
    (:APP (:OP := (:SEQ :INT)) (:VAR 0 (:SEQ :INT)) (:LIT (:SEQ :INT) NIL))
    (:VAR 0 (:SEQ :INT))
    (:APP (:OP :IF (:SEQ :INT))
     (:APP (:OP :CODE-EVAL (:CODE ((0 . :INT)) :BOOL))
      (:VAR 1 (:CODE ((0 . :INT)) :BOOL))
      (:APP (:OP :AT (:SEQ :INT)) (:VAR 0 (:SEQ :INT)) (:LIT :INT 0)))
     (:APP (:OP :CONS :INT)
      (:APP (:OP :AT (:SEQ :INT)) (:VAR 0 (:SEQ :INT)) (:LIT :INT 0))
      (:APP
       (:OP :FILTER
        (:CODE ((0 :SEQ :INT) (1 :CODE ((0 . :INT)) :BOOL)) (:SEQ :INT)))
       (:APP (:OP :TAIL :INT) (:VAR 0 (:SEQ :INT)))
       (:VAR 1 (:CODE ((0 . :INT)) :BOOL))))
     (:APP
      (:OP :FILTER
       (:CODE ((0 :SEQ :INT) (1 :CODE ((0 . :INT)) :BOOL)) (:SEQ :INT)))
      (:APP (:OP :TAIL :INT) (:VAR 0 (:SEQ :INT)))
      (:VAR 1 (:CODE ((0 . :INT)) :BOOL)))))
   :GUARD (:LIT :BOOL T) :TRIGGER NIL :RESIDUAL NIL :AUXILIARY-CODE NIL :STATUS
   :VALIDATED :CERTIFICATE NIL :BITS 192 :GAIN 0 :WORK 75546 :EDGES
   ((:DESCRIBED-BY :DESC/LEN-LE) (:DESCRIBED-BY :DESC/EMPTY->EMPTY)
    (:DESCRIBED-BY :DESC/SUBSET-ELEMENTS) (:FROM-BATTERY :SEQUENCES))
   :METADATA
   (:COMPOSITIONAL-NAME
    :FUNCTION/HO-SEQ->SEQ/LEN-LE/EMPTY->EMPTY/SUBSET-ELEMENTS
    :DESCRIPTOR-PROFILE
    ((:ID :DESC/HO-SEQ->SEQ :FACET :TYPE :TIER 1 :STATUS :NECESSARY
      :WEIGHT-BITS 2 :WORK-COST 1)
     (:ID :DESC/LEN-LE :FACET :SHAPE-DELTA :TIER 1 :STATUS :EMPIRICAL
      :WEIGHT-BITS 5 :WORK-COST 2)
     (:ID :DESC/EMPTY->EMPTY :FACET :BOUNDARY :TIER 1 :STATUS :EMPIRICAL
      :WEIGHT-BITS 4 :WORK-COST 2)
     (:ID :DESC/SUBSET-ELEMENTS :FACET :SAMPLED-CONTENT :TIER 2 :STATUS
      :EMPIRICAL :WEIGHT-BITS 4 :WORK-COST 8))
    :TOTAL-P NIL :CONDITIONAL-CODE-PARAMS (1)))
  (:ID :MAP-ADJACENT :KIND :FUNCTION :DOMAIN :INT :INPUTS
   ((0 :SEQ :INT) (1 :CODE ((0 . :INT) (1 . :INT)) :INT)) :TARGET (:SEQ :INT)
   :EXPRESSION
   (:APP (:OP :IF (:SEQ :INT))
    (:APP (:OP := (:SEQ :INT)) (:VAR 0 (:SEQ :INT)) (:LIT (:SEQ :INT) NIL))
    (:LIT (:SEQ :INT) NIL)
    (:APP (:OP :IF (:SEQ :INT))
     (:APP (:OP := (:SEQ :INT)) (:APP (:OP :TAIL :INT) (:VAR 0 (:SEQ :INT)))
      (:LIT (:SEQ :INT) NIL))
     (:LIT (:SEQ :INT) NIL)
     (:APP (:OP :CONS :INT)
      (:APP (:OP :CODE-EVAL (:CODE ((0 . :INT) (1 . :INT)) :INT))
       (:VAR 1 (:CODE ((0 . :INT) (1 . :INT)) :INT))
       (:APP (:OP :AT (:SEQ :INT)) (:APP (:OP :TAIL :INT) (:VAR 0 (:SEQ :INT)))
        (:LIT :INT 0))
       (:APP (:OP :AT (:SEQ :INT)) (:VAR 0 (:SEQ :INT)) (:LIT :INT 0)))
      (:APP
       (:OP :MAP-ADJACENT
        (:CODE ((0 :SEQ :INT) (1 :CODE ((0 . :INT) (1 . :INT)) :INT))
         (:SEQ :INT)))
       (:APP (:OP :TAIL :INT) (:VAR 0 (:SEQ :INT)))
       (:VAR 1 (:CODE ((0 . :INT) (1 . :INT)) :INT))))))
   :GUARD (:LIT :BOOL T) :TRIGGER
   (:APP (:OP :IF :BOOL)
    (:APP (:OP := (:SEQ :INT)) (:VAR 0 (:SEQ :INT)) (:LIT (:SEQ :INT) NIL))
    (:APP (:OP := (:SEQ :INT)) (:VAR 1 (:SEQ :INT)) (:LIT (:SEQ :INT) NIL))
    (:LIT :BOOL T))
   :RESIDUAL NIL :AUXILIARY-CODE NIL :STATUS :VALIDATED :CERTIFICATE NIL :BITS
   213 :GAIN 0 :WORK 109012 :EDGES
   ((:DESCRIBED-BY :DESC/LEN-DEC-1) (:DESCRIBED-BY :DESC/EMPTY->EMPTY)
    (:FROM-BATTERY :SEQUENCES))
   :METADATA
   (:COMPOSITIONAL-NAME :FUNCTION/HO-SEQ->SEQ/LEN-DEC-1/EMPTY->EMPTY/ANY
    :DESCRIPTOR-PROFILE
    ((:ID :DESC/HO-SEQ->SEQ :FACET :TYPE :TIER 1 :STATUS :NECESSARY
      :WEIGHT-BITS 2 :WORK-COST 1)
     (:ID :DESC/LEN-DEC-1 :FACET :SHAPE-DELTA :TIER 1 :STATUS :NECESSARY
      :WEIGHT-BITS 6 :WORK-COST 2 :SNAPSHOT
      ((:SEMANTICS (6 7) :KIND :FUNCTION :DOMAIN :INT :INPUTS
        ((0 :SEQ :INT) (1 :CODE ((0 . :INT) (1 . :INT)) :INT)) :TARGET
        (:SEQ :INT) :CODE
        ((:APP (:OP :IF (:SEQ :INT))
          (:APP (:OP := (:SEQ :INT)) (:VAR 0 (:SEQ :INT))
           (:LIT (:SEQ :INT) NIL))
          (:LIT (:SEQ :INT) NIL)
          (:APP (:OP :IF (:SEQ :INT))
           (:APP (:OP := (:SEQ :INT))
            (:APP (:OP :TAIL :INT) (:VAR 0 (:SEQ :INT)))
            (:LIT (:SEQ :INT) NIL))
           (:LIT (:SEQ :INT) NIL)
           (:APP (:OP :CONS :INT)
            (:APP (:OP :CODE-EVAL (:CODE ((0 . :INT) (1 . :INT)) :INT))
             (:VAR 1 (:CODE ((0 . :INT) (1 . :INT)) :INT))
             (:APP (:OP :AT (:SEQ :INT))
              (:APP (:OP :TAIL :INT) (:VAR 0 (:SEQ :INT))) (:LIT :INT 0))
             (:APP (:OP :AT (:SEQ :INT)) (:VAR 0 (:SEQ :INT)) (:LIT :INT 0)))
            (:APP
             (:OP :MAP-ADJACENT
              (:CODE ((0 :SEQ :INT) (1 :CODE ((0 . :INT) (1 . :INT)) :INT))
               (:SEQ :INT)))
             (:APP (:OP :TAIL :INT) (:VAR 0 (:SEQ :INT)))
             (:VAR 1 (:CODE ((0 . :INT) (1 . :INT)) :INT))))))
         (:LIT :BOOL T)
         (:APP (:OP :IF :BOOL)
          (:APP (:OP := (:SEQ :INT)) (:VAR 0 (:SEQ :INT))
           (:LIT (:SEQ :INT) NIL))
          (:APP (:OP := (:SEQ :INT)) (:VAR 1 (:SEQ :INT))
           (:LIT (:SEQ :INT) NIL))
          (:LIT :BOOL T))
         NIL)
        :CONTEXT (NIL NIL NIL NIL NIL) :DEPENDENCIES
        ((:MAP-ADJACENT ((0 :SEQ :INT) (1 :CODE ((0 . :INT) (1 . :INT)) :INT))
          (:SEQ :INT)
          (:APP (:OP :IF (:SEQ :INT))
           (:APP (:OP := (:SEQ :INT)) (:VAR 0 (:SEQ :INT))
            (:LIT (:SEQ :INT) NIL))
           (:LIT (:SEQ :INT) NIL)
           (:APP (:OP :IF (:SEQ :INT))
            (:APP (:OP := (:SEQ :INT))
             (:APP (:OP :TAIL :INT) (:VAR 0 (:SEQ :INT)))
             (:LIT (:SEQ :INT) NIL))
            (:LIT (:SEQ :INT) NIL)
            (:APP (:OP :CONS :INT)
             (:APP (:OP :CODE-EVAL (:CODE ((0 . :INT) (1 . :INT)) :INT))
              (:VAR 1 (:CODE ((0 . :INT) (1 . :INT)) :INT))
              (:APP (:OP :AT (:SEQ :INT))
               (:APP (:OP :TAIL :INT) (:VAR 0 (:SEQ :INT))) (:LIT :INT 0))
              (:APP (:OP :AT (:SEQ :INT)) (:VAR 0 (:SEQ :INT)) (:LIT :INT 0)))
             (:APP
              (:OP :MAP-ADJACENT
               (:CODE ((0 :SEQ :INT) (1 :CODE ((0 . :INT) (1 . :INT)) :INT))
                (:SEQ :INT)))
              (:APP (:OP :TAIL :INT) (:VAR 0 (:SEQ :INT)))
              (:VAR 1 (:CODE ((0 . :INT) (1 . :INT)) :INT))))))
          NIL)))
       ((:MAP-ADJACENT ((0 :SEQ :INT) (1 :CODE ((0 . :INT) (1 . :INT)) :INT))
         (:SEQ :INT)
         (:APP (:OP :IF (:SEQ :INT))
          (:APP (:OP := (:SEQ :INT)) (:VAR 0 (:SEQ :INT))
           (:LIT (:SEQ :INT) NIL))
          (:LIT (:SEQ :INT) NIL)
          (:APP (:OP :IF (:SEQ :INT))
           (:APP (:OP := (:SEQ :INT))
            (:APP (:OP :TAIL :INT) (:VAR 0 (:SEQ :INT)))
            (:LIT (:SEQ :INT) NIL))
           (:LIT (:SEQ :INT) NIL)
           (:APP (:OP :CONS :INT)
            (:APP (:OP :CODE-EVAL (:CODE ((0 . :INT) (1 . :INT)) :INT))
             (:VAR 1 (:CODE ((0 . :INT) (1 . :INT)) :INT))
             (:APP (:OP :AT (:SEQ :INT))
              (:APP (:OP :TAIL :INT) (:VAR 0 (:SEQ :INT))) (:LIT :INT 0))
             (:APP (:OP :AT (:SEQ :INT)) (:VAR 0 (:SEQ :INT)) (:LIT :INT 0)))
            (:APP
             (:OP :MAP-ADJACENT
              (:CODE ((0 :SEQ :INT) (1 :CODE ((0 . :INT) (1 . :INT)) :INT))
               (:SEQ :INT)))
             (:APP (:OP :TAIL :INT) (:VAR 0 (:SEQ :INT)))
             (:VAR 1 (:CODE ((0 . :INT) (1 . :INT)) :INT))))))
         NIL))
       (:SEMANTICS (6 7) :KIND :DESCRIPTOR :DOMAIN :INT :INPUTS
        ((0 :SEQ :INT) (1 :SEQ :INT)) :TARGET :BOOL :CODE
        ((:APP (:OP := :INT)
          (:APP (:OP :- :INT) (:APP (:OP :LENGTH :INT) (:VAR 0 (:SEQ :INT)))
           (:LIT :INT 1))
          (:APP (:OP :LENGTH :INT) (:VAR 1 (:SEQ :INT))))
         (:APP (:OP :IF :BOOL)
          (:APP (:OP := (:SEQ :INT)) (:VAR 0 (:SEQ :INT))
           (:LIT (:SEQ :INT) NIL))
          (:LIT :BOOL NIL) (:LIT :BOOL T))
         NIL
         (:APP (:OP :< :INT) (:LIT :INT 1)
          (:APP (:OP :LENGTH :INT) (:VAR 0 (:SEQ :INT)))))
        :META ((:SEQ-OUT) NIL :VIOLATED) :DEPENDENCIES NIL)))
     (:ID :DESC/EMPTY->EMPTY :FACET :BOUNDARY :TIER 1 :STATUS :NECESSARY
      :WEIGHT-BITS 4 :WORK-COST 2 :SNAPSHOT
      ((:SEMANTICS (6 7) :KIND :FUNCTION :DOMAIN :INT :INPUTS
        ((0 :SEQ :INT) (1 :CODE ((0 . :INT) (1 . :INT)) :INT)) :TARGET
        (:SEQ :INT) :CODE
        ((:APP (:OP :IF (:SEQ :INT))
          (:APP (:OP := (:SEQ :INT)) (:VAR 0 (:SEQ :INT))
           (:LIT (:SEQ :INT) NIL))
          (:LIT (:SEQ :INT) NIL)
          (:APP (:OP :IF (:SEQ :INT))
           (:APP (:OP := (:SEQ :INT))
            (:APP (:OP :TAIL :INT) (:VAR 0 (:SEQ :INT)))
            (:LIT (:SEQ :INT) NIL))
           (:LIT (:SEQ :INT) NIL)
           (:APP (:OP :CONS :INT)
            (:APP (:OP :CODE-EVAL (:CODE ((0 . :INT) (1 . :INT)) :INT))
             (:VAR 1 (:CODE ((0 . :INT) (1 . :INT)) :INT))
             (:APP (:OP :AT (:SEQ :INT))
              (:APP (:OP :TAIL :INT) (:VAR 0 (:SEQ :INT))) (:LIT :INT 0))
             (:APP (:OP :AT (:SEQ :INT)) (:VAR 0 (:SEQ :INT)) (:LIT :INT 0)))
            (:APP
             (:OP :MAP-ADJACENT
              (:CODE ((0 :SEQ :INT) (1 :CODE ((0 . :INT) (1 . :INT)) :INT))
               (:SEQ :INT)))
             (:APP (:OP :TAIL :INT) (:VAR 0 (:SEQ :INT)))
             (:VAR 1 (:CODE ((0 . :INT) (1 . :INT)) :INT))))))
         (:LIT :BOOL T)
         (:APP (:OP :IF :BOOL)
          (:APP (:OP := (:SEQ :INT)) (:VAR 0 (:SEQ :INT))
           (:LIT (:SEQ :INT) NIL))
          (:APP (:OP := (:SEQ :INT)) (:VAR 1 (:SEQ :INT))
           (:LIT (:SEQ :INT) NIL))
          (:LIT :BOOL T))
         NIL)
        :CONTEXT (NIL NIL NIL NIL NIL) :DEPENDENCIES
        ((:MAP-ADJACENT ((0 :SEQ :INT) (1 :CODE ((0 . :INT) (1 . :INT)) :INT))
          (:SEQ :INT)
          (:APP (:OP :IF (:SEQ :INT))
           (:APP (:OP := (:SEQ :INT)) (:VAR 0 (:SEQ :INT))
            (:LIT (:SEQ :INT) NIL))
           (:LIT (:SEQ :INT) NIL)
           (:APP (:OP :IF (:SEQ :INT))
            (:APP (:OP := (:SEQ :INT))
             (:APP (:OP :TAIL :INT) (:VAR 0 (:SEQ :INT)))
             (:LIT (:SEQ :INT) NIL))
            (:LIT (:SEQ :INT) NIL)
            (:APP (:OP :CONS :INT)
             (:APP (:OP :CODE-EVAL (:CODE ((0 . :INT) (1 . :INT)) :INT))
              (:VAR 1 (:CODE ((0 . :INT) (1 . :INT)) :INT))
              (:APP (:OP :AT (:SEQ :INT))
               (:APP (:OP :TAIL :INT) (:VAR 0 (:SEQ :INT))) (:LIT :INT 0))
              (:APP (:OP :AT (:SEQ :INT)) (:VAR 0 (:SEQ :INT)) (:LIT :INT 0)))
             (:APP
              (:OP :MAP-ADJACENT
               (:CODE ((0 :SEQ :INT) (1 :CODE ((0 . :INT) (1 . :INT)) :INT))
                (:SEQ :INT)))
              (:APP (:OP :TAIL :INT) (:VAR 0 (:SEQ :INT)))
              (:VAR 1 (:CODE ((0 . :INT) (1 . :INT)) :INT))))))
          NIL)))
       ((:MAP-ADJACENT ((0 :SEQ :INT) (1 :CODE ((0 . :INT) (1 . :INT)) :INT))
         (:SEQ :INT)
         (:APP (:OP :IF (:SEQ :INT))
          (:APP (:OP := (:SEQ :INT)) (:VAR 0 (:SEQ :INT))
           (:LIT (:SEQ :INT) NIL))
          (:LIT (:SEQ :INT) NIL)
          (:APP (:OP :IF (:SEQ :INT))
           (:APP (:OP := (:SEQ :INT))
            (:APP (:OP :TAIL :INT) (:VAR 0 (:SEQ :INT)))
            (:LIT (:SEQ :INT) NIL))
           (:LIT (:SEQ :INT) NIL)
           (:APP (:OP :CONS :INT)
            (:APP (:OP :CODE-EVAL (:CODE ((0 . :INT) (1 . :INT)) :INT))
             (:VAR 1 (:CODE ((0 . :INT) (1 . :INT)) :INT))
             (:APP (:OP :AT (:SEQ :INT))
              (:APP (:OP :TAIL :INT) (:VAR 0 (:SEQ :INT))) (:LIT :INT 0))
             (:APP (:OP :AT (:SEQ :INT)) (:VAR 0 (:SEQ :INT)) (:LIT :INT 0)))
            (:APP
             (:OP :MAP-ADJACENT
              (:CODE ((0 :SEQ :INT) (1 :CODE ((0 . :INT) (1 . :INT)) :INT))
               (:SEQ :INT)))
             (:APP (:OP :TAIL :INT) (:VAR 0 (:SEQ :INT)))
             (:VAR 1 (:CODE ((0 . :INT) (1 . :INT)) :INT))))))
         NIL))
       (:SEMANTICS (6 7) :KIND :DESCRIPTOR :DOMAIN :INT :INPUTS
        ((0 :SEQ :INT) (1 :SEQ :INT)) :TARGET :BOOL :CODE
        ((:APP (:OP := (:SEQ :INT)) (:VAR 1 (:SEQ :INT))
          (:LIT (:SEQ :INT) NIL))
         (:APP (:OP := (:SEQ :INT)) (:VAR 0 (:SEQ :INT))
          (:LIT (:SEQ :INT) NIL))
         NIL NIL)
        :META (NIL NIL :VIOLATED) :DEPENDENCIES NIL))))
    :TOTAL-P NIL :CONDITIONAL-CODE-PARAMS (1)))
  (:ID :POSITIONS :KIND :FUNCTION :DOMAIN :INT :INPUTS
   ((0 :SEQ :INT) (1 . :INT)) :TARGET (:SEQ :INT) :EXPRESSION
   (:APP (:OP :IF (:SEQ :INT))
    (:APP (:OP := (:SEQ :INT)) (:VAR 0 (:SEQ :INT)) (:LIT (:SEQ :INT) NIL))
    (:VAR 0 (:SEQ :INT))
    (:APP (:OP :CONS :INT) (:VAR 1 :INT)
     (:APP (:OP :POSITIONS (:CODE ((0 :SEQ :INT) (1 . :INT)) (:SEQ :INT)))
      (:APP (:OP :TAIL :INT) (:VAR 0 (:SEQ :INT)))
      (:APP (:OP :+ :INT) (:VAR 1 :INT) (:LIT :INT 1)))))
   :GUARD (:LIT :BOOL T) :TRIGGER NIL :RESIDUAL NIL :AUXILIARY-CODE NIL :STATUS
   :VALIDATED :CERTIFICATE (:DATA (:KIND :STRUCTURAL-TOTALITY)) :BITS 88 :GAIN
   0 :WORK 46196 :EDGES
   ((:DESCRIBED-BY :DESC/LEN-EQ) (:DESCRIBED-BY :DESC/EMPTY->EMPTY)
    (:FROM-BATTERY :SEQUENCES))
   :METADATA
   (:COMPOSITIONAL-NAME :FUNCTION/SEQ->SEQ/LEN-EQ/EMPTY->EMPTY/ANY
    :DESCRIPTOR-PROFILE
    ((:ID :DESC/SEQ->SEQ :FACET :TYPE :TIER 1 :STATUS :NECESSARY :WEIGHT-BITS 2
      :WORK-COST 1)
     (:ID :DESC/LEN-EQ :FACET :SHAPE-DELTA :TIER 1 :STATUS :EMPIRICAL
      :WEIGHT-BITS 6 :WORK-COST 2)
     (:ID :DESC/EMPTY->EMPTY :FACET :BOUNDARY :TIER 1 :STATUS :EMPIRICAL
      :WEIGHT-BITS 4 :WORK-COST 2))
    :TOTAL-P T :CONDITIONAL-CODE-PARAMS NIL))
  (:ID :SOLVE-AT-1 :KIND :SOLVER :DOMAIN :INT :INPUTS
   ((0 :SEQ :INT) (1 . :INT)) :TARGET :INT :EXPRESSION
   (:APP
    (:OP :FILTER
     (:CODE ((0 :SEQ :INT) (1 :CODE ((0 . :INT)) :BOOL)) (:SEQ :INT)))
    (:APP (:OP :POSITIONS (:CODE ((0 :SEQ :INT) (1 . :INT)) (:SEQ :INT)))
     (:VAR 0 (:SEQ :INT)) (:LIT :INT 0))
    (:APP
     (:OP :CODE-SUBST
      (:TUPLE (:CODE ((0 . :INT) (1 :SEQ :INT) (2 . :INT)) :BOOL)
       (:TUPLE (:CODE ((0 . :INT)) :INT) (:SEQ :INT) :INT)
       (:CODE ((0 . :INT)) :BOOL)))
     (:LIT (:CODE ((0 . :INT) (1 :SEQ :INT) (2 . :INT)) :BOOL)
      (:APP (:OP := :INT) (:VAR 2 :INT)
       (:APP (:OP :AT (:SEQ :INT)) (:VAR 1 (:SEQ :INT)) (:VAR 0 :INT))))
     (:APP (:OP :TUPLE (:TUPLE (:CODE ((0 . :INT)) :INT) (:SEQ :INT) :INT))
      (:LIT (:CODE ((0 . :INT)) :INT) (:VAR 0 :INT)) (:VAR 0 (:SEQ :INT))
      (:VAR 1 :INT))))
   :GUARD (:LIT :BOOL T) :TRIGGER NIL :RESIDUAL NIL :AUXILIARY-CODE NIL :STATUS
   :CONJECTURE :CERTIFICATE
   (:DATA
    (:METHOD :SAMPLED :OBLIGATIONS (:WITNESS :UNIQUENESS :NECESSITY) :SNAPSHOT
     (:SEMANTICS (6 7) :KIND :SOLVER :DOMAIN :INT :INPUTS
      ((0 :SEQ :INT) (1 . :INT)) :TARGET :INT :CODE
      ((:APP
        (:OP :FILTER
         (:CODE ((0 :SEQ :INT) (1 :CODE ((0 . :INT)) :BOOL)) (:SEQ :INT)))
        (:APP (:OP :POSITIONS (:CODE ((0 :SEQ :INT) (1 . :INT)) (:SEQ :INT)))
         (:VAR 0 (:SEQ :INT)) (:LIT :INT 0))
        (:APP
         (:OP :CODE-SUBST
          (:TUPLE (:CODE ((0 . :INT) (1 :SEQ :INT) (2 . :INT)) :BOOL)
           (:TUPLE (:CODE ((0 . :INT)) :INT) (:SEQ :INT) :INT)
           (:CODE ((0 . :INT)) :BOOL)))
         (:LIT (:CODE ((0 . :INT) (1 :SEQ :INT) (2 . :INT)) :BOOL)
          (:APP (:OP := :INT) (:VAR 2 :INT)
           (:APP (:OP :AT (:SEQ :INT)) (:VAR 1 (:SEQ :INT)) (:VAR 0 :INT))))
         (:APP (:OP :TUPLE (:TUPLE (:CODE ((0 . :INT)) :INT) (:SEQ :INT) :INT))
          (:LIT (:CODE ((0 . :INT)) :INT) (:VAR 0 :INT)) (:VAR 0 (:SEQ :INT))
          (:VAR 1 :INT))))
       (:LIT :BOOL T) NIL NIL)
      :CONTEXT ((:OP :AT (:SEQ :INT)) 1 ((:ARGUMENT 0) :TARGET) T T)
      :DEPENDENCIES
      ((:FILTER ((0 :SEQ :INT) (1 :CODE ((0 . :INT)) :BOOL)) (:SEQ :INT)
        (:APP (:OP :IF (:SEQ :INT))
         (:APP (:OP := (:SEQ :INT)) (:VAR 0 (:SEQ :INT))
          (:LIT (:SEQ :INT) NIL))
         (:VAR 0 (:SEQ :INT))
         (:APP (:OP :IF (:SEQ :INT))
          (:APP (:OP :CODE-EVAL (:CODE ((0 . :INT)) :BOOL))
           (:VAR 1 (:CODE ((0 . :INT)) :BOOL))
           (:APP (:OP :AT (:SEQ :INT)) (:VAR 0 (:SEQ :INT)) (:LIT :INT 0)))
          (:APP (:OP :CONS :INT)
           (:APP (:OP :AT (:SEQ :INT)) (:VAR 0 (:SEQ :INT)) (:LIT :INT 0))
           (:APP
            (:OP :FILTER
             (:CODE ((0 :SEQ :INT) (1 :CODE ((0 . :INT)) :BOOL)) (:SEQ :INT)))
            (:APP (:OP :TAIL :INT) (:VAR 0 (:SEQ :INT)))
            (:VAR 1 (:CODE ((0 . :INT)) :BOOL))))
          (:APP
           (:OP :FILTER
            (:CODE ((0 :SEQ :INT) (1 :CODE ((0 . :INT)) :BOOL)) (:SEQ :INT)))
           (:APP (:OP :TAIL :INT) (:VAR 0 (:SEQ :INT)))
           (:VAR 1 (:CODE ((0 . :INT)) :BOOL)))))
        NIL)
       (:POSITIONS ((0 :SEQ :INT) (1 . :INT)) (:SEQ :INT)
        (:APP (:OP :IF (:SEQ :INT))
         (:APP (:OP := (:SEQ :INT)) (:VAR 0 (:SEQ :INT))
          (:LIT (:SEQ :INT) NIL))
         (:VAR 0 (:SEQ :INT))
         (:APP (:OP :CONS :INT) (:VAR 1 :INT)
          (:APP (:OP :POSITIONS (:CODE ((0 :SEQ :INT) (1 . :INT)) (:SEQ :INT)))
           (:APP (:OP :TAIL :INT) (:VAR 0 (:SEQ :INT)))
           (:APP (:OP :+ :INT) (:VAR 1 :INT) (:LIT :INT 1)))))
        NIL)))))
   :BITS 193 :GAIN 0 :WORK 100 :EDGES
   ((:INVERTS :AT 1) (:FROM-BATTERY :SEQUENCES)) :METADATA
   (:OPERATOR (:OP :AT (:SEQ :INT)) :OPERATOR-NAME :AT :POSITION 1 :CONTEXT-MAP
    ((:ARGUMENT 0) :TARGET) :CERTIFIED-P NIL :UNIQUE-P T :NECESSARY-P T
    :SET-VALUED-P T))
  (:ID :COMPREHENSION/FILTER-MAP :KIND :DECODER-TEMPLATE :DOMAIN :INT :INPUTS
   ((0 :SEQ :INT) (1 :CODE ((0 . :INT)) :BOOL) (2 :CODE ((0 . :INT)) :INT))
   :TARGET (:SEQ :INT) :EXPRESSION
   (:APP
    (:OP :MAP (:CODE ((0 :SEQ :INT) (1 :CODE ((0 . :INT)) :INT)) (:SEQ :INT)))
    (:APP
     (:OP :FILTER
      (:CODE ((0 :SEQ :INT) (1 :CODE ((0 . :INT)) :BOOL)) (:SEQ :INT)))
     (:VAR 0 (:SEQ :INT)) (:VAR 1 (:CODE ((0 . :INT)) :BOOL)))
    (:VAR 2 (:CODE ((0 . :INT)) :INT)))
   :GUARD (:LIT :BOOL T) :TRIGGER
   (:APP (:OP :IF :BOOL)
    (:APP (:OP :< :INT) (:APP (:OP :LENGTH :INT) (:VAR 0 (:SEQ :INT)))
     (:APP (:OP :LENGTH :INT) (:VAR 1 (:SEQ :INT))))
    (:LIT :BOOL NIL) (:LIT :BOOL T))
   :RESIDUAL NIL :AUXILIARY-CODE NIL :STATUS :VALIDATED :CERTIFICATE NIL :BITS
   41 :GAIN 0 :WORK 0 :EDGES ((:FROM-BATTERY :SEQUENCES)) :METADATA
   (:COMPOSITIONAL-NAME :DECODER-TEMPLATE/HO-SEQ->SEQ/ANY/ANY/ANY
    :DESCRIPTOR-PROFILE
    ((:ID :DESC/HO-SEQ->SEQ :FACET :TYPE :TIER 1 :STATUS :NECESSARY
      :WEIGHT-BITS 2 :WORK-COST 1))
    :CHILD-IDS (1 2) :CHILD-ID 2 :BINDINGS :IDENTITY :LIFT-P T
    :STRICT-CONTRACTION-P T :POLICY-SCORE -18 :DEPENDENCIES
    ((:FILTER ((0 :SEQ :INT) (1 :CODE ((0 . :INT)) :BOOL)) (:SEQ :INT)
      (:APP (:OP :IF (:SEQ :INT))
       (:APP (:OP := (:SEQ :INT)) (:VAR 0 (:SEQ :INT)) (:LIT (:SEQ :INT) NIL))
       (:VAR 0 (:SEQ :INT))
       (:APP (:OP :IF (:SEQ :INT))
        (:APP (:OP :CODE-EVAL (:CODE ((0 . :INT)) :BOOL))
         (:VAR 1 (:CODE ((0 . :INT)) :BOOL))
         (:APP (:OP :AT (:SEQ :INT)) (:VAR 0 (:SEQ :INT)) (:LIT :INT 0)))
        (:APP (:OP :CONS :INT)
         (:APP (:OP :AT (:SEQ :INT)) (:VAR 0 (:SEQ :INT)) (:LIT :INT 0))
         (:APP
          (:OP :FILTER
           (:CODE ((0 :SEQ :INT) (1 :CODE ((0 . :INT)) :BOOL)) (:SEQ :INT)))
          (:APP (:OP :TAIL :INT) (:VAR 0 (:SEQ :INT)))
          (:VAR 1 (:CODE ((0 . :INT)) :BOOL))))
        (:APP
         (:OP :FILTER
          (:CODE ((0 :SEQ :INT) (1 :CODE ((0 . :INT)) :BOOL)) (:SEQ :INT)))
         (:APP (:OP :TAIL :INT) (:VAR 0 (:SEQ :INT)))
         (:VAR 1 (:CODE ((0 . :INT)) :BOOL)))))
      NIL)
     (:MAP ((0 :SEQ :INT) (1 :CODE ((0 . :INT)) :INT)) (:SEQ :INT)
      (:APP (:OP :IF (:SEQ :INT))
       (:APP (:OP := (:SEQ :INT)) (:VAR 0 (:SEQ :INT)) (:LIT (:SEQ :INT) NIL))
       (:LIT (:SEQ :INT) NIL)
       (:APP (:OP :CONS :INT)
        (:APP (:OP :CODE-EVAL (:CODE ((0 . :INT)) :INT))
         (:VAR 1 (:CODE ((0 . :INT)) :INT))
         (:APP (:OP :AT (:SEQ :INT)) (:VAR 0 (:SEQ :INT)) (:LIT :INT 0)))
        (:APP
         (:OP :MAP
          (:CODE ((0 :SEQ :INT) (1 :CODE ((0 . :INT)) :INT)) (:SEQ :INT)))
         (:APP (:OP :TAIL :INT) (:VAR 0 (:SEQ :INT)))
         (:VAR 1 (:CODE ((0 . :INT)) :INT)))))
      NIL))))
  (:ID :FOLDR=FOLDL/MONOID :KIND :MOTIF :DOMAIN :INT :INPUTS
   ((0 :SEQ :INT) (1 . :INT) (2 :CODE ((0 . :INT) (1 . :INT)) :INT)) :TARGET
   :BOOL :EXPRESSION
   (:APP (:OP := :INT)
    (:APP
     (:OP :FOLDR
      (:CODE ((0 :SEQ :INT) (1 . :INT) (2 :CODE ((0 . :INT) (1 . :INT)) :INT))
       :INT))
     (:VAR 0 (:SEQ :INT)) (:VAR 1 :INT)
     (:VAR 2 (:CODE ((0 . :INT) (1 . :INT)) :INT)))
    (:APP
     (:OP :FOLDL
      (:CODE ((0 :SEQ :INT) (1 . :INT) (2 :CODE ((0 . :INT) (1 . :INT)) :INT))
       :INT))
     (:VAR 0 (:SEQ :INT)) (:VAR 1 :INT)
     (:VAR 2 (:CODE ((0 . :INT) (1 . :INT)) :INT))))
   :GUARD (:LIT :BOOL T) :TRIGGER NIL :RESIDUAL NIL :AUXILIARY-CODE NIL :STATUS
   :CONJECTURE :CERTIFICATE NIL :BITS 61 :GAIN 0 :WORK 0 :EDGES
   ((:RELATES :FOLDR :FOLDL) (:REQUIRES :ASSOCIATIVE :IDENTITY)
    (:FROM-BATTERY :SEQUENCES))
   :METADATA (:ORIGIN :THEORY-MOTIF))
  (:ID :SPEC/MAP :KIND :SPEC :DOMAIN :INT :INPUTS
   ((0 :SEQ :INT) (1 :CODE ((0 . :INT)) :INT)) :TARGET (:SEQ :INT) :EXPRESSION
   NIL :GUARD (:LIT :BOOL T) :TRIGGER NIL :RESIDUAL
   (:DATA
    ((((:LIT (:SEQ :INT) NIL) (:LIT (:CODE ((0 . :INT)) :INT) (:VAR 0 :INT)))
      (:LIT (:SEQ :INT) NIL))
     (((:LIT (:SEQ :INT) (1 2 3))
       (:LIT (:CODE ((0 . :INT)) :INT)
        (:APP (:OP :+ :INT) (:VAR 0 :INT) (:LIT :INT 1))))
      (:LIT (:SEQ :INT) (2 3 4)))))
   :AUXILIARY-CODE NIL :STATUS :VALIDATED :CERTIFICATE NIL :BITS 0 :GAIN 0
   :WORK 0 :EDGES ((:SPECIFIES :MAP)) :METADATA (:TARGET-KIND :FUNCTION))
  (:ID :SPEC/FOLDR :KIND :SPEC :DOMAIN :INT :INPUTS
   ((0 :SEQ :INT) (1 . :INT) (2 :CODE ((0 . :INT) (1 . :INT)) :INT)) :TARGET
   :INT :EXPRESSION NIL :GUARD (:LIT :BOOL T) :TRIGGER NIL :RESIDUAL
   (:DATA
    ((((:LIT (:SEQ :INT) NIL) (:LIT :INT 7)
       (:LIT (:CODE ((0 . :INT) (1 . :INT)) :INT)
        (:APP (:OP :- :INT) (:VAR 0 :INT) (:VAR 1 :INT))))
      (:LIT :INT 7))
     (((:LIT (:SEQ :INT) (1 2 3)) (:LIT :INT 10)
       (:LIT (:CODE ((0 . :INT) (1 . :INT)) :INT)
        (:APP (:OP :- :INT) (:VAR 0 :INT) (:VAR 1 :INT))))
      (:LIT :INT -8))))
   :AUXILIARY-CODE NIL :STATUS :VALIDATED :CERTIFICATE NIL :BITS 0 :GAIN 0
   :WORK 0 :EDGES ((:SPECIFIES :FOLDR)) :METADATA (:TARGET-KIND :FUNCTION))
  (:ID :SPEC/FOLDL :KIND :SPEC :DOMAIN :INT :INPUTS
   ((0 :SEQ :INT) (1 . :INT) (2 :CODE ((0 . :INT) (1 . :INT)) :INT)) :TARGET
   :INT :EXPRESSION NIL :GUARD (:LIT :BOOL T) :TRIGGER NIL :RESIDUAL
   (:DATA
    ((((:LIT (:SEQ :INT) NIL) (:LIT :INT 7)
       (:LIT (:CODE ((0 . :INT) (1 . :INT)) :INT)
        (:APP (:OP :- :INT) (:VAR 0 :INT) (:VAR 1 :INT))))
      (:LIT :INT 7))
     (((:LIT (:SEQ :INT) NIL) (:LIT :INT 9)
       (:LIT (:CODE ((0 . :INT) (1 . :INT)) :INT)
        (:APP (:OP :- :INT) (:VAR 0 :INT) (:VAR 1 :INT))))
      (:LIT :INT 9))
     (((:LIT (:SEQ :INT) NIL) (:LIT :INT 6)
       (:LIT (:CODE ((0 . :INT) (1 . :INT)) :INT)
        (:APP (:OP :- :INT) (:VAR 0 :INT) (:VAR 1 :INT))))
      (:LIT :INT 6))
     (((:LIT (:SEQ :INT) (3)) (:LIT :INT 9)
       (:LIT (:CODE ((0 . :INT) (1 . :INT)) :INT)
        (:APP (:OP :- :INT) (:VAR 0 :INT) (:VAR 1 :INT))))
      (:LIT :INT 6))
     (((:LIT (:SEQ :INT) (2 3)) (:LIT :INT 11)
       (:LIT (:CODE ((0 . :INT) (1 . :INT)) :INT)
        (:APP (:OP :- :INT) (:VAR 0 :INT) (:VAR 1 :INT))))
      (:LIT :INT 6))
     (((:LIT (:SEQ :INT) (1 2 3)) (:LIT :INT 12)
       (:LIT (:CODE ((0 . :INT) (1 . :INT)) :INT)
        (:APP (:OP :- :INT) (:VAR 0 :INT) (:VAR 1 :INT))))
      (:LIT :INT 6))
     (((:LIT (:SEQ :INT) NIL) (:LIT :INT 10)
       (:LIT (:CODE ((0 . :INT) (1 . :INT)) :INT)
        (:APP (:OP :- :INT) (:VAR 0 :INT) (:VAR 1 :INT))))
      (:LIT :INT 10))
     (((:LIT (:SEQ :INT) (4)) (:LIT :INT 10)
       (:LIT (:CODE ((0 . :INT) (1 . :INT)) :INT)
        (:APP (:OP :- :INT) (:VAR 0 :INT) (:VAR 1 :INT))))
      (:LIT :INT 6))
     (((:LIT (:SEQ :INT) (1 4)) (:LIT :INT 11)
       (:LIT (:CODE ((0 . :INT) (1 . :INT)) :INT)
        (:APP (:OP :- :INT) (:VAR 0 :INT) (:VAR 1 :INT))))
      (:LIT :INT 6))))
   :AUXILIARY-CODE NIL :STATUS :VALIDATED :CERTIFICATE NIL :BITS 0 :GAIN 0
   :WORK 0 :EDGES ((:SPECIFIES :FOLDL)) :METADATA
   (:TARGET-KIND :FUNCTION :OPERATORS
    ((:OP :TAIL :INT) (:OP :AT (:SEQ :INT)) (:OP := (:SEQ :INT)) (:OP :IF :INT)
     (:OP :CODE-EVAL (:CODE ((0 . :INT) (1 . :INT)) :INT)))
    :CONSTANTS ((:LIT (:SEQ :INT) NIL))))
  (:ID :SPEC/FILTER :KIND :SPEC :DOMAIN :INT :INPUTS
   ((0 :SEQ :INT) (1 :CODE ((0 . :INT)) :BOOL)) :TARGET (:SEQ :INT) :EXPRESSION
   NIL :GUARD (:LIT :BOOL T) :TRIGGER NIL :RESIDUAL
   (:DATA
    ((((:LIT (:SEQ :INT) NIL)
       (:LIT (:CODE ((0 . :INT)) :BOOL)
        (:APP (:OP :< :INT) (:LIT :INT 0) (:VAR 0 :INT))))
      (:LIT (:SEQ :INT) NIL))
     (((:LIT (:SEQ :INT) (3))
       (:LIT (:CODE ((0 . :INT)) :BOOL)
        (:APP (:OP :< :INT) (:LIT :INT 0) (:VAR 0 :INT))))
      (:LIT (:SEQ :INT) (3)))
     (((:LIT (:SEQ :INT) (-2 3))
       (:LIT (:CODE ((0 . :INT)) :BOOL)
        (:APP (:OP :< :INT) (:LIT :INT 0) (:VAR 0 :INT))))
      (:LIT (:SEQ :INT) (3)))
     (((:LIT (:SEQ :INT) (4 -2 3))
       (:LIT (:CODE ((0 . :INT)) :BOOL)
        (:APP (:OP :< :INT) (:LIT :INT 0) (:VAR 0 :INT))))
      (:LIT (:SEQ :INT) (4 3)))
     (((:LIT (:SEQ :INT) NIL)
       (:LIT (:CODE ((0 . :INT)) :BOOL)
        (:APP (:OP := :INT)
         (:APP (:OP :* :INT) (:APP (:OP :/ :INT) (:VAR 0 :INT) (:LIT :INT 2))
          (:LIT :INT 2))
         (:VAR 0 :INT))))
      (:LIT (:SEQ :INT) NIL))
     (((:LIT (:SEQ :INT) (3))
       (:LIT (:CODE ((0 . :INT)) :BOOL)
        (:APP (:OP := :INT)
         (:APP (:OP :* :INT) (:APP (:OP :/ :INT) (:VAR 0 :INT) (:LIT :INT 2))
          (:LIT :INT 2))
         (:VAR 0 :INT))))
      (:LIT (:SEQ :INT) NIL))
     (((:LIT (:SEQ :INT) (4 3))
       (:LIT (:CODE ((0 . :INT)) :BOOL)
        (:APP (:OP := :INT)
         (:APP (:OP :* :INT) (:APP (:OP :/ :INT) (:VAR 0 :INT) (:LIT :INT 2))
          (:LIT :INT 2))
         (:VAR 0 :INT))))
      (:LIT (:SEQ :INT) (4)))))
   :AUXILIARY-CODE NIL :STATUS :VALIDATED :CERTIFICATE NIL :BITS 0 :GAIN 0
   :WORK 0 :EDGES ((:SPECIFIES :FILTER)) :METADATA
   (:TARGET-KIND :FUNCTION :OPERATORS
    ((:OP :CONS :INT) (:OP :TAIL :INT) (:OP :AT (:SEQ :INT))
     (:OP := (:SEQ :INT)) (:OP :IF (:SEQ :INT))
     (:OP :CODE-EVAL (:CODE ((0 . :INT)) :BOOL)))
    :CONSTANTS ((:LIT (:SEQ :INT) NIL))))
  (:ID :SPEC/MAP-ADJACENT :KIND :SPEC :DOMAIN :INT :INPUTS
   ((0 :SEQ :INT) (1 :CODE ((0 . :INT) (1 . :INT)) :INT)) :TARGET (:SEQ :INT)
   :EXPRESSION NIL :GUARD (:LIT :BOOL T) :TRIGGER NIL :RESIDUAL
   (:DATA
    ((((:LIT (:SEQ :INT) NIL)
       (:LIT (:CODE ((0 . :INT) (1 . :INT)) :INT)
        (:APP (:OP :- :INT) (:VAR 0 :INT) (:VAR 1 :INT))))
      (:LIT (:SEQ :INT) NIL))
     (((:LIT (:SEQ :INT) (9))
       (:LIT (:CODE ((0 . :INT) (1 . :INT)) :INT)
        (:APP (:OP :- :INT) (:VAR 0 :INT) (:VAR 1 :INT))))
      (:LIT (:SEQ :INT) NIL))
     (((:LIT (:SEQ :INT) (4 9))
       (:LIT (:CODE ((0 . :INT) (1 . :INT)) :INT)
        (:APP (:OP :- :INT) (:VAR 0 :INT) (:VAR 1 :INT))))
      (:LIT (:SEQ :INT) (5)))
     (((:LIT (:SEQ :INT) (1 4 9))
       (:LIT (:CODE ((0 . :INT) (1 . :INT)) :INT)
        (:APP (:OP :- :INT) (:VAR 0 :INT) (:VAR 1 :INT))))
      (:LIT (:SEQ :INT) (3 5)))
     (((:LIT (:SEQ :INT) NIL)
       (:LIT (:CODE ((0 . :INT) (1 . :INT)) :INT)
        (:APP (:OP :+ :INT) (:VAR 0 :INT) (:VAR 1 :INT))))
      (:LIT (:SEQ :INT) NIL))
     (((:LIT (:SEQ :INT) (5))
       (:LIT (:CODE ((0 . :INT) (1 . :INT)) :INT)
        (:APP (:OP :+ :INT) (:VAR 0 :INT) (:VAR 1 :INT))))
      (:LIT (:SEQ :INT) NIL))
     (((:LIT (:SEQ :INT) (2 5))
       (:LIT (:CODE ((0 . :INT) (1 . :INT)) :INT)
        (:APP (:OP :+ :INT) (:VAR 0 :INT) (:VAR 1 :INT))))
      (:LIT (:SEQ :INT) (7)))
     (((:LIT (:SEQ :INT) (1 2 5))
       (:LIT (:CODE ((0 . :INT) (1 . :INT)) :INT)
        (:APP (:OP :+ :INT) (:VAR 0 :INT) (:VAR 1 :INT))))
      (:LIT (:SEQ :INT) (3 7)))))
   :AUXILIARY-CODE NIL :STATUS :VALIDATED :CERTIFICATE NIL :BITS 0 :GAIN 0
   :WORK 0 :EDGES ((:SPECIFIES :MAP-ADJACENT)) :METADATA
   (:TARGET-KIND :FUNCTION :OPERATORS
    ((:OP :CONS :INT) (:OP :TAIL :INT) (:OP :AT (:SEQ :INT))
     (:OP := (:SEQ :INT)) (:OP :IF (:SEQ :INT))
     (:OP :CODE-EVAL (:CODE ((0 . :INT) (1 . :INT)) :INT)))
    :CONSTANTS ((:LIT (:SEQ :INT) NIL))))
  (:ID :SPEC/POSITIONS :KIND :SPEC :DOMAIN :INT :INPUTS
   ((0 :SEQ :INT) (1 . :INT)) :TARGET (:SEQ :INT) :EXPRESSION NIL :GUARD
   (:LIT :BOOL T) :TRIGGER NIL :RESIDUAL
   (:DATA
    ((((:LIT (:SEQ :INT) NIL) (:LIT :INT 0)) (:LIT (:SEQ :INT) NIL))
     (((:LIT (:SEQ :INT) NIL) (:LIT :INT 1)) (:LIT (:SEQ :INT) NIL))
     (((:LIT (:SEQ :INT) NIL) (:LIT :INT 2)) (:LIT (:SEQ :INT) NIL))
     (((:LIT (:SEQ :INT) NIL) (:LIT :INT 3)) (:LIT (:SEQ :INT) NIL))
     (((:LIT (:SEQ :INT) NIL) (:LIT :INT 4)) (:LIT (:SEQ :INT) NIL))
     (((:LIT (:SEQ :INT) (7)) (:LIT :INT 2)) (:LIT (:SEQ :INT) (2)))
     (((:LIT (:SEQ :INT) (4)) (:LIT :INT 3)) (:LIT (:SEQ :INT) (3)))
     (((:LIT (:SEQ :INT) (7)) (:LIT :INT 0)) (:LIT (:SEQ :INT) (0)))
     (((:LIT (:SEQ :INT) (6 7)) (:LIT :INT 1)) (:LIT (:SEQ :INT) (1 2)))
     (((:LIT (:SEQ :INT) (9 4)) (:LIT :INT 2)) (:LIT (:SEQ :INT) (2 3)))
     (((:LIT (:SEQ :INT) (5 6 7)) (:LIT :INT 0)) (:LIT (:SEQ :INT) (0 1 2)))))
   :AUXILIARY-CODE NIL :STATUS :VALIDATED :CERTIFICATE NIL :BITS 0 :GAIN 0
   :WORK 0 :EDGES ((:SPECIFIES :POSITIONS)) :METADATA
   (:TARGET-KIND :FUNCTION :OPERATORS
    ((:OP :CONS :INT) (:OP :TAIL :INT) (:OP :AT (:SEQ :INT))
     (:OP := (:SEQ :INT)) (:OP :IF (:SEQ :INT)) (:OP :+ :INT))
    :LITERALS (0 1) :CONSTANTS ((:LIT (:SEQ :INT) NIL))))))
