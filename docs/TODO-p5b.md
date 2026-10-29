# Phase 5b TODO: matching, unification, rewriting

Spec: the Haddock in `src/Lozenge/Rewrite.hs`. Run a group with, e.g.,
`stack test --test-arguments='-p Rewrite.match'`. Hints are rung 1 (a
question). Ask for the next rung when you want it.

**Prerequisites.** Phase 5a's `cata` (or plain recursion) is all you need. The
tests build their rules as `FixRule`s by hand, so nothing here waits on
`typecheck`, `ruleToFix` or `parseRules`.

## Decisions

- **`[Rule]` means `[FixRule]`**, as Phase 5a decided.
- **Only `PVar` is a variable.** `VarF a` is a constant symbol, like a literal.
  In `match`, a `PVar` in the *subject* is a constant too: only the pattern's
  variables get bound.
- **Preconditions are ignored in this phase.** `rewriteOnce` and `normalise`
  skip every rule that has one, so they never rewrite with a rule they can't
  check. `normalise` returns the names of the skipped rules, so its type is
  `([Text], NormalForm)`, not `NormalForm`. Phase 5c handles preconditions.
- **`NormalForm` has three constructors:** `Done`, `Cycle k ts` and
  `OutOfFuel ts`. A cycle is a repeat of *any* earlier term, not just the
  input. The repeat check comes before the fuel check, and `Done` wins when
  the last step the fuel allows reaches a normal form.
- **`unify` returns an idempotent most general unifier.** Then one
  `applySubst` pass is enough, and "most general" can be tested as
  `u . s = u` for every unifier `u`. The same `PVar` name on both sides is one
  variable. Phase 5c renames rules apart before unifying them.
- **`match` ignores sorts.** The `-- shortcut:` comment names the ceiling and
  the upgrade.
- **A Generic rule matches only at its written width**, because its literals
  carry that width. Run `instantiate w` on the `Rule` before `ruleToFix` to
  rewrite at width `w`.
- **The most-general test is a brute-force check.** For pairs of terms of
  depth 3 or less over `?x` and `?y`, it tries all 225 bindings of the two
  variables to ground terms of depth 2 or less. Every one that unifies the
  pair must factor through your answer, and if you say `Nothing`, none may
  unify.

## 1. `applySubst`

Tests: `-p Rewrite.applySubst`.

- [ ] *Which leaf is the only one that changes? Can you write it as a
  `cata` whose algebra handles one case and rebuilds every other layer as it
  is?*
- [ ] *The "one pass" test maps `?x` to `?y` and `?y` to `a`. Why does a
  `cata` give `?y` there and not `a`?*

## 2. `match`

Tests: `-p Rewrite.match`.

- [ ] *Matching walks the pattern and the subject together. When the pattern
  is not a `PVar`, what must be true of the two top layers before you look at
  the children? Is there a way to compare "same constructor, same operator,
  same leaf" without writing one case per constructor?*
- [ ] *A `PVar x` is reached a second time. You already have a binding for
  `x`. What do you compare, and with which `Eq` instance?*
- [ ] *The children's matches must agree with each other. Do you thread one
  `Subst` through the children in order, or match each child separately and
  combine the maps? With the second way, what goes wrong when two maps bind
  the same variable?*
- [ ] *Which `Foldable` or `Traversable` function walks the children of two
  layers in step? If there is none, what can you zip?*

## 3. `unify`

Tests: `-p Rewrite.unify`.

- [ ] *How is `unify` different from `match`? Which side may now contain
  variables, and what happens when both sides are variables?*
- [ ] *You are about to bind `x` to `t`. Which two checks must come first, and
  what is the occurs check protecting against?*
- [ ] *Idempotence: after binding `x` to `t`, some values in your `Subst` may
  still contain `x`. What must you do to them, and to `t` itself, so that no
  bound variable appears in any value?*
- [ ] *Why must you apply the current `Subst` to both children before you
  unify the next pair? Which test fails if you don't?*
- [ ] *The textbook algorithm works on a list of equations. Is that easier
  here than recursing on the two terms?*

## 4. `rewriteOnce`

Tests: `-p Rewrite.rewriteOnce`.

- [ ] *At one position, "try the rules in order, take the first that works" is
  a fold over a list of `Maybe`s. Is there already a function that picks
  the first `Just`, and which class is it from?*
- [ ] *Going into the children: you want to rewrite only the first child that
  can be rewritten and leave the rest. Why does `traverse` with `Maybe` not do
  that? What would it do instead?*
- [ ] *Is `para` useful here? At each node you need both the rewritten child
  and the original children.*

## 5. `normalise`

Tests: `-p Rewrite.normalise`.

- [ ] *The loop's state is the fuel left, the terms seen so far, and the
  current term. Which data structure answers "seen before?" quickly, and which
  instance from Phase 5a makes that possible?*
- [ ] *You need a set for the check and a list for the result. Can one value
  serve both, or do you keep both?*
- [ ] *Write down the order of the three checks (normal form? repeat? fuel
  left?) and walk the "fuel 2 is just enough" and "cycle that closes on the
  last step" tests through it.*
- [ ] *The cycle check catches a repeat. Give a rule that never terminates
  and never repeats a term. What does the "growing term" test use?*
