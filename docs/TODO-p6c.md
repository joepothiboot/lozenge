# Phase 6c TODO: saturation and extraction

Spec: the `## Spec` entries below. Run a group with, e.g.,
`stack test --test-arguments='-p Saturate.ematch'`. Hints are rung 1 (a
question). Ask for the next rung when you want it.

**Prerequisites.** All of 6a and 6b. `loadRules` needs Phase 3's
`verifyBrute`, `instantiate` and `renderVerdict`, and 5a's `ruleToFix`.
`saturate` needs Phase 1's `eval` for preconditions. The semantic property
needs 5a's `fromTyped` and `toTyped` and Phase 2's `checkEnv` and `evalT`.
Steps 1 and 2 need nothing outside 6.

## Decisions

- **Every test has a 64 s timeout** (`localOption (mkTimeout 64_000_000)` in
  `test/Main.hs`), so a looping `rebuild`, `extract` or `normalise` fails instead
  of hanging. That is 10x the slowest group that passes today, `EmitC.compiled
  with cc.hand-built programs`, at 6.37 s (11 tests, 2026-11-04, on a Mac).
- **Generic since Phase 8.** `EGraph f s` works over any node functor with
  `Language f` (`Traversable`, `Ord`, `Show`), and `CostFn f c = f c -> c`
  takes any `Ord c`, so that Phase 8 can put tensor `Op` nodes in the same
  e-graph. In this phase, read `f` as `ExprF` and `c` as `Int`: the
  implementation is the same code.

- **Three modules, plus `classes` in `Lozenge.EGraph`.** `EMatch`, `Extract`
  and `Saturate` each read the graph through `classes`, so `EGraph`'s
  representation stays private to its module. `classes` is the only addition
  to 6b.
- **`ClassSubst`, not `Subst'`.** `Subst'` reads badly in prose, and the
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
  That keeps extraction out of cycles; the `extract` Spec says how.
- **`shiftsAreCheap`**: shifts 1, multiplication 4, leaves 1, anything else 2,
  plus the children. So `x << 1` costs 3 and `x * 2` costs 6.
- **The tests write rules by hand**, as `Rule`s in the corpus style, so they
  don't need `parseRules`.
- **The property wraps 3 terms in 4 in a redex** (`t + 0`, `t * 2`,
  `t xor t`), so the 30% "astSize found a cheaper term" coverage holds by
  construction. It loads its 15 rules once (`propChecked`), because brute
  force over two 8-bit variables is 65536 evaluations a rule.
- `OverloadedStrings` in `Saturate`: for the `Text` literal in `loadRules`.
- **`extract` breaks a tie by the smaller node**, in the ascending order
  `classes` gives. No unit test has a tie.
- **`extract` finds the root with `equiv`** over the `classes` list, so 6b needs
  no second export. It costs one `find` pair per class on each call.
