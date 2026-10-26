# Phase 2 TODO: typed IR

Spec: the Haddock in `src/Lozenge/Typed.hs`, `src/Lozenge/Typecheck.hs` and
`src/Lozenge/EvalT.hs`. Each step names the tests that should go green; run a
group with, e.g., `stack test --test-arguments='-p Typed.erase'`. Hints are
rung 1 (a question). Ask for the next rung when you want it.

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

## 2. `Lozenge.EvalT.checkEnv`

Tests: `-p EvalT.checkEnv`.

- [ ] One variable. *Can you write the four checks for one `(name, sort)` pair
  as a single `do` block in `Either TypeError`, in the order the Haddock
  gives?*
- [ ] All of them. *In what order does `Map.toList` return the declared
  variables, and which function runs your one-variable check over a list,
  stopping at the first `Left`?*
- [ ] The result. *Which `Data.Map.Strict` function keeps only the keys that
  the context declares?*

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
