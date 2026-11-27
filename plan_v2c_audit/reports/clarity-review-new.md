# Clarity review of the parts written this round

Reviewed file: `/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/round3/v3-for-check.md` (frozen copy; all line numbers are of this file).

Scope read in full: front matter (L1-45), §1 (L47-116), §6 (L627-811), §7.2 (L841-895), §7.4 to §7.6 (L911-998), §8.0 (L1000-1006), §8.5 (L1101-1135), §8.7 (L1188-1270), §8.8 (L1272-1283), §10 rows 4, 7, 9, 12, 13, 14 (L1346-1356), §11.1 and §11.2 (L1376-1409). I read §5, §7.1, §7.3, §2.7, §2.8, §9 and the appendices only to follow cross-references and to see where terms are defined.

This is a review for clarity. I did not check any number against a log, and I did not judge the design. Where a rewrite needed a fact that the text does not give, I say what is missing and do not supply it. Where a rewrite rests on my reading of an unclear passage, I say so, and the author should confirm the reading before using the rewrite.

---

## 0. What I understood after one straight read of §6 and §7.2

I read §6 and then §7.2 once, in order, before anything else. This is what I came away with, and where the text lost me.

**"One question at two resolutions."** The one question is: how many bits does it take to write column B once columns A are known (L637). A resolution is how much of each value is kept. At full resolution the columns hold the values themselves. At coarse resolution they hold labels of the values. At each resolution the answer is either "nothing is left over" or "something is", which gives four cases.

I could state that much. I could not state confidently how "two resolutions" relates to the "two ways to compute" of §6.1, and this is my most important finding. The text gives three two-way distinctions and never sets them side by side:

- the *method*: by correction, row by row, or by counting, over groups (L641-647);
- the *resolution*: values or labels (L655);
- the *outcome*: nothing left over, or something (L655).

The section opens by saying the three jobs of geometry "are one question asked at two resolutions" (L631), and §1.3 summarizes the design in those words (L79). Then L670 says "the honest statement is the one in §6.1. There is one question, and there are two ways to compute the answer." So by the end of §6.2 the organizing idea has changed from resolution to method, and the next paragraph is headed "What each resolution can see" (L672) while it compares labels with corrections, which is one resolution against one method. On top of that, the second bullet at L667 says that a law is found by a third test (hashing a column into its class), which is neither counting in groups nor correction, and yet L670 says "Counting serves three of the four cases". After one read I could not say whether the design has two mechanisms or three, nor which mechanism answers which cell of the table, without going back and assembling it from the three bullets at L666-668. Section B1 proposes a fix.

**Quotient, label, verb table.** A quotient is a small term that takes a value to one of a few labels, such as `(sgn x)` (L653). A label is one of the values that term can return. A verb table is, for one operator and one quotient, the table from the labels of the inputs to the labels the output was seen to take, with counts (L660, L707). These three I could state confidently. The definition at L653 with its three examples is clear.

I could not state what a *word* is. The table of terms (L35) and the table in §6.4 (L706) say that the labels are the words. From L714 onward a word has labels ("a word with k labels", L732; "Words need several labels", L753), and "six words" and "six quotients" name the same six things (L714, L718, L1192). So a word is a label in two places and a quotient everywhere else. See A1.

**The four cells of the table in §6.2.** Top left: an exact fact at full resolution (a law, an invariant, an inverse). Top right: a near miss, whose leftover is a residual column priced by the codec. Bottom left: an exact fact about labels (the parity of a sum is determined by the parities of its parts). Bottom right: a tendency, recorded in a verb table. I could state these from the table, which is the clearest thing in the section.

Two things blurred the bottom row. First, the example given for a tendency is "Doubling a non-empty list always makes it all-even" (L660). That is an exact fact by the table's own definition, so the one example that should show the difference between the two bottom cells belongs in the other cell. Second, "exact" in the bottom-left cell turns out, at L771, to mean "one output label in every probe", which "is still a sample". So the left column is not uniformly "what the kernel can come to rely on" (L662). See A13.

**The order in which a search uses them (§7.2).** (1) Run every stored solution of the right type on the new rows; if none fits, label the inputs and the target, and let the verb tables order the operators. (2) Run a tentative pass that skips a candidate, before evaluating it, when its tables say it cannot give the target's labels. (3) If that finds nothing, run plain enumeration, and compare each evaluated candidate with the target by the correction code; a constant or regular residual proposes a `decode`, and agreement on most rows proposes an `if`, which is held and not accepted. (4) Once a split is held, its size bounds the rest of the search, so classes that cannot reach the target within the bound are not stored. Whatever the route, a finished program is verified on every row and accepted by description length alone. Tables are written between searches by the agenda and only read during a search.

I could state the order. Four things I could not state:

1. *How the "one move" relates to the "four steps".* The first half of §7.2 describes a top-down search: choose a hole, refine it with a construct, split the requirement (L845). The second half describes a bottom-up search: "Each candidate is an operator applied to classes already in the bank" (L875). No sentence says how the two fit together. I inferred from the first table row ("a leaf from the context ... this is enumeration by class") and from the Control list (L892) that the four steps describe leaf enumeration on one problem, and that step 3 is where it proposes refinements. That is an inference; the text should say it. See B2.
2. *What the label test asks of a candidate that is not the last step.* Step 2 says "given the labels of its arguments, can its result have the target's labels?" (L875). Read literally, that discards every intermediate class. In the running example `(sort (abs xs))` is (1, 2, 3, 4), which is not all-even, and the answer is built from it. §8.7 gives the real test ("within the size that remains", L1192). See A27.
3. *Which two things the four steps change from the review's proposal* (L871). The text promises two and does not name them. See A21.
4. *Where the running example ends.* It is used in step 1, replaced by `(reverse c)` in step 2, replaced by a different target in step 3, and absent from step 4. I never saw the answer found. See A25.

**What was measured against what was only proposed.** Measured, in Python, on a library of 61 operators written for the experiments: the gain from verb tables, from ordering alone, and on never-used operators; how many answers are lost under each way of choosing probes; that labels act on the last step and corrections rank weakly; the two near-miss proposals; the procedure for choosing words. Measured in the Lisp store prototype: that a strict label filter loses guard splits, and that a held split's bound cuts candidates and stored classes. Measured on the kernel's own codec: the properties of the present correction codes (§8.5). Proposed and not tested: all of this inside the kernel; words as ready-made guards and as k-way splits; the price of a name; words from VM faults and from the derivation space; a learned search policy as a verb table for moves; ranking refinements by tables of constructs.

Here I was unsure on two points. First, each of the four steps carries its own **[M]** number, and the text never says whether the four steps were run together as one search. Line 728 ("with the fallback for the lost tasks counted it was 6.6×") suggests a tentative pass with its fallback was run at least once, and X4 (L1404) reads as if the combination is still to be tested. One sentence in §7.2 would settle it. Second, five statements of measured results in §6 and §7.2 have no entry in §8.7, which is the section where these measurements are recorded (B14). A reader who goes there to see the measurement finds nothing.

---

## A. Unclear or telegraphic passages

Forty items, most important first within each group. "Cannot tell" is what a careful first reader is left unable to say.

### Terms

**A1. "Word" means a label in two places and a quotient everywhere else.** L35, L706, L79, against L732, L748, L753.

> L35: "The labels are the words of the kernel's vocabulary (§6.2)."
> L706: "its labels are the words"
> L79: "a vocabulary is a set of such labels"
> L732: "a word with k labels splits a space into k sub-spaces at once"
> L753: "*Words need several labels.*"

Cannot tell: whether "sign" is a word and "negative" a label, or "negative" is the word. The text from §6.4 on uses the first sense, so the rewrite below changes the three places that use the second. If the author intends the second sense, then L714, L718, L732, L748, L750, L753, L1209 and L1256 need changing instead.

Rewrite of L35: "A quotient of values is a small term that takes a value to one of a few labels, such as its sign. A quotient that the kernel keeps in its vocabulary is called a word. So "sign" is a word, and "negative", "zero" and "positive" are its labels (§6.2)."

Rewrite of the cell at L706: "the quotient is the word, and its labels are what the word can say of a value; two values with the same label are alike in that respect".

Rewrite at L79: "a vocabulary is a set of such quotients, which this plan calls words, and a description of a program is the program run on labels."

**A2. The table of terms omits nine terms that §6, §7.2, §8.7 and §11 use as fixed vocabulary.** L19-43.

Cannot tell, at first use: what a *gain* is (first used L714, defined L1192); what *plain search* is (L875, defined L1192); what a *candidate* is (defined L1006, and used in a second sense in §6.5, see A3); what the *reserve* is (L875, described only at L621 and L1307); what a *split* or *guard split* is (L726); what it means for an answer to be *held* (L879); what the *size-order rule* is (L883); what a *look-ahead* is (L1251, never defined, see A9); what *one step from the answer* and *true parent* mean (L668, L672).

Proposed rows, each built from sentences already in the document. The two marked with an asterisk rest on my reading and need the author's confirmation.

| Term | Meaning |
|:--|:--|
| *candidate* | One operator applied down one column, that is, to classes already in the bank (§8). A candidate word (§6.5) is a different thing and is always called by that name. |
| *plain search* | Bottom-up enumeration of terms by size that keeps one term per class and uses no guidance (§8.7). |
| *gain* | The number of candidates that plain search evaluates on a task, divided by the number a method evaluates on the same task (§8.7). |
| *reserve* | The present kernel's rule for dividing a budget: three parts go to a tentative attempt and one part is kept for the fallback (§9). |
| *split*, *guard split* | A program of the form `(if g a b)`, in which a guard `g` divides the rows between two smaller programs (§7.2). |
| *size-order rule* | A split is never accepted ahead of a smaller term that has no split (§8.5). |
| *held* | A program that fits the rows is held when it is kept as a provisional answer while the search checks that no smaller program also fits (§7.2). |
| *look-ahead* * | The test of whether the target's labels can still be reached from a class within the size that remains. A class that fails it is not stored (§7.2, §8.7). |
| *one step from the answer*, *true parent* * | A class is one step from the answer when one more operator applied to it gives the target. The true parent is the class of that kind from which the answer is in fact built (§8.7). |

**A3. The procedure for choosing words uses "candidate" and "pair" in new senses and leaves two steps incomplete.** L745-748.

> "1. *Enumerate candidates.* A candidate is a small term whose value is one of at most eight labels: a term of up to five nodes over the library's operators together with `sgn`, `mod`, `<`, `=`, and small constants, or a pair of two such terms. ...
> 2. *Score each by the dependency test.* For each operator, how much of the uncertainty about the output's label do the inputs' labels remove? ...
> 3. *Choose greedily, skipping repetition.* Take the best-scoring candidate, then the best that does not largely repeat one already taken, and so on. ...
> 4. *Pair words across types.* A word on lists is paired with a word on integers by scoring the pair on the operators that take a list to an integer, so that the labels of `sum`, `head`, and `len` mean something."

