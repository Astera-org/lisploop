
# prompt
Updated Monday 26 October 2026

The goal of this research is to make a recursive program synthesis system. 
This system takes output or input-output data, tagged by time and/or space, and iteratively and recursively derives a program, run on a fixed simulator with a growing library, which generates the data.   In the case of input-output data, this means generates the output data from the input data. 
The objective of the program synthesizer is thus to find a representation or compression of the data which minimizes the overall description length as well as metrics for computational cost, including the cost to search for the compression. The pricing mechanism for this will be a mix of fixed costs, information-theoretic estimates, and (of course, given the recursive nature) computed, bootstrapped metrics.    
The research is motivated by N pillars: 
1. **Search**.  Search over computation is fundamentally unavoidable: the *a priori* shortest way to predict the **exact** effects of a computation is simply to do it.  Hence the simulator / computation engine + the supplied data are the ultimate sources of truth. 
  a. Execution, conditional input values and state, is similarly the ultimate source of equivalence: a given (set of) outputs is equivalent to a program executed via a simulator on the inputs (e.g.). 
    1. Trick is to look for shortcuts! 
2. **Learned equivalence.** That said, it is possible to re-represent computations into different forms.  
  a. For example, it is strategic to look for conserved quantities by taking the observed data and treating it as input to a computation. 
    1. This constitutes inference of symmetry - equivalence under action.  
  b. Likewise inverting causality can propagate information from an observed output back to an input. 
    1. Learning the rules of this over a library + simulator is inspired by the work of [[FlashFill]] and FlashMeta, 
      a. Though here we will **learn** the propagation rules. 
    2. This is a more general form of backpropagation, adapted to discrete structures. 
  c. Exact computation can be approximated and shorted (in time and space) by heuristics.  
    1. This entails the emission of residuals from a given computation. 
      a. Which may or may not be used. 
    2. Heuristics are particularly useful in search with real-world data, which has finite Markov blankets hence finite dependencies / mixing.  
3. **Laws.** Conserved quantities can be learned aspects of the simulator (+library) itself
  a. Like commutativity laws - these can reduce search & representation space by proving equivalence.
    1. Particularly relevant with babble library learning <http://arxiv.org/abs/2212.04596>
  b. Laws can be synthesized from ongoing interaction with the simulator.
4. **Algebra.** Other learned rules take the form of algebras - 
  a. rules for exactly & symbolically converting inputs to outputs
  b. Aka 'solve rules' for exactly propagating information through a computational graph, per 2.b.1
5. **Lifting.** Computational compression requires re-use of programmatic structures:
  a. Library calls, loops, recursion, 
    1. Often with guards / conditions. 
  b. This means a topological projection or loss-of-information during computation, e.g. the loop index or function calling context
    1. Such variables are stored on the stack in typical environments.  In general they may be only weakly observed.
    2. Inference of them may be through sorting, hard EM, propagation, or at the limit (again) search. 
      a. See the Sudoku experiment, where EM was used to infer what class a mutex belonged to. 
  c. Hence a pillar is to "unproject" or lift data with induced or introduced context, thereby forming fibers through which attribution can be traced. 
6. **Abstraction.** A critical starting point for lifting is to move from base values to variables which can be substituted. 
  a. This is anti-unification, which forms the key method for variable introduction. 
  b. Anti-unification, like everything else here, is contextual, and depends on a frame or reference: *what* expressions are anti-unified into a LGG.
    1. The cost structure remains the same: description length (DL). 
