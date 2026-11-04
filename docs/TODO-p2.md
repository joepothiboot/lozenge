# Phase 2 TODO: typed IR

Spec: the `## Spec` entries below. Each step names the tests that should go
green; run a group with, e.g., `stack test --test-arguments='-p Typed.erase'`.
Hints are rung 1 (a question). Ask for the next rung when you want it.

**First finish Phase 1's `validValue` and `eval`.** Phase 2 uses `validValue`,
and every Phase 2 property compares against `eval`, so until both work those
properties fail with `TODO: eval`.

## 1. `Lozenge.Typed.erase`

Tests: `-p Typed.erase`.

- [ ] Imports. *Phase 1's `Value` and the typed `Value` both have constructors
  named `VBool` and `VBV`. How will you import `Lozenge.Expr` so that one
  module can use both?*
- [ ] `erase`. *The typed `VBV` holds an `SNat w`, but the untyped one wants an
  `Int`. Which function turns an `SNat` into a number, and what type does it
  return?*

## Spec: erase

```haskell
erase :: TExpr t -> Expr
```

- **Behaviour.** Forget the sorts: `TVar _ x` is `Var x`, `TLit` is `Lit`,
  `TUn` is `Un`, `TBin` is `Bin`, `TCmp` is `Cmp`, `TIte` is `Ite`. A typed
  value becomes the Phase 1 value with the same payload: `VBool b` is
  `VBool b`, and `VBV w v` is `VBV n v`, where `n` is the width `w` as a
  number.
- **Laws**, with `typecheck`:
  - If `typecheck ctx e == Right (SomeExpr s te)`, then `erase te == e`.
  - If `ctx` declares every variable of `te` at the sort it has in `te`,
    and every literal and width in `te` is well formed, then
    `typecheck ctx (erase te)` succeeds at the sort of `te`.
- **Tests.** `-p Typed.erase`: 10 cases, each named by the typed term (for
  example a width-13 literal and the widest literal, `2^64 - 1` at width
  64). The laws are the `Typecheck` property "accepts generated well-typed
  terms, and erase undoes it".

## 2. `Lozenge.EvalT.checkEnv`

Tests: `-p EvalT.checkEnv`.

- [ ] One variable. *Can you write the four checks for one `(name, sort)` pair
  as a single `do` block in `Either TypeError`, in the order the Spec
  gives?*
- [ ] All of them. *In what order does `Map.toList` return the declared
  variables, and which function runs your one-variable check over a list,
  stopping at the first `Left`?*
- [ ] The result. *Which `Data.Map.Strict` function keeps only the keys that
  the context declares?*

## Spec: checkEnv

```haskell
checkEnv :: Context -> Env -> Either TypeError TEnv
```

- **Behaviour.** Check that `env` gives every variable the context
  declares a well-formed value of its declared sort. The result keeps only
  the declared variables; the others are dropped.
- **Order.** The declared variables are checked in ascending order of name,
  and the first error is returned. For each one:
  1. `InvalidSort ty` if its declared width is outside `1..64`;
  2. `UnboundVar x` if `env` does not bind it;
  3. `InvalidValue v` if its value is not `validValue`;
  4. if the value has another sort: `ExpectedBV` (declared `BV w`, bound to
     a `Bool`), `ExpectedBool w` (declared `Bool`, bound to a `BV w`), or
     `WidthMismatch declared bound`.
- **Edge cases.** The empty context accepts the empty environment.
  Variables `env` binds but the context does not declare are not errors.
- **Tests.** `-p EvalT.checkEnv`: "testEnv models testContext",
  "undeclared variables are ignored", "empty", "not bound", "declared Bool,
  bound to a BV", "declared BV, bound to a Bool", "declared BV 16, bound to
  a BV 8", "ill-formed value", "declared width 0", "declared width 65",
  "first variable by name", "sort before binding", "value before its sort".

## 3. `Lozenge.EvalT.evalT`

Tests: `-p EvalT.evalT`, then `-p EvalT.properties`.

- [ ] `TLit` and `TVar`. *For `TVar s x` you have a `SingTy t` and maybe an
  untyped value. What must be true of that value before you can return it as
  a `Value t`, and what do you return when it isn't?*
