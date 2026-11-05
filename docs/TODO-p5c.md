# Phase 5c TODO: critical pairs

Spec: the `## Spec` entries below. Run a group with, e.g.,
`stack test --test-arguments='-p "Critical.criticalPairs, by hand"'`. Hints are
rung 1 (a question). Ask for the next rung when you want it.

**Prerequisites.** `criticalPairs` needs Phase 5b's `unify` and `applySubst`,
and `joinable` needs `normalise`. `checkPair` needs `toTyped` (5a), `erase`
(2) and `verifySmt` (4b). `renderPair` needs `renderVerdict` (3). `rename`
(step 1) stands alone.

## Decisions

- **`[Rule]` means `[FixRule]`.** Rules with a precondition are skipped, as in
  5b.
- **Fresh names are `x_n`.** `rename` gives each variable the next counter
  value, so the names from one `criticalPairs` call never collide (the
  `rename` Spec says why). The fixtures rename to `v0, v1, ...` by first occurrence
  and sort, so they don't depend on your fresh names or your order.
- **Rules are identified by their position in the list.** The root
  self-overlap is left out only for the same list entry, so `[comm, comm]`
  has two root pairs. Trivial pairs, whose two reducts are equal, are kept;
  `joinable` joins them at once.
- **Positions are `[Int]`, counted in `Foldable` order.** That is the order
  `traverse` and `toList` use, so the test can rewrite at a position with
  `mapAccumL`.
- **`f(g(x)) -> a`, `g(b) -> c` is encoded** with `f = not`, `g = neg`, and
  `a`, `b`, `c` as `VarF` constants. Those constants have no sort, so
  `checkPair` answers `Unsupported` for that pair without calling z3.
- **`PairVerdict` reuses `Verdict`.** For a pair that doesn't join, `Valid`
  means syntactically different but semantically equal (the situation R2
  studies), `Counterexample` means a rule is wrong, and `Unsupported` means
  it couldn't be checked.
- **Joinability follows `normalise`'s single path**, and z3 checks only at the
  written width. Each has a `-- shortcut:` comment naming the ceiling and the
  upgrade.
- **A missing z3 is a `VerifyError`**, from `verifySmt`. The z3 tests skip;
  the two `checkPair` tests that must not call z3 run without it.
- **The `renderPair` golden was written by hand**, from pairs built in the
  test, so it does not depend on `criticalPairs`.
- `OverloadedStrings` in `Critical`: for `Text` literals.
- **`criticalPairs` renames every rule twice up front**, one copy as outer and
  one as inner, from one counter, so the loop stays pure. The fresh numbers
  therefore depend on the whole rule list, and
  `test/golden/cli-critical-pairs.*` records them.
- **`rename` counts `VarF` names too**, as its spec says ("every name"), using
  `vars`. A constant is not renamed but takes a counter value, so the only
  effect is a gap in the numbering.
- **Positions are in pre-order:** a node, then each child's positions in turn,
  as in the `ite-ult-self` derivation. No test observes this order.
- **`cpVars` keeps variables the unifier eliminated**, as the spec's union
  says. A counterexample therefore lists them too, such as `x_46` below.
- **`checkPair` passes a `Fixed` rule named `<outer>/<inner>`.** `Fixed` is what
  makes `verifySmt` keep the pair's written width. A failed conversion is
  `Unsupported` with `show` of the `TypeError`, such as `UnboundVar "a"`.
- **`renderPair` prints terms with its own `cata`**, not `render`, which breaks
  lines past 80 columns and would break the five-line layout. Up to 80 columns
  the text is the same.
- **`renderPair` prints `NotJoinable (Joined t) v`** as `joinable: <t>; <check>`,
  which `checkPair` never builds. A position is `show` of the list, such as
  `[0,1]`.

## 1. `rename`

Tests: `-p Critical.rename`.

- [ ] *Collect the names first. Which `Data.Set` operations give "every name
  in `frVars` or in any side", already in ascending order?*
- [ ] *For each name you need the counter's value and then the counter plus
  one. Which `Control.Monad.State` function does both in one step?*
- [ ] *Once you have a `Map Text Text` from old names to new, do you need a new
  traversal to rename the sides, or can 5b's `applySubst` do it?*

