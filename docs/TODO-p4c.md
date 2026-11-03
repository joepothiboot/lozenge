# Phase 4c TODO: a tiny symbolic executor (optional)

The smallest version of Grisette's idea on this IR. Spec: the `## Spec`
entries below. Run a group with, e.g.,
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

## Spec: andC

```haskell
type Cond = TExpr 'TBool
andC :: Cond -> Cond -> Cond
```

- **Behaviour.** A condition equivalent to `a and b`, built from the
  `TExpr` constructors that exist (`TExpr` has no `and`).
- **Laws.** `andC true c` is `c` itself, and so is `andC c true`, where
  `true` is `TLit (VBool True)`. "Itself" means the same term (compared by
  `show`), not just an equivalent one.
- **Tests.** `-p "SymExec.andC and notC"`: "true on the left is dropped",
  "true on the right is dropped" (no z3), and "andC is and" (z3, on the
  pairs `(p, q)`, `(lt, gt)`, `(p, false)`, `(false, p)`, `(true, true)`).

## Spec: notC

```haskell
notC :: Cond -> Cond
```

- **Behaviour.** A condition equivalent to `not c`, built from the existing
  constructors.
- **Tests.** `-p "SymExec.andC and notC"`: "notC is not" (z3, on `p`,
  `x <u y` and `false`).

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

## Spec: fmap @Union

```haskell
newtype Union a = Union {unUnion :: [(Cond, a)]}
fmap :: (a -> b) -> Union a -> Union b
```

- **Behaviour.** Apply the function to each value; keep every guard and the
  order. Invariant of `Union` (documented, not enforced): the guards are
  disjoint.
- **Laws.** `fmap id u` is `u` (by `show`).
- **Tests.** `-p SymExec.Union`: "fmap keeps guards and order", property
  "fmap id".

## Spec: pure @Union

```haskell
pure :: a -> Union a
```

- **Behaviour.** `pure a` is `Union [(true, a)]`.
- **Tests.** `-p SymExec.Union`: "pure".

## Spec: <*> @Union

```haskell
(<*>) :: Union (a -> b) -> Union a -> Union b
```

- **Behaviour.** Agrees with `ap` for this `Monad`.
- **Tests.** `-p SymExec.Union`: "<*> agrees with ap".

## Spec: >>= @Union

```haskell
(>>=) :: Union a -> (a -> Union b) -> Union b
```

- **Behaviour.** For each entry `(g, a)` in order, and each entry `(h, b)`
  of `f a` in order, one entry `(andC g h, b)`. Outer order first. No
  entries in, no entries out.
- **Laws.** Left identity `pure a >>= f` is `f a`, and right identity
  `u >>= pure` is `u`, both by `show`. They hold syntactically only because
  of `andC`'s `true` law. Neither needs disjoint guards.
- **Tests.** `-p SymExec.Union`: "bind: andC of outer and inner guard, outer
  order first", "bind on no entries", properties "left identity" and "right
  identity".

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

## Spec: mrgIte @BV

```haskell
class Mergeable a where mrgIte :: Cond -> a -> a -> a
instance Mergeable (TExpr ('TBV w))
```

- **Behaviour.** `mrgIte c t e` is equivalent to `ite c t e`.
- **Tests.** `-p SymExec.mrgIte`: "BV" (z3).

## Spec: mrgIte @Bool

```haskell
instance Mergeable (TExpr 'TBool)
```

- **Behaviour.** `mrgIte c t e` is equivalent to `ite c t e` on booleans,
  built from the existing constructors (`TIte` takes only bitvectors).
- **Tests.** `-p SymExec.mrgIte`: "Bool", "Bool, literal branches"
  (`mrgIte p false true` is `not p`). Both need z3.

## Spec: SymExec.merge

```haskell
merge :: (Mergeable a) => Union a -> Union a
```

- **Behaviour.** No entries: no entries. One entry: that entry, unchanged.
  Two or more: one entry `(g, v)`, where `g` is equivalent to the
  disjunction of the guards, and `v` equals `v_i` wherever `g_i` holds,
  built with `mrgIte`.
- **Precondition.** The guards are disjoint. With overlapping guards the
  merged value can be wrong.
- **Tests.** `-p SymExec.merge`: "no entries", "one entry comes back
  unchanged", and with z3: "three BV entries", "two Bool entries", "guard
  is the disjunction".

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

## Spec: subst

