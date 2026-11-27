---
# The quoted prompt nests lists five deep; LaTeX's itemize stops at four.
header-includes: |
  \usepackage{enumitem}
  \setlistdepth{9}
  \renewlist{itemize}{itemize}{9}
  \setlist[itemize,1]{label=\textbullet}
  \setlist[itemize,2]{label=\textendash}
  \setlist[itemize,3]{label=\textasteriskcentered}
  \setlist[itemize,4,5,6,7,8,9]{label=\textperiodcentered}
---

# lisploop --- recursive program synthesis by quotienting one flat store --- plan 2

Planning document, 2026-10-19. This is the second pass. It replaces the
broad approach of `plan.md` (*plan 1*, cited with its section numbers) and
keeps the parts of it that survive the new outline: the fiber code, the
findings, the two traps, and several checks. Other background, cited by
short name: `../sudoku/antiunify-notes.md` (*Notes*), and `../arc1/plan.md`
with `../arc1/notebook.md` (*ARC1*). As the prompt asks, the
symbolic-regression work (`../symbreg`, `../arc-sat/modpoly`) is not used.
Nothing is implemented. While writing, nine small throwaway python checks
were run in the session's scratch directory (not in the repo); their
numbers are in \S5 and are marked "checked" where used.

The prompt that motivated this document, verbatim. The en dash is
transliterated to ASCII for pdflatex, `\mathbb{R}^d` is set as math, the
asterisks of `(**)` and `[[../*,]]` and the two tildes are escaped so that
they print, the URL is wrapped in angle brackets so that it renders as a
link, trailing spaces are dropped, and blank lines are added before the
lists so that they render as lists:

> Meta: I am not satisfied with pass 1 of the planning, so have gone back,
> read through the initial results / ideas, and reconfigured the broad
> approach.  Below is the outline that needs to be carefully examined,
> double-checked, and rendered into a concrete set of experiments and
> milestones.
>
> Further meta:
>
> * Other experiments in this directory, [[../\*,]] are somewhat relevant -- but do not index too highly on them.
> * Don't pay attention to the symbolic regression experiments.
>     * That proved that, to do a minimal 'program synthesis' task you very much need linear algebra,
>         * from which Gauss-Jordan is built.
>     * Discovering or building in linear algebra and the trove of learned and found algorithms is _out of scope_ for this document / planned experiments.
> * Below, areas where I'm uncertain are flagged with "(\*\*)".
> * Please put the result in plan2.md, same format as plan.md.
>
> --------------------
>
> The goal of this research is to make a recursive program synthesis system.
> We have:
>
> * Domains and types (sets, named sets)
>     * Numbers
>     * Operators
>         * Including inequalities
> * Expressions
> * Ability to execute those expressions
>     * Over the domains
>     * Over the expressions
>     * (Which my yield errors)
> * Execution implies equivalence;
>     * an expression is equivalent to its input-output mapping, conditional domain & co-domain.
>     * Input yields output; if the language is purely functional, this is all you need to know.
>     * Information is "created" or "destroyed" by computation
>         * This information (e.g. MI) has to be simply measured, with a fixed ambient space / correspondence.
>             * Computation is not allowed here.
>     * Topologically, computation may be seen as a projection,
>         * In which case the reverse process requires a lift.
>     * [This understanding is consistent with the relation between work and entropy, e.g. <https://en.wikipedia.org/wiki/Jarzynski_equality%20>]
> * Execution here is on a simulator
>     * the lisp machine
>     * but, in general, it may be external: the real world.
>         * Which has state and is very much not functional.
> * Equivalence in an ambient domain enables compression
>     * a shorter description of the data, the computation,
>         * or the series of computations that lead to a computation.
> * Perfect equivalences are important,
>     * And need to be remembered, symbolically
>     * Yet they are also rare in the real world:
> * Most equivalences are approximate or partial,
>     * And so require residuals.
>     * The previous proposal indicates that these constitute the fibers of a projection (\*\*)
>     * These fibers permit information flow to a lifted space.
>     * Some residuals cannot be a priori ordered (form a set), or cannot be otherwise observed,
>         * Which means that they must be inferred.
>         * EM served as this inference engine in the Sudoku rule-learning experiment:
>             * Which class a given mutex belongs to is an unobserved variable (2 bits, in the end).
>         * This can be as large of a problem as the program synthesis task
>             * And so needs quotienting, partitioning, and computational description just like PS.
> * Approximate equivalences \~= heuristics,
>     * Which can be thought of as loose, lossy approximations to data.
>     * They are essential in bootstrapping combinatorial search
>         * provided the heuristic is easier to evaluate and infer than running many branches of a search tree.
>     * In this case, the residuals are immaterial; the full branching search needs to recreate state, as the approximations only guide decisions.
> * Otherwise, residuals can then be a target for subsequent compression/modelling.
>     * This equates to computed lifting, or computed addressing. (\*\*)
> * Equivalence under an action are symmetries,
>     * Which are vital for describing and partitioning space,
>         * especially the search space in program synthesis.
> * Equivalence finding terminates at execution,
>     * yet from this you can learn algebras, or ways of manipulating expressions while maintaining equivalence
>     * as well as solve rules
>     * Both are essential for exploring and filling in the graph of an unknown computation (= program synthesis).
> * Algebras, for example, allow for transformation of LHS of expressions to RHS and vice-versa
>     * This enables exact conversion from inferred conserved quantities to generative expressions,
>         * via the exchange of input and outputs.
> * Likewise, solve rules work on both expressions and base values (e.g. integers) to propagate information from output to input.
>     * Input to output is trivial with the simulator.
>     * Input and output to expression is the recursive program synthesis problem.
> * The goal and final metric in all of this is description length (DL).
> * As mentioned, equivalences in a prescribed space enable this.
>     * The question is what to quotient - where to look for constants (and-or orderings? (\*\*)) - then becomes open-ended
>     * Anti-unification (AU) is a symbolic means of quotienting,
>         * One that allows for the introduction of new variables = abstractions.
>         * It can be validated against the simulator (purely symbolic expressions) or ground truth data.
>     * But it is not the only means,
>         * Though initially should be the primary means of introducing abstractions.  (Unless literature suggests otherwise (\*\*))
>             * Beta-expansion is another, but imho only supported where there is evidence; thence \~= AU.
> * This suggests that all data / experience should be in one 'flat' store.
>     * A list.  In lisp.
>     * It can be ordered by time (ordered execution),
>     * but the algorithm should be largely invariant to this.
> * The quotienting - AU algorithm goes over this list,
>     * Trying to find constants in the tree-structured entries, *conditioned* on other elements.
>         * One quotient is meaningless without a connection to another
>             * Just like in AU.
>         * If the condition is an action, then the quotienting is a form of symmetry finding.
>     * Trees can be e.g. expressions, lists of inputs, list of outputs
>     * They all have a type, which can be a compositional object too ('int' 'input').
>     * As in the first version of this proposal, one type may be time-space
>         * Attributes that make locality meaningful, and reduce the span of BFS / help DFS.
> * This makes the quotienting-AU problem that of a structure & type-aware & locality-seeded subgraph isomorphism problem.
>     * For which there appear to be good algorithms,
>         * Or at least, good precedence for a working algorithm here.
>         * The quotienting / AU problem is not *actually* graph isomorphism, just saying that we may be able to extract lessons from this literature.
> * This is NP-hard, think, and yet some of the search can be amortized
>     * Hypothetically through the development of a vocabulary / short descriptive language.
>     * This search is also highly amenable to parallelization.
>         * Vocab and language may also induce their own geometry,
>         * Or be embedded in a space with geometry,
>             * Which can help search - though TBD.
> * The quotienting and AU system is effectively a form of library learning,
>     * albeit with a higher degree of flexibility:
>     * it contains rules that rewrite expressions,
>         * so contains data, functions, functors, and functionals, solvers...
>     * As such we should be aware of other efforts to perform this,
>         * Some which leverage version spaces or e-graphs.
>             * These are discussed in pass 1 of the planning.
> * Meanwhile, amortization can be considered to form a type of semantic 'addressing space' over the learned rules, algebras, solvers.
>     * In ML, this is a geometric space - continuous $\mathbb{R}^d$ - which enables self-organization.
>     * In programming and human language, the space is expansive and compositional (e.g. docstrings, function names).
>         * This makes it more of a topology than a geometry,
>             * And so you could think of it as a graph over the graph of heterogenous experience data.
>             * In a meta-twist, like with computed addressing, this too can be computed ...
>                 * Beyond what the core algorithm may do
>                 * Let's not think about that now.
>     * Linear codes work in the same way,
>         * though in a discrete and non-compositional geometry
>     * True compositional addressing requires variable compute when decoding the address
>         * C.f. linear codes or the geometric spaces in ML.
>         * yet, it makes the encoding potentially much more compact and memory access much more energy-efficient.
>             * Memory access consumes most of the power of modern LLMs.
> * A language enables compositional description of the labeled computation,
>     * In a form that is shorter and cheaper than executing the function / rule / algorithm itself.
>         * Thus it is a form of heuristic.
>     * You can and should use the language to label the entries in the growing library.
>         * which enables the graph over a graph idea above.
> * We don't need this self-organization yet - first the simulator-bootstrapped data and algorithm
>     * but affordances should be made for its later addition.
>     * E.g. potential bindings to linear algebra or ML libraries.
> * Pivotal now is to show
>     * Quotienting & AU under a simulator, with the right flexible datastructure and (graph-isomorphism) algorithm
>         * yields algebra, solvers /  propagators, rewrite rules
>     * Recursive program synthesis with residual / fiber targets
>         * With allowance for unobserved inference (big question mark),
>             * and optional heuristics for search,
>         * Under a DL objective.
>     * Recursive rule expression
>         * Derived rules are themselves entries in the flat datastructure
>             * Which means, as sketched above, that we need a means of organizing their use / triggering their execution
>                 * In a way that is _less expensive_ than blind enumeration.
> * Circling back to the beginning, grammar is:
>     * Integers
>         * GF(p) but only at the start
>     * Bools
>         * And guards / conditional execution.
>     * Expressions
>     * & Types.

---

## 0. Summary

**What is being built.** A recursive program synthesis system with one
data structure and one engine. The data structure is a flat store, a Lisp
list of typed, tagged trees: observations, simulator executions, residuals,
rules, derivations. The engine anti-unifies entries that are *connected*,
by a relation between their tags or by a shared value. That turns a set of
instances into a pattern and a table of substitutions, a *frame*. The engine
then quotients the frame: it looks for constants, shared variables,
functional relations (by running candidate expressions on the simulator),
partitions and orderings, and it scores everything in bits. Accepted
patterns go back into the store as rule entries. Whatever they leave
unexplained goes back as residual entries, which are the next round's
targets. Rules run on the same simulator, so rules apply to rules.

**What the examination changed** (\S1; the checks are in \S5).

1. *Residuals are fibers* ((\*\*a), (\*\*b)). This is exact for findings
   that restrict the unknown to a set, by the identity
   $H(X) = H(f(X)) + \mathbb{E} \log_2 \lvert f^{-1}(f(X)) \rvert$
   (checked). Partial findings add a mask or a guard, and approximate ones
   an error code. A residual becomes a target only once its fiber has
   coordinates taken from the ambient space. Modeling it is then computed
   lifting; when the fiber's elements are positions it is computed
   addressing, and the target is set-valued (checked on list tasks, where
   the few rows with a unique source fix the address map).
2. *Orderings* ((\*\*c)) are needed alongside constants. An ordering is a
   latent successor correspondence, searched as a sort key or as a chain of
   a functional relation, never as a permutation. Partitions are a third
   kind of quotient, and guards are their descriptions.
3. *Abstraction* ((\*\*d)). The literature supports anti-unification as the
   main inductive route to new variables. Two additions are needed:
   anti-unify equivalence classes rather than single representatives
   (checked: the $a = 1$ part of the GF($p$) $\times$ table breaks
   representative AU), and use explanation-based generalization for rules
   derived from derivations.
4. *DL needs a third account.* With the simulator in the decoder, a law on
   a finite domain, or a solve rule used as a procedure, is a theorem about
   the simulator and carries no information about any data (checked:
   commuted pairs are exactly at chance in a value-joined store). What they
   save, like indexes and heuristics, is work. So the objective keeps three
   accounts: data, library, and derivations, the last in bits of work, as
   in Levin's $Kt$. This is the prompt's own "compression of the series of
   computations that lead to a computation".
5. *Matching.* "Structure and type aware subgraph isomorphism" is, precisely,
   matching conjunctive patterns: theta-subsumption, a homomorphism problem,
   which becomes subgraph isomorphism under object identity. It is
   NP-complete in the pattern's size and polynomial for acyclic patterns.
   The plan keeps patterns small and acyclic, joined along tags and rare
   values.
6. *Rules as entries* bring the utility problem: learned rules can make a
   system slower. Triggering is by term indexing and fingerprints, and every
   rule carries a utility, in units of work, that must stay positive.
7. *Conversion and linear algebra.* Converting one conserved quantity into a
   generator is isolation. Converting several jointly can need elimination,
   which is out of scope; such findings stay implicit generators, decoded by
   intersecting fibers over small domains.

**The pivotal claims, as experiments** (\S9).

- *P1.* Quotienting and AU over a store of ground executions, with the
  simulator as validator, yield laws, rewrite rules, solve rules with their
  guards and fiber profiles, propagators, tabled operators, and rules about
  rules (the solve rule parametric in $p$). Milestones M0 and M1.
- *P2.* Recursive synthesis on residual targets under DL solves more than
  blind enumeration at equal time, first with residuals that can be
  observed (M2), then with latent ones inferred by votes and hard EM (M4).
- *P3.* Derived rules are store entries, and indexed, utility-pruned
  triggering keeps the cost of using them sublinear in the library's size
  (M3).

M5 completes the prompt's grammar (integers, inequalities, guards, learned
interval propagators), and M6 tests heuristics as orderings scored in
derivation bits.