7. **Partitioning & Locality**.  In many cases, there are an unlimited number of ways of deciding what expressions to anti-unify, segment and co-lift, or build a library from, or look to unify through a conserved executable description.
  a. Human search proceeds with some intrinsic metric of locality: data that is close in time or space, or close in a constructed / learned space. 
    1. Spaces can extend to even abstract concepts, like 'colonies' or 'mountain passes', wherein similarity and hence locality is purely computational. 
  b. Locality serves to bias any breadth-first search to neighborhoods, and is reflective of the dependency structure of the real world: things generally don't depend on variables that are distant.  Segmentation often tries to be a max-cut. 
    1. In terms of the example above, abstract locality helps to transform computable attributes, like arithmetic in a constructed space. 
  c. Locality can of course be bootstrapped: items that have a certificate for being co-local (beyond supplied data: from search, comparison, or computational validation) can have induced locality -- which, in turn, can be amortized / synthesized / explained through a subsequent synthesis step. 
    1. Or, vice-versa, locality can be imposed (via selection and sorting), and equivalence checked. 
  d. Partitioning hence can be through basic equality (same types and/or values for each expression), **or** through ordering; either can be supplied or computed.
    1. Factoring is another related matter, as happens with library learning over one graph.  
    2. Here similarity is typically exact and structural, though human cognition also softly treats these as invented & analogical spaces. 
  e. Partitions form frames for recursive program synthesis. 
    1. They are hence a straightforward form of conditional-driven lifting. 
    2. Aside: deep learning does this in pre- and statically- allocated high-dimensional space; critical here is that space is allocated on the stack, in the search tree. 
  f. Partitioning is a hard form of ordering, effectively selection with ha Heaviside function or Dirac delta; application relies on the compressed form of the subsequent frame for computational generalization. 
    1. Basically saying 'these are the same, and everything else is different'. 
  g. A **relaxed** form of partitioning involves ordering and sorting, and learned metrics: 
    1. Each which says, effectively, 'these are this-much similar, and other things are that-much dissimilar'. 
    2. Metrics allow for sample-based approximation and generalization, as is common in machine learning (and learning or approximation in general!)
    3. They enable a related form of conservation, beyond equivalence: change is bounded for a map y = f(x) in both x and y
      a. This means both input and output need a geometry
      b. Geometry is not essential for this proposal, except ... 
  h. Below, when deriving heuristics, we have to accomidate lossy and imperfect compressions and approximations, hence need a way of ranking them. 
    1. Much of perception is seeking entities, attributes, and functions that are conserved through time or space.  Heuristics couple tightly to this, as they approximate data where the residual (and hence the residual) is measured with a learned or ambient metric.  This metric (or metrics) enables judging whether a given computational or DL compression fits supplied data. 
    2. Heuristics can also be "anytime" algorithms - more compute yields greater accuracy. This extends to e.g. decsion trees 
      a. But this does not need we need a decision tree datastructure in the kernel!  Should be subsumed by other primitives. 
8. **Recursion**. The program synthesis problem is recursive in several distinct ways: 
  a. Synthesis can proceed in stages: you solve a problem, which emits new frames, residuals, or fiber indexes that need to be predicted; these serve as recursive target for another round of synthesis. 
    1. Sometimes early or first stages yield no compression, e.g. basis expansion to make a problem linear, so the full DL cost must be measured by the *full* path.  
  b. The search procedure itself is a program which emits an oft-repetitive computational graph. 
    1. Synthesis can proceed on the search tree and execution graph itself to derive messages about inaccessible regions of solution space. 
      a. For example, when solving a hard Sudoku, following a strategic guess it's common to encounter chains of implication that indicate there are no possible solutions along that path.
      b. In SAT solving, these take the form of CDCL clauses, unique implication points, or dual implication points; the latter permits the introduction of new variables.  We aim to analogously replicate these powerful methods here. 
    2. The messages, in the form of expressions, strongly partition a given search problem -- even if they are not general to *all* problems, so only hold in the context of one problem. 
      a. Messages, like again everything else here, can be target for anti-unification / generalization / library learning, which lifts them out of the local problem context to be general for all problems - eg creation of a new (partial) conservation.   
      b. This is how CDCL and UIP / DIP was invented, afterall! 
    3. Other messages can simply be lossy condensations of the computation performed in a search branch, approximate expressions of "why this worked or didn't"
      a. Aka heuristics.   The residuals they emit are discarded. 
      b. Which is why the computational cost is essential. 
  c. Recursion through library learning + local messages serves to partition exponential to super-exponential search space such that it's tractable in linear time - which is all we get in the real world. 