## Spec: rename

```haskell
rename :: FixRule -> State Int FixRule
```

- **Behaviour.** Give the rule fresh variable names. Collect every name in
  `frVars` and in any side (lhs, rhs, precondition), in ascending order.
  Each name `x` becomes `x_n`, where `n` is the counter's value, and the
  counter goes up by one per name. The keys of `frVars` and every `PVar` in
  every side are renamed; the name, width and sorts stay.
- **Why the names never collide.** Every new name ends in a counter value
  that no other new name has, and one `criticalPairs` call threads a single
  counter through all its renames. So two renamed rules share no variable.
- **Tests.** `-p Critical.rename`: "one variable, from 0" (`x` becomes
  `x_0`, the counter ends at 1), "names in ascending order, from 5" (`x_5`,
  `y_6`, ends at 7), "the precondition too", "two renames from one counter
  share no variable".

## 2. `criticalPairs`

Tests: `-p "Critical.criticalPairs, by hand"`, then the property.

- [ ] Positions. *Would the loop be simpler with a helper that lists every
  position of a term together with its subterm? What would its type be, and
  which scheme from 5a gives a node its original children?*
- [ ] Replacing. *The inner reduct puts a term at a position. Is that the same
  walk as the test's `rewriteAt`, with a function in place of the rule?*
- [ ] The loop. *Outer rule, position, inner rule: is a list comprehension
  with three generators enough, plus one guard for the root self-overlap? How
  do you know two rules are "the same" if not by name?*
- [ ] Fresh names. *The comprehension is pure, but `rename` is in `State Int`.
  Which part must be monadic? Could you rename every rule twice up front and
  keep the comprehension pure?*
- [ ] *Why must the two rules be renamed apart before `unify`? Build two rules
  that share the name `?x` and give a unifier that would be missed.*
- [ ] *Why are `PVar` positions left out? What would overlapping at a variable
  produce?*
- [ ] *Run "ite and a comparison below the root". Does your position walk go
  into every kind of node with children?*

## Spec: criticalPairs

```haskell
data CriticalPair = CriticalPair
  { cpOuter :: Text, cpInner :: Text, cpPos :: [Int]
  , cpPeak, cpLeft, cpRight :: Fix ExprF, cpVars :: Context }
criticalPairs :: [FixRule] -> [CriticalPair]
```

- **Behaviour.** Every overlap of one rule's lhs with another's. For each
  outer rule, each position `p` of its lhs that is not a `PVar`, and each
  inner rule: rename the two rules apart, and unify the outer lhs's subterm
  at `p` with the inner lhs. Each unifier `s` gives one pair:
  - `cpPeak` is `applySubst s` of the outer lhs;
  - `cpLeft` is the peak rewritten at the root by the outer rule
    (`applySubst s` of the outer rhs);
  - `cpRight` is the peak rewritten at `p` by the inner rule;
  - `cpVars` is the union of the two renamed rules' `frVars`;
  - `cpOuter`, `cpInner` are the rule names and `cpPos` is `p`.
- **Positions** are `[Int]`, `[]` for the root, each index counting
  children in `Foldable` order.
- **Which pairs.** Rules are identified by their place in the list. The
  root overlap of a list entry with itself is left out, so `[comm]` alone
  gives none but `[comm, comm]` gives two root pairs. Rules with a
  precondition are skipped. Trivial pairs, whose two reducts are equal, are
  kept.
- **Order.** By outer rule in list order, then position, then inner rule in
  list order: for `[not-not, de-morgan-and]` the `not-not / not-not` pair
  comes before `not-not / de-morgan-and`.
- **Laws.** The peak rewrites to `cpLeft` by the outer rule at `[]` and to
  `cpRight` by the inner rule at `cpPos`, and every variable of the three
  terms is in `cpVars`.
- **Tests.** `-p "Critical.criticalPairs, by hand"`: "f(g(x)) -> a and g(b)
  -> c", "add-zero and comm", "not-not and de-morgan-and", "a rule with a
  precondition is skipped", "a rule alone: no root self-overlap", "the same
  rule twice in the list overlaps at the root", "the variables and their
  sorts", "ite and a comparison below the root", and the property "each peak
  rewrites to exactly its two reducts". Pairs are compared after renaming variables to `v0, v1, ...` by first
  occurrence and sorting, so your fresh names and order don't matter there.
