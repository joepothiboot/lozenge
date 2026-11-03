# Phase 6c TODO: saturation and extraction

Spec: the Haddock in `src/Lozenge/EMatch.hs`, `src/Lozenge/Extract.hs`,
`src/Lozenge/Saturate.hs`, and `classes` in `src/Lozenge/EGraph.hs`. Run a
group with, e.g., `stack test --test-arguments='-p Saturate.ematch'`. Hints
are rung 1 (a question). Ask for the next rung when you want it.

**Prerequisites.** All of 6a and 6b. `loadRules` needs Phase 3's
`verifyBrute`, `instantiate` and `renderVerdict`, and 5a's `ruleToFix`.
`saturate` needs Phase 1's `eval` for preconditions. The semantic property
needs 5a's `fromTyped` and `toTyped` and Phase 2's `checkEnv` and `evalT`.
Steps 1 and 2 need nothing outside 6.

## Decisions

- **Generic since Phase 8.** `EGraph f s` works over any node functor with
  `Language f` (`Traversable`, `Ord`, `Show`), and `CostFn f c = f c -> c`
  takes any `Ord c`, so that Phase 8 can put tensor `Op` nodes in the same
  e-graph. In this phase, read `f` as `ExprF` and `c` as `Int`: the
  implementation is the same code.

- **Three modules, plus `classes` in `Lozenge.EGraph`.** `EMatch`, `Extract`
  and `Saturate` each read the graph through `classes`, so `EGraph`'s
  representation stays private to its module. `classes` is the only addition
  to 6b.
- **`ClassSubst`, not `Subst'`.** Haddock reads `'Subst''` badly, and the
  name says what it maps to. It is `Map Text ClassId`, next to 5b's `Subst`.
- **`extract` returns `ST s (Fix ExprF)`**, not a pure `Fix ExprF`: the graph
  lives in `STRef`s, and reading one is an `ST` action.