- [ ] `TUn` and `TBin`. *`TBin` stores no width, but you need `2^w`. Once you
  have evaluated the operands, where is `w`?*
- [ ] `TCmp` and `TIte`. *In the `TIte` case, `evalT env c` has type
  `Value 'TBool`. Which constructors can it be, so how many cases does your
  `case` need?*
- [ ] Sharing. *Phase 1's `eval` already computes `add`, `shl`, `slt` and the
  rest on `Integer`s. How could both evaluators use the same arithmetic,
  without either one depending on the other's error handling?*
- [ ] Property `evalT agrees with Phase 1 eval`. *When it fails, QuickCheck
  shrinks the typed term. Which row of `docs/SEMANTICS.md` does the smallest
  counterexample exercise?*

## Spec: evalT

```haskell
evalT :: TEnv -> TExpr t -> Value t
```

- **Behaviour.** Each operation means what SEMANTICS.md says. Every
  bitvector result is in `[0, 2^w)`, and a shift by `w` or more gives 0.
  `TVar s x` reads the value the `TEnv` binds to `x` if it has sort `s`,
  and otherwise the zero of `s` (`VBool False` or `VBV w 0`), as with Z3's
  model completion. So a variable that is missing, or bound at another
  sort, reads as zero.
- **Laws.** Total: never fails and never throws, given well-formed literals
  and widths in `1..64` (all that `typecheck` builds). If
  `typecheck ctx e == Right (SomeExpr s te)` and
  `checkEnv ctx env == Right tenv`, then Phase 1's `eval env e` is
  `Right v`, where `v` is `evalT tenv te` as a Phase 1 value.
- **Tests.** `-p EvalT.evalT`: 17 cases, each named by the typed term,
  including "not bound at this sort: zero" (`nope`, `x` read as `Bool`, `x`
  read at width 16) and "variables the context does not declare read as
  zero". Then `-p EvalT.properties`: "evalT agrees with Phase 1 eval".

## 4. `Lozenge.Typecheck.typecheck`

Tests: `-p Typecheck.accepts`, `-p Typecheck.rejects`, then all of
`-p Typecheck`.

- [ ] Why `SomeExpr`. *Why can't `typecheck` return
  `Either TypeError (TExpr t)`? Who would choose `t`?*
- [ ] Leaves. *The context gives you a `Ty`, which is a value, but `TVar` needs
  a `SingTy t`. `GHC.TypeNats` will give you an `SNat` for a `Natural`, but
  only inside a function you pass in. Why can't it just return the `SNat`?*
- [ ] Literals. *`Lit (VBV (-1) 0)` must give `InvalidValue`. What does
  `fromIntegral (-1 :: Int) :: Natural` do, so which comes first?*
- [ ] `Un`, `Bin`, `Cmp`. *You hold `SBV wa` and `SBV wb`. Checking that the
  two widths are equal numbers convinces you, but not GHC. What value would
  convince GHC that `wa` and `wb` are the same type?*
- [ ] `Ite`. *Which check must come first, so that
  `(ite x (const 8 0) (const 16 0))` gives `ExpectedBool 8` and not
  `WidthMismatch 8 16`?*
- [ ] Error order. Tests: `-p Typecheck.rejects` and the property
  `fails exactly where Phase 1 eval fails`. *If you check every operand in one
  `do` block before you look at any of their sorts, which part of the order do
  you get for free?*
- [ ] Golden `-p Typecheck.golden` (`test/golden/typecheck.txt` is already
  written). *If only this test fails, the sorts and the round trip are right
  but the typed term is not. Which `TVar` or `TLit` in the diff has the wrong
  width?*
- [ ] Property `evalT of its result agrees with Phase 1 eval`. *It can fail
  while `accepts generated well-typed terms` passes. What can `typecheck` get
  wrong that `erase` cannot see?*

## Spec: typecheck

```haskell
type Context = Map Text Ty
typecheck :: Context -> Expr -> Either TypeError SomeExpr
```

- **Behaviour.** Check an expression against a context and return it with
  its sort. `typecheck ctx e` succeeds exactly when Phase 1's `eval env e`
  succeeds for an `env` that binds every declared variable to a
  well-formed value of its declared sort. When it fails, the error is the
  one `eval` would report (the first five `TypeError` constructors are
  `EvalError`'s), found in the same order, with the context standing in for
  the environment:
  1. Check the operands left to right (`ite`: condition, then, else). The
     first one that fails decides.
  2. Then check the node: the operands' sorts left to right (`ExpectedBool w`
     for an `ite` condition, `ExpectedBV` otherwise), then their widths
     (`WidthMismatch l r`).