**Deliberately absent.** Linear algebra, learned geometric addressing,
natural-language labels, external and stateful simulators, ARC, SAT, full
e-graphs. Each has an affordance (\S8).

**Language.** SBCL Common Lisp with no dependencies (\S10).

---

## 1. The outline, examined

Each claim of the outline was checked against an argument, a computation
(\S5), or the literature. The four items the prompt flags with (\*\*) are
called below (\*\*a) fibers, (\*\*b) computed lifting, (\*\*c) orderings
and (\*\*d) the literature on abstraction; the "big question mark" on
unobserved inference is (\*\*e). Verdicts: *holds*, *holds with a
condition* (stated), and *revised* (the plan departs, with the reason).

| outline claim | verdict | \S |
|---------------------------|------------------------------------|-----|
| domains, types, operators with inequalities | holds; inequalities only on ordered domains (tags now, integers later) | 1.10 |
| execution over domains and over expressions; errors | holds; $\bot$ is a value, and errors are data from which guards are learned | 2.2 |
| execution implies equivalence, relative to a domain | holds; decided exhaustively on small domains, by random probes elsewhere | 2.3 |
| information created or destroyed, measured with a fixed correspondence | holds; destroyed = mean log fiber size; created = usable information; computed correspondences are charged to the model | 1.1 |
| computation as projection, reversal as lift; Jarzynski | holds in the discrete sense; Landauer, Bennett and Sagawa--Ueda are the closer analogues | 1.1 |
| a simulator now, the stateful world later | holds; state must be made explicit, and hidden state is the canonical latent residual | 8 |
| equivalence compresses data, computation, derivations | holds; it becomes the three-account objective | 1.5 |
| perfect equivalences, remembered symbolically | holds; common in the bootstrap, because the simulator is exact | 9 |
| residuals are fibers of a projection (\*\*a) | holds for set-valued findings; partial and approximate findings add a mask or an error code | 1.2 |
| fibers carry information to a lifted space | holds once fibers have coordinates from the ambient space | 1.2 |
| unordered or unobservable residuals must be inferred (\*\*e) | holds; latent only when a row admits several labels; votes, then hard EM | 1.3, 7 |
| approximate equivalences as heuristics | holds when they only order the search; scored in derivation bits, their own cost included | 1.5 |
| residuals as targets: computed lifting, addressing (\*\*b) | holds; targets are set-valued when several fiber elements reproduce the data | 1.2 |
| symmetries partition the data and the search space | holds; data symmetries and laws come from one mechanism | 1.4 |
| algebra converts conserved quantities exactly | holds for one finding with one occurrence of the unknown; joint conversion can need elimination | 1.6 |
| solve rules propagate output to input, on values and on expressions | holds; this is the propagator model | 1.6 |
| DL is the final metric | revised: three accounts; DL of the data alone gives laws and solve rules no value on finite domains | 1.5 |
| what to quotient: constants and orderings (\*\*c) | both, plus shared variables, functional relations and partitions | 1.3 |
| AU as the primary route to abstraction (\*\*d) | supported; add AU over equivalence classes, and explanation-based generalization | 1.7 |
| one flat store, invariant to its order | holds; testable by shuffling, given canonical tie-breaks | 1.8, 2.1 |
| AU conditioned on connections; an action gives a symmetry | holds; tuple AU with shared variables, connected by tags or values | 2.4 |
| typed, compositional entries; time-space tags give locality | holds; tags are naturals, ordered, from the start | 2.1 |
| structure, type and locality aware subgraph isomorphism | holds as a pointer; precisely, conjunctive-pattern matching | 1.8 |
| NP-hard, amortizable, parallel | holds; hard only in pattern size and in correspondence choice | 1.8 |
| library learning with rewrite rules, functors, solvers | holds; the nearest systems each learn one of these kinds | 1.9, 13 |
| semantic addressing; compositional addresses cost decoding work | holds; term indexes and fingerprints are working instances | 1.9 |
| a language labels the library and acts as a heuristic | holds; symbolic labels now, natural language later | 1.9 |
| grammar: integers (GF($p$) first), bools, expressions, types | holds; tags are naturals, and lists are the structure of entries | 1.10 |

### 1.1 Information destroyed and created; projection and lift

For a deterministic $f$ on a finite domain with uniform input $X$,
$$H(X) = H(f(X)) + \sum_y P(f(X) = y) \log_2 \lvert f^{-1}(y) \rvert .$$
The information a computation destroys is the mean log size of the fiber
its input lands in. It is measured by counting, with no computation beyond
running $f$: the prompt's "simply measured". Checked (\S5): on
$\mathrm{GF}(59)^2$, which holds 11.77 bits, $+$ destroys 5.88 bits and
$\times$ destroys 5.89 (the fiber over 0 is larger). The transposed map
$(a, c) \mapsto b$ of $+$ has fiber size 1 everywhere, so $b$ is a function
of $(a, c)$; whether the language can express that function is a separate
question, and at depth 2 it can (\S4.1). The transposed $\times$ has
fiber size 1 on 3422 of the 3481 pairs $(a, c)$, 59 at $(0, 0)$, and 0 at
the 58 pairs $(0, c \ne 0)$. So its solve rule must carry the guard
$a \ne 0$, and $a = 0$ is where the inverse is not identifiable (ARC1
notebook, 2026-08-31, item 2).

Shannon information is never created by a deterministic map (the data
processing inequality). What computation creates is information that a
fixed, simple measurement can see. A constant-column test sees nothing in
`x0` or in `x1` of `2 4 6 8 10`, and everything in `(- x0 x1)`. Xu et al.
(2020) formalize this as usable information under a restricted family of
predictors, which computation can increase; Finzi et al. (2026) argue the
same for computationally bounded learners and show information being
created by computation. The prompt's "computation is not allowed here" is
that restriction. In this plan the fixed measurement is the ambient code:
per-row uniform codes over the domain $D$, with rows put in correspondence
by their tags. It follows that every correspondence that is *computed* (a
join on values, a sort, an EM assignment) belongs to the model and is paid
for in bits. It never belongs to the measurement; otherwise the alignment
would overfit.

A map $f$ splits its domain into fibers, and
$x \mapsto (f(x), \text{index of } x \text{ in its fiber})$ is a bijection.
Running a computation backwards is lifting: given $f(x)$, supply the index.
Landauer's principle puts a heat cost on discarding those bits, and Bennett
showed that any computation can be made reversible by keeping them (in his
construction, as a history). Sagawa and Ueda (2010) add a mutual-information
term to Jarzynski's equality for processes with measurement and feedback.
The prompt's analogy holds, but this plan relies only on the counting
identity above.

### 1.2 Residuals as fibers; computed lifting and addressing ((\*\*a), (\*\*b))

A finding $E(u, \cdot) = G(\cdot)$ at row $r$ says that $\pi_r(u) = G_r$,
where $\pi_r = E(\cdot, \text{context}_r)$. The unknown then lies in the
fiber $F_r = \pi_r^{-1}(G_r)$, and its residual is its index there, at
$\log_2 \lvert F_r \rvert$ bits (plan 1 \S1.6). So (\*\*a) is exact for
findings that hold on every row and restrict $u$ to a set. Two other cases
need one more piece each:

| finding | residual |
|---------------|--------------------------------------------------|
| exact, set-valued | the index in the fiber, under a uniform code |
| partial (holds on a subset of rows) | which rows (a mask, or a guard that is itself synthesized), and full values on the other rows |
| approximate ($u$ near $G$) | an error under a non-uniform code, which needs an order or a metric on $D$ |