- **`saturate` takes `[CheckedRule]`, not `[Rule]`.** `loadRules` is the only
  way to make a `CheckedRule` (its constructor isn't exported), so an
  unverified rule can't reach the graph. This is "parse, don't validate": the
  type records that the check ran.
- **Rules are verified by brute force at the width they're loaded at.**
  `loadRules w` instantiates each `Generic` rule at `w` and checks it there,
  precondition included. `Unsupported` is refused, so add-assoc (24 bits) is
  refused at width 8 and accepted at width 4. The `-- shortcut:` names SMT as
  the upgrade, which would make `loadRules` an `IO` action.
- **One width per graph.** Patterns are untyped, so the graph must hold terms
  of the width the rules were loaded at (and Bools). That is a precondition of
  `saturate`, not a check.
- **Preconditions are decided on literals only.** A match fires if every
  variable in the precondition is bound to a class holding a literal and
  `eval` says `true`. Otherwise it is skipped, which is sound but incomplete.
  The `-- shortcut:` names a constant-folding e-class analysis as the upgrade.
- **The backoff scheduler is egg's, re-derived.** A rule banned `k` times
  has a threshold of `limMatches * 2^k` matches and a ban of `limBan * 2^k`
  iterations, so both double with each ban. An iteration that hid a rule is
  never `Saturated`.
- **The stop check runs after each iteration, in a fixed order:** Saturated,
  then NodeLimit, then IterLimit. The tests pin the iteration count
  (`x + y` with comm saturates in 2) and the node count (15 for comm and assoc
  on 3 variables).
- **`CostFn` must be strictly monotone**: a node costs more than each child.
  That keeps extraction out of cycles; the Haddock says how.
- **`shiftsAreCheap`**: shifts 1, multiplication 4, leaves 1, anything else 2,
  plus the children. So `x << 1` costs 3 and `x * 2` costs 6.
- **The tests write rules by hand**, as `Rule`s in the corpus style, so they
  don't need `parseRules`.
- **The property wraps 3 terms in 4 in a redex** (`t + 0`, `t * 2`,
  `t xor t`), so the 30% "astSize found a cheaper term" coverage holds by
  construction. It loads its 15 rules once (`propChecked`), because brute
  force over two 8-bit variables is 65536 evaluations a rule.

## 1. `classes`

Tests: `-p EGraph.classes`.

- [ ] *You already canonicalise nodes in `checkInvariants`. Can `classes`
  share that code, and which `Data.Set` function gives "deduplicated, in
  ascending order" in one step?*

## 2. `astSize` and `shiftsAreCheap`

Tests: `-p "Saturate.extract.astSize and shiftsAreCheap, node by node"`.

- [ ] *`ExprF` is `Foldable`. What does `sum` of an `ExprF Int` add up, and
  what is it for a leaf?*

## 3. `extract`

Tests: `-p Saturate.extract`.

- [ ] *The fixpoint needs a "best so far" per class. Is an `IntMap (Int,
  ExprF ClassId)` enough, and why can it be pure inside one `classes`
  snapshot?*
- [ ] *A node can be costed only when every child class has a cost. Which
  `Traversable` function turns `ExprF ClassId` into `Maybe (ExprF Int)` with
  one lookup per child?*
- [ ] *Why does the loop stop? What decreases each round, and what is its
  floor?*
- [ ] *Reading the term back top-down: why can't it loop, even though the
  graph has a cycle? Which law on `CostFn` do you rely on?*

## 4. `ematch`

Tests: `-p Saturate.ematch`.

- [ ] *Write the helper first: match a pattern against one class, given the
  substitution so far, returning every extension. What is its type, and why
  a list rather than 5b's `Maybe`?*
- [ ] *For a non-variable layer, each node in the class with the same
  operator is a candidate. How do you test "same operator, ignoring
  children" with the derived `Eq`? (5b's `match` had the same question.)*
- [ ] *The children must match one after another, threading the
  substitution. Which monad gives backtracking for free, so `foldM` over the
  child pairs explores every combination?*
- [ ] *Why can the same `(class, substitution)` come out twice, and where do
  you remove duplicates?*

## 5. `loadRules` and `checkedRule`

Tests: `-p Saturate.loadRules` (the last one needs step 6).

- [ ] *Define `CheckedRule`. What does `saturate` need from a rule at match
  time, and at apply time?*
- [ ] *Three steps, any of which can refuse: `instantiate`, `verifyBrute`,
  `ruleToFix`. Can each give an `Either Text` so that one `do` block in
  `Either` runs all three?*
- [ ] *Which `Data.Either` function splits a list of results into the
  accepted and the refused, in order?*

## 6. `saturate`

Tests: `-p Saturate.saturate`, then the property.

- [ ] *Instantiating a right side: a `PVar` becomes its bound class, and
  any other layer becomes an `addNode` of its instantiated children. Is that
  `addTerm` with one extra case, and could `cata` do it?*
- [ ] *Why search every rule before applying any? What goes wrong if a rule
  applied early changes the classes a later rule is still matching?*
- [ ] *The scheduler keeps, per rule, the times banned and the iteration the
  ban ends. Where does that state live: an `STRef`, or a pure value threaded
  through the loop?*
- [ ] *"Changed nothing" compares class and node counts before and after.
  Why is comparing counts enough? (When can a merge or an `addNode` leave
  both counts the same?)*
- [ ] *The precondition: build an `Env` from the bound classes' literals and
  call `eval`. What should a class with no `LitF` node do, and what about an
  `EvalError`?*
- [ ] *If the property fails, the counterexample has the term and both
  extractions. Which is wrong: the meaning (a bad merge, so saturation) or
  only the cost (extraction)?*

## 7. Afterwards

- [ ] *Run comm and assoc on 4 to 7 variables and compare the node counts
  with `3^n - 2^(n+1) + 1 + n`. Why does the e-graph grow exponentially even
  though every term is "the same sum"?*
- [ ] *Run the corpus's valid rules through `loadRules 8`. Which are refused
  as `Unsupported`, and would `loadRules 4` accept them?*