Cannot tell: (a) that "candidate" here is a candidate word, when a page earlier "the search evaluates 14 to 18 times fewer candidates" (L718) meant candidate programs; (b) that "a pair of two such terms" in step 1 is one word made of two terms, while "the pair" in step 4 is two words, one per type, and "pairs of labels" at L761 is a third thing; (c) how the per-operator figures of step 2 become one score for a word; (d) what is compared in step 3 to decide that one word "largely repeats" another; (e) whether step 4 happens before or after the greedy choice, and what "mean something" means.

Rewrite, with the gaps marked:

"1. *Enumerate candidate words.* A candidate word is a small term whose value is one of at most eight labels. It is either a single term of up to five nodes over the library's operators together with `sgn`, `mod`, `<`, `=`, and small constants, or a *two-part word*, which is the values of two such terms taken together. Two candidate words that sort the probe values into the same groups count as one, whatever their labels are called.

2. *Score each candidate word by the dependency test.* For one operator, the score is the share of the uncertainty about the label of the output that the labels of the inputs remove. [Missing: how the scores for the separate operators are combined into one score for the word.] A word whose label is the same for every output scores zero, since it predicts nothing.

3. *Choose greedily, and skip repetition.* Take the best-scoring candidate word. Then take the best one that does not largely repeat a word already taken, and so on. [Missing: what is compared to decide that one word largely repeats another.] Without this step the first six words are all versions of the length.

4. *Match a word on lists with a word on integers.* Some operators, such as `sum`, `head`, and `len`, take a list and return an integer. Their tables need a word for the list that goes in and a word for the integer that comes out. A list word and an integer word are therefore scored together on those operators. [Missing: whether this is done before or after step 3, and how the match is chosen.]"

Then say "candidate word" at L752, L757 and L967, and "two-part word" at L753 ("Most of the words with many labels are two-part words") and L755 ("to each of the two parts of a two-part word").

**A4. "Correction" is a defined term (L34) and is also used for two other things.** L768, L737, L918, L877, L659.

> L768: "*No correction of tables during search.*"
> L737: "and from counts only as a correction that cannot price a name out **[P]**"
> L877: "Each candidate it evaluates is compared with the target, which costs one correction (§6.1)."

Cannot tell: at L768, whether this is about the correction code; at L737, what "price a name out" means; at L877, how a cost can be "one correction" when a correction is itself a number of bits.

Rewrite of L768: "*Tables are not repaired during a search.* The review first proposed to add to the tables whatever a fallback search discovers, and then dropped the idea. With good probes there was nothing left to add."

Rewrite of the last sentence of L737: "So a name's price comes first from its tables. Counts of past use may adjust that price afterwards, and the adjustment is limited so that it can never make a name too dear to be tried **[P]**."

Rewrite at L877: "Each candidate it evaluates is compared with the target. The comparison is one computation of the correction code of §6.1."

At L918 ("counts as a correction to them") use "counts as an adjustment to them".

**A5. "Free" means "costs nothing" in rules 1 and 5 and "not derived" in rule 4.** L682-688.

> L685: "A column no term derives is *free* and costs its code."
> L688: "A move is good when it turns an expensive free column into a term plus a cheaper free column."

Cannot tell: how a free column can be expensive. Rule 1 says a bijection "transfers code lengths for free" and rule 5 is headed "An exact cell is not free", both in the sense of cost.

Rewrite of rule 4: "**The graph gives the coding order.** Code the columns in dependency order. A column that a term derives from earlier columns costs only the bits of the term. A column that no term derives is called *underived* here, and it costs the full code of its cells. The total over all columns is the description length."

Rewrite at L688: "A move is good when it replaces an expensive underived column by a term plus a cheaper underived column."

**A6. "The agenda" in the Control list is not the agenda of the table of terms.** L891, against L40.

> L40: "The list of small problems the kernel poses to itself between searches (§7.5)."
> L891: "The agenda holds problems. A problem's budget is an account that can be topped up, so every problem is resumable and can be re-opened."

Cannot tell: whether the open sub-problems of the task being solved sit on the same list as the questions the kernel poses to itself between searches. Line 887, four lines earlier, says the agenda works "between searches".

I cannot rewrite this without knowing the design. If there is one list: "There is one agenda. It holds the open sub-problems of the tasks being solved, and also the small problems the kernel poses to itself between tasks (§7.5). A problem's budget is an account that can be topped up, so every problem can be resumed and re-opened." If there are two, the list inside a search needs its own name, and L40 stays as it is.

**A7. "The review" names the outside review in most of §6 and a literature review in other places.** L779, L954.

> L779: "That is the one principled, gradient-free criterion the review found for "when is a new space needed", and the kernel already has it."
> L954: "and the review found no system that learns termination guards from timeouts"

Cannot tell: which review. In §6.2, §6.4 and §6.5 "the review" is the outside review `plan_v2c_audit.md`. At L576, L954 and L1350 it appears to be one of the three literature reviews. L779 could be either.

Fix: write "the outside review" or "the literature review" in full at L779 and L954. I do not know which is meant at L779.

**A8. In the §8.5 table, "Stage A" is the present kernel's phase, the Kraft sum is called "the code lengths", and one clause can be misparsed.** L1133, with rule 5 at L686.

> L1133: "broken wherever cells are priced one by one, because an exact cell costs 0 bits: the code lengths sum to 1.5 for Booleans, 1.19 for GF(5), and 1.41 for integers, where a prefix code allows at most 1. Stage A does not price cell by cell, and leaves one bit per model unpaid instead. The row-by-row sum occurs in `induce-row-order`, which only tests call"
> L686: "the lengths sum to more than a prefix code allows. In a column priced row by row, every cell's code must include the zero"