In all three, the residual is $u$'s codeword under the conditional code that
the finding induces; the uniform fiber is the special case.

(\*\*b) holds as well. The residual column, tagged with its parent rows'
tags, is a new set of store entries. A program that computes it from the
tags and the values already decoded lets the decoder compute the lift
instead of reading it: computed lifting. When the fiber's elements are
positions in the data, the index is an address, and that program is
computed addressing. The checks added two conditions.

1. *Fiber coordinates come from the ambient space*: sort the fiber by value,
   or use a reference's position tuple. Per-row coordinates chosen any other
   way make the residual column look random however regular the lift is.
   This is the fixed correspondence of \S1.1 again.
2. *Targets can be set-valued.* When several elements of a fiber reproduce
   the data equally well, such as a value that occurs at several input
   positions, the program has to land somewhere in each row's *backward
   set*, not hit one coordinate. Checked (\S4.7): on lists over 4 colors,
   the 4 or 5 rows whose backward set is a singleton cut 19 205 index
   expressions to 39 for reverse and to 8 for rotate, and the remaining
   rows remove nothing further. The cheapest survivors, `(- n (+ i 1))` and
   `(mod (+ i 1) n)`, are right on held-out lists. Rotate needs `mod` or a
   guarded cover: with only `+` and `-`, no expression survives.

The recursion stops where a residual column is incompressible; what is left
are bare facts.

### 1.3 What to quotient ((\*\*c)), and when a residual is latent ((\*\*e))

(\*\*c) asks whether to look for orderings as well as constants. Yes, and for
three more structures. The quotient of a frame (\S2.5) looks for five:

| structure | what it says | example | found by |
|-----------|----------------------|-------------------|------------------|
| constant | a column, or an expression of columns, takes one value | `(- x0 x1) = 2` | value histogram |
| shared variable | two positions always hold the same value | `((+ ?x ?y) (+ ?y ?x))` | Plotkin's rule in the tuple LGG |
| functional relation | a column is an expression of the others | `b = (+ c (* 58 a))` | expansion over the other columns, run on the simulator |
| partition | a relation holds within each part, with a per-part constant | `b = (* ?K c)` within each value of `a` | grouping by a column or a tag expression |
| ordering | along a successor, a difference is constant | `{7 3 5 1}` sorted: step 2 | sort keys; chaining by a relation |

A constant under a relative reference needs a successor. Tags supply one: the
order of time or position. When the instances form a set, the successor is a
correspondence between instances that nobody observed. Searching for it as
one of $n!$ permutations is hopeless, but the useful successors come in two
cheap forms: sorting by a key expression from the expansion ($K$ keys at
$n \log n$ each), and chaining by a functional relation between instances
(instance $j$ follows $i$ when $R(i, j)$ holds; each instance has at most
one successor, so the chain takes linear time). Constants and orderings are
duals: a constant difference defines the successor, and a successor is what
makes the difference constant. Partitions hold piecewise, and guards are
their descriptions (plan 1 \S5.4).

*When a residual is latent* ((\*\*e)). The prompt says that some residuals
form a set or cannot be observed, and must be inferred. The checks suggest a
sharper line. A per-row label is *observable* when some computed column
reveals it row by row: the value of `(- x0 x1)` says which of two additive
rules applied. It is then an ordinary residual, and the next round
describes it. It is *latent* when a row is consistent with several labels:
several culprits in a sudoku clause, several input positions in a backward
set, rows on which two rules agree. The residual is then a set per row, and
the choice has to be made together with the description of the choices.
That is what hard EM did in sudoku (Notes \S2.3). Checked (\S4.8): in a
GF(251) sequence that switches between `x0 = (+ x1 k1)` and
`x0 = (* k2 x1)`, each row's fiber over the two constants, computed with the
solve rules of `+` and `*`, is a vote. 27 rows vote for $k_1 = 7$ and 13 for
$k_2 = 3$, against at most two for any other value. Hard EM converges in one
pass, and the one row on which both rules hold is assigned by the label's
description, `(= (mod i 3) 0)`, which costs about 5 bits instead of 40 bits
of bare labels. With a random switch no guard is found and the labels cost
$n H$ bits, as they should.

The prompt is also right that the latent problem can be as large as
synthesis: in general it is a search over joint assignments. The plan
bounds it at first (at most 4 labels per row, backward sets of at most 8),
requires every latent column to be described by the next round or coded as
bare facts, and measures its cost against the rest of synthesis (M4).

### 1.4 Symmetries: of the data and of the language

Equivalence under an action serves two purposes, which the plan keeps apart
although one mechanism serves both.

- *Symmetries of the data*: $x(\sigma(i)) = \tau(x(i))$ for an index map
  $\sigma$ and a value map $\tau$ (plan 1 \S5.10). In the store this is a
  quotient conditioned on an action: the connection between two templates
  is $\sigma$.
- *Symmetries of the language*: laws $E_1 = E_2$ under every substitution.
  They partition the search space into classes of programs with one
  behavior, and canonical forms pick one program per class.

Checked (\S4.4): join the `+` table of GF($p$) on equal results, and commuted
pairs are exactly a fraction $1/p$ of the joined pairs, so coding them as a
subset loses bits (28 at $p = 7$, 2447 at $p = 59$). In a store where both
orders were run on the same 50 inputs, joined on the shared instance tag,
the tuple LGG is `((+ ?v0 ?v1) (+ ?v1 ?v0))` at once. So laws come from
experiments that share inputs, plus universal validation on the simulator.
They do not come from compressing the data, and \S1.5 explains why they
cannot.

### 1.5 Description length in three accounts

The prompt makes DL the final metric, and the checks show that DL of the
data cannot be the only account. With the simulator in the decoder, a law
on a finite domain is a theorem about the simulator: its truth is no news
about any data. That is why commutativity was exactly at chance in \S1.4.
Used as a procedure, a solve rule saves no bits on a finite domain either,
because the decoder can enumerate the fiber instead. What both save is
work. A solve rule saves a factor of about $\lvert D \rvert$ in decoding (59
at $p = 59$, $2^{32}$ for 32-bit integers), and over unbounded integers it is
what makes decoding possible at all. Laws shrink enumerations: canonical
argument order took plan 1's one-dimensional depth-2 expansion from 25 955
to 17 399 raw expressions (plan 1 \S4), a factor of 1.49 at depth 2, which
should compound with depth. The prompt already names this: equivalence
compresses "the series of computations that lead to a computation". So the
objective keeps three accounts:

| account | measures | what pays in it |
|-----------|-------------------------------------|------------------------------|
| data | DL of the observations given the library: the fiber code (plan 1 \S1.6) | findings, lifts, programs |
| library | DL of each entry, charged once | abstractions and new operators that shorten programs across tasks |
| derivations | bits of work: $\log_2$ of the candidates tried at each choice, of simulator calls, of fiber searches | laws, solve rules used as procedures, indexes, heuristics, cached derived rules |

The inverse operator that a solve rule defines (`sub`, `inv`) belongs to
the second line: if programs that use it are shorter across tasks, it pays
like any abstraction, which is library learning's usual objective (Stitch,
DreamCoder). A law never appears in a program, and an index or a heuristic
changes only how fast a program is found, so they can pay only in the third
account.

Heuristics, the prompt's approximate equivalences used to guide search,
enter the third account. A heuristic reorders candidates. Its value is the
reduction in $\sum \log_2 (\text{rank of the chosen candidate})$, minus the
work of computing it. It never prunes, so completeness is kept, and the
residuals of the approximation are immaterial, as the prompt says, because
the search recreates the state.

The final metric therefore stays DL: library plus data for what is believed,
and work, in bits, for what is cached or used to steer. They are reported
separately, and compared only when deciding whether a cached rule earns its
place (\S6.2). This is Levin's $Kt$, description length plus $\log_2$ of
time, applied to search, as in his universal search and in Schmidhuber's
OOPS.

### 1.6 Algebra, conversion, and propagators

Algebra converts a conserved quantity into a generator exactly when the
unknown occurs once: isolation by solve rules (plan 1 \S6.5, after PRESS).
With two occurrences, collection by laws may reduce them to one. When
several findings fix the unknown only jointly, the conversion is a system of
equations, which in 2D is the norm (rows, columns and boxes in sudoku). For
linear systems that means elimination, the Gauss--Jordan machinery that the
prompt puts out of scope. So the plan converts single findings by isolation,
intersects fibers by enumeration where $D$ is small, keeps the rest as
implicit generators, and leaves a binding point for an external
linear-algebra primitive (\S8).

Solve rules on values and on expressions are the propagator model of
computation (Sussman and Steele 1980; Radul and Sussman 2009). Cells hold
partial information, here fibers (sets) and later intervals, and each
relation propagates in every direction for which it has a solve rule.
Forward, from input to output, is the simulator. From output to input on
values is a solve rule; on expressions it is isolation; from input and
output to an expression is the synthesis recursion. A propagator is thus a
deliverable of P1, and M1 tests the learned ones against brute-force
projection.

### 1.7 Anti-unification as the main route to abstraction ((\*\*d))

(\*\*d) asks whether the literature supports anti-unification as the primary
way to introduce abstractions. Broadly, it does:

