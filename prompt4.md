
# prompt
Updated Monday 26 October 2026

The goal of this research is to make a recursive program synthesis system. 
This system takes output or input-output data, tagged by time and/or space, and iteratively and recursively derives a program, run on a fixed simulator with a growing library, which generates the data.   In the case of input-output data, this means generates the output data from the input data. 
The objective of the program synthesizer is thus to find a representation or compression of the data which minimizes the overall description length as well as metrics for computational cost, including the cost to search for the compression. The pricing mechanism for this will be a mix of fixed costs, information-theoretic estimates, and (of course, given the recursive nature) computed, bootstrapped metrics.    
The research is motivated by N pillars: 
1. **Search**.  Search over computation is fundamentally unavoidable: the *a priori* shortest way to predict the **exact** effects of a computation is simply to do it.  Hence the simulator / computation engine + the supplied data are the ultimate sources of truth. 
  a. Execution, conditional input values and state, is similarly the ultimate source of equivalence: a given (set of) outputs is equivalent a program executed via a simulator on the inputs (e.g.). 
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
7. **Partitioning & Locality**.  In many cases, there are an unlimited number of ways of deciding what expressions to anti-unify or build a library from.
  a. Human search proceeds with some intrinsic metric of locality: data that is close in time or space. 
  b. This serves to bias any breadth-first search to local neighborhoods, and is reflective of the dependency structure of the real world: things generally don't depend on variables that are distant. 
  c. Locality can of course be bootstrapped: items that have a certificate for being co-local via search & computational validation can have induced locality (which, in turn, can be amortized / synthesized / explained through a subsequent synthesis step). 
    1. Or, vice-versa, locality can be imposed (via sorting), and equivalence checked. 
  d. Partitioning hence can be through basic equality (same types and/or values for each expression), through ordering, through basic computation.
    1. Factoring is another matter (as happens with library learning over one graph). 
  e. Partitions form frames for recursive program synthesis. 
    1. They are hence a straightforward form of lifting followed by a conditional. 
    2. Aside: deep learning does this in pre- and statically- allocated high-dimensional space; critical here is that space is allocated on the stack, in the search tree. 
8. **Recursion**. The program synthesis problem is recursive in several distinct ways: 
  a. Synthesis can proceed in stages: you solve a problem, which emits residuals or fiber indexes that need to be predicted; these serve as recursive target for another round of synthesis. 
    1. Sometimes early or first stages yield no compression, e.g. basis expansion to make a problem linear, so the full DL cost must be measured by the *full* path.  
  b. The search procedure itself is a program which emits an oft-repetitive computational graph. 
    1. Synthesis can proceed on the search tree and execution graph itself to derive messages about in accessible regions of solution space. 
      a. For example, when solving a hard Sudoku, following a strategic guess it's common to encounter chains of implication that indicate there are no possible solutions along that path.
      b. In SAT solving, these take the form of CDCL clauses, unique implication points, or dual implication points; the latter permits the introduction of new variables.  We aim to analogously replicate these powerful methods here. 
    2. The messages, in the form of expressions, partition a given search problem. 
      a. Messages, like again everything else here, can be target for anti-unification / generalization / library learning, which lifts them out of the local problem context to be general for all problems - eg creation of a new (partial) conservation.   This is how CDCL and UIP / DIP was invented, afterall! 
    3. Other messages can simply be lossy condensations of the computation performed in a search branch, approximate expressions of "why this worked or didn't"
      a. Aka heuristics.   The residuals they emit are discarded. 
      b. Which is why the computational cost is essential. 
  c. Recursion through library learning + local messages serves to partition exponential to super-exponential search space such that it's tractable in linear time - which is all we get in the real world. 
9. **Vocabulary and language**. The combination of locality, analogy, and heuristic compression motivates the final element of the proposal: that of vocabulary and language development. 
  a. Viz: the names of functions are short, easy-to decode, heuristic / approximate descriptions of what the functions do. Without them, libraries and code are un-navigable.  
  b. Language is compositional, which means that the decoder needs to execute some variable time/space computation
    1. But: it is not infinitely compositional like actual computer code, so that a fixed allocation of time or space is sufficient (like in a transformer). 
  c. This is a last goal/pillar of the research; like many of the preceding goals, it may be updated as the research is fleshed out. 