- **`extract` calls `error` for an id the graph never issued.** Its type has no
  failure case, and every class of a real graph has a term, so only a bare `Int`
  from elsewhere reaches it (6b's `ClassId` shortcut).
- **A rule is banned when its matches exceed the threshold, not when they reach
  it**, as in egg and as the Spec's "over its threshold" reads.
- **The iteration that bans a rule drops that rule's matches and counts as
  hiding it**, as in egg. Applying them would defeat the ban on the iteration
  when the rule is largest. The ban's length includes that iteration, so
  `limBan = 1` hides the rule only there.
- **The threshold counts `ematch`'s results**, before preconditions are decided.
- **Preconditions read the literals in the graph when the iteration's search
  ran**, so a literal that an apply adds is seen in the next iteration.
- **"Changed nothing" counts nodes as `classes` does**, canonical and
  deduplicated, the same count as `satNodes`.
- **`loadRules`' reasons.** A width outside 1 to 64 gives `verifyBrute`'s
  `unsupported: width ...` through `renderVerdict`; `ruleToFix`'s `Left` is passed
  on as it is. `verifyBrute` checks the same things first, so neither is reached
  by a test.
- **`loadRules` also refuses a rhs variable the lhs does not bind.** `parseRules`
  rejects these, but `Rule`'s constructor is public, and `verifyBrute` accepts
  `(mul ?x 0) => (mul ?y 0)`. `saturate` would then put a `?y` node in the graph.
- **`limIters` of 0 or less still runs one iteration**, because the stop check
  runs after each iteration. No test passes one.

## 1. `classes`

Tests: `-p EGraph.classes`.

- [ ] *You already canonicalise nodes in `checkInvariants`. Can `classes`
  share that code, and which `Data.Set` function gives "deduplicated, in
  ascending order" in one step?*

## Spec: classes

```haskell
classes :: (Language f) => EGraph f s -> ST s [(ClassId, [f ClassId])]
```

- **Behaviour.** Every class once, in ascending order of its (root) id,
  with its nodes canonicalised, deduplicated and in ascending order. After
  `merge a b` and `rebuild`, `f(a)` and `f(b)` are one node.
- **Tests.** `-p EGraph.classes`: "each class once, by ascending id, with its
  nodes", "after merge a b and rebuild: one class with a and b, and f(a),
  f(b) as one node".

## 2. `astSize` and `shiftsAreCheap`

Tests: `-p "Saturate.extract.astSize and shiftsAreCheap, node by node"`.

- [ ] *`ExprF` is `Foldable`. What does `sum` of an `ExprF Int` add up, and
  what is it for a leaf?*

## Spec: astSize

```haskell
type CostFn f c = f c -> c
astSize :: CostFn ExprF Int
```

- **Behaviour.** 1 plus the children's costs; a leaf costs 1.
- **Tests.** `-p "Saturate.extract.astSize and shiftsAreCheap, node by node"`.

## Spec: shiftsAreCheap

```haskell
shiftsAreCheap :: CostFn ExprF Int
```

- **Behaviour.** Plus the children's costs: a shift (`shl`, `lshr`) 1, a
  multiplication 4, a leaf 1, anything else 2. So `x << 1` costs 3 and
  `x * 2` costs 6.
- **Tests.** `-p "Saturate.extract.astSize and shiftsAreCheap, node by node"`.

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
- [ ] *Run "a cycle through two classes: merge a f(f(a))" and "... merge f(f(a))
  a". Why might one of them fail when the other passes? Which id is the root in
  each?*

## Spec: extract

```haskell
extract :: (Language f, Ord c) => CostFn f c -> EGraph f s -> ClassId -> ST s (Fix f)
```

- **Behaviour.** A cheapest term of the id's class under the cost
  function. Compute a best cost per class as a fixpoint: a node can be
  costed once every child class has a cost, and a class's cost is its
  cheapest costable node's. Then read the term back top-down, taking each
  class's best node.
- **Precondition.** The `CostFn` is strictly monotone: a node costs more
  than each of its children. Then every child on the way down has a
  strictly smaller cost than its parent, so the read-back never revisits a
  class, even when the graph has a cycle.
- **Edge cases.** A non-canonical (stale) id extracts its class. With no
  merges, a term extracts to itself.
- **Tests.** `-p Saturate.extract`: "with no merges, a term extracts to
  itself", "cycles: once f(a) = a, f(a) and f(f(a)) extract to a", "the
  cost function decides: shifts or multiplications", "a stale id still
  extracts its class", "a cycle through two classes: merge a f(f(a))", "a cycle
  through two classes: merge f(f(a)) a".
- **Derivation of the two-class cycle**, with `f = neg` and `astSize`. Add
  `(add a (neg a))` and `(neg (neg a))`, then merge `a` with `(neg (neg a))` and
  rebuild. Call the class of `a` A and the class of `(neg a)` F:
  - A holds `a` and `(neg F)`; F holds `(neg A)`; the sum's class S holds
    `(add A F)`.
  - Congruence merges nothing more: `(neg A)` and `(neg F)` have different
    children, so A and F stay apart. `a = f(f(a))` does not imply `a = f(a)`.
  - Costs: `a` is 1 and `(neg A)` is 2. Then A's `(neg F)` is 3, so A stays at
    1 and F at 2. `(add A F)` is 1 + 1 + 2 = 4.
  - Extraction: A gives `a`; F gives `(neg a)`; the stale id of `(neg (neg a))`
    is in A, so it gives `a`; S gives `(add a (neg a))`.

  The expected list, for the ids of `a`, `(neg a)`, `(neg (neg a))` and the sum,
  is `[a, (neg a), a, (add a (neg a))]`, in both merge directions. No class has
  a tie.

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

## Spec: ematch

```haskell
type ClassSubst = Map Text ClassId
ematch :: EGraph ExprF s -> Fix ExprF -> ST s [(ClassId, ClassSubst)]
```

- **Behaviour.** Every `(class, substitution)` such that the pattern
  matches a term in the class, with each `PVar` bound to a class. A `PVar`
  alone matches every class once. A `VarF` or a literal in the pattern
  matches only itself. A variable that occurs twice must bind one class.
  Matching goes through classes, so a pattern matches a node whose child
  class holds the needed node. A class with two matching nodes, such as
  `(add a b)` and `(add b a)`, gives two results. Class ids are canonical,
  and there are no duplicates. The order is not specified.
- **Tests.** `-p Saturate.ematch`: "(add ?x ?y) on (add a b) binds x to a and
  y to b", "a variable that occurs twice binds one class: (xor ?x ?x)", "it
  matches through classes: (neg (add ?x ?y)) on neg c, once c = a + b", "a
  class holding (add a b) and (add b a) matches (add ?x ?y) twice", "?x
  alone matches every class once", "a term variable in a pattern matches
  only itself: (add a ?y)", "a literal in a pattern matches only itself:
  (add ?x 0)". Results are compared after sorting.

## 5. `loadRules` and `checkedRule`

Tests: `-p Saturate.loadRules` (the last one needs step 6).

- [ ] *Define `CheckedRule`. What does `saturate` need from a rule at match
  time, and at apply time?*
- [ ] *Three steps, any of which can refuse: `instantiate`, `verifyBrute`,
  `ruleToFix`. Can each give an `Either Text` so that one `do` block in
  `Either` runs all three?*
- [ ] *Which `Data.Either` function splits a list of results into the
  accepted and the refused, in order?*

## Spec: checkedRule

```haskell
data CheckedRule      -- constructor not exported
checkedRule :: CheckedRule -> Rule
```

- **Behaviour.** The rule as `loadRules` accepted it, that is, instantiated
  at the load width: `map checkedRule (fst (loadRules 4 [r]))` is
  `maybeToList (instantiate 4 r)` for a valid `r`.
- **Tests.** `-p Saturate.loadRules`: "an accepted rule is instantiated at
  the width".

## Spec: loadRules

```haskell
loadRules :: Int -> [Rule] -> ([CheckedRule], [(Text, Text)])
```

- **Behaviour.** Admit each rule only if it verifies at width `w`: run
  `instantiate w`, then `verifyBrute w` (precondition included), then
  `ruleToFix`. A rule passes only if all three succeed and the verdict is
  `Valid`. The result is the accepted rules and the refused ones as
  `(name, reason)`, each in input order. For a verdict that is not
  `Valid`, the reason is `renderVerdict` of that verdict. `Unsupported` is
  refused, so `add-assoc` (24 bits) is refused at width 8 and accepted at
  width 4.
- **Tests.** `-p Saturate.loadRules`: "a wrong rule is refused, the valid
  ones kept", "the reason is the verdict", "a rule too big to check is
  refused: assoc at width 8 has 24 bits", "the same rule at width 4 is
  accepted", "a valid rule with a precondition is accepted", "an accepted
  rule is instantiated at the width", "the property's rule set loads with
  nothing refused", "a refused rule can't corrupt the graph: not a and neg a
  stay apart".

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

## Spec: saturate

```haskell
data Limits = Limits {limIters, limNodes, limMatches, limBan :: Int}
data StopReason = Saturated | IterLimit | NodeLimit
data SatReport = SatReport {satStop :: StopReason, satIterations :: Int, satNodes :: Int, satBanned :: [Text]}
saturate :: Limits -> [CheckedRule] -> EGraph ExprF s -> ST s SatReport
```

- **Precondition.** The graph holds terms of the width the rules were
  loaded at, and Bools.
- **One iteration.** `ematch` every rule that is not banned, all before
  applying any. Then, for each match, instantiate the rhs (a `PVar` is its
  bound class, any other layer an `addNode`) and merge it with the matched
  class. Then `rebuild`.
- **Preconditions on rules.** A match fires only if every variable of the
  precondition is bound to a class holding a literal, and `eval` on those
  literals gives `true`. Otherwise it is skipped.
- **Scheduler** (egg's backoff). A rule banned `k` times so far has a
  threshold of `limMatches * 2^k` matches. A rule over its threshold in an
  iteration is banned for `limBan * 2^k` iterations, and `k` goes up.
  `satBanned` names every rule banned at least once, in rule order.
- **Stopping.** After each iteration, in this order:
  1. `Saturated` if the iteration changed nothing (the same number of
     classes and nodes before and after) and no rule was hidden by a ban;
  2. `NodeLimit` if the graph has more than `limNodes` nodes;
  3. `IterLimit` after `limIters` iterations.
- **Report.** `satIterations` counts every iteration run, the last included,
  and `satNodes` is the number of nodes in the graph at the end.
- **Tests.** `-p Saturate.saturate`: "x*2 and x<<1 end up in one class;
  shiftsAreCheap picks the shift", "(x+0)+0 extracts to x", "commutativity
  alone saturates: x + y in 2 iterations, 4 nodes", "comm and assoc saturate
  3 variables at 3^3 - 2^4 + 1 + 3 = 15 nodes", "on 7 variables (1932 nodes
  saturated) the node limit stops it", "on 7 variables with 2 iterations
  allowed, the iteration limit stops it", "the scheduler bans rules that
  match too often, in rule order", "bans delay saturation but don't prevent
  it", "with a high threshold, nothing is banned", "saturating a saturated
  graph takes 1 iteration", "a precondition is decided on literals: lshr 3
  4 is 0; lshr 200 4 and lshr x 4 are not". Then the property "the
  extracted term means the same as the input and costs no more".

## 7. Afterwards

- [ ] *Run comm and assoc on 4 to 7 variables and compare the node counts
  with `3^n - 2^(n+1) + 1 + n`. Why does the e-graph grow exponentially even
  though every term is "the same sum"?*
- [ ] *Run the corpus's valid rules through `loadRules 8`. Which are refused
  as `Unsupported`, and would `loadRules 4` accept them?*

## Shortcuts

- **The 64 s timeout comes from today's passing tests.** Ceiling: most tests
  still stop at a stub, so a slow correct test (such as z3 on the corpus, or
  brute force at 2^20) has never been timed, and could time out on a slower
  machine. A loop that does not allocate can't be interrupted. `localOption` also
  overrides `--timeout` on the command line. Upgrade: re-measure once the stubs
  are done.
- **`loadRules` verifies by brute force.** Ceiling: a rule over the
  `2^20`-assignment cap is refused at that width (`add-assoc` at width 8).
  Upgrade: SMT, which would make `loadRules` an `IO` action.
- **`saturate` decides preconditions on literals only.** Ceiling: a
  conditional rule fires only when its variables are bound to classes
  holding literals; sound but incomplete. Upgrade: a constant-folding
  e-class analysis.
- **`ematch` is naive.** Ceiling: patterns are matched top-down against
  every class, with no indexing, so saturation slows down quickly as the
  graph grows; node and iteration limits stop it. Upgrade: indexing or
  relational e-matching (README, "Limitations").
- **`saturate`: "changed nothing" compares counts**, as the Spec says. Ceiling:
  in one iteration, a merge that collapses two nodes and a new node in a new
  class cancel out, so the counts match and `Saturated` can come early. That is
  sound, but it may miss rewrites. Upgrade: compare the two `classes` lists.

## Open questions

None.