| route | examples | relation to AU |
|-------------------|----------------------|---------------------------------------------|
| clause LGG, relative LGG | Plotkin 1970; GOLEM | AU over sets of atoms |
| inverse resolution | CIGOL (intra-construction) | AU, plus a new predicate defined by the parts that differ: the residual lift of \S1.2 |
| analytical functional synthesis | Summers 1977; IGOR2 | AU of input-output equations; subterms under holes become subproblems with induced examples, and recursion is recognized when they match the original ones |
| library learning | DreamCoder; Stitch; babble; LILO | inverse beta in version spaces; a corpus-guided search for the best AU of subtrees; AU over e-graphs |
| rewrite-rule learning | Getafix | hierarchical AU of before/after pairs, holes shared across the pair |
| analogical generalization | SME; SEQL and SAGE | alignment of relational cases, facts kept with frequencies |
| graph compression | SUBDUE | repeated substructures under MDL, applied hierarchically |
| theory exploration | QuickSpec; Ruler; TheSy | enumerate and test; no AU (plan 1's buckets) |
| explanation-based generalization | Mitchell et al.; DeJong and Mooney | generalize one derivation; needs the derivation, not two instances |
| chunking, macro-operators | Soar; Korf | compose rules that fired in sequence |
| latent classes | sudoku stage 1 (Notes \S2.3) | new discrete variables, not holes |

Every inductive route in the table is anti-unification or reduces to it,
apart from enumerate-and-test, which finds laws rather than abstractions,
and latent classes, which introduce discrete variables rather than holes.
EBG and chunking are not inductive at all: they generalize or compose
derivations that already exist. Two entries are close to this plan: IGOR2
is recursive synthesis on residual targets, and intra-construction is the
residual lift.

Two additions follow.

1. *Anti-unify equivalence classes, not representatives.* Syntactic AU is
   sensitive to representation. Plan 1 \S5.5 met this with commutativity
   and deferred AU modulo a theory; the check in \S4.3 shows that M1
   already needs it. In the part of the `*` table where $a = 1$, the
   cheapest solution is `c`; in the other parts it is `(* k c)`; and the
   LGG of these representatives is a bare variable. Choosing from each
   part's bucket the member that aligns gives `(* ?K c)`. The bucket is a
   small e-class, so this is babble's anti-unification over e-graphs in
   miniature. With equational axioms there is in general no single least
   general generalization, only a finite minimal complete set (Alpuente et
   al. 2014), so the choice is a small search, scored by DL.
2. *Explanation-based generalization (EBG) for derived rules.* EBG
   generalizes one solved instance by variablizing whatever its derivation
   did not depend on. It needs the derivation, which the store keeps as
   provenance, and one instance rather than two. It is the natural source of
   macro solve rules and composite rewrites (\S4.10, M3), while AU remains
   the source of inductive abstractions. Kitzelmann and Schmid (2006)
   combine the two for functional programs.

On beta-expansion, the prompt's reading matches the evidence. An
abstraction $(\lambda x.\, b)\, a$ supported by several occurrences is the
anti-unifier of the occurrences, and Stitch's corpus-guided search finds
such abstractions three to four orders of magnitude faster than DreamCoder's
inverse-beta version spaces. One occurrence is no evidence. Abstractions
over functions applied to bound variables need higher-order pattern AU
(Baumgartner et al. 2017), which waits until functionals appear.

Validation comes in two modes. A law claims every substitution, and is
validated on the simulator (\S2.3). A finding claims only the data's
substitutions, and is validated by running the program forward and against
the null frame (plan 1 \S1.4).

### 1.8 The store and the matching problem

A flat store whose results do not depend on its order is sound, and
testable: canonical iteration and canonical tie-breaking make every result a
function of the store as a set (\S2.1), and M0 shuffles the store to check
this.

The matching problem is, precisely, the following. A pattern is a set of
typed templates with shared variables and constraints between their tags: a
conjunctive query, or the body of a Datalog clause. Its instances are the
homomorphisms from the pattern into the store, which in ILP is
theta-subsumption. Requiring distinct variables to map to distinct entries
(object identity: Semeraro, Esposito and Malerba 1994) makes it subgraph
isomorphism, the prompt's analogy. Matching is NP-complete in the size of
the pattern (Chandra and Merlin 1977) and polynomial for acyclic patterns
(Yannakakis 1981). The LGG of two sets of atoms, Plotkin's clause LGG, is
their product, can be as large as the product of their sizes, and needs
subsumption tests to reduce. Ordered trees with known roots, on the other
hand, anti-unify in linear time. In this plan, hardness enters in exactly
three places: choosing which entries form an instance tuple (the
correspondence), unordered parts (sets, associative-commutative operators),
and patterns that span many entries.

Lessons taken from the subgraph-matching and graph-mining literature:

- filter candidates by type and label before anything else (VF2, LAD, the
  Glasgow solver);
- bind the most constrained variable first: rare values first, as the rare
  rows of \S1.2 did and as "confident first" did in sudoku;
- grow each pattern only once, by giving patterns a canonical code (gSpan's
  DFS codes; here, canonical variable naming);
- bound the best utility a pattern's extensions could reach before growing
  it (Stitch; SUBDUE's beam under MDL);
- seed and extend along locality, that is along tags, as sequence aligners
  seed on short exact matches.

The plan's restrictions follow from this: patterns of at most three
templates, acyclic, joined by tag constraints with offsets of at most 2 or
by values (rarest first), within one family of types; AU over ordered
trees; sets handled only through an ordering or a partition (\S2.5). Each
restriction is lifted only after a measurement says it binds.

Amortization, which the prompt asks for, comes from the library itself: an
accepted pattern becomes one symbol for later matching, so later patterns
are smaller (SUBDUE's hierarchical compression). Parallelism comes from the
seeds, which are independent within a round, while the store is read-only.

### 1.9 Library, addressing, and labels

The prompt's semantic addressing has two concrete, existing forms, and the
plan builds both.

- *Structural, compositional addresses.* Term indexes (discrimination trees
  and substitution trees: McCune 1992, Graf 1995) let a first-order prover
  retrieve, from millions of clauses, those that could match a query term,
  at a cost that grows with the query rather than with the store. Decoding
  such an address costs work proportional to the term: the prompt's
  "variable compute when decoding". Rete networks (Forgy 1982) share
  condition tests across rules and match them incrementally against a
  working memory. They are the closest existing match to rules triggered
  over a flat store, and were scaled to very large numbers of learned rules
  in Soar (Doorenbos 1995).
- *Behavioral, non-compositional addresses.* A fingerprint, the value vector
  on fixed probes, is a hash: constant-time lookup, no structure, much like
  a linear code. Plan 1's buckets are this index, and Bansal and Aiken
  (2006) built a database of peephole optimizations on it.

Labels, in the prompt's sense of a short language describing an entry,
start symbolic: type signature, domain, the laws the entry satisfies, its
fiber profile, its use count. Property signatures (Odena and Sutton 2020)
are this idea used as search features; LAPS and LILO attach natural-language
names, which is deferred. The graph over the graph is the set of links
between entries (derived from, generalizes, inverse of, used with), stored
as entries.

The known risk of making derived rules entries is the *utility problem*. In
explanation-based learning, adding learned rules made systems slower,
because the cost of matching grew faster than the savings (Minton 1990; on
expensive chunks, Tambe, Newell and Rosenbloom 1990). The plan makes it
P3's central measurement (\S6.2, M3). The energy argument, that memory
access dominates the energy of computing (Horowitz 2014), favors
compositional addresses; it is not tested here.

### 1.10 Grammar

The grammar is the prompt's, with three precisions.

- *Values* are GF($p$) at the start, with `+ *` and `=`. Subtraction and
  division are withheld, as in plan 1 \S5.9. Bounded integers, with
  `- div mod <`, follow in M5.
- *Tags* are naturals from the start, with `+ - mod div < =`. Locality and
  guards need an order, and GF($p$) has none compatible with addition
  ($a < b$ does not give $a + c < b + c$). So inequalities apply to tags at
  first, and to values only from M5. Tags enter value expressions through
  an implicit cast mod $p$.
- *Lists and tuples* are the structure of entries (input and output lists,
  tuples of instances). The list tasks of M2 need no list operators: their
  programs are index maps over tags and relations between values.

Booleans come from comparisons and serve guards (`if`). Expressions are
values (quoted trees) with `eval`, `match` and `inst` (instantiate), so
rules are expressions over expressions. Types are compositional lists of
symbols, holes are typed, and AU never generalizes across base types.

---

## 2. Objects and vocabulary

### 2.1 The store

The store is one list of entries. An entry has seven fields:

| field | content | example |
|--------|------------------------------|---------------------------------|
| `id` | insertion counter, i.e. time | `17` |
| `type` | a list of symbols, compositional | `(gf 59 output)` |
| `tags` | index attributes, naturals | `((e . 2) (i . 3))` |
| `body` | a tree of integers, symbols and lists | `(ev (+ 3 4) 7)` |
| `prov` | how the entry was made | `(:exp table)`, `(:res 18 (- x0 x1))` |
| `label` | a symbolic summary (\S1.9) | `(:sig ((gf 59) (gf 59)) :laws (comm))` |
| `stats` | DL, support, uses, last use | |

For example:

```
(:id 17 :type (gf 59) :tags () :body (ev (+ 3 4) 7) :prov (:exp table))
(:id 18 :type (gf 251 x) :tags ((s . 2) (i . 3)) :body (x 8) :prov (:obs))
(:id 19 :type (gf 59 rule solve) :tags ((p . 59))
 :body (solve (= (+ ?a ?b) ?c) ?b (+ ?c (* 58 ?a)) :guard t :fiber 1)
 :prov (:quot 4 :verified :exhaustive))
(:id 20 :type (gf 251 x residual) :tags ((s . 2) (i . 3)) :body (r 19)
 :prov (:res 18 (- x0 x1)))
```

Granularity is one entry per observation or execution: one sequence element,
one table row. Frames are then built by AU and never given, and locality
lives entirely in the tags. One exception keeps the law experiments small:
the executions of one expression on a shared set of instances are stored as
one entry holding the value vector, which is their tuple AU done in advance
(\S2.4).

Indexes are derived, and rebuilt or maintained incrementally: by type, by
skeleton (the body with its leaves replaced by their types), by atom (each
value to the entries that contain it), by tag, and by fingerprint (\S2.3).
Algorithms iterate over indexes in a canonical order (type, then skeleton,
then canonical print), never by `id`, and break ties the same way. So
permuting the list changes nothing but variable names; that is the prompt's
invariance, and M0 tests it.

### 2.2 The simulator

The evaluator `run` takes a tree and an environment and returns a value or
$\bot$. The domains at the start:

| domain | values | operators |
|----------|----------------|-----------------------------------------|
| `(gf p)` | $0, \ldots, p - 1$ | `+ *`, `=`; no `-` or `/` (plan 1 \S5.9) |
| `nat` (tags) | naturals | `+`, `-` ($\bot$ below 0), `mod div < =` |
| `bool` | `t nil` | `and or not if` |
| `expr` | quoted trees | `eval`, `match`, `inst` |

Bounded integers, with `- div mod <` on values, arrive in M5 (\S1.10).
Operators are strict in $\bot$. An execution that yields $\bot$ is stored
like any other: errors are data, and guards are learned from them.

Experiments are executions chosen by a fixed policy at first: whole tables
of an operator for small $p$, samples for large $p$, and, for laws, the
depth-2 expansion run on one shared set of random instances (M1). Choosing
experiments that split rival rules waits until the uniform ones are
saturated (Notes \S5).

### 2.3 Equivalence and fingerprints

Two expressions are equivalent on a domain when they agree at every point of
it. The *fingerprint* of an expression is its value vector on a fixed probe
set (64 points, as in plan 1 \S7.1). Equal fingerprints propose an
equivalence, which is then decided:

- exhaustively on domains of up to a few $10^5$ points (all of $\mathrm{GF}(59)^3$
  is $2 \times 10^5$);
- for polynomials over GF($p$), by $k$ independent random probes, under
  which a false equivalence of degree-$d$ polynomials survives with
  probability at most $(d/p)^k$ (Schwartz 1980; Zippel 1979; at depth 2,
  $d \le 4$);
- otherwise, by $10^4$ random tests plus a memory of counterexamples, as in
  QuickSpec.

The fingerprint index is the behavioral address of \S1.9.

### 2.4 Patterns, tuple anti-unification, frames

A *pattern* is a list of typed templates (trees with variables) and
constraints between their tags, for example

```
((x ?a) :tags ((s ?s) (i ?i)))   ((x ?b) :tags ((s ?s) (i (+ ?i 1))))
```

which is plan 1's window `x1, x0` written as a two-template pattern. A
pattern is a conjunctive query, and its *instances* are the tuples of
entries it matches.

The LGG of a set of instance tuples is computed jointly over each tuple with
one variable map: Plotkin's rule gives positions that hold the same tuple of
differing subtrees the same variable. That is how a connection becomes a
shared variable. In the commutativity experiment the tuple LGG is
`((+ ?v0 ?v1) (+ ?v1 ?v0))` (checked).

The *frame* of a pattern is its table of substitutions: one row per
instance, one typed column per variable, plus the instances' tags. Frames
are plan 1's tables, now built rather than given.

*AU over buckets.* An instance can come as a set of equivalent trees, a
bucket of the expansion. The LGG then chooses one member per instance so as
to minimize the pattern's DL; the default choice is the skeleton that most
instances share. Without this, a part whose solution simplifies (at an
identity element) makes the LGG a bare variable (\S4.3).

*Connections.* Two templates are connected by a tag constraint
($i' = i + d$, the same $e$) or by a shared variable whose values must be
equal (a value join). A tag join on a functional relation picks a unique
partner and costs nothing. A value join can offer several partners; the
choice is then a latent correspondence and is paid for (\S1.1, \S7).

### 2.5 Quotients of a frame

For each frame the quotient looks for the five structures of \S1.3:

1. *Constants*: the value histogram of each column and of each expression of
   the expansion over the columns (plan 1's constant buckets).
2. *Shared variables*: equal columns, found by hashing columns.
3. *Functional relations*: each column in turn is the target of the depth-2
   expansion over the other columns and the tags, with at most one fitted
   constant (plan 1 \S5.3), hashed on a sample of rows and verified on all
   (plan 1 \S7.1). No column is designated as input or output. All
   directions are searched, and the solve rules are the directions other
   than the one in which the data were produced. The prompt's "exchange of
   input and outputs" thus needs no transposition step (plan 1 needed one).
4. *Partitions*: rows are grouped by the value of a column or of a small tag
   expression (`(mod i k)`, `(div i k)`), and relations are sought within
   each part. Per-part constants are anti-unified across parts (over
   buckets), and the varying constant becomes a child frame keyed by the
   part.
5. *Orderings*: an unordered instance set is sorted by key expressions from
   the expansion, or chained by a relation found between instances, and
   items 1 to 3 are rerun along the new successor.

Each candidate is scored by the bits it saves through fibers (plan 1 \S1.6)
and accepted greedily by marginal net bits, recomputed after each acceptance
(plan 1 \S5.13).

### 2.6 Kinds of entry

| kind | claims | validated by |
|-------------|-------------------------------|------------------------------|
| finding | a relation holds on the data's frame | forward execution reproduces the data; null frame |
| law | $E_1 = E_2$ for every substitution in the domain | the simulator, universally (\S2.3) |
| rewrite rule | a law oriented to reduce DL, or a term order for a commutative law | its law |
| solve rule | a relation solved for one column, with a guard and a fiber profile | the simulator, over the operator's domain |
| propagator | the solve rules of one relation, applied to partial information (sets, intervals) | equality with brute-force projection (M1, M5) |
| tabled operator | a lifted child with no short generator, kept as a table | the simulator |
| residual | an instance's unexplained part: fiber index, mask, error, hole value, latent label | decoding |
| derivation | the steps that produced an entry | replay |

All are entries. All but residuals and derivations are rules, which means
they are executable.

### 2.7 The three accounts, concretely

- *Data.* The fiber code of plan 1 \S1.6. An unexplained value costs a
  constant $\log_2 \lvert D \rvert$ whatever the size of the residual (ARC1
  M2, lesson 2: a code whose marginal cost falls as the residual grows lets
  memorization beat rules).
- *Library.* A prefix code of each entry's tree under a uniform grammar,
  charged once; priors from usage come later.
- *Derivations.* For each task, the sum over choice points of $\log_2$ of the
  rank of the chosen candidate under the ordering in force, plus $\log_2$ of
  the simulator calls spent in fiber searches and verification.

---

## 3. The engine

### 3.1 One round

```
(defun run-round (targets store)
  "One pass of the engine over the entries not yet explained."
  (let ((cands '()))
    ;; seeds: locality first, then rare values
    (dolist (seed (seeds targets store))
      ;; the tuple LGG, grown while its bound pays, and its frame
      (let* ((pat (grow seed store))
             (frame (instances pat store)))
        (setf cands (append (quotients pat frame) cands))))
    ;; greedy by marginal net bits, recomputed after each acceptance
    (let ((accepted (accept-greedily cands)))
      (assert (every #'reproduces-p accepted))  ; forward execution
      (emit-rules accepted store)
      (emit-residuals accepted store))))        ; next round's targets
```

- *Seeds* are pairs of target entries with the same base type (an input
  and an output may pair), ordered by tag distance, then by the rarity of
  the values they share, then by skeleton size.
- *Grow* starts from the seed's tuple LGG, adds every instance the pattern
  matches (through the indexes), and extends the pattern by one connected
  template while an upper bound on the extension's utility beats the best
  so far (as in Stitch).
- *Quotients* are those of \S2.5.
- *Accept* is greedy by marginal net bits. Findings that predict the same
  continuation are grouped and the cheapest kept (plan 1 \S5.2); bounds and
  dominance prune as in plan 1 \S7.3.
- *Emit* writes rule entries and residual entries, with provenance.
  Residual entries are the next round's targets. Rule entries become
  templates for later matching (the vocabulary of \S1.8) and executables.
  Child frames are memoized by content (plan 1 \S7.4).
- The recursion ends when no candidate has positive net bits. The targets
  that remain are bare facts.

### 3.2 Control

- Locality first: the smallest tag distance.
- Rare values first: the most constrained binding (\S1.2; Notes, "confident
  first").
- Confident first inside EM (\S7).
- Canonical tie-breaks, for order invariance.
- Budgets at first: patterns of at most three templates, expansion depth 2,
  one fitted constant per expression, four residual rounds. M2 measures
  which of them binds.

### 3.3 Where the cost is

| step | cost | measured (\S5) |
|-------------------|------------------------------|----------------------------------|
| grouping by skeleton | linear in the store | 7 690 entries into 10 frames in 0.01 s (python) |
| functional relations | expansion size $\times$ hashed rows, per target column | 30 targets on 10 frames, depth 2, one fitted constant: 2.7 s (numpy) |
| tag joins | linear per connection | --- |
| value joins | linear, but partners can be many | 100 949 value-joined pairs for the GF(59) `+` table |
| latent choice | product of the candidate sets, cut by votes and EM | \S4.8, \S7 |
| conjunctive matching | exponential in the pattern's size in general | kept to three acyclic templates |

---

## 4. Worked examples

Examples marked "checked" were reproduced by the scratch scripts of \S5; the
others are worked by hand.

### 4.1 Operator tables from a shuffled store (checked)

The store holds the full tables of `+` and `*` for
$p \in \{5, 7, 11, 13, 59\}$: 7 690 ground entries `(ev (op a b) c)` in
random order. Grouping by type and skeleton gives ten frames, each with
columns $a, b, c$. In each frame every column in turn is the target of the
depth-2 expansion over the other two, with operators `+ *` and one fitted
constant:

| frame | $c$ from $a, b$ | $b$ from $a, c$ | $a$ from $b, c$ |
|---------------|------------------|------------------------|------------------------|
| GF($p$) `+` | `(+ a b)` | `(+ c (* k a))`, $k = p - 1$ | `(+ c (* k b))`, $k = p - 1$ |
| GF($p$) `*` | `(* a b)` | none on all rows | none on all rows |

These hold for all five primes and were verified on every row. No column was
designated as input; the solve rules are simply the other directions of the
same relation.

### 4.2 One solve rule for every field (checked)

The five solve rules for $b$ are entries of type `(gf p rule solve)`. Their
LGG is `(+ c (* ?K a))`, and the child frame $p \mapsto ?K$ holds
$(5, 4), (7, 6), (11, 10), (13, 12), (59, 58)$, so $?K = p - 1$ on every
row, which is `(- p 1)` in tag arithmetic. Here the engine ran on its own
output: plan 1 \S3.8, now checked.

### 4.3 The multiplicative inverse, by parts (checked)

In GF(5), the guarded relation ($a \ne 0$) has the depth-2 solution
`(* (* a a) (* a c))`, since $a^{-1} = a^3$. For $p \ge 7$ there is none.
The partition step groups the `*` frame by $a$ and solves $b$ from $c$ in
each part, with two possible results:

- *Representatives.* The cheapest solution in the part $a = 1$ is `c`, and
  elsewhere it is `(* k c)`. Their LGG is a bare variable, which explains
  nothing.
- *Buckets.* Every part's bucket contains `(* k c)`, with $k = 1$ in the part
  $a = 1$. The aligned LGG is `(* ?K c)`, and the child frame $a \mapsto ?K$
  equals $a^{-1}$ on every part, for $p = 5, 7, 11, 13$.

The child has the generator `(* a (* a a))` for $p = 5$, and none at depth 2
for $p \ge 7$, so there it is kept as a tabled operator `inv` with $p - 1$
entries. The part $a = 0$ has no solution: there $c = 0$ and $b$ is free
(fiber $p$), the region of \S1.1 where the inverse is not identifiable. This
is plan 1 \S3.7's four-step sketch, checked, with one correction:
anti-unify buckets, not representatives.

### 4.4 Where laws come from (checked)

Join the GF($p$) `+` table on equal results. For $p = 59$ that gives 100 949
pairs, of which 1711 are commuted pairs: a fraction $1/p$, exactly. Coding
them as a subset (a mask, then one column fewer for those rows, since the
join already fixes one) costs 2447 bits more than not doing so (28 bits
more at $p = 7$). In a value-joined store commutativity is invisible, as it
must be, since given the simulator it is no news about these data. Running
both orders on the same 50 random
inputs and joining on the shared instance tag gives the tuple LGG
`((+ ?v0 ?v1) (+ ?v1 ?v0))` at once, and universal validation then confirms
it. Laws come from designed experiments plus validation, and they pay in
derivation bits (\S1.5), not by compressing the store.

### 4.5 `2 4 6 8 10` as element entries

Five entries `(x v)` carry the tags `(s . 1)` and `(i . 0)` to `(i . 4)`.
The seed is two entries at tag distance 1, the pattern is the two-template
window of \S2.4, and its frame has the rows $i = 0, \ldots, 3$ with columns
$a = x_i$ and $b = x_{i+1}$. The quotient finds `b = (+ a 2)` and the
constant `(- b a) = 2`, and over the one-template frame the closed form
`x = (* 2 (+ i 1))`, with the code lengths of plan 1 \S3.1. The entry at
$i = 0$ is not covered as a $b$, so under the recurrence it is a bare fact
(the initial condition). Plan 1's boundary trap (\S4, trap 2) cannot arise:
a pattern matches only where all of its templates exist.

### 4.6 Cubes: a residual round

At depth 2 nothing is exact in the window frame. The lift $v = b - a$ is
injective in $b$ given $a$, so the engine emits residual entries `(r v)`
tagged by $i$: `7 19 37 61 91 127 169`. The next round runs on them, and its
three-template window finds the second difference 6. The parent is recovered
through the lift's singleton fibers. Fourth powers need two residual rounds
(plan 1 \S3.5, checked there).

### 4.7 Reverse and rotate: computed addresses (checked)

For list tasks `out[i] = in[f(i, n)]`, each output element's residual is its
backward set $B_i = \{j : \mathtt{in}[j] = \mathtt{out}[i]\}$, and an index
expression over `i, n` is accepted if it lands in $B_i$ on every row of
every example. With three examples of lengths 5 to 8 over 4 colors:

| task | rare rows | index expressions surviving | cheapest |
|--------------|----|------------------------|----------------------|
| reverse | 4 | 39 of 19 205 | `(- n (+ i 1))` |
| rotate | 5 | 8 of 19 205 | `(mod (+ i 1) n)` |
| identity | 4 | 188 of 6 055 (`+ -` only) | `i` |
| drop-first | 3 | 150 of 6 055 (`+ -` only) | `(+ i 1)` |

For reverse and rotate, the rare rows alone (those with
$\lvert B_i \rvert = 1$) leave the same survivors as all rows together. The
survivors are extensionally equal on the data, so grouping by prediction
keeps the cheapest, and the cheapest is right on held-out lists (100 of 100
for reverse and for rotate). Without `mod`, rotate has no survivor and needs
a guarded cover (`(+ i 1)` except at $i = n - 1$). Coding the addresses
directly as residuals would cost 21 to 28 bits per task.

### 4.8 A hidden switch (checked)

In GF(251), $x_i = x_{i-1} + 7$, except that $x_i = 3 x_{i-1}$ where
$i \bmod 3 = 0$; $n = 40$, and the switch is not observed. Each row's fiber
over the parameters is one value per rule, computed with the solve rules:
$k_1 = x_i - x_{i-1}$, and $k_2 = x_i x_{i-1}^{-1}$. These are votes: 27 for
$k_1 = 7$, 13 for $k_2 = 3$, and at most two for any other value. Hard EM
assigns every row in one pass, leaving one row on which both rules hold. The
label
column, a residual tagged by $i$, is described by `(= (mod i 3) 0)` at about
5 bits, against 40 bits as bare labels, and the guard also settles the
ambiguous row. Total DL is roughly 45 bits against 319 raw. With a random
switch the votes still find both constants, no guard is accepted, and the
labels are coded as bare facts at 42 bits, which is $n H$.

### 4.9 An unordered set

The entries `(v 7) (v 3) (v 5) (v 1)` have no tags, so no relative
reference exists. Sorting by the key `v`, the cheapest key in the expansion,
gives a successor, along which the difference is the constant 2; the set is
coded as a start, a step and a count instead of four values. With entries
`(v (k w))`, the keys include both fields, and the cheapest key under which
some column becomes constant wins.

### 4.10 A macro solve rule by explanation-based generalization (M3)

Isolating $u$ in `(= (+ (* 3 u) 5) c)` over GF(7) takes two solve-rule
steps: peel the `+`, which gives `(+ c (* 6 5))`, then peel the `*`, which
multiplies by `(inv 3)`. The derivation is an entry. EBG variablizes what
the steps did not depend on, the constants 3 and 5 and the field, and gives
for `(= (+ (* ?k u) ?m) ?c)` the rule `u = (* (+ ?c (* (- p 1) ?m)) (inv ?k))`,
guarded by $?k \ne 0$. AU over two derivations of the same shape gives the
same schema by induction. The macro is kept only while its savings in
derivation bits exceed its matching cost (\S6.2).

---

## 5. Checks run while writing

Nine throwaway python scripts, in the session's scratch directory (not in
the repo).

| check | result |
|-------------------|------------------------------------------------------|
| information destroyed (\S1.1) | on $\mathrm{GF}(59)^2$ (11.765 bits), `+` destroys 5.883 bits and `*` 5.892; the identity of \S1.1 holds to $10^{-9}$; transposed `+` is a bijection; transposed `*` has fiber 1 on 3422 pairs, 59 at $(0, 0)$, 0 at 58 pairs |
| commutativity, value-joined (\S4.4) | commuted pairs are $1/p$ of the value-joined pairs (21 of 147 at $p = 7$, 1711 of 100 949 at $p = 59$); coding them as a subset nets $-28$ and $-2447$ bits |
| commutativity, shared inputs (\S4.4) | 50 instances; tuple LGG `((+ ?v0 ?v1) (+ ?v1 ?v0))` |
| frames from a shuffled store (\S4.1) | 7 690 entries into 10 frames in 0.01 s; all three directions of `+` for the five primes; `*` forward only; 2.7 s in all (numpy, depth 2, one fitted constant, 64 hashed rows, then all rows) |
| solve rules across $p$ (\S4.2) | LGG `(+ c (* ?K a))`, with $?K = p - 1$ on all five rows |
| `*` inverse by parts (\S4.3) | representatives: the LGG is a bare variable (the part $a = 1$ gives `c`); buckets: `(* ?K c)`, $?K = a^{-1}$ for $p = 5, 7, 11, 13$; child generator $a^3$ at $p = 5$, none at $p \ge 7$ (tabled, $p - 1$ entries) |
| computed addresses (\S4.7) | see the table there; rotate needs `mod`; rare rows decide; the cheapest maps are right on 100 of 100 held-out lists |
| latent switch (\S4.8) | votes 27 and 13, at most 2 for any other value; one ambiguous row; label `(= (mod i 3) 0)` at about 5 bits against 40 bare; random switch: no guard, labels at $n H$ (42 bits) |

Three lessons are new to this plan: anti-unify buckets, not
representatives; laws do not compress data, so they need the derivation
account; and in computed addressing the rare rows decide. The two traps of
plan 1 \S4 still apply. The null is drawn uniformly over $D$, and boundary
rows are now handled structurally (\S4.5).

---

## 6. Triggering, utility, and heuristics

This is the design behind P3 (M3) and the heuristics of M6.

### 6.1 Indexes

- *Structural.* A discrimination tree over the trigger templates of rewrite
  rules, solve rules and patterns, with types in the path and variables as
  wildcards. A query term retrieves the rules whose trigger could match it,
  at a cost that grows with the query, not with the library.
- *Type signatures* (domain, arity, result type) filter first.
- *Behavioral.* Fingerprints (\S2.3) retrieve rules by what they compute;
  coarse fingerprints serve M6.

Rete-style incremental matching of multi-template triggers is deferred
until single-template triggers have been measured.

### 6.2 Utility

For a rule $R$, over a window of recent tasks,
$$U(R) = \sum_{\text{uses}} (\text{work saved}) - \sum_{\text{retrievals}} (\text{matching work}),$$
counted in simulator calls and match attempts, as in Minton (1990). The work
a use saves is that of the cheapest derivation without $R$ minus that of the
derivation with it, estimated by replay on a sample. A rule with $U < 0$
over the window is demoted: it stays in the store, but leaves the index.
Valid rules are never deleted, since the store keeps all experience.

### 6.3 Derived rules

There are three sources: EBG over one derivation (\S4.10), AU over
derivations of the same shape, and composition of rules that fired in
sequence (chunking). All three produce entries with provenance, and all are
subject to utility.

### 6.4 Heuristics

Approximate equivalences are used only to order candidates. Coarse quotients
of a task's entries (whether input and output hold the same value set,
sortedness, constant columns, parity profile, length relation: property
signatures) are computed for each task, and stored with each rule's past
successes. Candidates are tried in order of agreement between signatures,
then of usage prior. Nothing is pruned. The value of a heuristic is measured
in derivation bits, including the work of computing the signatures.

---

## 7. Latent residuals: votes and hard EM

When a row admits several labels (a rule, a partner, a part, an address),
its residual is a set. The procedure, designed for M4:

1. *Votes.* Each row's fiber over the hypothesis parameters is computed with
   solve rules (\S4.8), and values supported by many rows become candidates.
   This generalizes sudoku's `votes` (Notes \S2.3), where the fiber was the
   culprit set.
2. *Hard EM.* Each row is assigned to the candidate that explains it at
   least cost, candidates are refit on their rows, and this repeats to a
   fixpoint. Confident first: rows with a single consistent label are
   committed before ambiguous ones (Notes \S3, item 3), in best-first order
   (ARC1 M2, lesson 3). Restarts; the best by DL is kept.
3. *Describe the label.* The label column is a residual entry tagged by its
   rows' tags. The next round describes it (a guard, a sort key, an index
   map) or codes it as bare facts.
4. *Price.* The DL of the label's description, plus $\log_2$ of the choices
   still open in each row. A latent assignment that is not described costs
   what it should.

If the labels are random, step 3 finds nothing, and a latent model is kept
only where its rules pay for the bare labels (\S4.8, the random switch). The
bounds of \S1.3 apply at first.

---

## 8. Affordances

Designed in now, built later.

| later capability | affordance now |
|----------------------|--------------------------------------------------|
| external or stateful simulators | `run` sits behind a protocol with an optional state; entries `(obs t s)` and `(act t a)`; the eventual use of the engine there is the quotient of histories by future behavior (Nerode; causal states, Crutchfield and Young 1989), whose classes are the hidden state |
| linear algebra and other numeric libraries | foreign primitives: operators implemented outside the evaluator, with a DL, domain tags and fingerprints, callable like any other; none is used in the planned experiments |
| learned, geometric addressing | an index protocol (`add`, `query`); an embedding index is one more index |
| language labels | the `label` field, symbolic for now |
| parallel search | seeds are independent and the store is read-only during a round (SBCL threads) |
| e-graphs | buckets are small e-classes; a full e-graph if bucket AU fails beyond depth 2 (plan 1 \S7.6 triggers) |
| SAT | none, as in plan 1 |

---

## 9. Experiments and milestones

| # | claim | deliverable | exit test |
|----|--------|-------------------|------------------------------------------|
| M0 | substrate | store, simulator, tuple AU, matcher, the three accounts | LGG properties; order invariance; lossless frames; planted patterns recovered; timings |
| M1 | P1 | algebra from the store | all directions of `+`; guarded `*` and tabled `inv`; reference laws and no false law; $?K = p - 1$; propagators equal to brute force; confluence of rewrite rules measured |
| M2 | P2, observed residuals | the engine on sequences and lists | suites solved with frames built by AU; more solved than blind enumeration at equal time on residual and address tasks; nulls clean |
| M3 | P3 | rules as entries: indexes, utility, EBG | matching work sublinear in library size; utility keeps time flat; macros pay; the parametric rule serves an unseen field |
| M4 | P2, latent residuals | votes, hard EM, orderings | switches, sorts, permutations, ambiguous addresses; random nulls clean; sudoku as a stretch |
| M5 | the grammar | integers, inequalities, interval propagators | integer laws exact, field-only laws not carried over; interval propagators exact; guarded tasks |
| M6 | heuristics | signatures as orderings | fewer derivation bits on held-out tasks, no task lost, net time saved |

### M0 --- substrate

*Purpose.* Build the data structure and the matcher, and test them on
synthetic stores with known answers before any claim depends on them.

*Deliverables.* `store.lisp`, `sim.lisp`, `au.lisp`, `dl.lisp`, `m0.lisp`.

*Exit tests.*

1. *LGG.* On 1000 random tuples of small typed trees, every instance matches
   its LGG; on 200 small cases, the LGG is an instance of every common
   generalization found by brute force; the commutativity tuple gives
   `((+ ?v0 ?v1) (+ ?v1 ?v0))`.
2. *Bucket AU.* The parts of the GF(7) `*` frame give `(* ?K c)`, and
   representative AU gives a bare variable (\S4.3).
3. *Lossless frames.* Pattern plus frame decode to the original entries,
   printed identically, for the operator tables and for a sequence store.
4. *Order invariance.* Ten shuffles of each store give the same patterns and
   frames up to variable names.
5. *Planted patterns.* Stores of $10^3$, $10^4$ and $10^5$ entries of mixed
   types hold 5 planted patterns of one to three templates, connected by
   tags or by shared values (for example `(a ?x)` at tag $t$ and
   `(b (+ ?x 3))` at $t + 1$, 100 instances each), among noise entries of
   the same types. At least 95 % of the planted patterns and their frames
   are recovered, no other pattern is accepted by the null-checked DL, and
   time against store size is reported.
6. *Timings.* Index construction and grouping by skeleton for $10^5$
   entries; tuple LGG over $10^4$ instances.

### M1 --- P1: algebra from the store

*Setup.* The store holds the full tables of `+` and `*` over GF($p$) for
$p \in \{5, 7, 11, 13, 59\}$ (7 690 entries). For laws, for each $p$, 64
random instances of $(a, b, c)$ share one depth-2 expansion over $a, b, c$
and the constants 0 and 1, stored as one fingerprint entry per expression
(\S2.1). A variant has `neg` as a base operator and no constants (plan 1
M0).

*Procedure.* Frames by skeleton (M0); quotients in each frame (all
directions; partitions where no relation holds on all rows; AU over
buckets; lifted children; tabled operators); laws from fingerprint
collisions, kept if they survive universal validation and are minimal (not
an instance of a kept law, not one rewrite away from kept laws: plan 1
\S6.2); laws oriented into rewrite rules; rule entries anti-unified across
$p$; propagators assembled from the solve rules of each relation.

*Measurements.* Laws found and rejected; solve rules with their guards and
fiber profiles; tabled operators; time; sizes of the enumeration with and
without the rewrite rules; decoding time of the same tasks by fiber search
and by solve rules, for $p = 59, 251, 65521$.

*Exit.*

(a) For every $p$, the three directions of `+`, verified on all rows.
(b) For `*`: the forward direction only on all rows; the guarded inverse
    with its fiber profile (1 where $a \ne 0$, $p$ at $(0, 0)$, 0 at
    $(0, c \ne 0)$); `(* ?K c)` with `inv` intensional for $p = 5$ and
    tabled ($p - 1$ entries) for $p \ge 7$.
(c) For every $p$, the laws $a + b = b + a$, $ab = ba$, both associativities,
    distributivity, $a + 0 = a$, $a \cdot 1 = a$ and $a \cdot 0 = 0$, and no
    false law (each checked exhaustively, at most $59^3$ points). Extra laws
    are reported, not required.
(d) $?K = p - 1$ from the rule entries alone, and the rule instantiated for
    $p = 17$ and $p = 19$ and verified.
(e) Propagators: on 1000 random networks of 5 to 10 `+` and `*` constraints
    over GF(7) with random partial domains, propagation with the learned
    solve rules reaches the same fixpoint domains as propagation by
    brute-force projection of each constraint (generalized arc consistency).
(f) Rewrite rules: the fraction of depth-2 buckets whose members all
    normalize to one form is reported. If it is below 90 %, completion
    (Knuth--Bendix) or an e-graph is the next step (plan 1 \S7.6, trigger c).
(g) Order invariance (M0, test 4) on this store.
(h) Derivation bits: the rewrite rules shrink the depth-2 expansion of M2's
    suites by a measured factor with unchanged answers, and solve rules cut
    decoding time by a factor of about $p$.

*What failure would mean.* If (a) to (d) need frames or roles supplied by
hand, the AU half of P1 is not doing the work. If (c) admits a false law,
validation is insufficient. Either stops M2.

### M2 --- P2 with observed residuals

*Setup.* Values in GF(251), tags naturals, and M1's library (laws for
canonical AU, solve rules for lifts and isolation). The suites are stored as
element entries.

- *S1, about 20 sequences:* plan 1's M0 list (`2 4 6 8 10`; Fibonacci;
  squares; `1 2 4 7 11 16`; `3 3 3 3 3`; `5 7 5 7 5 7`; `3 6 12 24 48`;
  `1 3 7 15 31`; `1 -1 1 -1 1`), plus cubes and fourth powers (residual
  rounds), the interleaving `1 10 2 20 3 30` (a partition and a join across
  parts), triangular numbers (`x0 = (+ x1 i)`), a period of 3,
  `x0 = (* x1 x2)`, `x0 = (+ (+ x1 x1) x2)`, `x0 = (* x1 x1)`, and a constant
  with one exception (`3 3 3 7 3 3`, a partial finding).
- *S2, 12 list tasks with 2 or 3 examples each:* identity, add 1, double,
  reverse, rotate, drop the first, shift right with fill 0, prefix sums,
  pairwise sums, constant output, swap adjacent pairs (a partition by
  parity), take every other element.

*Procedure.* The engine of \S3 runs from each task's entries. The program is
the accepted rules plus bare facts, verified by forward execution, and its
prediction is checked on a held-out continuation (S1, three elements) or a
held-out example (S2).

*Baseline.* Blind enumeration of explicit generators (S1) or index maps
(S2) of size up to 7, at equal wall time (plan 1 M3).

*Nulls.* 200 random sequences and 50 random list tasks: nothing accepted.

*Exit.* All of S1 and at least 10 of S2 predicted exactly; strictly more
solved than the baseline at equal time on the tasks that need a residual
round or an address (cubes, fourth powers, interleaving, reverse, rotate,
swapped pairs); nulls clean; order invariance; per round, the numbers of
seeds, patterns, frames and residual entries reported.

*What failure would mean.* If the baseline matches the engine at equal time,
P2 fails in one dimension, and that is the result.

### M3 --- P3: rules as entries, triggering, utility

*Setup.* Every entry from M1 and M2, with their derivations. Tasks:

- *T1*, 500 isolation problems: solve for $u$ in random equations of depth
  up to 4 with one occurrence of $u$, over GF(7) and GF(59), with ground
  truth from the simulator;
- *T2*, 500 canonicalization problems: random expressions of depth up to 3,
  normalized by the rewrite rules;
- *T3*, the M2 suites again.

*Conditions.* Blind (every rule tried at every subterm); indexed (\S6.1);
indexed with utility (\S6.2); each with and without macros (\S6.3). Library
sizes $L \in \{30, 300, 3000, 30000\}$, inflated with valid but redundant
derived rules (instances and two-step compositions of M1's rules): the
stress test of the utility problem.

*Measurements.* For each task: match attempts, rule applications, simulator
calls, wall time, derivation bits; tasks solved; the answers.

*Exit.*

(a) Indexed match attempts per application grow sublinearly in $L$ (the
    fitted exponent is reported; blind should be near 1).
(b) With utility, wall time at $L = 30000$ is within twice that at $L = 30$,
    and no task is lost.
(c) Macros cut T1's derivation bits by a measured amount, and survive
    utility only where they are used.
(d) The parametric rule of M1 (d) is retrieved through the index for a field
    never seen in experiments (GF(23)), and verified.
(e) The answers are identical across conditions.

*What failure would mean.* If indexed triggering does not beat blind by a
margin that grows with $L$, P3 fails as stated. If utility pruning loses
tasks, its estimates are wrong.

### M4 --- P2 with latent residuals, orderings, partitions

*Setup.* The engine of M2 with the procedure of \S7.

- *L1, switches:* two recurrences with unknown constants over GF(251), mixed
  by a switch that is computable (`(mod i 2)`, `(mod i 3)`,
  `(= (mod i 4) 0)`) or random (100 nulls), including a case where the two
  rules agree on some rows.
- *L2, orderings:* unordered sets whose sorted order has a constant step;
  input-output tasks whose output is the input sorted ascending, sorted
  descending, or sorted by the key `(mod v 5)` with distinct keys, with the
  output given as a set, without tags.
- *L3, ambiguous addresses:* reverse, rotate and swap over 2 or 3 colors,
  where most rows have several sources.
- *L4, stretch* (if wanted, \S12): the sudoku mutex classes from one board's
  rejection clauses, as entries, through votes and hard EM, then described by
  coordinates; compared with Notes \S2.2 to \S2.4.

*Exit.* L1: every computable switch recovered with its guard and exact
constants; on random switches the labels cost at most $n H + 2 \log_2 n$
bits and no guard is accepted on any null. L2: all tasks solved through
orderings. L3: held-out lists exact. L4: the four rules, or a documented
failure. The iterations, restarts and time of latent inference are reported
against the rest of synthesis: the prompt's "as large of a problem as the
program synthesis task".

### M5 --- integers, inequalities, guards, propagators

*Setup.* Values in bounded integers, with exact arithmetic inside
expressions and the coding range $[-64, 64)$ for values (plan 1 \S1.1);
operators `+ - * div mod < =`; tags as before.

*Procedure.* M1 again on integer tables, sampled on $[-16, 16)^2$, with laws
validated by $10^4$ random tests on $[-10^6, 10^6]$. Interval propagators
are learned on a lifted domain: experiment entries
`(prop op (iv la ua) (iv lb ub) (iv lc uc))`, whose output interval is the
exact image computed by the simulator, go through AU and quotients like any
other entries. S1 and S2 run again in integers, plus 6 tasks guarded on
values (for example `x0 = (+ x1 1)` while `(< x1 5)`, else 0; clipping;
absolute difference).

*Exit.*

(a) The laws of M1 that hold in $\mathbb{Z}$ are found again, none of the
    field-only facts (a total inverse of `*` away from 0, wraparound)
    carries over, and every law's domain tag is right.
(b) Solve rules: `b = (- c a)` for `+`; for `*`, `b = (div c a)` guarded by
    $a \ne 0$ and `(= (mod c a) 0)`; `mod` recorded as multivalued, with its
    fiber.
(c) Interval propagators for `+` and `-` exact in every direction on $10^4$
    random boxes, and for `*` exact after a partition by the signs of the
    bounds.
(d) At least 4 of the 6 guarded tasks.
(e) Over $\mathbb{Z}$ implicit generators cannot be decoded by fiber search;
    the number of M2 programs that needed a solve rule to become explicit is
    reported.

### M6 --- heuristics

*Setup.* The signatures of \S6.4 over the tasks of M2, M4 and M5, and a
held-out set of 30 tasks of the same kinds.

*Conditions.* No ordering (canonical order), usage priors only, signatures
only, both.

*Exit.* On the held-out tasks: fewer derivation bits, no task lost, and less
wall time including the work of computing signatures. The contribution of
each signature is reported.

### Order, dependencies, and risks

M0, then M1, then M2. M3 and M4 depend only on M2 and may go in either order;
M5 needs M1 to M4; M6 needs M3's indexes. The risks, in the order the
milestones meet them: matching cost turning AU into enumeration (M0, M2);
false laws or over-general rules (M1); residual rounds not beating blind
enumeration (M2); the utility problem (M3); latent inference growing as
large as synthesis (M4); calibration of DL on small data, which plan 1 and
ARC1 both met (all milestones).

---

## 10. Implementation

SBCL 2.6.4 Common Lisp (installed; plan 1 recorded 2.5.2), with no
libraries, for the reasons of plan 1 \S8.1: s-expressions for everything,
`equalp` hash tables keyed by vectors, exact integers, native compilation of
the inner loops, a REPL and `sb-sprof`.

```
lisploop/
  plan.md, plan2.md, plan.pdf, plan2.pdf, Makefile
  store.lisp   entries, types, tags, the store, indexes      (M0)
  sim.lisp     domains, evaluation with bot, experiments,
               fingerprints                                  (M0)
  au.lisp      tuple LGG, bucket AU, conjunctive matching    (M0)
  dl.lisp      ambient code, fibers, the three accounts      (M0)
  quot.lisp    quotients of a frame                          (M1)
  rules.lisp   rule execution, isolation, propagators        (M1)
               indexes, utility, EBG                         (M3)
  engine.lisp  rounds: seed, grow, quotient, accept, emit    (M2)
  em.lisp      votes and hard EM                             (M4)
  m0.lisp ...  each milestone's demonstrations, as assertions
```

`sbcl --script m0.lisp` runs a milestone's checks; a `make m0` target arrives
with the code. Style as in plan 1 \S8.3: intent docstrings; assertions for
invariants (the true value lies in its fiber; every instance matches its
LGG; a verified program reproduces its entries; a shuffled store gives the
same results); small comments; no capitalized emphasis. Indentation is
still open (\S12).

---

## 11. What carries over from plan 1

| plan 1 | in plan 2 |
|----------------------|--------------------------------------------------------|
| frames (\S1.2) | built by AU from the store (\S2.4), never given |
| expansion and buckets (\S1.4) | the quotient's search for functional relations within a frame (\S2.5) |
| findings and fibers (\S1.5, \S1.6) | unchanged; residuals generalized (\S1.2) |
| transposition (\S2, \S6.3) | unnecessary: every direction of a frame is searched (\S4.1) |
| laws (\S6.2) | from fingerprints of experiments that share inputs; validated; scored in derivation bits (\S1.5) |
| AU across instances (\S5.5) | the central mechanism, over buckets from M1 on (\S4.3) |
| lifts (\S5.6) | residual entries and rounds (\S3) |
| frame operators (\S5.7) | partitions, orderings and tag joins (\S2.5); group-by is a partition |
| meet in the middle (\S5.8) | set-valued residuals and latent choice (\S1.2, \S7) |
| bounds, dominance, memoization (\S7.3, \S7.4) | unchanged, applied to patterns and residual frames |
| e-graphs (\S7.6) | buckets as small e-classes now; the triggers kept |
| milestones M0 to M5 (\S9) | replaced by \S9 here; the 2D and ARC bridge leaves this plan |
| open questions (\S10) | 1 answered by the prompt (GF($p$) first, then integers); 3 answered (no symbolic-regression data); 5 superseded; 2 and 4 still open (\S12) |

---

## 12. Open questions for you

1. *The derivation account.* Laws, solve rules used as procedures, indexes
   and heuristics are scored in bits of work (\S1.5). Is that an acceptable
   reading of "DL is the final metric", or should work only be reported
   next to DL?
2. *Granularity.* One entry per element or execution, as planned, or one per
   sequence or table?
3. *Latent scope.* At most 4 labels per row and backward sets of at most 8,
   at first: acceptable?
4. *The sudoku stretch in M4.* Wanted, or left out as indexing too much on
   the earlier experiments?
5. *The handicap* (plan 1, question 2): keep `-` and `/` out of GF($p$)?
6. *Order of M3 and M4.* Triggering first, as listed, or latent residuals
   first?
7. *Indentation* in `.lisp` files (plan 1, question 4): spaces as Emacs
   produces them, or tabs?

---

## 13. Related work (short)

New relative to plan 1 \S11, which covers EUSolver, QuickSpec, Ruler,
Enumo, TheSy, FlashMeta, Duet, PRESS, babble, egg, Stitch, DreamCoder and
the conserved-quantity literature.

- **Information and reversibility.** Landauer (1961); Bennett (1973);
  Jarzynski (PRL 1997); Sagawa and Ueda (PRL 2010), the generalized
  Jarzynski equality with mutual information. Xu, Zhao, Song, Stewart and
  Ermon (ICLR 2020), usable (V-) information; Finzi, Qiu, Jiang, Izmailov,
  Kolter and Wilson (arXiv 2601.03220, 2026), epiplexity: information
  created by computation, for bounded observers.
- **Anti-unification and generalization.** Plotkin (1970); Reynolds (1970);
  Alpuente, Escobar, Espert and Meseguer (Inf. Comput. 2014), order-sorted
  generalization modulo associativity, commutativity and identity;
  Baumgartner, Kutsia, Levy and Villaret (JAR 2017), higher-order pattern
  anti-unification.
- **Analytical synthesis.** Summers (JACM 1977), recursive Lisp programs
  from examples; Kitzelmann and Schmid (JMLR 2006), synthesis of functional
  programs by explanation-based generalization; Hofmann, Kitzelmann and
  Schmid (AGI 2009) and Hofmann (PEPM 2010), IGOR2.
- **ILP.** Muggleton and Buntine (ICML 1988), CIGOL and predicate
  invention by inverting resolution; Muggleton and Feng (1990), GOLEM and
  relative LGG; Semeraro, Esposito and Malerba (1994) and Esposito,
  Laterza, Malerba and Semeraro (1996), subsumption under object identity;
  Maloberti and Sebag (MLJ 2004), theta-subsumption as constraint
  satisfaction.
- **Library learning and labels.** Wong, Ellis, Tenenbaum and Andreas
  (ICML 2021), LAPS; Grand et al. (ICLR 2024), LILO.
- **Rewrite rules from data.** Bader, Scott, Pradel and Chandra (OOPSLA
  2019), Getafix; Bansal and Aiken (ASPLOS 2006), peephole superoptimizers
  over a fingerprint database; Knuth and Bendix (1970), completion.
- **Explanation-based learning and its utility.** Mitchell, Keller and
  Kedar-Cabelli (MLJ 1986); DeJong and Mooney (MLJ 1986); Laird, Rosenbloom
  and Newell (MLJ 1986), chunking in Soar; Korf (AIJ 1985), macro-operators;
  Minton (AIJ 1990), the utility of explanation-based learning; Tambe,
  Newell and Rosenbloom (MLJ 1990), expensive chunks.
- **Matching and mining.** Chandra and Merlin (STOC 1977); Yannakakis (VLDB
  1981); Cordella, Foggia, Sansone and Vento (TPAMI 2004), VF2; Solnon (AIJ
  2010), LAD; McCreesh, Prosser and Trimble (ICGT 2020), the Glasgow
  subgraph solver, and (IJCAI 2017) McSplit; Yan and Han (ICDM 2002),
  gSpan; Cook and Holder (JAIR 1994), SUBDUE; McKay and Piperno (JSC 2014),
  nauty and Traces.
- **Analogy.** Falkenhainer, Forbus and Gentner (AIJ 1989), SME; Kuehne,
  Forbus, Gentner and Quinn (2000), SEQL; McLure, Friedman and Forbus
  (2010), SAGE.
- **Indexing and production matching.** McCune (JAR 1992); Graf (LNCS 1053,
  1995), term indexing; Forgy (AIJ 1982), Rete; Doorenbos (CMU thesis,
  1995), production matching for large learning systems.
- **Propagators.** Sussman and Steele (AIJ 1980), CONSTRAINTS; Radul and
  Sussman (2009), the propagator model; Radul (MIT thesis, 2009).
- **Search, description length, heuristics.** Levin (1973), universal
  search; Schmidhuber (MLJ 2004), OOPS; Odena and Sutton (ICLR 2020),
  property signatures; Odena et al. (ICLR 2021), BUSTLE; Celeux and Govaert
  (1992), classification EM.
- **State.** Crutchfield and Young (PRL 1989) and Shalizi and Crutchfield
  (J. Stat. Phys. 2001), causal states; Littman, Sutton and Singh (NIPS
  2001), predictive state representations.
- **Verification by probes.** Schwartz (JACM 1980); Zippel (1979).
- **Energy.** Horowitz (ISSCC 2014).

---

## 14. Progress log

Kept short: one entry per milestone, with the measured exit criteria.
Nothing yet.
