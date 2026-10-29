# Phase 5c TODO: critical pairs

Spec: the Haddock in `src/Lozenge/Critical.hs`. Run a group with, e.g.,
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
  Haddock says why). The fixtures rename to `v0, v1, ...` by first occurrence
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

## 1. `rename`

Tests: `-p Critical.rename`.

- [ ] *Collect the names first. Which `Data.Set` operations give "every name
  in `frVars` or in any side", already in ascending order?*
- [ ] *For each name you need the counter's value and then the counter plus
  one. Which `Control.Monad.State` function does both in one step?*
- [ ] *Once you have a `Map Text Text` from old names to new, do you need a new
  traversal to rename the sides, or can 5b's `applySubst` do it?*

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

## 3. `joinable`

Tests: `-p Critical.joinable`.

- [ ] *`normalise` gives `([Text], NormalForm)`. Which part do you need, and
  which combinations of the two sides give `Joined`, `NotJoined` and
  `Unknown`?*
- [ ] *Why does the order `[comm, add-zero]` give `Unknown` where
  `[add-zero, comm]` joins? Walk `(add 0 v0)` through both.*

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

## 5. `renderPair`

Tests: `-p Critical.renderPair`.

- [ ] *Phase 1's `render` prints an `Expr`. Can it print a `PVar` as `?x`? If
  not, is a `cata` over `Fix ExprF` shorter than converting to `Expr` first?*
- [ ] *Each line ends in a newline, including the last. Which `Data.Text`
  function joins lines that way?*
- [ ] *The golden file is the spec. Run the test, read the diff, and do not
  `--accept` until your output and the file differ only in a way you
  understand.*

## 6. Run it on the corpus

When everything passes, run `criticalPairs` on the valid corpus rules
(through `ruleToFix`) and `checkPair` on each pair.

- [ ] *How many pairs are `Joinable`, how many are semantically equal, and is
  any `UNSOUND`? If one is, which of its two rules is wrong, and does
  `verifyBrute` agree?*