- **Leaves.** An undeclared variable is `UnboundVar x`. A variable declared
  with a width outside `1..64` is `InvalidSort ty`. A literal that is not
  `validValue` is `InvalidValue v`. Like `eval`'s environment, the context
  is checked only where it is used, so an unused bad declaration is not an
  error.
- **Laws.** If `typecheck ctx e == Right (SomeExpr s te)`, then
  `erase te == e`, and `s` is the sort of the value `eval` returns. Every
  `TVar` in the result has the sort `ctx` declares for it.
- **Tests.** `-p Typecheck`, against `testContext` plus `w0 : BV 0` and
  `w65 : BV 65`: `accepts` (14 cases) and `rejects` (26), each named by the
  expression; the golden `golden` (`test/golden/typecheck.txt`, already
  written); and the properties "accepts generated well-typed terms, and
  erase undoes it", "evalT of its result agrees with Phase 1 eval", and
  "fails exactly where Phase 1 eval fails, with the same error".

## GHC errors you are likely to hit

Symptoms only. Ask for a hint if one stops you.

1. Writing `typecheck` for `Bin`:
   `Could not deduce ‘w1 ~ w’ from the context: t ~ TBV w bound by a pattern with constructor: SBV :: ...`
2. Trying to write `unwrap :: SomeExpr -> TExpr t`:
   `Couldn't match type ‘t1’ with ‘t’ ... ‘t1’ is a rigid type variable bound by a pattern with constructor: SomeExpr :: ...`
3. Trying to get the `SNat` out of `withSomeSNat`:
   `Couldn't match type ‘n1’ with ‘n’ ... ‘n1’ is a rigid type variable bound by a type expected by the context: forall (n1 :: Nat). SNat n1 -> SNat n`
4. Your first `case` on a `SingTy` or `TExpr` in `Typecheck.hs` or `EvalT.hs`:
   the warning `[-Wgadt-mono-local-binds] Pattern matching on GADTs without MonoLocalBinds is fragile.`,
   which fails CI (it builds with `-Werror`).
5. Handling `VBV` when you unwrap a `Value 'TBool`, as Phase 1's `eval` had
   to: `Pattern match is redundant`, then
   `Inaccessible code in a pattern with constructor: VBV :: ... Couldn't match type ‘TBool’ with ‘TBV w’`.

## Decisions

- `GADTs` in `Typecheck` and `EvalT`: both match on `SingTy`, `TExpr` or
  `Value`, and it also turns on the `MonoLocalBinds` that `-Wall` asks for.
- `DataKinds` in `Typecheck`: `sameWidth`'s signature names `'TBV w`.
- `Eval` exports `unOp`, `binOp` and `cmpOp`, so `eval` and `evalT` share one
  set of arithmetic. They work on `Integer`s and carry no `EvalError`.
- `Typed` exports `widthOf`, and `Typecheck` exports `checkTy`: `typecheck` and
  `checkEnv` must agree on what `InvalidSort` means. Neither is named `tyOf` or
  `withSing`, which `test/TExprGen.hs` defines and would clash with.
- `evalT`: `TIte` evaluates only the selected branch. `eval` has to evaluate
  both to report errors, but `evalT` can't fail, so the results are the same.

## Shortcuts

- **`Typed`: the types allow widths outside 1..64 and payloads outside
  `[0, 2^w)`.** `typecheck` and `checkEnv` reject both, and `evalT` keeps
  its results in range, so only hand-built terms can break the invariant.
  Upgrade: a `(1 <= w, w <= 64)` constraint on `SBV` and `VBV`, and a smart
  constructor for `VBV`.
- **`evalT`: nothing ties a `TExpr` to the context it was checked
  against**, so `evalT` can meet a variable that this `TEnv` does not bind,
  and reads it as zero. Upgrade: index `TExpr` by its context (a
  type-level list of variable sorts), so that the mismatch becomes a type
  error.

## Open questions

None. The tests and the Phase 2 Haddock that survived in git history pin
every case.
