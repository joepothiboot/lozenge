# Phase 4b TODO: the SMT verifier

Spec: the Haddock in `src/Lozenge/VerifySmt.hs`. Run a group with, e.g.,
`stack test --test-arguments='-p VerifySmt.runVerify'`. Hints are rung 1 (a
question). Ask for the next rung when you want it.

**Prerequisites.** `runVerify` and `toAssignment` (steps 1 and 2) need only
`validValue` and `smtName`. `verifySmt` needs `instantiate`, `ruleQuery`,
`typecheck`, `checkEnv` and `evalT`. The corpus test also needs `parseRules`
and `verifyBrute`.

## Decisions

- **The width lives in `Config`.** `verifySmt :: Rule -> Verify Verdict` has
  no width argument, so `configWidth` plays the role of `verifyBrute`'s `w`.
  The tests change it per call; `local` would too.
- **`VerifyError` is for the tooling; `Unsupported` is for the rule.** An
  ill-typed rule, a width outside 1..64, or z3 answering `unknown` (a
  timeout included) is a verdict, as in brute force. z3 missing or rejecting
  the query is thrown.
- **`verifySmt` checks z3's model.** It evaluates the rule at the model, and
  if the counterexample is not real it throws `SpuriousCounterexample`. A
  disagreement between z3 and `evalT` is a bug, and silently returning either
  answer would hide it.
- **`Verify`'s constructor is not exported.** Callers use `runVerify` and the
  derived instances.
- **The key test was checked before you start.** For all 30 corpus rules at
  widths 1-6 (180 pairs), z3 agrees with `test/ref/corpus.py`, and every z3
  model is a real counterexample there. A failure is in the Haskell.

## 1. `runVerify`

Tests: `-p VerifySmt.runVerify`.

- [ ] *`Verify` wraps a `ReaderT Config (ExceptT VerifyError IO) a`. Which
  `run...` function removes each layer, and which layer comes off first?*
- [ ] *Why must `runVerify` be defined in `Lozenge.VerifySmt` and not by a
  caller?*
- [ ] *`deriving newtype (MonadReader Config)`: what instance does that
  generate, and why didn't you have to write `ask` yourself?*

## 2. `toAssignment`

Tests: `-p VerifySmt.toAssignment`.

- [ ] *You must do something that can fail for every entry of the `Context`
  and get back a `Map`. Which `Data.Map` function walks a map, gives you each
  key and value, and works in any `Applicative`, such as `Either Text`?*
- [ ] *Why look up `smtName x` and not `x`? What does `"other"` in the first
  test check?*
- [ ] *Which Phase 1 function already decides whether `VBV w n` fits?*

## 3. `verifySmt`

Tests: `-p "VerifySmt.Unsupported before z3"`, then
`-p "VerifySmt.beyond brute force"`, then `-p "VerifySmt.corpus"`.

- [ ] Early exits. *Instantiating gives a `Maybe` and `ruleQuery` an `Either`.
  Each failure ends with `pure (Unsupported ...)`, which is not an error. How
  do you write that without five nested `case`s? Is a helper that turns
  `Maybe Rule` into `Verify Rule` the right shape, or not, given that the exit
  is a verdict?*
- [ ] Reading the config. *What is the type of `asks configWidth` here?*
- [ ] Calling z3. *`runZ3` is in `IO`, and you're in `Verify`. Which derived
  instance lets you call it?*
- [ ] Evaluating the model. *Per assignment, `verifyBrute` already
  typechecks, runs `checkEnv` and `evalT`. Can both verifiers share one
  function for "evaluate pre, lhs and rhs at an assignment"? Where should it
  live so that neither verifier imports the other?*
- [ ] Spurious models. *Why throw `SpuriousCounterexample` rather than return
  `Valid`, or the counterexample anyway?*
- [ ] Width 32. *Brute force would try 2^64 assignments for `add-comm`. What
  does z3 do instead of enumerating them?*

## 4. Reading a corpus failure

`-p "VerifySmt.corpus"` runs all 30 rules at one width per test and lists
every disagreement, each with where to look first.

- [ ] *Why is the emitter suspected before `evalT` when z3 and brute force
  disagree?*
- [ ] *The test re-evaluates every SMT counterexample with `evalT` instead of
  trusting the lhs and rhs inside `Counterexample`. Why?*
- [ ] *Brute force says `Valid`, z3 finds a counterexample, and `evalT`
  confirms it. Why does that point at `verifyBrute`, not at z3?*
