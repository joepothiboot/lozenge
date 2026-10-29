# Phase 4c TODO: a tiny symbolic executor (optional)

The smallest version of Grisette's idea on this IR. Spec: the Haddock in
`src/Lozenge/SymExec.hs`. Run a group with, e.g.,
`stack test --test-arguments='-p SymExec.Union'`. Hints are rung 1 (a
question). Ask for the next rung when you want it.

**Prerequisites.** Steps 1 to 4 stand alone. The z3 tests also need Phase 4a's
`smtName` and `toSmt`: until those are written, they fail with
`TODO: smtName`.

## Decisions

- **`TExpr` is not extended.** `TExpr 'TBool` has no `and`, `not` or Bool
  `ite`, and `TIte` takes only bitvectors. Adding constructors would change
  the Phase 2 and 4a exercises (`erase`, `evalT`, `toSmt`), so `andC`, `notC`
  and the Bool `mrgIte` must be built from the constructors that exist. Only
  equivalence is tested, by z3, so any correct encoding passes.
- **One width per program.** `Program w`, `Env w` and `symExec :: Program w ->
  Union (Env w)` put the width in the type. Every program variable is a
  `'TBV w`; Bool values only appear as conditions and in `envOk`. This keeps
  `subst` and `mrgIte @Env` total.
- **An unassigned variable is an input.** There are no declarations: reading
  `x` before assigning it gives the free `TVar x`, and so does merging an `Env`
  that never assigned it.
- **`Assert` records and goes on.** Each path's `envOk` says whether its
  asserts held, so the program is safe exactly when the merged `envOk` is
  valid. This keeps the user's `Program -> Union Env` shape; dropping the
  failing paths instead would make it `assume`.
- **`symExec` does not merge.** You call `merge` at the end. The
  `-- shortcut:` comment names the cost (2^n paths) and the upgrade.
- **`Union`'s constructor is exported.** The invariant (disjoint guards) is
  only documented. Grisette hides its constructor to enforce the invariant;
  here the tests build unions by hand.
- **Tests compare by `show`.** `TExpr` has no `Eq` instance. Where the spec
  fixes the exact term (the `andC` `true` law, `subst`, the order of `>>=`),
  the tests compare `show` output. Everywhere else they ask z3.

## 1. `andC` and `notC`

Tests: `-p "SymExec.andC and notC"` (the two `true` cases run without z3).

- [ ] *List the `TExpr` constructors whose result type is `TExpr 'TBool`.
  Which constructor is the only one that takes a `TExpr 'TBool` as an
  argument, and what type does it return?*
- [ ] *Once you have a bitvector, how do you get back to a `TExpr 'TBool`?
  Which width is the smallest that can hold a truth value?*
- [ ] *The law says `andC true c` must return `c` itself. Why can't you test
  for "is `true`" with `==` here, and what can you pattern-match on instead?*

## 2. `Functor`, `Applicative`, `Monad` for `Union`

Tests: `-p SymExec.Union`.

- [ ] *`Union` wraps a list of pairs. Which existing `Functor` instances can
  `fmap` reuse, and how many layers deep is the value?*
- [ ] *`>>=` makes a list from a list of lists. Which list syntax builds that
  in one expression and lets you name the outer guard and the inner guard?*
- [ ] *Write `>>=` first. Can `<*>` then be written without looking at the
  guards at all?*
- [ ] *Why does left identity hold syntactically only because of the `andC`
  law? What would `pure a >>= f` look like without it?*

## 3. `mrgIte` for BV and Bool, then `merge`

Tests: `-p SymExec.mrgIte`, then `-p SymExec.merge`.

- [ ] *For BV, is there a constructor that is already `mrgIte`? For Bool, can
  you reuse step 1's encoding?*
- [ ] *`merge` folds n entries into one value with n − 1 `mrgIte`s. Which end
  of the list does the fold start from, and why does the last value need no
  test?*
- [ ] *Why is `merge` only correct if the guards are disjoint? Give two
  overlapping guards whose merge gives the wrong value under one assignment.*
- [ ] *The merged guard is a disjunction, but there is no `orC`. Which identity
  gives `or` from `andC` and `notC`?*
- [ ] *Grisette merges as it runs, not once at the end. What does that save,
  and what does it cost in the size of each term?*

## 4. `subst`

Tests: `-p SymExec.subst`.

- [ ] *At a `TVar s x` of type `TExpr t`, the map gives a
  `TExpr ('TBV w)`. What must GHC know before it accepts that value as a
  `TExpr t`, and what in `s` can tell it?*
- [ ] *Two `SNat`s can be compared at runtime. How do you turn "they are
  equal" into a proof that GHC can use? Is there already a class in `base`
  that decides whether two type indices are equal?*
- [ ] *Why does the "x and y swap" test need one pass, and what would two
  passes give?*

## 5. `mrgIte` for `Env`

Tests: the `Env` cases in `-p SymExec.symExec` once step 6 is done; until then,
write a quick check in GHCi.

- [ ] *Which `Data.Map` function combines two maps and lets you handle "only
  left", "only right" and "both" differently?*
- [ ] *A variable only one side assigned must be `TVar (SBV w) x` on the other
  side. Where can you get an `SNat w` when the `Env` doesn't store one? Which
  `TExpr ('TBV w)` constructors carry it, and is every term built from them?*

## 6. `symExec`

Tests: `-p SymExec.symExec`.

- [ ] *Running one statement takes an `Env w` and gives a `Union (Env w)`.
  Running a block is then a fold in a monad. Which `Control.Monad` function is
  that?*
- [ ] *An `If` needs two guarded starting points, one for each branch. How do
  you build a `Union` that holds both and then runs a different block in each?*
- [ ] *Which statements must call `subst`, and on what? What would the
  "condition sees earlier assignments" test give if `If` did not?*
- [ ] *The shortcut comment says some paths are infeasible. Give a two-`If`
  program with an unsat path. Which tool would detect it, and at what cost
  per `If`?*

## 7. Read the main test

`-p "two branches merge"` checks, with z3, that `merge (symExec maxProg)` is one
entry whose `m` equals `ite (x <u y) y x`, whose guard is valid, and whose
`envOk` is valid.

- [ ] *Write down the terms your `merge` produces for `m`, for the guard and
  for `envOk`. Which of the three checks could `show` do instead of z3, and
  which could it not?*