- **Derivation of "ite and a comparison below the root".** The rules:
  - `ite-ult-self`: `(ite (ult (neg ?x) (neg ?x)) ?y (neg ?z)) => (neg ?z)`
  - `neg-neg`: `(neg (neg ?x)) => ?x`
  - `ult-self`: `(ult ?x ?x) => false`

  Write `w` for the renamed variable of the inner rule. The non-`PVar` positions
  of the first lhs are `[]` (ite), `[0]` (ult), `[0,0]`, `[0,1]` and `[2]`
  (neg). `[1]`, `[0,0,0]`, `[0,1,0]` and `[2,0]` are variables. Each overlap:

  | Outer / inner | Position | Unifier | Peak | Left | Right |
  |---|---|---|---|---|---|
  | `ite-ult-self` / `neg-neg` | `[0,0]` | `?x := (neg w)` | `(ite (ult (neg (neg w)) (neg (neg w))) ?y (neg ?z))` | `(neg ?z)` | `(ite (ult w (neg (neg w))) ?y (neg ?z))` |
  | `ite-ult-self` / `neg-neg` | `[0,1]` | `?x := (neg w)` | the same | `(neg ?z)` | `(ite (ult (neg (neg w)) w) ?y (neg ?z))` |
  | `ite-ult-self` / `ult-self` | `[0]` | `w := (neg ?x)` | `(ite (ult (neg ?x) (neg ?x)) ?y (neg ?z))` | `(neg ?z)` | `(ite false ?y (neg ?z))` |
  | `ite-ult-self` / `neg-neg` | `[2]` | `?z := (neg w)` | `(ite (ult (neg ?x) (neg ?x)) ?y (neg (neg w)))` | `(neg (neg w))` | `(ite (ult (neg ?x) (neg ?x)) ?y w)` |
  | `neg-neg` / `neg-neg` | `[0]` | `?x := (neg w)` | `(neg (neg (neg w)))` | `(neg w)` | `(neg w)` |

  Nothing else overlaps. `ite` unifies with no other rule's lhs, and its own root
  overlap is left out. `neg` and `ult` never unify with each other. `neg-neg` and
  `ult-self` have no other non-`PVar` position that unifies, and their own root
  overlaps are left out. So there are 5 pairs.

## 3. `joinable`

Tests: `-p Critical.joinable`.

- [ ] *`normalise` gives `([Text], NormalForm)`. Which part do you need, and
  which combinations of the two sides give `Joined`, `NotJoined` and
  `Unknown`?*
- [ ] *Why does the order `[comm, add-zero]` give `Unknown` where
  `[add-zero, comm]` joins? Walk `(add 0 v0)` through both.*

## Spec: joinable

```haskell
data Joinability = Joined (Fix ExprF) | NotJoined (Fix ExprF) (Fix ExprF) | Unknown
joinable :: Int -> [FixRule] -> CriticalPair -> Joinability
```

- **Behaviour.** `normalise fuel rules` both reducts (`cpLeft`, `cpRight`).
  Both `Done` with equal normal forms: `Joined t`. Both `Done` with
  different ones: `NotJoined l r`. Anything else (a `Cycle` or
  `OutOfFuel` on either side): `Unknown`.
- **Tests.** `-p Critical.joinable`: "f(g(x)) -> a and g(b) -> c: two normal
  forms", "add-zero then comm: both pairs join", "comm then add-zero: comm
  cycles first, so Unknown", "not-not and de-morgan-and".

## 4. `checkPair`

Tests: `-p Critical.checkPair`.

- [ ] *`verifySmt` takes a `Rule`, whose sides are `Expr`s, and you have
  `Fix ExprF`. Which two functions from earlier phases take you from one to
  the other, and what can fail on the way?*
- [ ] *A failure there is a verdict (`Unsupported`), not a `VerifyError`. How
  do you turn an `Either Text` into a `Verify PairVerdict` without throwing?*
- [ ] *Why is a joined pair returned without asking z3, even though z3 would
  say `Valid`?*
