# Phase 4b TODO: the SMT verifier

Spec: the `## Spec` entries below. Run a group with, e.g.,
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
- `OverloadedStrings` in `VerifySmt`: for `Text` literals.
- **`VerifyBrute` exports `evalSome`.** `VerifySmt` already imports `VerifyBrute`
  for `Verdict`, so this needs no new module, and `verifyBrute` itself is
  unchanged. The rest of `confirm` (`checkEnv`, then pre, lhs and rhs) is not
  shared with `verifyBrute`, which typechecks once and loops over assignments.
- **A model `toAssignment` rejects is `SolverFailed`**, with its `Left` text: z3
  gave no usable answer. No test pins this.
- **A failed `checkEnv` or `typecheck` in `confirm` is
  `SpuriousCounterexample`.** Neither can fail once `ruleQuery` and
  `toAssignment` have succeeded, and the model is still not confirmed real.
- **`toAssignment` does not run `checkTy`.** `verifySmt` only reaches it after
  `ruleQuery` did. A direct call with a width above `2^63` wraps in
  `fromIntegral`, and `checkEnv` still rejects that result.
- **`Unsupported` text:** `width N is outside 1..64` as in `verifyBrute`,
  `ruleQuery`'s `Left`, or `runZ3`'s `Unknown` text. **`SolverFailed` text:**
  `runZ3`'s `SolverError` text or `toAssignment`'s `Left`. The tests only check
  the constructors.

## 1. `runVerify`

Tests: `-p VerifySmt.runVerify`.

- [ ] *`Verify` wraps a `ReaderT Config (ExceptT VerifyError IO) a`. Which
  `run...` function removes each layer, and which layer comes off first?*
- [ ] *Why must `runVerify` be defined in `Lozenge.VerifySmt` and not by a
  caller?*
- [ ] *`deriving newtype (MonadReader Config)`: what instance does that
  generate, and why didn't you have to write `ask` yourself?*

## Spec: runVerify

```haskell
newtype Verify a = Verify (ReaderT Config (ExceptT VerifyError IO) a)
runVerify :: Config -> Verify a -> IO (Either VerifyError a)
```

- **Behaviour.** Run a `Verify` action with the given `Config`. A
  `throwError e` inside it gives `Left e`; otherwise `Right` the result.
  `ask`/`asks` read the `Config`, and `liftIO` runs `IO`.
- **Tests.** `-p VerifySmt.runVerify`: "pure", "asks reads the config",
  "throwError", "liftIO".

## 2. `toAssignment`

Tests: `-p VerifySmt.toAssignment`.

- [ ] *You must do something that can fail for every entry of the `Context`
  and get back a `Map`. Which `Data.Map` function walks a map, gives you each
  key and value, and works in any `Applicative`, such as `Either Text`?*
- [ ] *Why look up `smtName x` and not `x`? What does `"other"` in the first
  test check?*
- [ ] *Which Phase 1 function already decides whether `VBV w n` fits?*

## Spec: toAssignment

```haskell
type Model = Map Text Integer      -- from Lozenge.Solver
toAssignment :: Context -> Model -> Either Text Assignment
```

- **Behaviour.** Read z3's model back as an assignment of the context's
  variables. Each declared `x` is looked up under `smtName x`. A `BV w`
  variable becomes `VBV w n`; a `Bool` variable is `1` for `true` and `0`
  for `false`. Symbols that belong to no declared variable are ignored.
- **Errors.** `Left` if a declared variable is missing from the model, if a
  BV value is not `validValue` at its width (256 at width 8), or if a Bool
  value is not 0 or 1.
- **Tests.** `-p VerifySmt.toAssignment`: "BV and Bool, extra symbols
  ignored", "a missing variable", "a BV value too wide", "a Bool value other
  than 0 or 1".

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

## Spec: verifySmt

```haskell
data Config = Config {configWidth :: Int, configTimeoutMs :: Int}
data VerifyError = SolverFailed Text | SpuriousCounterexample Assignment
verifySmt :: Rule -> Verify Verdict
```

- **Behaviour.** The SMT counterpart of `verifyBrute`, at width
  `configWidth`:
  1. `instantiate` at that width; `Nothing` is `Unsupported`.
  2. `ruleQuery`; a `Left` is `Unsupported`.
  3. Run z3 with `configTimeoutMs`. `unsat` is `Valid`. `unknown`, a timeout
     included, is `Unsupported`.
  4. `sat`: read the model with `toAssignment`, then evaluate the
     precondition, lhs and rhs at it with `evalT`. If the precondition
     holds and the two sides differ, the verdict is
     `Counterexample assignment lhsValue rhsValue`, as Phase 1 values.
- **Errors (thrown, not verdicts).** `SolverFailed msg` when z3 is missing,
  rejects the query, or gives no answer. `SpuriousCounterexample a` when
  z3's model is not a real counterexample under `evalT`.
- **Laws.** Wherever brute force finishes, `verifySmt` agrees with it:
  both `Valid`, both `Unsupported`, or both counterexamples (not
  necessarily the same one), each confirmed by `evalT`.
- **Tests.** `-p "VerifySmt.Unsupported before z3"`: "ill-typed lhs",
  "Generic at width 0", "Generic at width 65" (no z3 needed). Then, with
  z3: `-p "VerifySmt.beyond brute force"` ("add-comm at width 32 is
  valid", "ult-to-slt at width 32 has a real counterexample") and
  `-p "VerifySmt.corpus"` (the 30 corpus rules at widths 1 to 6).

## 4. Reading a corpus failure

`-p "VerifySmt.corpus"` runs all 30 rules at one width per test and lists
every disagreement, each with where to look first.

- [ ] *Why is the emitter suspected before `evalT` when z3 and brute force
  disagree?*
- [ ] *The test re-evaluates every SMT counterexample with `evalT` instead of
  trusting the lhs and rhs inside `Counterexample`. Why?*
- [ ] *Brute force says `Valid`, z3 finds a counterexample, and `evalT`
  confirms it. Why does that point at `verifyBrute`, not at z3?*

## Shortcuts

None recorded for this phase. README, "Limitations": `--solver smt|both`
needs z3 on `PATH`.

## Open questions

- `toAssignment`: the text of each `Left`. The tests only check that it is a
  `Left`.