Cannot tell: what sums to 1.5 (code lengths in bits cannot sum to 1.5 over several code words; the quantity bounded by 1 is the sum of 2 to the power of minus the length); which Stage A is meant (the table of terms at L42 promises "the text says which is meant", and Appendix D at L1556 shows it is the present kernel's first search phase); and whether "which only tests call" means "which is called only by tests".

Rewrite of the cell at L1133: "Broken wherever cells are priced one by one, because an exact cell costs 0 bits. A prefix code requires that 2 to the power of minus the length, summed over all code words, be at most 1. Here that sum is 1.5 for Booleans, 1.19 for GF(5), and 1.41 for integers. The present kernel's first search phase, which its code calls "Stage A" and which is not Stage A of this plan, does not price cell by cell, and leaves one bit per model unpaid instead. Pricing cell by cell occurs in the function `induce-row-order`, which is called only from the test suite."

Rewrite of rule 5 at L686: "**An exact cell does not cost zero.** Suppose a cell that matches its prediction costs zero bits while every other cell pays a full prefix code. Then the code breaks the bound that every prefix code obeys: the sum over all code words of 2 to the power of minus the length exceeds 1. So in a column priced row by row, the zero correction must have a code word of its own, and an exact cell costs at least one bit. One more bit per column can then say that the whole column is exact. The kernel avoids the violation in its main pricing path only because it lists exception rows with their indices, and what it leaves unpaid there is one bit per model. A store that prices a residual column row by row would not avoid it (§8.5)."

**A9. "Look-ahead", "label filter", "strict filter" and "label test" are four names, and the reader cannot tell whether they are one mechanism or several.** L1251, L1266, L1276, L1279, L1349, L1394, L1395, L1403.

> L1251: "*Labels pay as a look-ahead, once a size bound exists.*"
> L1266: "stored classes fell 2.4×, or 7.1× with a one-step look-ahead"
> L1403: "with and without the bounded look-ahead of §7.2"
> L1349: "the label test moves that wall only for ring arithmetic with a target"

Cannot tell: what a look-ahead computes; what makes one "one-step"; whether the "label test" that saves memory is the same thing; and where in §7.2 the "bounded look-ahead" is, since §7.2 never uses the word.

Missing: a definition. From L1192 ("cannot give the target's labels within the size that remains") and L1264 ("a class whose residues cannot reach the target's within the size bound is not kept") my reading is the following, to be confirmed. "Starting from the labels of a class, the verb tables say which labels can be reached in the number of operators that the size bound still allows. If the target's labels are not among them, the class cannot lead to the answer within the bound. Used before a candidate is evaluated, this test is the *label filter*. Used before a class is stored, it is the *look-ahead*. A *strict* filter is one that skips every candidate that fails, with no tolerance for a few mismatched rows." Put the definition in step 4 of §7.2, and use "look-ahead" there, so that X3's pointer lands on something.

### Section 6

**A10. The list of correction rules is a string of noun phrases.** L643.

> "its correction rules price a value given a prediction of it: for integers, a universal code of the difference, so roughly its logarithm; for Booleans, which rows differ; for sequences, a correction per position and a change of length; for code, an anti-unification edit. ... Given nothing better than a prediction of zero it costs 29."

Cannot tell: what is charged for one Boolean value ("which rows differ" describes a column, and the sentence is about a value); what "an anti-unification edit" is; where 29 comes from.

Rewrite: "**By correction, row by row.** The kernel's codec assigns every value a prefix code. It also has a correction rule for each type of value, which prices a value when a prediction of it is given. For integers, the rule codes the difference between the value and the prediction with a universal code, so the price grows roughly as the logarithm of the difference. For Booleans, [missing: what one cell is charged; the present text describes a whole column]. For sequences, the rule charges a correction for each position and a further amount for a change of length. For code, the rule charges for the edit that turns the predicted expression into the true one. [Missing: one clause on how that edit is found; the text says only that anti-unification is involved.] For example, suppose a candidate's column is `u` = (7, 5, 4, 0) and the target is `y` = (8, 6, 5, 1). Each row is off by one. A difference of one costs 4 bits in the present integer code, so `y` costs 4 × 4 = 16 bits given `u`. Given only a prediction of zero on every row, `y` costs 29 bits. These per-type codes are the basic sense in which two things are close. They work on a handful of rows, because each row is priced on its own."

**A11. Two short statements in §6.1 that the reader has to decode.** L645, L649.

> L645: "So the tariff and the metric are one object."
> L649: "Being concave, it has no averages and no angles, and it favours a few exact hits over many small errors."

Cannot tell: what "the tariff" is (the word is not in the table of terms and appears in §6 only here and in a quotation at L737); why "So"; what it means for a distance to have "no averages and no angles".

Rewrite of L645: "So the price list and the distance are one object. The price list, which earlier plans called the tariff, says how many bits a correction costs. The distance from a prediction to a value is that same number of bits. Plan 7 said the same of decoders: "A metric and a decoder shell are two views of one correction code.""

Rewrite of the sentence at L649, on my reading of it: "The integer distance is concave in the difference, and two consequences follow. First, the distance does not come from a vector space, so the average of two values and the angle between two differences have no meaning under it. Second, an error concentrated on a few rows costs less than the same total error spread thinly over all rows. The code therefore prefers a candidate that is exactly right on most rows and far off on a few to a candidate that is slightly off everywhere."

**A12. "Ledger" at L641 is the bit account, and elsewhere the ledger is the work account.** L641.

> "both give bits, so both go in the same ledger."

Cannot tell: whether this is the ledger of work units of §7.1 ("The ledgers of work spent are exact", L817). It is not; it is the description length.

Rewrite: "Both give an answer in bits, so both can be added into the same description length."

**A13. The example of a tendency is an exact fact, and the bottom-left cell does not say what its table is.** L660.

> "| **Coarse resolution:** their labels | An exact fact about labels. The operator has a small table of its own on them: the parity of a sum is determined by the parities of its parts. | A *tendency*. The operator's **verb table** records which output labels were seen to follow which input labels, with counts. Doubling a non-empty list always makes it all-even. Filtering it says little about its parity. |"

Cannot tell: what separates the two cells, since "always makes it all-even" is "nothing left over"; whether the "small table of its own" in the left cell is a verb table; and whether "exact" means proved or seen on the probes (L771 says it is "still a sample").

Rewrite. First define the verb table in the sentence before the table, since both cells need it: "For one operator and one quotient, the operator's **verb table** records which output labels were seen to follow which combination of input labels, with counts."

Left cell: "An exact fact about labels. In the operator's verb table, every combination of input labels was followed by exactly one output label. Two examples: the parity of a sum is determined by the parities of its parts, and doubling a non-empty list always gives a list whose elements are all even. "Exact" here means exact on the probe rows; §6.5 says which of these facts can be proved."

Right cell: "A *tendency*. Some combination of input labels was followed by more than one output label, and the counts say how often each occurred. An example: filtering a list says little about the parity of what remains."

**A14. "What each resolution can see" uses four terms before defining them.** L668, L672.

> L668: "it was undefined for 41–43% of the classes one step from an answer"
> L672: "On a library of 61 operators that is not what was measured (§8.7) **[M]**. ... Corrections were weakly informative at every distance and too weak to cut on. So with the vocabularies tried, labels are a sharp test of the *last* step, and corrections are a ranking of everything. ... Labels left the true parent tied with other classes in a quarter of tasks"

Cannot tell: what "one step from the answer" and "distance" count; what the "true parent" is; what "too weak to cut on" means; which library of 61 operators (§6 has not mentioned it).

Rewrite of L672: "**What labels can see, and what corrections can see.** The review also argued that labels see several steps ahead while corrections see only the last step. That is not what was measured **[M]**. The measurement was made in Python, on the library of 61 operators that was written for these experiments (§8.7). Call a class *one step from the answer* when applying one more operator to it gives the target, and call the class of that kind from which the answer is in fact built the *true parent*. Among the classes one step from the answer, the labels ruled out nearly half, and never the true parent. Among classes two or more steps away, the labels ruled out none. Corrections carried a little information at every distance, and too little to discard classes by. So with the vocabularies tried, labels are a sharp test of the *last* step only, and corrections give a weak ranking of all classes. The two do complement each other next to the answer. In a quarter of the tasks the labels left the true parent tied with other classes, and in about half of those ties the correction ranked the true parent first, where chance would give a little over a third. A correction can also do one thing that labels cannot. When a candidate differs from the target by the same amount on every row, the residual is a constant, and the constant names the last step outright."

At L668, write "the classes one step from the answer (defined below)" or move the definition up to there.

**A15. "Except through rule 1 or by paying rule 2" cannot be parsed.** L690.

> "The theory says no induced space can price a residual below its ambient cost, except through rule 1 or by paying rule 2."

Cannot tell: how either exception makes a price lower. Rule 1 says the cost is the same on both sides, and rule 2 adds bits. Also "ambient" and "induced" were last glossed at L276.

Rewrite, on my reading (Appendix A at L1444 makes the same statement and would need the same change): "The ambient space is the problem's original space, and an induced space is one derived from it by a move. The theory says that pricing in an induced space never makes a residual truly cheaper than pricing it in the ambient space. A price found in an induced space is valid in two cases only. If a verified bijection relates the two spaces, the price is the same on both sides (rule 1). If the map is many-to-one, the fiber bits of rule 2 must be added."

**A16. Three bullets that are fragments, and not parallel.** L692-694.

> "- eight unrelated representations of a residual, where the store has one: a residual is a column;
> - a metric that cannot depend on the row, where a column's code can depend on any earlier column;
> - adding program bits sized at the root to residual bits sized in a child space. The fix is to move the child's residual back along the map and price each root row once."

Cannot tell: in each bullet, which half is the present kernel and which is the store; what "sized at the root" means.

Rewrite: "Three facts about the present implementation did (§2.7).

- The code has eight unrelated representations of a residual. The store has one: a residual is a column.
- A frame's metric cannot depend on the row. On the store, the code of a column can depend on any earlier column, and so on the row.
- A sub-problem's score adds two numbers measured in different places: the bits of the program, measured at the root, and the bits of the residual, measured in a child space. The fix is to move the child's residual back along the map to the root, and to price each root row once."

**A17. "The three are one object seen three ways" is asserted for three and shown for two.** L710.

> "The three are one object seen three ways. A quotient that an operator respects carries the operator's large table onto a small one, which is what an analogy does between two operators (§8.6 tested 350 candidate maps between operator tables in 1.3 ms, and 29 held)."

Cannot tell: what it means for an operator to "respect" a quotient; how the verb table (the 'action' row) is the same object as the other two.

Rewrite, on my reading: "The three are closely related. Say that an operator *respects* a quotient when the label of its output is determined by the labels of its inputs. Such a quotient is a map that carries the operator's large table on values onto a small table on labels, and that small table is the operator's verb table. An analogy is a map of the same kind between the tables of two operators. (§8.6 tested 350 candidate maps between operator tables in 1.3 ms, and 29 held.)"

**A18. "Gain" is used before it is defined, and the second bullet drops its verb.** L714-720.

> L714: "They gave a gain of 1.7× on tasks where six words gave 15.7× (§8.7)."
> L719: "Counts of past use do not: used as prices they sent 5 of 8 such tasks past the search's cap."

Cannot tell: a gain in what, against what; "do not" what; how counts are "used as prices"; what "the search's cap" is.

Rewrite of L716-720: "**What it buys in search [M]** (§8.7). The measurements are in Python, on the library of 61 operators written for these experiments. The baseline is *plain search*: bottom-up enumeration by size that keeps one term per class. The *gain* of a method is the number of candidates that plain search evaluates, divided by the number the method evaluates.

- With six quotients listed by hand, the gain is 14× to 18×. The search also takes 1.3 to 4 times less time, and the saving in time is larger at larger program sizes.
- The tables work for an operator that has never appeared in a solved task, because a verb table needs only the operator's own probe rows. Counts of past use do not work for such an operator. When the counts were used as prices, 5 of the 8 tasks that need such an operator ran past the cap of three million candidates. [Missing: one clause saying what "used as prices" does to the order of enumeration.]
- Used only to *order* the operators, with nothing skipped and so no answer lost, the tables give a gain of 6×, against 2.6× for counts."

At L714 write: "Their gain, in the sense defined just below, was 1.7× on tasks where six words gave 15.7× (§8.7)."

**A19. "In one run" gives three numbers with no setting.** L728.

> "In one run the per-task average gain was 16×. The saving summed over all tasks was 12×, and with the fallback for the lost tasks counted it was 6.6×."

Cannot tell: which run; how many tasks; how the probes were chosen; how many tasks the filter lost. §8.7 does not contain 12× or 6.6×, so the pointer in the heading of the list cannot be followed.

Missing: the setting. The sentence should have the form "In one run of [N] tasks, with tables built from [number and kind of] probes, the filter lost [k] tasks. The per-task average gain was 16×. The saving summed over all tasks was 12×. With the cost of the fallback on the lost tasks counted, it was 6.6×." The same run should then appear in §8.7.

**A20. "Each a single leaf, where published guard search stops at about four nodes."** L732.

> "So a vocabulary of words is also a stock of ready-made guards, each a single leaf, where published guard search stops at about four nodes."

Cannot tell: how "a single leaf" and "four nodes" are related.

Rewrite: "A guard is a two-label quotient. So a vocabulary of words is also a stock of ready-made guards. Each word enters a guard as a single leaf, however large the term behind it. That matters because published guard search stops at guards of about four nodes (§5.5). A word with several labels generalizes this: a word with k labels splits a space into k sub-spaces at once **[P]**."

**A21. Two places promise "two things" and do not name them.** L741, L871.

> L741: "Most of the rules hold. Two of the review's reasons for them do not."
> L871: "The order below keeps its outline and changes two things that the measurements of §8.7 forced."

Cannot tell: which two, in either place. For L741 the candidates I found are that the score does not rediscover human concepts (L752), that feeding the library into the grammar is "not a source of compounding" (L754), and that the review's hand-chosen transforms are beaten (L763). For L871 the candidates are that the near-miss check must see every candidate (L881), that the label pass is tentative and acts only on the last step (L875), and that step 4 is new.

Fix: name the two in the sentence that announces them, in the form "... changes two things that the measurements of §8.7 forced. First, ... . Second, ... ." I cannot write the content.

**A22. "Without them" leaves the reader unable to picture the grammar.** L754.

> "With the library's list operators in the grammar the gain was 13.0×; without them, 12.8×."

Cannot tell: what candidate words are built from when the library's list operators are left out. Step 1 (L745) defines a candidate as a term "over the library's operators", and nine of the ten chosen words contain the length (L752). The same paragraph calls re-choosing the vocabulary "cheap insurance" three lines before L757 gives its cost as about 21 CPU-minutes.

Missing: one clause saying what remains in the grammar in the 12.8× run.

**A23. Three numbers in §6.5 that are half stated.** L755, L769, L771.

> L755: "Applying the repetition test to the two halves of a pair as well gave 13.9× and lost no answer, and is the version to build."
> L769: "raised the gain from 17× to 22×, and still lost answers at ten times the probes."
> L771: "a filter that uses only those keeps a gain of 10.2× of 17.0×."

Cannot tell: at L755, that the 13.0× version had lost an answer (§8.7 says one of 60, L1256), so "lost no answer" has nothing to stand against; at L769, ten times what, and how many answers; at L771, what "10.2× of 17.0×" means.

Rewrite of L755: "The 13.0× vocabulary lost one answer of 60. Applying the repetition test to each of the two parts of a two-part word as well gave 13.9× and lost no answer. That is the version to build."

Rewrite of L769: "*No merged quotients.* Merging three quotients into one finer one raised the gain from 17× to 22×. It still lost 10 of 600 answers at 10,000 probes per operator, which is ten times the number of probes at which the separate quotients lost none (§8.7)."

Rewrite at L771: "A filter that uses only those entries has a gain of 10.2×, where a filter that uses every entry has 17.0×."

**A24. Two pairs of percentages that seem to disagree.** L798.

> "it raised solve rates in one domain from 42.6% to 82.0% ... with human rather than synthetic descriptions its best result in that domain fell from 98.2% to 58.6%."

Cannot tell: how a method that reaches 82.0% in a domain has a "best result" of 98.2% in the same domain.

Missing: what differs between the configuration that scored 82.0% and the one that scored 98.2%.

### Section 7.2

**A25. The running example is started and not carried through.** L871-883.

> L871: "Take as the running example a task over whole-sequence operators: from `xs` = (3, −1, 4, 2) produce (2, 4, 6, 8). The answer is to take absolute values, sort, and double."

Cannot tell: at which step the answer is found. Step 1 uses the example. Step 2 illustrates with `(reverse c)`, which is not on the path to the answer. Step 3 changes the target ("Had the target been (3, 5, 7, 9)"). Step 4 has no example at all.

Fix. Carry the first example to its end in step 2, and announce a second example for steps 3 and 4, which need a near miss and a guard that the first example does not have. A possible ending for step 2, to be confirmed by the author since it says what the search would do: "In the running example the tentative pass finds the answer. `(abs xs)` and `(sort (abs xs))` are evaluated, because nothing in their tables puts the target's labels out of reach. At the last step `(double c)` is evaluated for each class `c`, since doubling makes any list all-even, and `(reverse c)` is skipped for `c` = `(sort (abs xs))`, which is ascending." For step 3, open with: "The running example has no near miss, so take a second target." For step 4, an example with a guard is missing.

**A26. The two measured figures in steps 1 and 2 have no baseline.** L873, L875.

> L873: "Ordering alone gave 6× **[M]**."
> L875: "This pass gave about 16× **[M]**."

Cannot tell: six times what, against what; whether the 16× of step 2 includes the 6× of step 1, multiplies it, or is an alternative to it.

Rewrite of L873: "Used alone, with no candidate skipped, this ordering cut the number of candidates evaluated to about a sixth of what plain search evaluates **[M]** (§8.7)."

Rewrite at L875: "This pass evaluated about 16 times fewer candidates than plain search **[M]** (§8.7). [Missing: one sentence saying whether the 16× already includes the ordering of step 1.]"

**A27. Step 2 states the label test in a form that would discard every intermediate class, and uses "the reserve" before it is described.** L875.

> "Before a candidate is evaluated on the rows, its tables are read: given the labels of its arguments, can its result have the target's labels? ... both are reasons it is only a first attempt, run under the reserve with the plain search behind it."

Cannot tell: why `(sort (abs xs))`, whose result is not all-even, is not skipped; whether "a tentative pass" is one sweep or one sweep per size bound (§8.7 says "the size bound is deepened step by step and every pass is counted", L1192, so "pass" also names each round of deepening); what "the reserve" is.

Rewrite of step 2, using the test as §8.7 states it: "2. *A tentative pass that tests labels before evaluating.* Each candidate is an operator applied to classes already in the bank, which is the set of classes enumerated so far on this space. The size of the answer is not known in advance, so the pass is repeated with a size bound of 1, 2, 3 and so on (§8.7). Before a candidate is evaluated on the rows, its tables are read. The question is whether the target's labels can still be reached from the labels this candidate's result can have, within the number of operators that the current bound leaves. For a candidate at the bound itself, the question is simply whether its result can have the target's labels. `(reverse c)` is ascending only if `c` is descending, so at the bound it is skipped for every `c` that is not. For smaller candidates the tables tried so far ruled out nothing (§6.4), so in practice the test acts on the last step. A skipped candidate costs a few look-ups and no evaluation. This pass evaluated about 16 times fewer candidates than plain search **[M]**. It has two limits, and both are reasons it is only a first attempt. Its tables are tested knowledge and can be wrong (§6.5). And it cannot find an answer that needs a guard, because the near miss that a guard is built on fails the labels on the very rows it gets wrong. So the pass runs under the kernel's reserve rule, which gives three parts of the budget to a tentative attempt and keeps one part for the plain search behind it (§5.9, §9)."

Use one fixed word, for example "round", for each repetition at a new bound, here and at L993, L1192 and L1234, so that "pass" always means the tentative pass or the plain pass.

**A28. Step 3 uses `U`, "held" and "ordinary tasks" without saying what they are.** L878-879.

> "the proposal is `(decode U ?r)` with the residual as the new and smaller target. ... the proposal is `(if ?g U ?else)`: a guard is sought for the rows that disagree, and the remainder is solved on those rows alone. Such a proposal is held and not accepted. On ordinary tasks a split that fits the rows was the right program in 2 cases of 64 **[M]**"

Cannot tell: what `U` is; where "some other class with a small term" lives; what "held" means, and whether it is the proposal or the finished split that is held; what makes a task "ordinary".

Rewrite: "   - Write `U` for the candidate. If the residual of the target given `U` is a constant, or is the column of some other class in the bank that has a small term, the proposal is `(decode U ?r)`, with the residual as the new and smaller target for `?r`. For example, had the target been (3, 5, 7, 9), the class with column (2, 4, 6, 8) would leave the constant residual 1. On tasks built to contain such a step this was worth 2.4× to 3.0× beyond what labels gave **[M]**.
   - If `U` agrees with the target on most rows, the proposal is `(if ?g U ?else)`. A guard `?g` is sought that separates the rows that agree from the rows that disagree, and `?else` is solved on the disagreeing rows alone. When both are found, the resulting split fits every row. It is then *held*: it is kept as a provisional answer and is not yet accepted. The reason is a measurement on ordinary tasks, meaning tasks that were not built to need a conditional. A split that fits the rows existed in 64 of them, and it was the right program in 2 **[M]**. So a split is accepted only once every smaller term without a split has been ruled out."

**A29. Step 4 leaves the mechanism, the seven tasks and the cost unstated.** L883.

> "so a class that cannot reach the target within the bound is not stored, and an operator whose result type cannot lead to the target is not enumerated. In the store prototype, on the seven guarded tasks, this cut candidates 36× and stored classes 34× and changed no answer **[M]**. It recovers part of what the size-order rule costs (§8.5)."

Cannot tell: by what test a class "cannot reach the target" (types and labels are named only in the last sentence); which seven tasks ("the seven guarded tasks" has no antecedent; L726 has "7 of 9 guarded runs", L1251 has "the seven guarded runs", and nothing says whether these are the same seven); what the size-order rule costs.

Rewrite: "4. *A held answer bounds the rest of the search.* A held split has a known size. From then on the search needs only programs smaller than that, so it has a size bound. With a bound, two savings become possible. A class is not stored when the types and the verb tables say that the target cannot be reached from it within the bound. And an operator is not enumerated when its result type cannot lead to the target. This was measured in the store prototype, on seven runs of tasks whose answer needs a guard (§8.7). [Missing: whether these are the seven runs of L726 or a different seven.] It cut candidates 36× and stored classes 34×, and it changed no answer **[M]**. Types alone gave the whole saving on five of the seven, and labels were needed on the other two. The saving recovers part of the cost of the size-order rule, which was 625 and 824 times the candidates on the two kernel specs that need a guard (§8.5)."

**A30. "Two further rules" are run together, and "Those splitting laws" points back over two paragraphs.** L867, L869.

> L867: "Two further rules for this table were measured (§8.5). An inverse's guard has two parts with different sources. *Uniqueness* is read from the operator's table by the dependency test. *Existence* needs no search at all: a candidate answer is replayed forward and compared. And a split competes in the same size order as everything else: it is never accepted ahead of a smaller unsplit term."
> L869: "Those splitting laws are Boolean equivalences."

Cannot tell: where the first rule ends and the second begins; uniqueness and existence of what; what "Those" refers to (the nearest antecedent is "the law that splits a requirement" at L863, two paragraphs back).

Rewrite of L867: "Two further rules for this table were measured (§8.5). The first concerns the guard of an inverse. The guard has two parts, and they come from different sources. *Uniqueness* says that the known values determine the unknown argument, and it is read from the operator's table by the dependency test. *Existence* says that some value of the argument gives the known result, and it needs no search at all: a candidate answer is replayed forward and compared. The second rule concerns splits. A split competes in the same size order as everything else, so it is never accepted ahead of a smaller unsplit term."

At L869: "The laws in the middle column of the table are Boolean equivalences." Better still, move the paragraph up to follow L863 directly.

**A31. The Control list has four phrases the reader cannot resolve.** L892-895.

> L892: "When leaf enumeration under a problem reaches its current horizon"
> L893: "Refinements are ranked as candidates are in step 1: by the labels of the problem and the tables of the constructs."
> L894: "Its results should be reported as cost summed over tasks"
> L895: "for guards, and for features (search-engine report, §11)"

Cannot tell: what "leaf enumeration" and "horizon" are; what the table of a construct such as `tabulate` is (step 1 orders operators, not candidates); what "Its" refers to; whether "§11" is §11 of this document; what "features" are.

Rewrite of L892: "*Leaf enumeration* is the filling of a hole with a finished term from the bank, tried in order of size (the first row of the table). It runs up to the size that the problem's present budget allows. When it reaches that size, further budget goes to the next-ranked *refinement* as well as to larger terms. This is what lets budget buy structure (§2.3)."

Rewrite of L893: "Refinements are ranked in the way step 1 orders operators: by the labels of the problem and the tables of the constructs. [Missing: what the table of a construct is, and whether one has been built.] Before any table exists, the order is a short fixed list keyed on types."

At L894: "The results of any tentative pass should be reported as cost summed over tasks, with the fallback counted".

At L895: "(§11 of the search-engine report)", and gloss "features" in a clause, for example "the features the present kernel learns in order to tell rows apart (§2.6)", if that is what is meant.

### Sections 7.4 to 7.6

**A32. Two sentences in §7.4 with unexplained nouns and a loose "It".** L917, L926.

> L917: "replay found all 25 at no more than 57 candidates per task, and an index of past problems found 19 at best (§8.7) **[M]**. Replay's cost grows with the store, so an index may be needed later. The ones tried did not earn their place."
> L926: "The existing `yield-gate` experiment proves the plumbing. It is not on the critical path, and the one learned predictor that exists today learned a constant (§2.6)."

Cannot tell: what an index of past problems is; what "The ones tried" are; what `yield-gate` is (the name appears nowhere else in the document); whether "It" is the experiment or the learned policy.

Rewrite of L917, from the middle: "... replay found all 25, at no more than 57 candidates per task **[M]**. The alternative that was tried is an index: a look-up from a key computed on the new task to the stored problems that have the same key. Depending on the key, an index found between 9 and 19 of the 25 (§8.7) **[M]**. Replay's cost grows with the number of stored solutions, so an index may be needed later. None of the indexes tried was good enough to replace replay."

Rewrite of L926, end: "The present kernel has one experiment of this kind, called `yield-gate` [missing: one clause on what it does], and it shows that the plumbing works. A learned policy is not on the critical path of this plan. The one learned predictor that exists today learned a constant (§2.6)."

**A33. The agenda's six bullets are fragments, although the lead-in calls them questions.** L934-939.

> "- **Laws.** Classes on a standard probe space over `f` and the operators in scope, to a size bound.
> - **Inverses.** Per argument: the dependency test; a guard for the rows where it fails; a small search for the term.
> ...
> - **Lifted forms.** `f` under `tabulate`, `fold`, and `scan`."

Cannot tell: what question each bullet asks, and for "Lifted forms" what is found or recorded.

Rewrite:

"- **Laws.** Which small terms over `f` and the operators in scope have the same column? The agenda enumerates classes on a standard probe space, up to a size bound.
- **Inverses.** For each argument of `f`: is that argument a function of the result and the other arguments (the dependency test)? If that holds only on some rows, which guard picks out those rows? And which small term computes the argument?
- **Definedness.** Which guard picks out the rows where `f` returns an error? The kernel's milestone code already does this for arithmetic (§2.4).
- **Verb tables.** For each word in the vocabulary: which output labels follow which input labels? This is one group-by over `f`'s probe rows (§6.4).
- **Lifted forms.** What does `f` do when it is placed under `tabulate`, `fold`, and `scan`? [Missing: what is recorded about the lifted form.]
- **Abstraction.** What pattern do the terms of accepted solutions share? The agenda anti-unifies them over the instance space."

### Sections 8.5, 8.7 and 8.8

**A34. Two phrases in §8.5 that name things the reader cannot identify.** L1112, L1120.

> L1112: "| `sum-all`, `len-all`, `prd-all`, `last-or` | 200/200 through `fold` | without lifting, two of them return impostors (23/200 and 20/200) |"
> L1120: "With size-minimal acceptance all eight sequence specs score 200/200, at 625 and 824 times the candidates on the two that need a guard."

Cannot tell: which configuration "without lifting" is, since `fold` is itself one of the granted forms, and which two specs; which eight specs are "the sequence specs".

Missing at L1112: the name of the configuration and of the two specs. Rewrite of L1120, on my count of the table rows, to be confirmed: "With size-minimal acceptance, all eight specs that return a sequence (`copy`, `inc-all`, `dbl-all`, `positions`, `scan`, `shift-seq`, `filter`, and `map-adjacent`) score 200/200. On the two that need a guard, `scan` and `shift-seq`, it costs 625 and 824 times the candidates."

**A35. The opening of §8.7 and its two tables.** L1190, L1196-1203, L1214-1222.

> L1190: "Everything in this section except the last experiment is standard-library Python"
> L1199: "| the same, on tasks that need an operator held out of all training | 21.4×, 14.2× |"
> L1214: "on 300 random tasks with three table seeds, and on two sets of 200 tasks with one unusual row each."
> L1216: "| How the probes are chosen | Answers lost in 900 runs, at 300 / 1,000 / 3,000 probes per operator | Answers lost in 800 runs on the two unusual-row sets, same budgets | Wrong table entries met per 1,000 tasks, at 1,000 / 3,000 probes |"

Cannot tell:

- At L1190: which experiment is "the last". The one experiment not in Python is the one headed "In the store prototype" (L1247), and three more paragraphs follow it.
- In the first table: what "training" a verb table has. No training has been mentioned; the word belongs to the count-based method two rows further down.
- In the second table, without the prose: what a "run" is and why there are 900; how 800 arises from two sets of 200 (the prose gives three seeds for the first set and none for these); what makes a row "unusual"; what "met" means and over which tasks the last column was counted.
- That the "1,700 runs" of L724, L763 and L1392 is the sum of the two middle columns. §8.7 never says 1,700.

Rewrite of L1190: "Everything in this section is standard-library Python on a library of operators written by hand for the purpose, with one exception: the experiment headed "In the store prototype" below was run in the Lisp prototype of §8.1."

First table. Heading of the second column: "Gain over plain search: candidates evaluated by plain search divided by candidates evaluated by the method (geometric mean over tasks; one figure for each of two sets of 20 tasks)". Row labels, of which the second rests on my reading of "held out of all training" and of L1210 ("the two held-out operators"): "verb tables with six quotients, all tasks"; "the same, on the tasks whose answer needs an operator that appears in none of the 80 solved tasks used to train the count-based method below"; "the same, on the remaining tasks"; "verb tables used only to order the operators, with nothing skipped"; "counts of past use: Naive Bayes over 23 hand-written properties, trained on 80 solved tasks, and used only to order the operators"; "types only (60 tasks)".

Second table. Column 2: "Answers lost out of 900 runs (300 random tasks, each run with tables built from 3 random seeds), when the tables are built from 300 / 1,000 / 3,000 probes per operator". Column 3: "Answers lost out of 800 runs on the two sets of 200 tasks that each contain one unusual row, at the same three numbers of probes" [missing: how 800 runs arise, and what makes a row unusual]. Column 4: "Number of times, per 1,000 tasks, that a search read a table entry that lacked a possible output label, at 1,000 / 3,000 probes per operator" [missing: on which tasks this was counted].

Add after the table: "At 1,000 probes per operator, the rule in bold lost no answer in the 1,700 runs of the two columns together. Random probes lost 5 + 7 = 12, and the review's transforms lost 2 + 3 = 5."

**A36. The bullet on two-argument operators hides who proposed what.** L1228.

> "*Tables for two-argument operators must be built from joint probes of both arguments.* Tables built from slices that hold one argument at a few fixed values rejected 287 of 500 true results for `div` and 422 for `mod`, with the slices the review chose. Those slices were a bad case, and most random choices of slice reject nothing. The rule stands for a plainer reason"

Cannot tell: whether the review proposed slices or proposed the rule against them; why a result that "most random choices" do not reproduce is reported.

Rewrite, on my reading that the rule is the review's and the slices were its demonstration: "*Tables for two-argument operators must be built from probes that vary both arguments together.* The review proposed this rule. It supported the rule by building tables the other way, from slices, in which one argument is held at a few fixed values while the other varies. With the slices the review chose, those tables rejected 287 of 500 true results for `div` and 422 of 500 for `mod`. That evidence is weaker than it looks: the review's slices were a bad case, and most random choices of slice reject nothing. The rule stands for a plainer reason. A table keyed on labels is a claim about every value that carries the label, and a slice samples only a few of those values."

**A37. Near-miss results: "fired", an unexplained bound, and "cost half as much".** L1241, L1245, with L881.

> L1241: "the proposal fired on 70 of 234 and was right on fresh rows in 64 of them. Once labels are in use it adds little there: the best possible ordering of the last step adds 1.1×."
> L1245: "Running the near-miss check on every candidate that is evaluated cost half as much as running it only on the candidates the labels let through."

Cannot tell: what "fired" means; what the best possible ordering of the last step has to do with the offset proposal; half as much of what (candidates, seconds), and why checking more candidates costs less.

Rewrite of L1241, second half, on my reading: "On the ordinary tasks, which were not built to contain a near miss, some class left a constant residual in 70 of 234, and the program proposed from it was right on fresh rows in 64 of those 70. Once labels are in use the proposal adds little on these tasks. An ordering of the last step that always tried the right candidate first would add only 1.1× there, and the proposal can do no better than that."

For L1245 and L881: missing are the unit and the reason. The sentence should have the form "Running the near-miss check on every candidate that is evaluated cost half as many [candidates, or seconds] in total as running it only on the candidates that the labels let through, because [reason]."

**A38. The gain of the same six hand-listed quotients is quoted with about a dozen different figures.** L94, L718, L728, L875, L1198, L1205, L1209, L1224, L1230, L1234, L1256, L1391.

> "about 15 times" (L94); "14 to 18 times" (L718); "16×" (L728); "about 16×" (L875); "17.5×, 18.5×" (L1198); "13.9× and 16.7×" (L1205); "15.7×" (L1209); "17×" (L1224); "17.0×" (L1230); "15.6× and 16.9×" (L1234); "15.8×" (L1256); "about 15×" (L1391).

Cannot tell: whether these are the same quantity. Each is presumably the figure for a different set of tasks, and nothing says so. A reader who annotates will mark every one.

Fix: add one sentence to "The setting" (L1192): "Each experiment below has its own set of tasks, so the gain of the six hand-listed quotients is not one number. Across the experiments it runs from 13.9× to 18.5×, and each experiment quotes the figure for its own tasks." Then use one summary phrase everywhere outside §8.7, for example "14× to 18×", in place of "about 15".

**A39. Item 2 of §8.8 and the two places that point to "the rule of §8.8".** L1275, L853, L1403.

> L1275: "Beyond that the store offers three further tests, in increasing cost: ... This is part of the gate of experiment X3 (§11.2)."
> L1403: "no guard split accepted that fails the rule of §8.8"
> L853: "accepted only under the rule of §8.8"

Cannot tell: whether "This" is the size-order rule alone or the rule with the three further tests; whether the three tests are adopted or only available; which numbered item "the rule of §8.8" is, since §8.8 has ten items.

Missing: the author's intent about the three further tests. If the gate is the size-order rule only: at L1275, "The size-order rule is part of the gate of experiment X3 (§11.2). The three further tests are available and are not yet part of any gate." At L853 and L1403: "the size-order rule (§8.8, item 2)".

### Sections 10, 11 and 1

**A40. Short passages in §10, §11 and §1 that are compressed past easy reading.**

(a) §10 row 13, L1355: "lost from none to 11% of tasks, depending on the number and choice of probes". Cannot tell: which setting gives which end. Rewrite: "They are tested knowledge. With 100 random probes per operator they lost 34 of 300 tasks, which is 11%. With 1,000 probes chosen by the rule of §6.5 they lost none in 1,700 runs (§8.7)."

(b) §10 row 9, L1351: "the per-column codes are needed regardless, the rest is optional". Cannot tell: the rest of what. Rewrite: "The per-column correction codes of §6.1 and §6.3 are needed whatever X4 shows. The words and verb tables of §6.4 and §6.5 are built further only if X4 passes."

(c) §11.1, L1393: "Do labels look ahead, with corrections taking over at the end?" This assumes the reader knows the outside review's claim. Rewrite: "Do labels rule out candidates several steps before the answer, and do corrections matter only at the last step, as the outside review argued?"

(d) X4, L1404: "*Gate:* at least 3× lower total wall time on held-out tasks". Cannot tell: lower than which of the five arms. Presumably the arm with no guidance; the text should say so. Also "the baseline averaged over operator orders" should read "the no-guidance arm averaged over random orders of the operator list, because the order alone changes the gain (§8.7)".

(e) X9, L1409: "the map-hole form of §5.9". Rewrite: "the form of problem in which the hole of a requirement has the type of a map (§5.9, first consequence)".

(f) §1, L51: "For the geometry, yes in a derived sense and not yet in a learned one." Cannot tell, on the first page, what "derived" is opposed to. Rewrite: "For the geometry, yes in one sense and not yet in another. The geometry this plan can build is derived by counting and coding: the cost in bits of one column given others, and coarse labels of values (§6). A geometry of learned coordinates, such as an embedding, is not yet supported by the evidence (§6.6)."

(g) §1.1, L60: "What goes with what was handed in by every plan and never stored." The subject of the sentence is "What goes with what", and a reader has to read it twice to find the verb. Rewrite: "In every plan, the knowledge of which rows, values and sub-problems belong together was supplied from outside. The kernel never found it for itself and never stored it."

(h) §1.4, L93: "Matching rows with no key needed backtracking only on regular structures without symmetry and to reject look-alikes." Rewrite: "When no term computes a key that says which row of one space goes with which row of another, the rows have to be matched by how they are connected. That matching needed backtracking in only two situations: on regular structures that have no symmetry, and to reject two structures that look alike and are not the same."

(i) §1.5, L102: "Not a question of what can be represented." This has no subject. Rewrite: "The choice between flat and nested is not a question of what can be represented."

(j) §1.6, L110: "The compounding has no precedent, and the one small test of it showed none." Cannot tell at once whether "none" is "no precedent" or "no compounding". Rewrite: "Compounding of that kind has no precedent. The one small test of it here, in which the words were chosen again as a library grew, showed no compounding."

### Smaller items, one line each

- L26: "*work unit* | The present kernel's unit of search effort." This defines the term by itself. L177 has the content: "The cheapest instruction of the kernel's VM costs one unit; larger instructions cost more, and host work such as scheduling is charged in the same units."
- L81: "stored solutions, then labels, then a tentative pass filtered by labels". "Then labels" should be "then an ordering of the operators by labels".
- L95: "Measured: nested guard splits overfit; ...". A colon list in place of sentences; "Three limits were measured. Nested guard splits overfit. ..." reads better.
- L100: "Taking instances modulo classes" is jargon for "treating two instances as the same when they fall in one class".
- L664: ""behaviour distance"" and "property signatures" assume the reader recalls the earlier plans. A section reference to §2.7 and §8.6 would do.
- L678: the counting identity is given as a formula with no words. L298 has the words; one clause ("the information in an input is the information in the output plus the bits that say which member of the fiber it was") would save a look-up.
- L684: "A new latent column" and "Cluster labels". "Latent" is undefined, and "labels" here is not the label of §6.2.
- L735: "22 have a family member as their nearest table" should be "for 22 of them, the operator with the nearest table belongs to the same family".
- L802: "What has none." followed by "What has no precedent at all is the compounding". The first two things are also said to have no precedent, so "at all" grades nothing. See B15.
- L850-851: `(f k ?z)`: `k` is never said to be a known argument.
- L915: "Its readers, in order of evidence" should be "in decreasing order of the evidence for each".
- L928: 30 + 30 + 52 + 51 is 163, not 158. L219 explains the overlap and names six accounting rules that this sentence does not map. Add "(the categories overlap; the six accounting rules stay as they are)" if that is the case.
- L968: "in the reproduction" assumes the reader knows that §8.7 reproduces the review's experiments. Write "in the Python experiments of §8.7".
- L992: "a class that cannot reach the target within the bound": the rule does not say that the test is the label test until rule 3.
- L998: "Hours then compound": "then" has nothing to follow from. "Spent that way, hours can compound, as the audit measured" is clearer.
- L1210: "in the manner of the published grammar-reweighting method" names a method the document does not otherwise describe.
- L1234: "(0 of 410)": 410 of what, when there are 234 tasks.
- L1243: "56 of 64 tasks ... (3 or 4 of 32)": the reader cannot connect 64 and 32 with the 192 tasks of L1241.
- L1268: "a divisibility law had seven": seven what (seven weakest guards, none weaker than the others?).
- L1354: "verb tables worked, on that library": "that library" reaches back over the §8.6 clause to the Python library.
- L1386: "with four measured limits": name them or point to "What did not work" in §8.1.
- L1401: "the present bucket engine" and "v1's enumerator" are glossed only at L1309 and L142.

---

## B. Places where the argument does not follow

**B1. The section argues for "two resolutions" and concludes with "two ways to compute"; and there are three ways.** L631, L641, L651, L667, L670, L672.

> L631: "they are one question asked at two resolutions"
> L667: "A law is two terms with the *same* column, which the store finds by hashing columns into classes (§5.2). That is as cheap, but it is a different test."
> L670: "So the honest statement is the one in §6.1. There is one question, and there are two ways to compute the answer. Counting serves three of the four cases with one routine. Correction serves the fourth."

The problem is set out in section 0. In short: resolution and method are two different distinctions, the text moves from one to the other without saying how they cross, and L670 counts the top-left cell for counting two sentences after L667 has said that laws, which are in that cell, use a different test.

Suggestion. (a) Add a line "Computed by" to each cell of the table at L657-660. (b) Replace L670 with the statement the three bullets support: "So the claim holds in part. There is one question. Its answer is computed in three ways, and the cell decides which. Hashing a column into its class finds laws (top left). Counting within groups, which is one routine, finds inverses (top left), exact facts about labels (bottom left), and verb tables (bottom right). Correction, row by row, measures a near miss (top right)." If the author prefers to keep "two ways", then say that a law is the case in which the correction cost is zero on every row, and that hashing is how the store detects it. (c) Retitle L672 "What labels can see, and what corrections can see". (d) Make §1.3 (L79) agree with whichever statement is kept.

**B2. The "one move" is top-down and the "four steps" are bottom-up, and nothing joins them.** L845, L871, L875.

> L845: "Choose a hole. Choose a program construct with fresh holes of its own. Substitute it."
> L875: "Each candidate is an operator applied to classes already in the bank"

A reader finishes the table of constructs expecting the search to be a tree of refinements, and then meets an enumeration over a bank with no hole in sight. Suggestion, on my reading, to go before "One search, four steps": "A problem is attacked in two ways. *Leaf enumeration* fills the hole with a finished term, built bottom-up from the bank in order of size; this is the first row of the table. *Refinement* fills the hole with a construct that has holes of its own; these are the other rows. The four steps below describe leaf enumeration on one problem, and the points at which it proposes refinements, namely the `decode` and `if` rows."

**B3. "Nothing else is needed" for an inverse, against "followed by a small search".** L666, against L576 and L935.

> L666: "Given an operator's table it reproduces the inverse of `*` with its guard `b ≠ 0` as §8.2 found it. Given labels it returns the verb table. Nothing else is needed."
> L576: "finding inverses by a dependency test on an operator's own table followed by a small search"

A group-by returns a table and the rows on which the dependency fails. The terms `(div c b)` and `(not (= b 0))` came from a search of 141,652 candidates (L1053). So either "the inverse" here means the table and not the term, or something else is needed. Suggestion: "Given an operator's table, it finds that the argument is determined on the rows where `b ≠ 0`, as in §8.2, and it returns the inverse as a table. Turning that table into the term `(div c b)` is the small search of §8.2. Given labels, the routine returns the verb table. For the dependency itself nothing else is needed."

**B4. §7.5 says laws are the same routine; §6.2 says they are not.** L943, against L667; also L932.

> L943: "The first three and the verb tables are literally one routine with different columns passed in (§6.2)."

The first three bullets are Laws, Inverses and Definedness. §6.2, which this sentence cites, says of laws "it is a different test" (L667). Separately, L932 says "every one of them is the question of §6.1", and the bullets "Lifted forms" and "Abstraction" are not shown to be. Suggestion: "Inverses, definedness, and verb tables are one routine with different columns passed in (§6.2). Laws use the class table instead, which is as cheap." And at L932: "most of them are the question of §6.1 put to some probe space".

**B5. "So the gain is a constant factor of about one level of branching."** L725, and the same gap at L1234.

> L725: "The tables ruled out nearly half of the classes one operator from the target and none of those further away. So the gain is a constant factor of about one level of branching, and was the same for programs of 3 to 6 nodes."

The "So" needs two links the text does not give: how ruling out about half of the classes at the last step becomes a gain of about 16× in candidates, and what number "one level of branching" is for this library. A technically strong reader will stop here and try to derive 16 from one half. Suggestion: either give the link (for example, how many candidates per class are skipped at the last step), or drop the inference and set the two measurements side by side: "The gain did not grow with program size: it was about the same for programs of 3 to 6 nodes (§8.7). That is what a test that acts on the last step alone would give."

**B6. "The price of a name" seems to contradict §7.1 and "Acceptance is by one exact code".** L737, against L837 and L885.

> L737: "an operator's place in the enumeration, and so its price, is read from how well its tables fit the labels of the problem at hand"
> L837: "An operator's name costs −log₂ of its share of uses in accepted solutions (§6.4), under a prefix code as now."
> L885: "Labels and corrections decide what is tried. They never decide what is accepted."

Everywhere else in §6 a price is a number of bits in a description length. If a name's price in that sense depended on the labels of the problem at hand, labels would enter the code that decides acceptance, which L885 rules out. And §7.1, citing §6.4, prices names from counts of use, which §6.4 calls "the form that failed on new operators". The reader cannot tell whether "price" at L737 is bits or search order. Suggestion: separate the two in so many words: "A name has two costs. Its *price* is the bits it adds to a program's description, and it comes from [the author's choice]. Its *rank* is its place in the order of enumeration, and it is read from how well its tables fit the labels of the problem at hand. The tables set the rank and never the price." Then make L837 agree.

**B7. "Which is the definition of the tested grade" is not the definition §5.5 gives.** L724, against L540.

> L724: "That is knowledge carried across spaces without being re-checked there (§5.9), which is the definition of the tested grade (§5.5)."
> L540: "**Tested**: the two terms also have the same column on several fresh spaces that include boundary values."

By L540, a table built on one probe space and read on a task's space has been checked on no fresh space at all. Suggestion: "By the grades of §5.5 such knowledge is at most tested: it may order and propose, and it may never eliminate."

**B8. Step 4 lets labels prune the search that decides whether a held split is accepted.** L883, against L885 and L540.

> L883: "a class that cannot reach the target within the bound is not stored ... labels were needed on the other two."
> L540: "It may never be used where a mistake would make the kernel accept something false."

In step 4 the search is the plain pass, looking for a smaller rival to a held split. If a wrong table entry prunes that rival, the held split is accepted, and L879 has just said that a split that fits the rows is the right program in 2 cases of 64. So here a label can change what is accepted, and the text does not say what stands behind it. Step 2 gives the label filter a fallback; step 4 gives its look-ahead none. Suggestion: one sentence stating the safeguard (for example, that the part of the look-ahead that uses types is certain and the part that uses labels runs under the reserve), or a note that this is open.

**B9. Three statements of what a bank belongs to.** L30, L895, L988.

> L30: "The classes enumerated so far in one search on one space."
> L895: "One bank of classes per (space, context) serves everything that enumerates there. ... A bank that has been pruned toward one target is scratch memory for that search"
> L988: "A problem's bank of classes is scratch memory, bounded by its account."

Per search, per (space, context), or per problem? L895 says a bank is shared by everything that enumerates on a space and, in the same bullet, that a pruned bank belongs to one search. Suggestion: two names. "The *shared bank* of a (space, context) holds every class enumerated there, and everything that enumerates there reads it. A search that prunes toward its target, as in step 4, does so in a working copy of its own, which is scratch memory and is discarded."

**B10. "Two fifths of the gain rests on entries that are tested and nothing more."** L1230, against L771.

> L1230: "So roughly two fifths of the gain rests on entries that are tested and nothing more."
> L771: "But "exactly one label in every probe" is still a sample. ... So the tables are tested knowledge throughout"

By L771, the single-label entries are also tested and nothing more; only the tables for length (3.6×) follow from something provable. Suggestion for L1230: "So roughly two fifths of the gain rests on entries that allow more than one output label. The other three fifths rests on entries that showed a single label in every probe, which is still a sample."

**B11. The same condition is the reason the prototype cannot skip and is present where the Python search does skip.** L1250, against L1192.

> L1250: "The prototype deepens one size at a time and does not know which size is the last, so it cannot skip, only reorder."
> L1192: "The size of the answer is not known, so the size bound is deepened step by step and every pass is counted."

Both searches deepen by size without knowing the size of the answer. One skips candidates and the other "cannot". The difference between them is the missing reason.

**B12. "Never the right one", and answers lost.** L672 and L1234, against L724 and L1212.

> L672: "The labels ruled out nearly half of the classes one step from the answer, never the right one"
> L724: "with random probes 12 were"

Read as a property of labels, "never the right one" contradicts the losses reported five paragraphs later. It is a result of one measurement (0 of 410, L1234). Suggestion at L672: "and in that measurement never the true parent".

**B13. Two build times for tables from random probes.** L1224, against L1260.

> L1224: "Building the tables takes 17.6 s under the rule in bold against 1.1 s at random."
> L1260: "Learning the tables for a chosen vocabulary takes 0.2 s with random probes."

1.1 s and 0.2 s for what reads as the same thing. Say what differs (presumably the number of probes).

**B14. Five statements of measured results in §6 and §7.2 have no entry in §8.7.** The first cites §8.7 directly. The next three carry an **[M]** tag in a passage whose measurements are those of §8.7. The fifth is untagged.

- L664-666: "That was tested by writing the one routine and running it on each case (§8.7) **[M]**" and "One routine of 30 lines". §8.7 has no such experiment. Appendix D (L1539) lists a report for it.
- L728: the 12× and 6.6× figures.
- L735: "Of the 32 operators placed by hand in seven families, 22 have a family member as their nearest table, where chance gives 9 **[M]**."
- L887: "That happened in none of 234 tasks **[M]**."
- L807: "A merged, finer quotient showed a gain that rose with program size". §8.7 (L1227) gives 22× against 17× and says nothing about program size.

The brief for this review says §6 states results that §8.7 gives in full. For these five that is not so. Suggestion: add each to §8.7 in a sentence, or cite the report by name where the number is stated.

**B15. The grading of precedent in §6.7.** L800-802.

> L800: "That exception, Atlas, learns its predicates from four training problems per domain, fits each operator's abstract behaviour from random samples"
> L802: "No published synthesizer was found that reads an operator's table off its own samples by grouping, with no solved tasks and no hand-written semantics; ... What has no precedent at all is the compounding"

Atlas "fits each operator's abstract behaviour from random samples", which is close to reading a table off samples, and the next paragraph says no synthesizer does that. The difference (no training problems, no hand-supplied axioms) is there, but the reader has to find it. Then "no precedent at all" implies that the two items just listed have some. Suggestion: "Two things have a near precedent in Atlas and no exact one: reading an operator's table off its own samples with no solved tasks and no hand-written semantics, and choosing abstractions by the dependency score. Both were measured for this plan, in Python (§8.7). One thing has no precedent of any kind: the compounding, ..."

**B16. Lists whose items are not parallel.**

- §7.4, L915-920, "Its readers, in order of evidence". The list is of readers of the derivation space. Item 2 leads with verb tables, which are built from probe rows and do not read the derivation space; only the counts do. Item 3, ablation, is a procedure and not a reader. Suggestion: head the list "Four uses of the search's record, in decreasing order of the evidence for each", and in item 2 put the counts first.
- §6.4, L730-735, "The same tables serve four other purposes". Item 1 is about words (quotients), not tables.
- §6.6, L779: a bullet about how a space is made ends with "a residual makes a new column", which is not a space.
- §10, L1341: the heading "What would show it" does not describe the cells of rows 4, 7, 9, 13 and 14, each of which mixes a design decision with a test ("tables first, counts only as a correction (§6.4); the guidance ablation (X4) before building more"; "bank memory bounded per problem account; measure retained classes per hour; hours go to breadth"; "use them to order, or to filter a tentative attempt that has a fallback; in X4 count answers lost ..."). Suggestion: head the column "What the design does about it, and what would show it", and write each cell as two labelled sentences, "Design: ... Test: ...".

**B17. Further places where one section in scope seems to disagree with another.**

- *Replay and the stages.* Step 1 of every search runs replay (L873). Replay is a reader of the derivation space (L917), which is in Stage D with X7 (L1407, L1418). The tentative pass is in Stage C (L1417). The reader cannot tell whether a Stage C search has its step 1.
- *Where the near-miss check runs.* L881 says the review placed the check "after the label filter" and that it "has to see every candidate". In the four steps as written, the check is in the plain pass, which has no label filter for it to come after. The remark makes sense only if the tentative pass also runs the check, and step 2 does not say whether it does.
- *The memory figure for the sequence library.* §7.6 (L994), §8.8 item 6, §10 row 7 and §11.1 quote 1.5× in bytes. §8.7 (L1266) gives "1.5× and 4.3×", the second "with a one-step look-ahead". Since step 4 of §7.2 is a look-ahead, the reader cannot tell why the 4.3× is set aside.
- *Columns dropped, then used.* L996: "Classes of the largest stored size can only be arguments of one-argument operators at the final size, so they can be held as hashes and their columns dropped." Applying a one-argument operator to a class needs its column. The step that makes this work (for example, applying those operators before the column is dropped) is not given.
- *Which two specs.* §11.1 (L1387) says "two more only through the `fold` route". The §8.5 table lists four specs "through `fold`" (L1112), and L1122 says the aggregate change also solves three of those four.
- *The strict filter and the seven runs.* "7 of 9 guarded runs" (L726, L1249), "the seven guarded tasks" (L883) and "the seven guarded runs" (L1251) may or may not be the same seven.

---

## C. Repetition

Words saved are estimates. The rule applied: the design sections keep the mechanism and one headline number; §8.7 keeps the full numbers; summaries (§1.4, §8.8, §10, §11.1) say the result in a clause and point.

**C1. §6.5 and the matching parts of §8.7 are the same text twice.** §6.5 is 1,120 words. "Choosing the vocabulary" and "Answers are lost" in §8.7 are about 1,100 words. The following series appear in both, almost word for word:

- 13.0× with six words, 15.3× with ten, against 15.8× (L750, L1256; again at L1392);
- 4.8×, 8.4×, 12.2×, 13.0× for 2, 4, 6, 8 labels (L753, L1258);
- 13.0× with the library in the grammar and 12.8× without; 26 to 45 to 61 operators; two of six carried over; 12.0× (L754, L1259);
- nine of the ten include the length; about 4,000th (L752, L1257);
- 13.9× with the repetition test on both parts (L755, L1256);
- 21 CPU-minutes for 95,732 candidates (L757, L1256 and L1260; again at L967);
- no answer lost in 1,700 runs, 12 for random, 5 for the review's transforms (L763, table at L1216; again at L724 and L1392);
- 17× to 22× for merged quotients (L769, L1227);
- 71%, 10.2× of 17.0×, 3.6× (L771, L1230).

Keep in §6.5: the four-step procedure, the probe rule in its blockquote with the reason random lists are poor probes, the three further rules as rules, the headline (13.0× and 15.3× against 15.8×; none lost in 1,700 runs against 12 and 5), and the conclusions in words ("not the words a person would list", "words need several labels", "re-choosing is insurance, not compounding", "tested knowledge throughout"). Move the other number series to §8.7 only, each replaced in §6.5 by "(§8.7)". Saves about 250 words in §6.5. §8.7 is the record and should stay whole.

**C2. "Labels act on the last step; corrections rank weakly" is given in full three times.** L672 (174 words), L725, L1232-1237 (264 words), and in summary at L94, L111, L807, L1282, L1393. Keep the full statement in §8.7. §6.2 keeps the conclusion (about 80 words, see the rewrite in A14, which can be cut to its last five sentences if the definitions go in the table of terms). §6.4's bullet at L725 becomes "It acts on the last step (§6.2), so the gain did not grow with program size." Saves about 110 words.

**C3. "A near miss fails the labels on exactly the rows it gets wrong" is stated six times.** L668 (in part), L726, L875, L1249, L1282, and §10 row 14 at L1356; "7 of 9 guarded runs" is at L726, L1249, L1356 and L1394. Keep the reason in §6.4 (L726) and the measurement in §8.7 (L1249). In §7.2 step 2 say "for the third limit of §6.4". In §10 row 14 keep the risk and drop the repeated figure. Saves about 70 words.

**C4. The memory results are given at paragraph length in three places and in summary in five.** §7.6 "Memory within one search" (L990-996, 292 words), §8.7 "Memory" (L1262-1266, 248 words), §8.4 first bullet (L1095, about 100 words), and L727, L734, L1279, L1349, L1395. "8.5 to 26" appears at L994, L1095, L1264, L1395; "1.0 to 2.1 times" at L993 and L1265; "test before the class enters the duplicate table" at L992 and L1265. Keep the three rules in §7.6 as rules, with one clause of numbers each. Keep the numbers in §8.7. Cut the §8.4 bullet after "Two of the prototype's own runs did die at a 10 GB heap." to one sentence: "For ring arithmetic with a target the wall can be moved out by two or three sizes (§7.6, §8.7)." Saves about 130 words.

**C5. The held-split bound is described three times.** L883 (step 4), L1251, L1276 (§8.8 item 3), and L1394. "36×" and "34×" appear at L883, L1251, L1394. Keep the mechanism in §7.2, the figures in §8.7, and reduce §8.8 item 3 to: "A held split bounds the rest of the search, which recovers part of the cost of the size-order rule (§7.2, §8.7)." Saves about 45 words.

**C6. The size-order rule is stated twice inside §7.2 and six more times elsewhere.** L867 ("it is never accepted ahead of a smaller unsplit term") and L879 ("a split is accepted only once every smaller unsplit term has been ruled out"), then L90, L1036, L1120, L1242, L1275, L1387. Inside §7.2, state it at L879, where its reason is, and drop the last sentence of L867 (the paragraph then announces one further rule, not two). §8.5 keeps the full account. Saves about 30 words.

**C7. "The fallback stays" is concluded five times.** L724 ("never an elimination"), L771 ("the fallback is part of the design, not a precaution"), L875, L887 ("the fallback covers it"), L1224 ("So the fallback stays"). Keep L771, which follows the evidence, and L875, which is the design. At L724 end the bullet after the two figures. Saves about 30 words.

**C8. "Report cost summed over tasks, with the fallback counted, because the lost tasks are the dearest" appears four times.** L728, L894, L1355, L1404. It is a result at L728 and a reporting rule at L1404. Drop the second sentence of L894 and the last clause of §10 row 13. Saves about 45 words.

**C9. Counts as an adjustment to tables appears four times.** L737, L918, L1281 (§8.8 item 8), L1346 (§10 row 4). Keep L737. At L918 one clause is enough. Saves about 35 words.

**C10. The probe rule is stated three times.** L761-763 (in full), L950 (rule 4 of §7.5, 50 words), L1280 (§8.8 item 7). Keep §6.5. Rule 4 of §7.5 becomes: "*Probe with what programs produce.* The rule is in §6.5." Saves about 35 words.

**C11. The correction-code measurements are in §6.1 and in the §8.5 table.** L649 (122 words) and L1130-1132: the same bit counts (0, 4, 5, 5, 8, and 17 at 1000), the asymmetry, the triangle inequality. Keep the numbers in §8.5. §6.1 keeps three sentences without numbers: symmetric and logarithmic on integers; strongly asymmetric on sequences and code; the triangle inequality fails for large values on sequences and code. Saves about 45 words. The prefix-code defect is likewise in rule 5 (L686), the §8.5 table (L1133) and Appendix D (L1556); the three need not all repeat the "one bit per model" detail. If this saving is taken, the rewrite of rule 5 in A8 ends at "One more bit per column can then say that the whole column is exact (§8.5)." Saves about 45 more.

**C12. The precedent figures in §6.7 repeat Appendix C.** L800 (155 words) and L1506-1507: 519 of 544 against 456 and 409; 8.3× and 9.2×; 2.1× and 3.1×. Likewise L798 and L1505 (42.6% to 82.0%). Keep the figures in Appendix C. §6.7 keeps the point: guidance by abstract values is established where the abstractions are written by hand, and Atlas is the one system that learns them, with training problems and hand-supplied axioms. Saves about 90 words.

**C13. "A vocabulary that goes on improving ... has no precedent, and the one small test showed none" is said three times.** L110, L802, L1368. Keep §10 (L1368), which is where precedent is tallied. §1.6 keeps its bullet (it is the summary). §6.7 can end at "Both were measured for this plan, in Python (§8.7)." and point to §10. Saves about 35 words.

**C14. §11.1's last ten rows restate §1.4 and §8.8 at paragraph length inside table cells.** L1386-1395 are 453 words; the same results are in §1.4 (L89-95) and §8.8. For example the cell at L1387 is about 70 words and the cell at L1392 about 55. In a table headed "Question | Result | Where", a result of one clause is enough: "Mostly: 13 of 16 reach 200/200 in some configuration" and the pointer. Saves about 180 words.

**C15. §8.8 items 8 to 10 repeat §1.4's vocabulary bullet nearly word for word.** L1281-1283 and L94 ("to within a fifth of the gain of one listed by hand"; "it acts on the last step, and it cannot find an answer that needs a guard"). §8.8 is headed "What the measurements change in the plan", so each item should state the change and not the result. Item 9: "The label filter is one tentative pass with the plain pass behind it, and near-miss proposals belong to the plain pass (§7.2)." Item 10: "The vocabulary and the probes are chosen by the kernel and not listed by hand (§6.5); neither has been run inside the kernel." Saves about 50 words.

**C16. A probe space is defined three times.** L31, L545, L932. The table of terms says each term "is defined again where it first matters", which is L545. Drop the sentence at L932. Saves about 25 words.

**C17. Flat against nested is argued in §1.5 and §6.6.** L102 and L792 ("not a question of what can be represented"; "storage economy"). Both are needed, one as summary. No saving; noted so that a later pass does not cut L792, which is the full statement.

Total: about 1,250 words. Nearly all of it is inside the scope of this review; the exception is about 70 words in §8.4 (C4). None of it requires compressing a sentence.

---

## D. What works, and should not be cut

- **§6.1, the question in a blockquote and the worked example** (L637, L643): `u` = (7, 5, 4, 0), `y` = (8, 6, 5, 1), 16 bits against 29. This is the one place where "cost of B given A" becomes a number the reader can check. The sentence about eight rows whose cells are all different (L647) does the same for counting.
- **§6.2, the definition of a quotient with three examples** (L653) and **the four-cell table** (L657-660). With the changes in A13 the table carries the section.
- **§6.2, the three bullets under "How far the four cases are one mechanism"** (L666-668). Each says what was claimed, what was found, and why. They are clear because they take a paragraph each. The fault is only in the sentence that sums them up (B1).
- **§6.3, the five rules as a numbered list, and the sentence at L688**: "the graph is the factorization of the description, and the geometry is the code on each factor." This is the sentence a reader will carry away.
- **§6.3, "A small residual is not yet structure"** (L696): the claim, the measurement, the consequence and the rejected alternative, in order.
- **§6.4, the table of word types** (L704-708), especially the analogy row with `neg(max(a, b)) = min(neg(a), neg(b))`.
- **§6.4, "A description is a run on labels"** (L712) and **"The same thing in other words: a learned type system"** (L714). For a reader who is not a Lisp programmer the type-system paragraph is probably the most useful in the section: it says why the mechanism is cheap, why it acts on the last step, and why it can be wrong, in terms the reader already has.
- **§6.4, "What it does not buy"** as a list of five named limits (L722-728). The form is right even where single items need work.
- **§6.5, the paragraph on why random lists are poor probes, and the rule in its blockquote** (L759-763). "They are other operators' outputs: sorted lists, lists with repeated elements, two arguments computed from the same input" is exactly the kind of sentence that should survive any shortening.
- **§6.5, "The words it chooses are not the ones a person would list"** (L752), with the quoted example of a chosen word.
- **§6.6, "What this does not provide"** (L785-790), and **§6.8** as a list of open questions.
- **§7.2, the definition of a problem and of the one move** (L843-845), and **the table of constructs** (L847-861).
- **§7.2, the labelled example in step 1** (L873): "the input has mixed signs, mixed parities, and no order, and the target is all-even, all-positive, ascending, and as long as the input". Also the `(reverse c)` sentence in step 2 and the (3, 5, 7, 9) sentence in step 3. These are what make the steps concrete; the request in A25 is to finish the example, not to shorten it.
- **§7.2, "Acceptance is by one exact code" and "A search reads; the agenda learns"** (L885-887). Two short paragraphs that each state one rule of the design plainly.
- **§7.4, the explanation of a nogood and of the two conflict-analysis steps** (L922).
- **§7.5, the four rules for choosing experiments** (L947-950), each with its reason.
- **§7.6, the cost table** (L960-978) and memory rules 1 and 2 (L992-993).
- **§8.0, the two cautions** (L1006).
- **§8.5, the table of specs** (L1107-1116) and **the paragraph on why collect does not replace `fold`** (L1122), which gives three failures and three different reasons.
- **§8.7, "The setting"** (L1192). It defines the library, a task, plain search, the vocabulary, the filter and the gain in one paragraph. Several of the items in section A would not arise if §6.4 and §7.2 pointed here or borrowed from it.
- **§8.7, the `take3` example of a wrong table entry** (L1212).
- **§8.7, "Where labels act, and where corrections do"** (L1232-1237), especially the percentile sentence with "where the 50th is chance".
- **§8.7, "What these measurements do not show"** (L1270).
- **The table of terms and the table of evidence tags** in the front matter, and **§1.3** as a whole.

---

## E. Verdict on §6 and §7.2

Read once, §6 gives the owner most of the design. The question of §6.1, the quotient, the label, the verb table, the four cells, and the reading of verb tables as a learned type system all come across, and they come across because the text takes its time over them: a worked example, a definition with three instances, a table. What does not come across in one read is the claim in the section's own title sentence. The reader is told the three jobs of geometry are "one question at two resolutions", is then given "two ways to compute", and at the end of §6.2 is told that the second is "the honest statement", with a third way (hashing for laws) mentioned and not counted. §7.2 has the matching fault: the table of constructs describes a search that refines holes from the top down, the four steps describe an enumeration that builds classes from the bottom up, and no sentence says that the second is what happens inside one problem of the first. In both sections the parts are clear and the join between them is missing. The telegraphic passages are mostly the measured results: figures quoted without a baseline, terms such as gain, reserve, held, look-ahead and true parent used before they are defined, and "word" defined one way and used another. The single change that would help most is a short orienting passage at each join: in §6.2, a line in each cell of the table saying which computation answers it (hashing, counting, or correction), with L670 rewritten to match; and in §7.2, one paragraph before "One search, four steps" saying that the four steps describe leaf enumeration on one problem and where it hands over to refinement, followed by the running example carried through to the step at which the answer is found. If only one of the two can be done, do the first, because §1.3, §7.2 and §7.5 all lean on it.
