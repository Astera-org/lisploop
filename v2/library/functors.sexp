(:KNOWLEDGE-LIBRARY :ENCODING-VERSION 7 :VERSION 26 :METADATA
 (:BATTERY :FUNCTORS :PARAMETERS ((LISPLOOP::?A :INT))) :FUNCTION-NAMES NIL
 :DE-NOVO-COUNTER 0 :ENTRY-COUNTER 0 :ENTRIES
 ((:ID :FUNCTOR/MAP-INVERSE-0 :KIND :TRANSFORMER :DOMAIN :INT :INPUTS
   ((0 :CODE ((0 . :INT) (1 . :INT)) :INT)
    (1 :CODE ((0 . :INT) (1 . :INT)) :INT))
   :TARGET (:CODE ((0 :CODE ((0 . :INT)) :INT)) (:CODE ((0 . :INT)) :INT))
   :EXPRESSION
   (:APP
    (:OP :CODE-SUBST
     (:TUPLE
      (:CODE
       ((0 :CODE ((0 . :INT) (1 . :INT)) :INT)
        (1 :CODE ((0 . :INT) (1 . :INT)) :INT) (2 :CODE ((0 . :INT)) :INT))
       (:CODE ((0 . :INT)) :INT))
      (:TUPLE (:CODE ((0 . :INT) (1 . :INT)) :INT)
       (:CODE ((0 . :INT) (1 . :INT)) :INT)
       (:CODE ((0 :CODE ((0 . :INT)) :INT)) (:CODE ((0 . :INT)) :INT)))
      (:CODE ((0 :CODE ((0 . :INT)) :INT)) (:CODE ((0 . :INT)) :INT))))
    (:LIT
     (:CODE
      ((0 :CODE ((0 . :INT) (1 . :INT)) :INT)
       (1 :CODE ((0 . :INT) (1 . :INT)) :INT) (2 :CODE ((0 . :INT)) :INT))
      (:CODE ((0 . :INT)) :INT))
     (:APP
      (:OP :CODE-SUBST
       (:TUPLE (:CODE ((0 . :INT) (1 . :INT)) :INT)
        (:TUPLE (:CODE ((0 . :INT)) :INT) (:CODE ((0 . :INT)) :INT))
        (:CODE ((0 . :INT)) :INT)))
      (:VAR 1 (:CODE ((0 . :INT) (1 . :INT)) :INT))
      (:APP
       (:OP :TUPLE
        (:TUPLE (:CODE ((0 . :INT)) :INT) (:CODE ((0 . :INT)) :INT)))
       (:APP
        (:OP :CODE-BIND
         (:TUPLE (:CODE ((0 . :INT) (1 . :INT)) :INT) (:CODE ((0 . :INT)) :INT)
          (:CODE ((0 . :INT)) :INT)))
        (:VAR 0 (:CODE ((0 . :INT) (1 . :INT)) :INT))
        (:VAR 2 (:CODE ((0 . :INT)) :INT)) (:LIT :INT 1))
       (:LIT (:CODE ((0 . :INT)) :INT) (:VAR 0 :INT)))))
    (:APP
     (:OP :TUPLE
      (:TUPLE (:CODE ((0 . :INT) (1 . :INT)) :INT)
       (:CODE ((0 . :INT) (1 . :INT)) :INT)
       (:CODE ((0 :CODE ((0 . :INT)) :INT)) (:CODE ((0 . :INT)) :INT))))
     (:VAR 0 (:CODE ((0 . :INT) (1 . :INT)) :INT))
     (:VAR 1 (:CODE ((0 . :INT) (1 . :INT)) :INT))
     (:LIT (:CODE ((0 :CODE ((0 . :INT)) :INT)) (:CODE ((0 . :INT)) :INT))
      (:VAR 0 (:CODE ((0 . :INT)) :INT)))))
   :GUARD (:LIT :BOOL T) :TRIGGER NIL :RESIDUAL NIL :AUXILIARY-CODE NIL :STATUS
   :VALIDATED :CERTIFICATE NIL :BITS 448 :GAIN 0 :WORK 0 :EDGES
   ((:FROM-BATTERY :FUNCTORS)) :METADATA
   (:ORIGIN :BOOTSTRAP-FUNCTOR-TRANSFORMER))
  (:ID :FUNCTOR/MAP-INVERSE-1 :KIND :TRANSFORMER :DOMAIN :INT :INPUTS
   ((0 :CODE ((0 . :INT) (1 . :INT)) :INT)
    (1 :CODE ((0 . :INT) (1 . :INT)) :INT))
   :TARGET (:CODE ((0 :CODE ((0 . :INT)) :INT)) (:CODE ((0 . :INT)) :INT))
   :EXPRESSION
   (:APP
    (:OP :CODE-SUBST
     (:TUPLE
      (:CODE
       ((0 :CODE ((0 . :INT) (1 . :INT)) :INT)
        (1 :CODE ((0 . :INT) (1 . :INT)) :INT) (2 :CODE ((0 . :INT)) :INT))
       (:CODE ((0 . :INT)) :INT))
      (:TUPLE (:CODE ((0 . :INT) (1 . :INT)) :INT)
       (:CODE ((0 . :INT) (1 . :INT)) :INT)
       (:CODE ((0 :CODE ((0 . :INT)) :INT)) (:CODE ((0 . :INT)) :INT)))
      (:CODE ((0 :CODE ((0 . :INT)) :INT)) (:CODE ((0 . :INT)) :INT))))
    (:LIT
     (:CODE
      ((0 :CODE ((0 . :INT) (1 . :INT)) :INT)
       (1 :CODE ((0 . :INT) (1 . :INT)) :INT) (2 :CODE ((0 . :INT)) :INT))
      (:CODE ((0 . :INT)) :INT))
     (:APP
      (:OP :CODE-SUBST
       (:TUPLE (:CODE ((0 . :INT) (1 . :INT)) :INT)
        (:TUPLE (:CODE ((0 . :INT)) :INT) (:CODE ((0 . :INT)) :INT))
        (:CODE ((0 . :INT)) :INT)))
      (:VAR 1 (:CODE ((0 . :INT) (1 . :INT)) :INT))
      (:APP
       (:OP :TUPLE
        (:TUPLE (:CODE ((0 . :INT)) :INT) (:CODE ((0 . :INT)) :INT)))
       (:APP
        (:OP :CODE-BIND
         (:TUPLE (:CODE ((0 . :INT) (1 . :INT)) :INT) (:CODE ((0 . :INT)) :INT)
          (:CODE ((0 . :INT)) :INT)))
        (:VAR 0 (:CODE ((0 . :INT) (1 . :INT)) :INT))
        (:VAR 2 (:CODE ((0 . :INT)) :INT)) (:LIT :INT 0))
       (:LIT (:CODE ((0 . :INT)) :INT) (:VAR 0 :INT)))))
    (:APP
     (:OP :TUPLE
      (:TUPLE (:CODE ((0 . :INT) (1 . :INT)) :INT)
       (:CODE ((0 . :INT) (1 . :INT)) :INT)
       (:CODE ((0 :CODE ((0 . :INT)) :INT)) (:CODE ((0 . :INT)) :INT))))
     (:VAR 0 (:CODE ((0 . :INT) (1 . :INT)) :INT))
     (:VAR 1 (:CODE ((0 . :INT) (1 . :INT)) :INT))
     (:LIT (:CODE ((0 :CODE ((0 . :INT)) :INT)) (:CODE ((0 . :INT)) :INT))
      (:VAR 0 (:CODE ((0 . :INT)) :INT)))))
   :GUARD (:LIT :BOOL T) :TRIGGER NIL :RESIDUAL NIL :AUXILIARY-CODE NIL :STATUS
   :VALIDATED :CERTIFICATE NIL :BITS 445 :GAIN 0 :WORK 0 :EDGES
   ((:FROM-BATTERY :FUNCTORS)) :METADATA
   (:ORIGIN :BOOTSTRAP-FUNCTOR-TRANSFORMER))
  (:ID :FUNCTOR/MAP-GUARD-0 :KIND :TRANSFORMER :DOMAIN :INT :INPUTS
   ((0 :CODE ((0 . :INT) (1 . :INT)) :INT)
    (1 :CODE ((0 . :INT) (1 . :INT)) :INT))
   :TARGET (:CODE ((0 :CODE ((0 . :INT)) :INT) (1 :SEQ :INT)) :BOOL)
   :EXPRESSION
   (:APP
    (:OP :CODE-SUBST
     (:TUPLE
      (:CODE
       ((0 :CODE ((0 . :INT) (1 . :INT)) :INT)
        (1 :CODE ((0 . :INT) (1 . :INT)) :INT) (2 :CODE ((0 . :INT)) :INT))
       :BOOL)
      (:TUPLE (:CODE ((0 . :INT) (1 . :INT)) :INT)
       (:CODE ((0 . :INT) (1 . :INT)) :INT)
       (:CODE ((0 :CODE ((0 . :INT)) :INT) (1 :SEQ :INT))
        (:CODE ((0 . :INT)) :INT)))
      (:CODE ((0 :CODE ((0 . :INT)) :INT) (1 :SEQ :INT)) :BOOL)))
    (:LIT
     (:CODE
      ((0 :CODE ((0 . :INT) (1 . :INT)) :INT)
       (1 :CODE ((0 . :INT) (1 . :INT)) :INT) (2 :CODE ((0 . :INT)) :INT))
      :BOOL)
     (:APP (:OP :IF :BOOL)
      (:APP
       (:OP :CODE-MATCH
        (:TUPLE (:CODE ((0 . :INT) (1 . :INT)) :INT)
         (:CODE ((0 . :INT)) :INT)))
       (:VAR 0 (:CODE ((0 . :INT) (1 . :INT)) :INT))
       (:VAR 2 (:CODE ((0 . :INT)) :INT)))
      (:APP (:OP :IF :BOOL)
       (:APP (:OP := (:CODE ((0 . :INT)) :INT))
        (:APP
         (:OP :CODE-BIND
          (:TUPLE (:CODE ((0 . :INT) (1 . :INT)) :INT)
           (:CODE ((0 . :INT)) :INT) (:CODE ((0 . :INT)) :INT)))
         (:VAR 0 (:CODE ((0 . :INT) (1 . :INT)) :INT))
         (:VAR 2 (:CODE ((0 . :INT)) :INT)) (:LIT :INT 0))
        (:LIT (:CODE ((0 . :INT)) :INT) (:VAR 0 :INT)))
       (:APP (:OP :IF :BOOL)
        (:APP (:OP := :INT)
         (:APP (:OP :CODE-KIND (:CODE ((0 . :INT)) :INT))
          (:APP
           (:OP :CODE-BIND
            (:TUPLE (:CODE ((0 . :INT) (1 . :INT)) :INT)
             (:CODE ((0 . :INT)) :INT) (:CODE ((0 . :INT)) :INT)))
           (:VAR 0 (:CODE ((0 . :INT) (1 . :INT)) :INT))
           (:VAR 2 (:CODE ((0 . :INT)) :INT)) (:LIT :INT 1)))
         (:LIT :INT 1))
        (:APP (:OP :CODE-TOTAL (:CODE ((0 . :INT)) :INT))
         (:APP
          (:OP :CODE-SUBST
           (:TUPLE (:CODE ((0 . :INT) (1 . :INT)) :INT)
            (:TUPLE (:CODE ((0 . :INT)) :INT) (:CODE ((0 . :INT)) :INT))
            (:CODE ((0 . :INT)) :INT)))
          (:VAR 1 (:CODE ((0 . :INT) (1 . :INT)) :INT))
          (:APP
           (:OP :TUPLE
            (:TUPLE (:CODE ((0 . :INT)) :INT) (:CODE ((0 . :INT)) :INT)))
           (:APP
            (:OP :CODE-BIND
             (:TUPLE (:CODE ((0 . :INT) (1 . :INT)) :INT)
              (:CODE ((0 . :INT)) :INT) (:CODE ((0 . :INT)) :INT)))
            (:VAR 0 (:CODE ((0 . :INT) (1 . :INT)) :INT))
            (:VAR 2 (:CODE ((0 . :INT)) :INT)) (:LIT :INT 1))
           (:LIT (:CODE ((0 . :INT)) :INT) (:VAR 0 :INT)))))
        (:LIT :BOOL NIL))
       (:LIT :BOOL NIL))
      (:LIT :BOOL NIL)))
    (:APP
     (:OP :TUPLE
      (:TUPLE (:CODE ((0 . :INT) (1 . :INT)) :INT)
       (:CODE ((0 . :INT) (1 . :INT)) :INT)
       (:CODE ((0 :CODE ((0 . :INT)) :INT) (1 :SEQ :INT))
        (:CODE ((0 . :INT)) :INT))))
     (:VAR 0 (:CODE ((0 . :INT) (1 . :INT)) :INT))
     (:VAR 1 (:CODE ((0 . :INT) (1 . :INT)) :INT))
     (:LIT
      (:CODE ((0 :CODE ((0 . :INT)) :INT) (1 :SEQ :INT))
       (:CODE ((0 . :INT)) :INT))
      (:VAR 0 (:CODE ((0 . :INT)) :INT)))))
   :GUARD (:LIT :BOOL T) :TRIGGER NIL :RESIDUAL NIL :AUXILIARY-CODE NIL :STATUS
   :VALIDATED :CERTIFICATE NIL :BITS 783 :GAIN 0 :WORK 0 :EDGES
   ((:FROM-BATTERY :FUNCTORS)) :METADATA
   (:ORIGIN :BOOTSTRAP-FUNCTOR-TRANSFORMER))
  (:ID :FUNCTOR/MAP-GUARD-1 :KIND :TRANSFORMER :DOMAIN :INT :INPUTS
   ((0 :CODE ((0 . :INT) (1 . :INT)) :INT)
    (1 :CODE ((0 . :INT) (1 . :INT)) :INT))
   :TARGET (:CODE ((0 :CODE ((0 . :INT)) :INT) (1 :SEQ :INT)) :BOOL)
   :EXPRESSION
   (:APP
    (:OP :CODE-SUBST
     (:TUPLE
      (:CODE
       ((0 :CODE ((0 . :INT) (1 . :INT)) :INT)
        (1 :CODE ((0 . :INT) (1 . :INT)) :INT) (2 :CODE ((0 . :INT)) :INT))
       :BOOL)
      (:TUPLE (:CODE ((0 . :INT) (1 . :INT)) :INT)
       (:CODE ((0 . :INT) (1 . :INT)) :INT)
       (:CODE ((0 :CODE ((0 . :INT)) :INT) (1 :SEQ :INT))
        (:CODE ((0 . :INT)) :INT)))
      (:CODE ((0 :CODE ((0 . :INT)) :INT) (1 :SEQ :INT)) :BOOL)))
    (:LIT
     (:CODE
      ((0 :CODE ((0 . :INT) (1 . :INT)) :INT)
       (1 :CODE ((0 . :INT) (1 . :INT)) :INT) (2 :CODE ((0 . :INT)) :INT))
      :BOOL)
     (:APP (:OP :IF :BOOL)
      (:APP
       (:OP :CODE-MATCH
        (:TUPLE (:CODE ((0 . :INT) (1 . :INT)) :INT)
         (:CODE ((0 . :INT)) :INT)))
       (:VAR 0 (:CODE ((0 . :INT) (1 . :INT)) :INT))
       (:VAR 2 (:CODE ((0 . :INT)) :INT)))
      (:APP (:OP :IF :BOOL)
       (:APP (:OP := (:CODE ((0 . :INT)) :INT))
        (:APP
         (:OP :CODE-BIND
          (:TUPLE (:CODE ((0 . :INT) (1 . :INT)) :INT)
           (:CODE ((0 . :INT)) :INT) (:CODE ((0 . :INT)) :INT)))
         (:VAR 0 (:CODE ((0 . :INT) (1 . :INT)) :INT))
         (:VAR 2 (:CODE ((0 . :INT)) :INT)) (:LIT :INT 1))
        (:LIT (:CODE ((0 . :INT)) :INT) (:VAR 0 :INT)))
       (:APP (:OP :IF :BOOL)
        (:APP (:OP := :INT)
         (:APP (:OP :CODE-KIND (:CODE ((0 . :INT)) :INT))
          (:APP
           (:OP :CODE-BIND
            (:TUPLE (:CODE ((0 . :INT) (1 . :INT)) :INT)
             (:CODE ((0 . :INT)) :INT) (:CODE ((0 . :INT)) :INT)))
           (:VAR 0 (:CODE ((0 . :INT) (1 . :INT)) :INT))
           (:VAR 2 (:CODE ((0 . :INT)) :INT)) (:LIT :INT 0)))
         (:LIT :INT 1))
        (:APP (:OP :CODE-TOTAL (:CODE ((0 . :INT)) :INT))
         (:APP
          (:OP :CODE-SUBST
           (:TUPLE (:CODE ((0 . :INT) (1 . :INT)) :INT)
            (:TUPLE (:CODE ((0 . :INT)) :INT) (:CODE ((0 . :INT)) :INT))
            (:CODE ((0 . :INT)) :INT)))
          (:VAR 1 (:CODE ((0 . :INT) (1 . :INT)) :INT))
          (:APP
           (:OP :TUPLE
            (:TUPLE (:CODE ((0 . :INT)) :INT) (:CODE ((0 . :INT)) :INT)))
           (:APP
            (:OP :CODE-BIND
             (:TUPLE (:CODE ((0 . :INT) (1 . :INT)) :INT)
              (:CODE ((0 . :INT)) :INT) (:CODE ((0 . :INT)) :INT)))
            (:VAR 0 (:CODE ((0 . :INT) (1 . :INT)) :INT))
            (:VAR 2 (:CODE ((0 . :INT)) :INT)) (:LIT :INT 0))
           (:LIT (:CODE ((0 . :INT)) :INT) (:VAR 0 :INT)))))
        (:LIT :BOOL NIL))
       (:LIT :BOOL NIL))
      (:LIT :BOOL NIL)))
    (:APP
     (:OP :TUPLE
      (:TUPLE (:CODE ((0 . :INT) (1 . :INT)) :INT)
       (:CODE ((0 . :INT) (1 . :INT)) :INT)
       (:CODE ((0 :CODE ((0 . :INT)) :INT) (1 :SEQ :INT))
        (:CODE ((0 . :INT)) :INT))))
     (:VAR 0 (:CODE ((0 . :INT) (1 . :INT)) :INT))
     (:VAR 1 (:CODE ((0 . :INT) (1 . :INT)) :INT))
     (:LIT
      (:CODE ((0 :CODE ((0 . :INT)) :INT) (1 :SEQ :INT))
       (:CODE ((0 . :INT)) :INT))
      (:VAR 0 (:CODE ((0 . :INT)) :INT)))))
   :GUARD (:LIT :BOOL T) :TRIGGER NIL :RESIDUAL NIL :AUXILIARY-CODE NIL :STATUS
   :VALIDATED :CERTIFICATE NIL :BITS 780 :GAIN 0 :WORK 0 :EDGES
   ((:FROM-BATTERY :FUNCTORS)) :METADATA
   (:ORIGIN :BOOTSTRAP-FUNCTOR-TRANSFORMER))
  (:ID :FUNCTOR/MAP-WITNESS-0 :KIND :TRANSFORMER :DOMAIN :INT :INPUTS
   ((0 :CODE ((0 :CODE ((0 . :INT)) :INT) (1 :SEQ :INT))
     (:FN ((:SEQ :INT) (:CODE ((0 . :INT)) :INT)) (:SEQ :INT)))
    (1 :CODE ((0 . :INT) (1 . :INT)) :INT)
    (2 :CODE ((0 . :INT) (1 . :INT)) :INT))
   :TARGET (:CODE ((0 :CODE ((0 . :INT)) :INT) (1 :SEQ :INT)) (:SEQ :INT))
   :EXPRESSION
   (:APP
    (:OP :CODE-APPLY
     (:CODE ((0 :CODE ((0 . :INT)) :INT) (1 :SEQ :INT))
      (:FN ((:SEQ :INT) (:CODE ((0 . :INT)) :INT)) (:SEQ :INT))))
    (:VAR 0
     (:CODE ((0 :CODE ((0 . :INT)) :INT) (1 :SEQ :INT))
      (:FN ((:SEQ :INT) (:CODE ((0 . :INT)) :INT)) (:SEQ :INT))))
    (:APP
     (:OP :TUPLE
      (:TUPLE (:CODE ((0 :CODE ((0 . :INT)) :INT) (1 :SEQ :INT)) (:SEQ :INT))
       (:CODE ((0 :CODE ((0 . :INT)) :INT) (1 :SEQ :INT))
        (:CODE ((0 . :INT)) :INT))))
     (:LIT (:CODE ((0 :CODE ((0 . :INT)) :INT) (1 :SEQ :INT)) (:SEQ :INT))
      (:VAR 1 (:SEQ :INT)))
     (:APP
      (:OP :CODE-SUBST
       (:TUPLE
        (:CODE
         ((0 :CODE ((0 . :INT) (1 . :INT)) :INT)
          (1 :CODE ((0 . :INT) (1 . :INT)) :INT) (2 :CODE ((0 . :INT)) :INT))
         (:CODE ((0 . :INT)) :INT))
        (:TUPLE (:CODE ((0 . :INT) (1 . :INT)) :INT)
         (:CODE ((0 . :INT) (1 . :INT)) :INT)
         (:CODE ((0 :CODE ((0 . :INT)) :INT) (1 :SEQ :INT))
          (:CODE ((0 . :INT)) :INT)))
        (:CODE ((0 :CODE ((0 . :INT)) :INT) (1 :SEQ :INT))
         (:CODE ((0 . :INT)) :INT))))
      (:LIT
       (:CODE
        ((0 :CODE ((0 . :INT) (1 . :INT)) :INT)
         (1 :CODE ((0 . :INT) (1 . :INT)) :INT) (2 :CODE ((0 . :INT)) :INT))
        (:CODE ((0 . :INT)) :INT))
       (:APP
        (:OP :CODE-SUBST
         (:TUPLE (:CODE ((0 . :INT) (1 . :INT)) :INT)
          (:TUPLE (:CODE ((0 . :INT)) :INT) (:CODE ((0 . :INT)) :INT))
          (:CODE ((0 . :INT)) :INT)))
        (:VAR 1 (:CODE ((0 . :INT) (1 . :INT)) :INT))
        (:APP
         (:OP :TUPLE
          (:TUPLE (:CODE ((0 . :INT)) :INT) (:CODE ((0 . :INT)) :INT)))
         (:APP
          (:OP :CODE-BIND
           (:TUPLE (:CODE ((0 . :INT) (1 . :INT)) :INT)
            (:CODE ((0 . :INT)) :INT) (:CODE ((0 . :INT)) :INT)))
          (:VAR 0 (:CODE ((0 . :INT) (1 . :INT)) :INT))
          (:VAR 2 (:CODE ((0 . :INT)) :INT)) (:LIT :INT 1))
         (:LIT (:CODE ((0 . :INT)) :INT) (:VAR 0 :INT)))))
      (:APP
       (:OP :TUPLE
        (:TUPLE (:CODE ((0 . :INT) (1 . :INT)) :INT)
         (:CODE ((0 . :INT) (1 . :INT)) :INT)
         (:CODE ((0 :CODE ((0 . :INT)) :INT) (1 :SEQ :INT))
          (:CODE ((0 . :INT)) :INT))))
       (:VAR 1 (:CODE ((0 . :INT) (1 . :INT)) :INT))
       (:VAR 2 (:CODE ((0 . :INT) (1 . :INT)) :INT))
       (:LIT
        (:CODE ((0 :CODE ((0 . :INT)) :INT) (1 :SEQ :INT))
         (:CODE ((0 . :INT)) :INT))
        (:VAR 0 (:CODE ((0 . :INT)) :INT)))))))
   :GUARD (:LIT :BOOL T) :TRIGGER NIL :RESIDUAL NIL :AUXILIARY-CODE NIL :STATUS
   :VALIDATED :CERTIFICATE NIL :BITS 557 :GAIN 0 :WORK 0 :EDGES
   ((:FROM-BATTERY :FUNCTORS)) :METADATA
   (:ORIGIN :BOOTSTRAP-FUNCTOR-TRANSFORMER))
  (:ID :FUNCTOR/MAP-WITNESS-1 :KIND :TRANSFORMER :DOMAIN :INT :INPUTS
   ((0 :CODE ((0 :CODE ((0 . :INT)) :INT) (1 :SEQ :INT))
     (:FN ((:SEQ :INT) (:CODE ((0 . :INT)) :INT)) (:SEQ :INT)))
    (1 :CODE ((0 . :INT) (1 . :INT)) :INT)
    (2 :CODE ((0 . :INT) (1 . :INT)) :INT))
   :TARGET (:CODE ((0 :CODE ((0 . :INT)) :INT) (1 :SEQ :INT)) (:SEQ :INT))
   :EXPRESSION
   (:APP
    (:OP :CODE-APPLY
     (:CODE ((0 :CODE ((0 . :INT)) :INT) (1 :SEQ :INT))
      (:FN ((:SEQ :INT) (:CODE ((0 . :INT)) :INT)) (:SEQ :INT))))
    (:VAR 0
     (:CODE ((0 :CODE ((0 . :INT)) :INT) (1 :SEQ :INT))
      (:FN ((:SEQ :INT) (:CODE ((0 . :INT)) :INT)) (:SEQ :INT))))
    (:APP
     (:OP :TUPLE
      (:TUPLE (:CODE ((0 :CODE ((0 . :INT)) :INT) (1 :SEQ :INT)) (:SEQ :INT))
       (:CODE ((0 :CODE ((0 . :INT)) :INT) (1 :SEQ :INT))
        (:CODE ((0 . :INT)) :INT))))
     (:LIT (:CODE ((0 :CODE ((0 . :INT)) :INT) (1 :SEQ :INT)) (:SEQ :INT))
      (:VAR 1 (:SEQ :INT)))
     (:APP
      (:OP :CODE-SUBST
       (:TUPLE
        (:CODE
         ((0 :CODE ((0 . :INT) (1 . :INT)) :INT)
          (1 :CODE ((0 . :INT) (1 . :INT)) :INT) (2 :CODE ((0 . :INT)) :INT))
         (:CODE ((0 . :INT)) :INT))
        (:TUPLE (:CODE ((0 . :INT) (1 . :INT)) :INT)
         (:CODE ((0 . :INT) (1 . :INT)) :INT)
         (:CODE ((0 :CODE ((0 . :INT)) :INT) (1 :SEQ :INT))
          (:CODE ((0 . :INT)) :INT)))
        (:CODE ((0 :CODE ((0 . :INT)) :INT) (1 :SEQ :INT))
         (:CODE ((0 . :INT)) :INT))))
      (:LIT
       (:CODE
        ((0 :CODE ((0 . :INT) (1 . :INT)) :INT)
         (1 :CODE ((0 . :INT) (1 . :INT)) :INT) (2 :CODE ((0 . :INT)) :INT))
        (:CODE ((0 . :INT)) :INT))
       (:APP
        (:OP :CODE-SUBST
         (:TUPLE (:CODE ((0 . :INT) (1 . :INT)) :INT)
          (:TUPLE (:CODE ((0 . :INT)) :INT) (:CODE ((0 . :INT)) :INT))
          (:CODE ((0 . :INT)) :INT)))
        (:VAR 1 (:CODE ((0 . :INT) (1 . :INT)) :INT))
        (:APP
         (:OP :TUPLE
          (:TUPLE (:CODE ((0 . :INT)) :INT) (:CODE ((0 . :INT)) :INT)))
         (:APP
          (:OP :CODE-BIND
           (:TUPLE (:CODE ((0 . :INT) (1 . :INT)) :INT)
            (:CODE ((0 . :INT)) :INT) (:CODE ((0 . :INT)) :INT)))
          (:VAR 0 (:CODE ((0 . :INT) (1 . :INT)) :INT))
          (:VAR 2 (:CODE ((0 . :INT)) :INT)) (:LIT :INT 0))
         (:LIT (:CODE ((0 . :INT)) :INT) (:VAR 0 :INT)))))
      (:APP
       (:OP :TUPLE
        (:TUPLE (:CODE ((0 . :INT) (1 . :INT)) :INT)
         (:CODE ((0 . :INT) (1 . :INT)) :INT)
         (:CODE ((0 :CODE ((0 . :INT)) :INT) (1 :SEQ :INT))
          (:CODE ((0 . :INT)) :INT))))
       (:VAR 1 (:CODE ((0 . :INT) (1 . :INT)) :INT))
       (:VAR 2 (:CODE ((0 . :INT) (1 . :INT)) :INT))
       (:LIT
        (:CODE ((0 :CODE ((0 . :INT)) :INT) (1 :SEQ :INT))
         (:CODE ((0 . :INT)) :INT))
        (:VAR 0 (:CODE ((0 . :INT)) :INT)))))))
   :GUARD (:LIT :BOOL T) :TRIGGER NIL :RESIDUAL NIL :AUXILIARY-CODE NIL :STATUS
   :VALIDATED :CERTIFICATE NIL :BITS 554 :GAIN 0 :WORK 0 :EDGES
   ((:FROM-BATTERY :FUNCTORS)) :METADATA
   (:ORIGIN :BOOTSTRAP-FUNCTOR-TRANSFORMER))
  (:ID :FUNCTOR/UNARY-MAP-WITNESS :KIND :TRANSFORMER :DOMAIN :INT :INPUTS
   ((0 :CODE ((0 :SEQ :INT))
     (:FN ((:SEQ :INT) (:CODE ((0 . :INT)) :INT)) (:SEQ :INT)))
    (1 :CODE ((0 . :INT)) :INT))
   :TARGET (:CODE ((0 :SEQ :INT)) (:SEQ :INT)) :EXPRESSION
   (:APP
    (:OP :CODE-APPLY
     (:CODE ((0 :SEQ :INT))
      (:FN ((:SEQ :INT) (:CODE ((0 . :INT)) :INT)) (:SEQ :INT))))
    (:VAR 0
     (:CODE ((0 :SEQ :INT))
      (:FN ((:SEQ :INT) (:CODE ((0 . :INT)) :INT)) (:SEQ :INT))))
    (:APP
     (:OP :TUPLE
      (:TUPLE (:CODE ((0 :SEQ :INT)) (:SEQ :INT))
       (:CODE ((0 :SEQ :INT)) (:CODE ((0 . :INT)) :INT))))
     (:LIT (:CODE ((0 :SEQ :INT)) (:SEQ :INT)) (:VAR 0 (:SEQ :INT)))
     (:APP
      (:OP :CODE-SUBST
       (:TUPLE (:CODE ((0 :CODE ((0 . :INT)) :INT)) (:CODE ((0 . :INT)) :INT))
        (:TUPLE (:CODE ((0 . :INT)) :INT))
        (:CODE ((0 :SEQ :INT)) (:CODE ((0 . :INT)) :INT))))
      (:LIT (:CODE ((0 :CODE ((0 . :INT)) :INT)) (:CODE ((0 . :INT)) :INT))
       (:VAR 0 (:CODE ((0 . :INT)) :INT)))
      (:APP (:OP :TUPLE (:TUPLE (:CODE ((0 . :INT)) :INT)))
       (:VAR 1 (:CODE ((0 . :INT)) :INT))))))
   :GUARD (:LIT :BOOL T) :TRIGGER NIL :RESIDUAL NIL :AUXILIARY-CODE NIL :STATUS
   :VALIDATED :CERTIFICATE NIL :BITS 187 :GAIN 0 :WORK 0 :EDGES
   ((:FROM-BATTERY :FUNCTORS)) :METADATA
   (:ORIGIN :BOOTSTRAP-FUNCTOR-TRANSFORMER))
  (:ID :FUNCTOR/POINTWISE-SEQ-WITNESS :KIND :TRANSFORMER :DOMAIN :INT :INPUTS
   ((0 :CODE ((0 . :INT) (1 :SEQ :INT))
     (:FN ((:SEQ :INT) (:CODE ((0 . :INT)) :INT)) (:SEQ :INT)))
    (1 :CODE ((0 . :INT) (1 . :INT)) :INT))
   :TARGET (:CODE ((0 . :INT) (1 :SEQ :INT)) (:SEQ :INT)) :EXPRESSION
   (:APP
    (:OP :CODE-APPLY
     (:CODE ((0 . :INT) (1 :SEQ :INT))
      (:FN ((:SEQ :INT) (:CODE ((0 . :INT)) :INT)) (:SEQ :INT))))
    (:VAR 0
     (:CODE ((0 . :INT) (1 :SEQ :INT))
      (:FN ((:SEQ :INT) (:CODE ((0 . :INT)) :INT)) (:SEQ :INT))))
    (:APP
     (:OP :TUPLE
      (:TUPLE (:CODE ((0 . :INT) (1 :SEQ :INT)) (:SEQ :INT))
       (:CODE ((0 . :INT) (1 :SEQ :INT)) (:CODE ((0 . :INT)) :INT))))
     (:LIT (:CODE ((0 . :INT) (1 :SEQ :INT)) (:SEQ :INT)) (:VAR 1 (:SEQ :INT)))
     (:APP
      (:OP :CODE-SUBST
       (:TUPLE
        (:CODE ((0 :CODE ((0 . :INT) (1 . :INT)) :INT) (1 . :INT))
         (:CODE ((0 . :INT)) :INT))
        (:TUPLE (:CODE ((0 . :INT) (1 . :INT)) :INT)
         (:CODE ((0 . :INT) (1 :SEQ :INT)) :INT))
        (:CODE ((0 . :INT) (1 :SEQ :INT)) (:CODE ((0 . :INT)) :INT))))
      (:LIT
       (:CODE ((0 :CODE ((0 . :INT) (1 . :INT)) :INT) (1 . :INT))
        (:CODE ((0 . :INT)) :INT))
       (:APP
        (:OP :CODE-SUBST
         (:TUPLE (:CODE ((0 . :INT) (1 . :INT)) :INT)
          (:TUPLE (:CODE ((0 . :INT)) :INT) :INT) (:CODE ((0 . :INT)) :INT)))
        (:VAR 0 (:CODE ((0 . :INT) (1 . :INT)) :INT))
        (:APP (:OP :TUPLE (:TUPLE (:CODE ((0 . :INT)) :INT) :INT))
         (:LIT (:CODE ((0 . :INT)) :INT) (:VAR 0 :INT)) (:VAR 1 :INT))))
      (:APP
       (:OP :TUPLE
        (:TUPLE (:CODE ((0 . :INT) (1 . :INT)) :INT)
         (:CODE ((0 . :INT) (1 :SEQ :INT)) :INT)))
       (:APP
        (:OP :CODE-SUBST
         (:TUPLE (:CODE ((0 . :INT) (1 . :INT)) :INT)
          (:TUPLE (:CODE ((0 . :INT) (1 . :INT)) :INT)
           (:CODE ((0 . :INT) (1 . :INT)) :INT))
          (:CODE ((0 . :INT) (1 . :INT)) :INT)))
        (:VAR 1 (:CODE ((0 . :INT) (1 . :INT)) :INT))
        (:APP
         (:OP :TUPLE
          (:TUPLE (:CODE ((0 . :INT) (1 . :INT)) :INT)
           (:CODE ((0 . :INT) (1 . :INT)) :INT)))
         (:LIT (:CODE ((0 . :INT) (1 . :INT)) :INT) (:VAR 1 :INT))
         (:LIT (:CODE ((0 . :INT) (1 . :INT)) :INT) (:VAR 0 :INT))))
       (:LIT (:CODE ((0 . :INT) (1 :SEQ :INT)) :INT) (:VAR 0 :INT))))))
   :GUARD (:LIT :BOOL T) :TRIGGER NIL :RESIDUAL NIL :AUXILIARY-CODE NIL :STATUS
   :VALIDATED :CERTIFICATE NIL :BITS 476 :GAIN 0 :WORK 0 :EDGES
   ((:FROM-BATTERY :FUNCTORS)) :METADATA
   (:ORIGIN :BOOTSTRAP-FUNCTOR-TRANSFORMER))
  (:ID :FUNCTOR/POINTWISE-PARAM-WITNESS :KIND :TRANSFORMER :DOMAIN :INT :INPUTS
   ((0 :CODE ((0 . :INT) (1 . :INT)) :INT)) :TARGET
   (:CODE ((0 :SEQ :INT) (1 :SEQ :INT)) :INT) :EXPRESSION
   (:APP
    (:OP :CODE-SUBST
     (:TUPLE (:CODE ((0 . :INT) (1 . :INT)) :INT)
      (:TUPLE (:CODE ((0 :SEQ :INT) (1 :SEQ :INT)) :INT)
       (:CODE ((0 :SEQ :INT) (1 :SEQ :INT)) :INT))
      (:CODE ((0 :SEQ :INT) (1 :SEQ :INT)) :INT)))
    (:VAR 0 (:CODE ((0 . :INT) (1 . :INT)) :INT))
    (:APP
     (:OP :TUPLE
      (:TUPLE (:CODE ((0 :SEQ :INT) (1 :SEQ :INT)) :INT)
       (:CODE ((0 :SEQ :INT) (1 :SEQ :INT)) :INT)))
     (:LIT (:CODE ((0 :SEQ :INT) (1 :SEQ :INT)) :INT)
      (:APP (:OP :AT (:SEQ :INT)) (:VAR 0 (:SEQ :INT)) (:LIT :INT 0)))
     (:LIT (:CODE ((0 :SEQ :INT) (1 :SEQ :INT)) :INT)
      (:APP (:OP :AT (:SEQ :INT)) (:VAR 1 (:SEQ :INT)) (:LIT :INT 0)))))
   :GUARD (:LIT :BOOL T) :TRIGGER NIL :RESIDUAL NIL :AUXILIARY-CODE NIL :STATUS
   :EMPIRICAL :CERTIFICATE NIL :BITS 189 :GAIN 0 :WORK 50000 :EDGES
   ((:FROM-BATTERY :FUNCTORS)) :METADATA
   (:ORIGIN :SYNTHESIZED :TRAINING-ROWS 1))
  (:ID :FUNCTOR/POINTWISE-PARAM-GUARD :KIND :TRANSFORMER :DOMAIN :INT :INPUTS
   ((0 :CODE ((0 . :INT) (1 . :INT)) :BOOL)) :TARGET
   (:CODE ((0 :SEQ :INT) (1 :SEQ :INT)) :BOOL) :EXPRESSION
   (:APP
    (:OP :CODE-SUBST
     (:TUPLE (:CODE ((0 :SEQ :INT) (1 :SEQ :INT) (2 . :BOOL)) :BOOL)
      (:TUPLE (:CODE ((0 :SEQ :INT) (1 :SEQ :INT)) (:SEQ :INT))
       (:CODE ((0 :SEQ :INT) (1 :SEQ :INT)) (:SEQ :INT))
       (:CODE ((0 :SEQ :INT) (1 :SEQ :INT)) :BOOL))
      (:CODE ((0 :SEQ :INT) (1 :SEQ :INT)) :BOOL)))
    (:LIT (:CODE ((0 :SEQ :INT) (1 :SEQ :INT) (2 . :BOOL)) :BOOL)
     (:APP (:OP :IF :BOOL)
      (:APP (:OP :< :INT) (:LIT :INT 0)
       (:APP (:OP :LENGTH :INT) (:VAR 0 (:SEQ :INT))))
      (:APP (:OP :IF :BOOL)
       (:APP (:OP := :INT) (:APP (:OP :LENGTH :INT) (:VAR 0 (:SEQ :INT)))
        (:APP (:OP :LENGTH :INT) (:VAR 1 (:SEQ :INT))))
       (:VAR 2 :BOOL) (:LIT :BOOL NIL))
      (:LIT :BOOL NIL)))
    (:APP
     (:OP :TUPLE
      (:TUPLE (:CODE ((0 :SEQ :INT) (1 :SEQ :INT)) (:SEQ :INT))
       (:CODE ((0 :SEQ :INT) (1 :SEQ :INT)) (:SEQ :INT))
       (:CODE ((0 :SEQ :INT) (1 :SEQ :INT)) :BOOL)))
     (:LIT (:CODE ((0 :SEQ :INT) (1 :SEQ :INT)) (:SEQ :INT))
      (:VAR 0 (:SEQ :INT)))
     (:LIT (:CODE ((0 :SEQ :INT) (1 :SEQ :INT)) (:SEQ :INT))
      (:VAR 1 (:SEQ :INT)))
     (:APP
      (:OP :CODE-SUBST
       (:TUPLE (:CODE ((0 . :INT) (1 . :INT)) :BOOL)
        (:TUPLE (:CODE ((0 :SEQ :INT) (1 :SEQ :INT)) :INT)
         (:CODE ((0 :SEQ :INT) (1 :SEQ :INT)) :INT))
        (:CODE ((0 :SEQ :INT) (1 :SEQ :INT)) :BOOL)))
      (:VAR 0 (:CODE ((0 . :INT) (1 . :INT)) :BOOL))
      (:APP
       (:OP :TUPLE
        (:TUPLE (:CODE ((0 :SEQ :INT) (1 :SEQ :INT)) :INT)
         (:CODE ((0 :SEQ :INT) (1 :SEQ :INT)) :INT)))
       (:LIT (:CODE ((0 :SEQ :INT) (1 :SEQ :INT)) :INT)
        (:APP (:OP :AT (:SEQ :INT)) (:VAR 0 (:SEQ :INT)) (:LIT :INT 0)))
       (:LIT (:CODE ((0 :SEQ :INT) (1 :SEQ :INT)) :INT)
        (:APP (:OP :AT (:SEQ :INT)) (:VAR 1 (:SEQ :INT)) (:LIT :INT 0)))))))
   :GUARD (:LIT :BOOL T) :TRIGGER NIL :RESIDUAL NIL :AUXILIARY-CODE NIL :STATUS
   :VALIDATED :CERTIFICATE NIL :BITS 498 :GAIN 0 :WORK 0 :EDGES
   ((:FROM-BATTERY :FUNCTORS)) :METADATA
   (:ORIGIN :BOOTSTRAP-FUNCTOR-TRANSFORMER))
  (:ID :SPEC/FUNCTOR/MAP-INVERSE-0 :KIND :SPEC :DOMAIN :INT :INPUTS
   ((0 :CODE ((0 . :INT) (1 . :INT)) :INT)
    (1 :CODE ((0 . :INT) (1 . :INT)) :INT))
   :TARGET (:CODE ((0 :CODE ((0 . :INT)) :INT)) (:CODE ((0 . :INT)) :INT))
   :EXPRESSION NIL :GUARD (:LIT :BOOL T) :TRIGGER NIL :RESIDUAL
   (:DATA
    ((((:LIT (:CODE ((0 . :INT) (1 . :INT)) :INT)
        (:APP (:OP :+ :INT) (:VAR 0 :INT) (:VAR 1 :INT)))
       (:LIT (:CODE ((0 . :INT) (1 . :INT)) :INT)
        (:APP (:OP :- :INT) (:VAR 1 :INT) (:VAR 0 :INT))))
      (:LIT (:CODE ((0 :CODE ((0 . :INT)) :INT)) (:CODE ((0 . :INT)) :INT))
       (:APP
        (:OP :CODE-SUBST
         (:TUPLE (:CODE ((0 . :INT) (1 . :INT)) :INT)
          (:TUPLE (:CODE ((0 . :INT)) :INT) (:CODE ((0 . :INT)) :INT))
          (:CODE ((0 . :INT)) :INT)))
        (:LIT (:CODE ((0 . :INT) (1 . :INT)) :INT)
         (:APP (:OP :- :INT) (:VAR 1 :INT) (:VAR 0 :INT)))
        (:APP
         (:OP :TUPLE
          (:TUPLE (:CODE ((0 . :INT)) :INT) (:CODE ((0 . :INT)) :INT)))
         (:APP
          (:OP :CODE-BIND
           (:TUPLE (:CODE ((0 . :INT) (1 . :INT)) :INT)
            (:CODE ((0 . :INT)) :INT) (:CODE ((0 . :INT)) :INT)))
          (:LIT (:CODE ((0 . :INT) (1 . :INT)) :INT)
           (:APP (:OP :+ :INT) (:VAR 0 :INT) (:VAR 1 :INT)))
          (:VAR 0 (:CODE ((0 . :INT)) :INT)) (:LIT :INT 1))
         (:LIT (:CODE ((0 . :INT)) :INT) (:VAR 0 :INT))))))))
   :AUXILIARY-CODE NIL :STATUS :VALIDATED :CERTIFICATE NIL :BITS 0 :GAIN 0
   :WORK 0 :EDGES ((:SPECIFIES :FUNCTOR/MAP-INVERSE-0)) :METADATA
   (:TARGET-KIND :TRANSFORMER))
  (:ID :SPEC/FUNCTOR/MAP-GUARD-0 :KIND :SPEC :DOMAIN :INT :INPUTS
   ((0 :CODE ((0 . :INT) (1 . :INT)) :INT)
    (1 :CODE ((0 . :INT) (1 . :INT)) :INT))
   :TARGET (:CODE ((0 :CODE ((0 . :INT)) :INT) (1 :SEQ :INT)) :BOOL)
   :EXPRESSION NIL :GUARD (:LIT :BOOL T) :TRIGGER NIL :RESIDUAL
   (:DATA
    ((((:LIT (:CODE ((0 . :INT) (1 . :INT)) :INT)
        (:APP (:OP :+ :INT) (:VAR 0 :INT) (:VAR 1 :INT)))
       (:LIT (:CODE ((0 . :INT) (1 . :INT)) :INT)
        (:APP (:OP :- :INT) (:VAR 1 :INT) (:VAR 0 :INT))))
      (:LIT (:CODE ((0 :CODE ((0 . :INT)) :INT) (1 :SEQ :INT)) :BOOL)
       (:APP (:OP :IF :BOOL)
        (:APP
         (:OP :CODE-MATCH
          (:TUPLE (:CODE ((0 . :INT) (1 . :INT)) :INT)
           (:CODE ((0 . :INT)) :INT)))
         (:LIT (:CODE ((0 . :INT) (1 . :INT)) :INT)
          (:APP (:OP :+ :INT) (:VAR 0 :INT) (:VAR 1 :INT)))
         (:VAR 0 (:CODE ((0 . :INT)) :INT)))
        (:APP (:OP :IF :BOOL)
         (:APP (:OP := (:CODE ((0 . :INT)) :INT))
          (:APP
           (:OP :CODE-BIND
            (:TUPLE (:CODE ((0 . :INT) (1 . :INT)) :INT)
             (:CODE ((0 . :INT)) :INT) (:CODE ((0 . :INT)) :INT)))
           (:LIT (:CODE ((0 . :INT) (1 . :INT)) :INT)
            (:APP (:OP :+ :INT) (:VAR 0 :INT) (:VAR 1 :INT)))
           (:VAR 0 (:CODE ((0 . :INT)) :INT)) (:LIT :INT 0))
          (:LIT (:CODE ((0 . :INT)) :INT) (:VAR 0 :INT)))
         (:APP (:OP :IF :BOOL)
          (:APP (:OP := :INT)
           (:APP (:OP :CODE-KIND (:CODE ((0 . :INT)) :INT))
            (:APP
             (:OP :CODE-BIND
              (:TUPLE (:CODE ((0 . :INT) (1 . :INT)) :INT)
               (:CODE ((0 . :INT)) :INT) (:CODE ((0 . :INT)) :INT)))
             (:LIT (:CODE ((0 . :INT) (1 . :INT)) :INT)
              (:APP (:OP :+ :INT) (:VAR 0 :INT) (:VAR 1 :INT)))
             (:VAR 0 (:CODE ((0 . :INT)) :INT)) (:LIT :INT 1)))
           (:LIT :INT 1))
          (:APP (:OP :CODE-TOTAL (:CODE ((0 . :INT)) :INT))
           (:APP
            (:OP :CODE-SUBST
             (:TUPLE (:CODE ((0 . :INT) (1 . :INT)) :INT)
              (:TUPLE (:CODE ((0 . :INT)) :INT) (:CODE ((0 . :INT)) :INT))
              (:CODE ((0 . :INT)) :INT)))
            (:LIT (:CODE ((0 . :INT) (1 . :INT)) :INT)
             (:APP (:OP :- :INT) (:VAR 1 :INT) (:VAR 0 :INT)))
            (:APP
             (:OP :TUPLE
              (:TUPLE (:CODE ((0 . :INT)) :INT) (:CODE ((0 . :INT)) :INT)))
             (:APP
              (:OP :CODE-BIND
               (:TUPLE (:CODE ((0 . :INT) (1 . :INT)) :INT)
                (:CODE ((0 . :INT)) :INT) (:CODE ((0 . :INT)) :INT)))
              (:LIT (:CODE ((0 . :INT) (1 . :INT)) :INT)
               (:APP (:OP :+ :INT) (:VAR 0 :INT) (:VAR 1 :INT)))
              (:VAR 0 (:CODE ((0 . :INT)) :INT)) (:LIT :INT 1))
             (:LIT (:CODE ((0 . :INT)) :INT) (:VAR 0 :INT)))))
          (:LIT :BOOL NIL))
         (:LIT :BOOL NIL))
        (:LIT :BOOL NIL))))))
   :AUXILIARY-CODE NIL :STATUS :VALIDATED :CERTIFICATE NIL :BITS 0 :GAIN 0
   :WORK 0 :EDGES ((:SPECIFIES :FUNCTOR/MAP-GUARD-0)) :METADATA
   (:TARGET-KIND :TRANSFORMER))
  (:ID :SPEC/FUNCTOR/MAP-INVERSE-1 :KIND :SPEC :DOMAIN :INT :INPUTS
   ((0 :CODE ((0 . :INT) (1 . :INT)) :INT)
    (1 :CODE ((0 . :INT) (1 . :INT)) :INT))
   :TARGET (:CODE ((0 :CODE ((0 . :INT)) :INT)) (:CODE ((0 . :INT)) :INT))
   :EXPRESSION NIL :GUARD (:LIT :BOOL T) :TRIGGER NIL :RESIDUAL
   (:DATA
    ((((:LIT (:CODE ((0 . :INT) (1 . :INT)) :INT)
        (:APP (:OP :+ :INT) (:VAR 0 :INT) (:VAR 1 :INT)))
       (:LIT (:CODE ((0 . :INT) (1 . :INT)) :INT)
        (:APP (:OP :- :INT) (:VAR 1 :INT) (:VAR 0 :INT))))
      (:LIT (:CODE ((0 :CODE ((0 . :INT)) :INT)) (:CODE ((0 . :INT)) :INT))
       (:APP
        (:OP :CODE-SUBST
         (:TUPLE (:CODE ((0 . :INT) (1 . :INT)) :INT)
          (:TUPLE (:CODE ((0 . :INT)) :INT) (:CODE ((0 . :INT)) :INT))
          (:CODE ((0 . :INT)) :INT)))
        (:LIT (:CODE ((0 . :INT) (1 . :INT)) :INT)
         (:APP (:OP :- :INT) (:VAR 1 :INT) (:VAR 0 :INT)))
        (:APP
         (:OP :TUPLE
          (:TUPLE (:CODE ((0 . :INT)) :INT) (:CODE ((0 . :INT)) :INT)))
         (:APP
          (:OP :CODE-BIND
           (:TUPLE (:CODE ((0 . :INT) (1 . :INT)) :INT)
            (:CODE ((0 . :INT)) :INT) (:CODE ((0 . :INT)) :INT)))
          (:LIT (:CODE ((0 . :INT) (1 . :INT)) :INT)
           (:APP (:OP :+ :INT) (:VAR 0 :INT) (:VAR 1 :INT)))
          (:VAR 0 (:CODE ((0 . :INT)) :INT)) (:LIT :INT 0))
         (:LIT (:CODE ((0 . :INT)) :INT) (:VAR 0 :INT))))))))
   :AUXILIARY-CODE NIL :STATUS :VALIDATED :CERTIFICATE NIL :BITS 0 :GAIN 0
   :WORK 0 :EDGES ((:SPECIFIES :FUNCTOR/MAP-INVERSE-1)) :METADATA
   (:TARGET-KIND :TRANSFORMER))
  (:ID :SPEC/FUNCTOR/MAP-GUARD-1 :KIND :SPEC :DOMAIN :INT :INPUTS
   ((0 :CODE ((0 . :INT) (1 . :INT)) :INT)
    (1 :CODE ((0 . :INT) (1 . :INT)) :INT))
   :TARGET (:CODE ((0 :CODE ((0 . :INT)) :INT) (1 :SEQ :INT)) :BOOL)
   :EXPRESSION NIL :GUARD (:LIT :BOOL T) :TRIGGER NIL :RESIDUAL
   (:DATA
    ((((:LIT (:CODE ((0 . :INT) (1 . :INT)) :INT)
        (:APP (:OP :+ :INT) (:VAR 0 :INT) (:VAR 1 :INT)))
       (:LIT (:CODE ((0 . :INT) (1 . :INT)) :INT)
        (:APP (:OP :- :INT) (:VAR 1 :INT) (:VAR 0 :INT))))
      (:LIT (:CODE ((0 :CODE ((0 . :INT)) :INT) (1 :SEQ :INT)) :BOOL)
       (:APP (:OP :IF :BOOL)
        (:APP
         (:OP :CODE-MATCH
          (:TUPLE (:CODE ((0 . :INT) (1 . :INT)) :INT)
           (:CODE ((0 . :INT)) :INT)))
         (:LIT (:CODE ((0 . :INT) (1 . :INT)) :INT)
          (:APP (:OP :+ :INT) (:VAR 0 :INT) (:VAR 1 :INT)))
         (:VAR 0 (:CODE ((0 . :INT)) :INT)))
        (:APP (:OP :IF :BOOL)
         (:APP (:OP := (:CODE ((0 . :INT)) :INT))
          (:APP
           (:OP :CODE-BIND
            (:TUPLE (:CODE ((0 . :INT) (1 . :INT)) :INT)
             (:CODE ((0 . :INT)) :INT) (:CODE ((0 . :INT)) :INT)))
           (:LIT (:CODE ((0 . :INT) (1 . :INT)) :INT)
            (:APP (:OP :+ :INT) (:VAR 0 :INT) (:VAR 1 :INT)))
           (:VAR 0 (:CODE ((0 . :INT)) :INT)) (:LIT :INT 1))
          (:LIT (:CODE ((0 . :INT)) :INT) (:VAR 0 :INT)))
         (:APP (:OP :IF :BOOL)
          (:APP (:OP := :INT)
           (:APP (:OP :CODE-KIND (:CODE ((0 . :INT)) :INT))
            (:APP
             (:OP :CODE-BIND
              (:TUPLE (:CODE ((0 . :INT) (1 . :INT)) :INT)
               (:CODE ((0 . :INT)) :INT) (:CODE ((0 . :INT)) :INT)))
             (:LIT (:CODE ((0 . :INT) (1 . :INT)) :INT)
              (:APP (:OP :+ :INT) (:VAR 0 :INT) (:VAR 1 :INT)))
             (:VAR 0 (:CODE ((0 . :INT)) :INT)) (:LIT :INT 0)))
           (:LIT :INT 1))
          (:APP (:OP :CODE-TOTAL (:CODE ((0 . :INT)) :INT))
           (:APP
            (:OP :CODE-SUBST
             (:TUPLE (:CODE ((0 . :INT) (1 . :INT)) :INT)
              (:TUPLE (:CODE ((0 . :INT)) :INT) (:CODE ((0 . :INT)) :INT))
              (:CODE ((0 . :INT)) :INT)))
            (:LIT (:CODE ((0 . :INT) (1 . :INT)) :INT)
             (:APP (:OP :- :INT) (:VAR 1 :INT) (:VAR 0 :INT)))
            (:APP
             (:OP :TUPLE
              (:TUPLE (:CODE ((0 . :INT)) :INT) (:CODE ((0 . :INT)) :INT)))
             (:APP
              (:OP :CODE-BIND
               (:TUPLE (:CODE ((0 . :INT) (1 . :INT)) :INT)
                (:CODE ((0 . :INT)) :INT) (:CODE ((0 . :INT)) :INT)))
              (:LIT (:CODE ((0 . :INT) (1 . :INT)) :INT)
               (:APP (:OP :+ :INT) (:VAR 0 :INT) (:VAR 1 :INT)))
              (:VAR 0 (:CODE ((0 . :INT)) :INT)) (:LIT :INT 0))
             (:LIT (:CODE ((0 . :INT)) :INT) (:VAR 0 :INT)))))
          (:LIT :BOOL NIL))
         (:LIT :BOOL NIL))
        (:LIT :BOOL NIL))))))
   :AUXILIARY-CODE NIL :STATUS :VALIDATED :CERTIFICATE NIL :BITS 0 :GAIN 0
   :WORK 0 :EDGES ((:SPECIFIES :FUNCTOR/MAP-GUARD-1)) :METADATA
   (:TARGET-KIND :TRANSFORMER))
  (:ID :SPEC/FUNCTOR/POINTWISE-PARAM-WITNESS :KIND :SPEC :DOMAIN :INT :INPUTS
   ((0 :CODE ((0 . :INT) (1 . :INT)) :INT)) :TARGET
   (:CODE ((0 :SEQ :INT) (1 :SEQ :INT)) :INT) :EXPRESSION NIL :GUARD
   (:LIT :BOOL T) :TRIGGER NIL :RESIDUAL
   (:DATA
    ((((:LIT (:CODE ((0 . :INT) (1 . :INT)) :INT)
        (:APP (:OP :- :INT) (:VAR 1 :INT) (:VAR 0 :INT))))
      (:LIT (:CODE ((0 :SEQ :INT) (1 :SEQ :INT)) :INT)
       (:APP (:OP :- :INT)
        (:APP (:OP :AT (:SEQ :INT)) (:VAR 1 (:SEQ :INT)) (:LIT :INT 0))
        (:APP (:OP :AT (:SEQ :INT)) (:VAR 0 (:SEQ :INT)) (:LIT :INT 0)))))))
   :AUXILIARY-CODE NIL :STATUS :VALIDATED :CERTIFICATE NIL :BITS 0 :GAIN 0
   :WORK 0 :EDGES ((:SPECIFIES :FUNCTOR/POINTWISE-PARAM-WITNESS)) :METADATA
   (:TARGET-KIND :TRANSFORMER))
  (:ID :SPEC/FUNCTOR/POINTWISE-PARAM-GUARD :KIND :SPEC :DOMAIN :INT :INPUTS
   ((0 :CODE ((0 . :INT) (1 . :INT)) :BOOL)) :TARGET
   (:CODE ((0 :SEQ :INT) (1 :SEQ :INT)) :BOOL) :EXPRESSION NIL :GUARD
   (:LIT :BOOL T) :TRIGGER NIL :RESIDUAL
   (:DATA
    ((((:LIT (:CODE ((0 . :INT) (1 . :INT)) :BOOL)
        (:APP (:OP :IF :BOOL) (:APP (:OP := :INT) (:VAR 0 :INT) (:LIT :INT 0))
         (:LIT :BOOL NIL) (:LIT :BOOL T))))
      (:LIT (:CODE ((0 :SEQ :INT) (1 :SEQ :INT)) :BOOL)
       (:APP (:OP :IF :BOOL)
        (:APP (:OP :< :INT) (:LIT :INT 0)
         (:APP (:OP :LENGTH :INT) (:VAR 0 (:SEQ :INT))))
        (:APP (:OP :IF :BOOL)
         (:APP (:OP := :INT) (:APP (:OP :LENGTH :INT) (:VAR 0 (:SEQ :INT)))
          (:APP (:OP :LENGTH :INT) (:VAR 1 (:SEQ :INT))))
         (:APP (:OP :IF :BOOL)
          (:APP (:OP := :INT)
           (:APP (:OP :AT (:SEQ :INT)) (:VAR 0 (:SEQ :INT)) (:LIT :INT 0))
           (:LIT :INT 0))
          (:LIT :BOOL NIL) (:LIT :BOOL T))
         (:LIT :BOOL NIL))
        (:LIT :BOOL NIL))))))
   :AUXILIARY-CODE NIL :STATUS :VALIDATED :CERTIFICATE NIL :BITS 0 :GAIN 0
   :WORK 0 :EDGES ((:SPECIFIES :FUNCTOR/POINTWISE-PARAM-GUARD)) :METADATA
   (:TARGET-KIND :TRANSFORMER))))
