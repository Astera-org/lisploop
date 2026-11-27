# Citation check: abstraction-guided synthesis precedents

All seven exist (Crossref). Items 1–6 read as preprints or author copies.

| # | (a) Exists | (b) What it does | (c) Abstraction source | (d) Headline result, verbatim | (e) Status |
|---|---|---|---|---|---|
| 1 Blaze | Yes. PACMPL 2(POPL), 2018. | Finds a program fitting the examples under coarse abstract semantics (abstract tree automaton), refining on concrete failure. Reviewer is right. | Hand-written. §6.2: "the domain expert needs to provide ... a universe of possible predicates ..., the abstract semantics of each DSL construct". | Abstract: "Blaze results in a 90x speed-up over Prose" (matrix). §7.1: "solves 60% more benchmarks (90 vs. 56) and outperforms CFTA by 363x" (108 string tasks). | Checked against paper text |
| 2 Atlas | Yes. CAV 2018, LNCS 10981:407–426. | Learns predicate templates and transformers for Blaze. | Domain: learned from four training problems per domain via tree interpolation. Transformers: fitted from random operator samples (not training problems), then validity-checked against hand-supplied operator axioms. | §7.2: "an average 8.3× speed-up over Blaze†" (string; † = hand-written), "an overall speed-up of 9.2× on average" (matrix). Fig. 8: only 2.1× / 3.1× on Blaze's original benchmarks. | Checked against paper text |
| 3 Simba | Yes. PACMPL 7(PLDI), Art. 174, 2023. | Top-down enumeration pruned by alternating forward and backward abstract interpretation. | Hand-designed by the authors. §1: "Our method requires a highly precise abstract domain for the target application." | Numbers correct. §1: "for the 544 non-conditional bitvector-manipulation problems, Simba is able to solve 519 problems ... compared to only 456 and 409 by Duet and Probe". Set: 44 Hacker's Delight + 500 deobfuscation tasks. Omitted (Fig. 3d): all 1,875 tasks, 1716 vs. Duet 1671; on 750 conditional tasks Duet wins 646–619. | Checked against paper text |
| 4 Absynthe | Yes. PACMPL 7(PLDI), Art. 171, 2023. | User supplies an abstract specification and tests; search prunes abstractly, then runs candidates. | User-written. | §5.1: "Absynthe solves around 77% of the benchmarks" (SyGuS strings). §5.2: "Absynthe solves 17 programs, the same number of programs as AutoPandas neural model" (of 29, my count). Correction: Ruby is the implementation language, not a benchmark. | Checked against paper text |
| 5 Amurth | Yes. PACMPL 6(OOPSLA2):1291–1319, 2022. | Builds transformers for static analyzers; not an example-driven synthesizer. | Domain user-supplied. Transformers synthesized from a logical operator specification plus a user-written grammar; "most-precise" means best within that grammar. | Abstract: "four of the existing transformers were unsound". §5.1: "synthesizing 57 transformers". | Checked against paper text |
| 6 Merge-and-Shrink | Yes. JACM 61(3), Art. 16, 2014. | AI planning: merges per-variable abstractions and aggregates states to get admissible heuristics. | Computed automatically per task, by (greedy) bisimulation. No training. | §1: perfect heuristics "in polynomial time in three of the six classical planning benchmarks that have polynomial-time optimal solution algorithms". §8.2: "all the competitors (except “PDB (a)”) do better in terms of total coverage". | Checked against paper text (Fig. 9 unreadable) |
| 7 Knuth | Yes. IPL 6(1):1–5, 1977. | Per Nederhof (2003): extends Dijkstra to lowest-weight derivations of a context-free grammar with "superior" weight functions. | Not applicable. | None verified. | Could not fetch (publisher 403); secondary source only |

## Q-A

None found. Closest is Atlas: its transformer step generates examples "by evaluating F on randomly-generated inputs" (§5.1). Differences: it fits a symbolic affine formula, not a table grouped by abstract value; samples and result are validity-checked against hand-supplied operator semantics; the domain comes from training tasks.

Next closest:
- Moito (Johnson et al., OOPSLA 2024) derives interval semantics "for free from the concrete semantics" for monotone operators, without sampling. Its abstract says abstraction-based pruning generally "requires manually designed, domain-specific abstract domains and semantics".
- Nye et al. (ICLR 2021) train "a separate neural module" per DSL function as approximate semantics; unsound, no partition.

Queries: sampling-learned transformers; lookup-table transformers; black-box specification inference by execution; unsound data-driven abstraction; value clustering with transition tables; learned abstract semantics 2024–2025.

## Q-B

Origin confirmed second-hand: Feret et al. (2010) cite Kemeny & Snell, *Finite Markov Chains* (1960) for "A Markov chain is lumpable ... if the lumped chain preserves the Markov property"; Wikipedia concurs. Book not fetched.

No use found in program synthesis (four queries: with program synthesis, abstract interpretation, programming by example, syntax-guided synthesis); it surfaced only in Markov-chain model reduction. Merge-and-shrink says "bisimulation" instead.

Sources: arXiv 1710.07740, 1804.04152, 2304.10768, 2302.13145, 2105.00493, 2408.15822, 2012.12964, 1011.0496; ai.dmi.unibas.ch/papers/helmert-et-al-jacm2014.pdf; aclanthology.org/J03-1006.
