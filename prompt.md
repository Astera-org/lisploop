
# prompt
Updated Monday 26 October 2026

The goal of this research is to make a recursive program synthesis system. 
This system takes output or input-output data, tagged by time or space, and iteratively and recusively derives a program, run on a fixed simulator with a growing library, which describes the data. 
The objective of the program synthesizer is to find a representation or compression of the data which minimizes the overall description length as well as metrics for computational cost, including the cost to search for the compression. The pricing mechanism for this will be a mix of fixed costs and information-theoretic estimates.   
It is motivated by N pillars: 
1. Search over computations is fundamentally unavoidable: the *a priori* shortest way to predict the **exact** effects of a computation is simply to do it.  Hence the simulator / computation engine + the supplied data are the ultimate sources of truth. 
2. That said, it is possible to re-represent computations in different forms.  
  a. For example, it is strategic to look for conserved quantities by taking the observed data and treating it as input to a computation. 
  b. Exact computation can be approximated and shorted by heuristics.  
    1. This is particuarly useful in search with real-world data, which has finite Markov blankets hence finite dependencies / mixing.  
3. Conserved quantities can be related to features of the simulator itself
  a. Like commutativity laws - these can reduce search space by providing equivalence.
  b. These laws can be derived from ongoing interaction with the simulator.
4. Other learned re-representations take the form of 
We have: 
- Domains and types (sets, named sets)
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