9. **Vocabulary and language**. The combination of locality, analogy, and heuristic compression motivates the final element of the proposal: that of vocabulary and language development. 
  a. Viz: the names of functions are short, easy-to decode, heuristic / approximate descriptions of what the functions do. Without them, libraries and code are un-navigable.  
  b. Language is compositional, which means that the decoder needs to execute some variable time/space computation
    1. But: it is not infinitely compositional like actual computer code, so that a fixed allocation of time or space is sufficient (like in a transformer). 
  c. This is a last goal/pillar of the research; like many of the preceding goals, it may be updated as the research is fleshed out. 

  
Original motivating sketch outline: 

- Start with Domains and types (sets, named sets)
  - Numbers
  - Operators
    - Including inequalities
- Expressions
- Ability to execute those expressions
  - Over the domains 
  - Over the expressions
  - (Which my yield errors)
- Execution implies equivalence; 
  - an expression is equivalent to its input-output mapping, conditional domain & co-domain. 
  - Input yields output; if the language is purely functional, this is all you need to know. 
  - Information is "created" or "destroyed" by computation
    - This information (e.g. MI) has to be simply measured, with a fixed ambient space / correspondence. 
      - Computation is not allowed here. 
  - Topologically, computation may be seen as a projection, 
    - In which case the reverse process requires a lift. 
  - [This understanding is consistent with the relation between work and entropy, e.g. <https://en.wikipedia.org/wiki/Jarzynski_equality%20]>
- Execution here is on a simulator
  - the lisp machine
  - but, in general, it may be external: the real world. 
    - Which has state and is very much not functional. 
- Equivalence in an ambient domain enables compression
  - a shorter description of the data, the computation, 
    - or the series of computations that lead to a computation. 
- Perfect equivalences are important,
  - And need to be remembered, symbolically
  - Yet they are also rare in the real world: 
- Most equivalences are approximate or partial,
  - And so require residuals. 
  - The previous proposal indicates that these constitute the fibers of a projection (\*\*)
  - These fibers permit information flow to a lifted space. 
  - Some residuals cannot be a priori ordered (form a set), or cannot be otherwise observed,
    - Which means that they must be inferred. 
    - EM served as this inference engine in the Sudoku rule-learning experiment: 
      - Which class a given mutex belongs to is an unobserved variable (2 bits, in the end). 
    - This can be as large of a problem as the program synthesis task
      - And so needs quotienting, partitioning, and computational description just like PS.  
- Approximate equivalences ~= heuristics,
  - Which can be thought of as loose, lossy approximations to data. 
  - They are essential in bootstrapping combinatorial search
    - provided the heuristic is easier to evaluate and infer than running many branches of a search tree. 
  - In this case, the residuals are immaterial; the full branching search needs to recreate state, as the approximations only guide decisions.  
- Otherwise, residuals can then be a target for subsequent compression/modelling. 
  - This equates to computed lifting, or computed addressing. (\*\*)
- Equivalence under an action are symmetries, 
  - Which are vital for describing and partitioning space, 
    - especially the search space in program synthesis. 
- Equivalence finding terminates at execution, 
  - yet from this you can learn algebras, or ways of manipulating expressions while maintaining equivalence
  - as well as solve rules
  - Both are essential for exploring and filling in the graph of an unknown computation (= program synthesis). 
- Algebras, for example, allow for transformation of LHS of expressions to RHS and vice-versa
  - This enables exact conversion from inferred conserved quantities to generative expressions, 
    - via the exchange of input and outputs. 
- Likewise, solve rules work on both expressions and base values (e.g. integers) to propagate information from output to input.
  - Input to output is trivial with the simulator. 
  - Input and output to expression is the recursive program synthesis problem. 
- The goal and final metric in all of this is description length (DL). 
- As mentioned, equivalences in a prescribed space enable this. 
  - The question is what to quotient - where to look for constants (and-or orderings? (\*\*)) - then becomes open-ended 
  - Anti-unification (AU) is a symbolic means of quotienting, 
    - One that allows for the introduction of new variables = abstractions. 
    - It can be validated against the simulator (purely symbolic expressions) or ground truth data. 
  - But it is not the only means, 
    - Though initially should be the primary means of introducing abstractions.  (Unless literature suggests otherwise (\*\*))
      - Beta-expansion is another, but imho only supported where there is evidence; thence ~= AU. 
- This suggests that all data / experience should be in one 'flat' store. 
  - A list.  In lisp.  
  - It can be ordered by time (ordered execution), 
  - but the algorithm should be largely invariant to this. 
- The quotienting - AU algorithm goes over this list, 
  - Trying to find constants in the tree-structured entries, *conditioned* on other elements. 
    - One quotient is meaningless without a connection to another
      - Just like in AU. 
    - If the condition is an action, then the quotienting is a form of symmetry finding. 
  - Trees can be e.g. expressions, lists of inputs, list of outputs
  - They all have a type, which can be a compositional object too ('int' 'input'). 
  - As in the first version of this proposal, one type may be time-space
    - Attributes that make locality meaningful, and reduce the span of BFS / help DFS.
- This makes the quotienting-AU problem that of a structure & type-aware & locality-seeded subgraph isomorphism problem. 
  - For which there appear to be good algorithms, 
    - Or at least, good precedence for a working algorithm here. 
    - The quotienting / AU problem is not *actually* graph isomorphism, just saying that we may be able to extract lessons from this literature. 
- This is NP-hard, think, and yet some of the search can be amortized
  - Hypothetically through the development of a vocabulary / short descriptive language. 
  - This search is also highly amenable to parallelization. 
    - Vocab and language may also induce their own geometry,
    - Or be embedded in a space with geometry, 
      - Which can help search - though TBD. 
- The quotienting and AU system is effectively a form of library learning, 
  - albeit with a higher degree of flexibility: 
  - it contains rules that rewrite expressions, 
    - so contains data, functions, functors, and functionals, solvers...  
  - As such we should be aware of other efforts to perform this, 
    - Some which leverage version spaces or e-graphs.  
      - These are discussed in pass 1 of the planning.
- Meanwhile, amortization can be considered to form a type of semantic 'addressing space' over the learned rules, algebras, solvers.
  - In ML, this is a geometric space - continuous \mathbb{R}^d - which enables self-organization. 
  - In programming and human language, the space is expansive and compositional (e.g. docstrings, function names). 
    - This makes it more of a topology than a geometry, 
      - And so you could think of it as a graph over the graph of heterogenous experience data. 
      - In a meta-twist, like with computed addressing, this too can be computed ... 
        - Beyond what the core algorithm may do
        - Let's not think about that now. 
  - Linear codes work in the same way, 
    - though in a discrete and non-compositional geometry
  - True compositional addressing requires variable compute when decoding the address
    - C.f. linear codes or the geometric spaces in ML. 
    - yet, it makes the encoding potentially much more compact and memory access much more energy-efficient. 
      - Memory access consumes most of the power of modern LLMs. 
- A language enables compositional description of the labeled computation, 
  - In a form that is shorter and cheaper than executing the function / rule / algorithm itself. 
    - Thus it is a form of heuristic. 
  - You can and should use the language to label the entries in the growing library. 
    - which enables the graph over a graph idea above. 
- We don't need this self-organization yet - first the simulator-bootstrapped data and algorithm
  - but affordances should be made for its later addition. 
  - E.g. potential bindings to linear algebra or ML libraries. 
- Pivotal now is to show
  - Quotienting & AU under a simulator, with the right flexible datastructure and (graph-isomorphism) algorithm 
    - yields algebra, solvers /  propagators, rewrite rules
  - Recursive program synthesis with residual / fiber targets
    - With allowance for unobserved inference (big question mark), 
      - and optional heuristics for search,
    - Under a DL objective. 
  - Recursive rule expression
    - Derived rules are themselves entries in the flat datastructure
      - Which means, as sketched above, that we need a means of organizing their use / triggering their execution
        - In a way that is _less expensive_ than blind enumeration.
- Circling back to the beginning, grammar is: 
  - Integers
    - GF(p) but only at the start
  - Bools
    - And guards / conditional execution. 
  - Expressions
  - & Types.