```haskell
subst :: Map Text (TExpr ('TBV w)) -> TExpr t -> TExpr t
```

- **Behaviour.** Replace every `TVar (SBV w) x` at the map's width `w`
  whose name `x` is in the map by its value, under every constructor. One
  pass: a replacement is not substituted again, so mapping `x` to `y` and
  `y` to `x` swaps them. Bool variables, variables of another width, and
  names not in the map stay.
- **Tests.** `-p SymExec.subst`: "every occurrence", "under a comparison and
  an ite", "one pass: x and y swap", "unbound and Bool variables stay", "a
  variable of another width stays".

## 5. `mrgIte` for `Env`

Tests: the `Env` cases in `-p SymExec.symExec` once step 6 is done; until then,
write a quick check in GHCi.

- [ ] *Which `Data.Map` function combines two maps and lets you handle "only
  left", "only right" and "both" differently?*
- [ ] *A variable only one side assigned must be `TVar (SBV w) x` on the other
  side. Where can you get an `SNat w` when the `Env` doesn't store one? Which
  `TExpr ('TBV w)` constructors carry it, and is every term built from them?*

## Spec: mrgIte @Env

```haskell
data Env w = Env {envVars :: Map Text (TExpr ('TBV w)), envOk :: Cond}
instance Mergeable (Env w)
```

- **Behaviour.** `mrgIte c l r` merges two paths' environments:
  - a variable both sides assign is `mrgIte c (l ! x) (r ! x)`;
  - a variable only one side assigns has its input `TVar (SBV w) x` on the
    other side, since an unassigned variable is an input;
  - `envOk` is `mrgIte c (envOk l) (envOk r)`.
- **Tests.** Through `-p SymExec.symExec`: "a variable one branch leaves
  alone keeps its input there" and "an assert that can fail" (z3).

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

## Spec: symExec

```haskell
data Stmt w = Assign Text (TExpr ('TBV w)) | If Cond [Stmt w] [Stmt w] | Assert Cond
type Program w = [Stmt w]
symExec :: Program w -> Union (Env w)
```

- **Behaviour.** Run the program on every path, without merging; the
  caller calls `merge`. It starts from one path, `(true, Env empty true)`.
  - `Assign x e` sets `x` to `e` with the path's current assignments
    substituted in (`subst`). Reading a variable never assigned gives its
    input `TVar x`.
  - `If c t e` substitutes the current assignments into `c`, then splits
    the path in two: guard `c` running `t`, and guard `notC c` running `e`.
  - `Assert c` records and goes on: `envOk` becomes `andC envOk c'`, where
    `c'` is `c` with the assignments substituted in.
- **Laws.** One `If` doubles the paths, so `n` `If`s in a row give `2^n`.
  Nested `If`s give one path per leaf. The program is safe exactly when
  the merged `envOk` is valid.
- **Edge cases.** `symExec []` is exactly `Union [(true, Env empty true)]`.
  Straight-line code keeps guard and `envOk` as the literal `true`.
- **Tests.** `-p SymExec.symExec`: "empty program", "straight line, each
  assignment sees the last", "two branches give two paths before
  merging", "two ifs in a row give four paths", and with z3: "two branches
  merge into one ite, equal to the hand-written max", "a variable one branch
  leaves alone keeps its input there", "the condition sees earlier
  assignments", "nested ifs", "an assert that always holds", "an assert
  that can fail".

## 7. Read the main test

`-p "two branches merge"` checks, with z3, that `merge (symExec maxProg)` is one
entry whose `m` equals `ite (x <u y) y x`, whose guard is valid, and whose
`envOk` is valid.

- [ ] *Write down the terms your `merge` produces for `m`, for the guard and
  for `envOk`. Which of the three checks could `show` do instead of z3, and
  which could it not?*

## Shortcuts

- **`symExec` does not merge as it runs.** Ceiling: `n` `If`s in a row give
  `2^n` paths, infeasible ones included. Upgrade: not recorded (the
  `-- shortcut:` comment was removed before it was committed); step 3
  compares Grisette, which merges as it runs.
- **`Union`'s constructor is exported.** Ceiling: nothing enforces disjoint
  guards; the tests build unions by hand. Upgrade: hide the constructor,
  as Grisette does (see Decisions).

## Open questions

- `symExec`: the order of the two paths an `If` creates. The tests check
  only the number of paths and, through z3, the merged result.
- `merge`: the merged value where no guard holds. Disjoint guards that
  cover every case never reach it.