- [ ] *If z3 finds a counterexample to a critical pair, at least one of the
  two rules is unsound. Why? What does the counterexample tell you about the
  rule at the root?*

## Spec: checkPair

```haskell
data PairVerdict = Joinable (Fix ExprF) | NotJoinable Joinability Verdict
checkPair :: Int -> [FixRule] -> CriticalPair -> Verify PairVerdict
```

- **Behaviour.** If `joinable fuel rules cp` is `Joined t`, return
  `Joinable t` without calling z3. Otherwise, with `j` the joinability
  (`NotJoined` or `Unknown`), ask whether the two reducts are equal:
  convert `cpLeft` and `cpRight` back to `Expr`s through `toTyped cpVars`
  and `erase`, and run `verifySmt` on the rule `cpLeft => cpRight` over
  `cpVars`, at the pair's written width. The result is `NotJoinable j v`:
  - `Valid`: syntactically different, semantically equal;
  - `Counterexample`: at least one of the two rules is unsound;
  - `Unsupported`: couldn't be checked.
- **Edge cases.** A conversion that fails, such as a `VarF` constant that is
  not in `cpVars`, is `Unsupported`, decided before z3 is called. A
  missing z3 is a `VerifyError`, from `verifySmt`.
- **Tests.** `-p Critical.checkPair`: "a joined pair needs no z3", "a VarF
  constant is not in cpVars: Unsupported before z3" (both run without z3),
  and with z3: "de Morgan: syntactically different, semantically equal",
  "xor-self and the wrong xor-left: unsound".

## 5. `renderPair`

Tests: `-p Critical.renderPair`.

- [ ] *Phase 1's `render` prints an `Expr`. Can it print a `PVar` as `?x`? If
  not, is a `cata` over `Fix ExprF` shorter than converting to `Expr` first?*
- [ ] *Each line ends in a newline, including the last. Which `Data.Text`
  function joins lines that way?*
- [ ] *The golden file is the spec. Run the test, read the diff, and do not
  `--accept` until your output and the file differ only in a way you
  understand.*

## Spec: renderPair

```haskell
renderPair :: CriticalPair -> PairVerdict -> Text
```

- **Behaviour.** Five lines, each ending in a newline:

  ```
  <outer> / <inner> at <pos>
    peak:  <term>
    left:  <term>
    right: <term>
    <verdict>
  ```

  `<pos>` is the position list as `[0]` or `[]`. A term is printed as
  Phase 1's `render` would, with a `PVar x` as `?x` and a `VarF a` as `a`.
  `<verdict>` is:
  - `joinable: <t>` for `Joinable t`;
  - `not joined: normal forms <l> and <r>; <check>` for
    `NotJoinable (NotJoined l r) v`;
  - `not joined: no normal form within the budget; <check>` for
    `NotJoinable Unknown v`;

  where `<check>` is `syntactically different, semantically equal` for
  `Valid`, `UNSOUND: ` and `renderVerdict` of the verdict for a
  `Counterexample`, and `not checked: <msg>` for `Unsupported msg`.
- **Tests.** `-p Critical.renderPair`: the golden
  `test/golden/critical-pairs.txt`, written by hand from 5 pairs built in
  the test (blocks joined by a blank line).

## 6. Run it on the corpus

When everything passes, run `criticalPairs` on the valid corpus rules
(through `ruleToFix`) and `checkPair` on each pair.

- [ ] *How many pairs are `Joinable`, how many are semantically equal, and is
  any `UNSOUND`? If one is, which of its two rules is wrong, and does
  `verifyBrute` agree?*

## Shortcuts

- **`joinable` follows `normalise`'s single path.** Ceiling: a pair that
  joins only along another rewriting order is reported `NotJoined` or
  `Unknown`. Upgrade: not recorded (the `-- shortcut:` comment was removed
  before it was committed).
- **`checkPair` asks z3 only at the written width.** Ceiling: a pair equal
  at that width but not at others is reported `Valid`. Upgrade: not
  recorded, as above.
- Both appear in README, "Limitations": critical pairs are joined along one
  rewriting path and checked only at the chosen width.

## Open questions

None.
