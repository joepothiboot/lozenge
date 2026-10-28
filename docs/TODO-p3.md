# Phase 3 TODO: brute-force rule verifier

Spec: the Haddock in `src/Lozenge/Rule.hs` and `src/Lozenge/VerifyBrute.hs`.
Each step names the tests that should go green; run a group with, e.g.,
`stack test --test-arguments='-p VerifyBrute.renderVerdict'`. Hints are rung 1
(a question). Ask for the next rung when you want it.

**Prerequisites.** `verifyBrute` runs `typecheck`, `checkEnv` and `evalT`, and
the property also uses `erase` and Phase 1's `eval`. Finish Phases 1 and 2
first; only `renderVerdict` and `instantiate` (steps 1 and 2) stand alone.

## Decision: rule widths

Rules are written with concrete widths. `ruleWidth` says what they mean:

- `Fixed`: exactly what is written. `verifyBrute w` ignores `w`.
- `Generic`: written at one width but claimed at every width.
  `verifyBrute w` first runs `instantiate w`, which sets every BV width to
  `w` and keeps the low `w` bits of every constant. All-ones stays all-ones;
  the sign bit does not (128 at width 4 is 0). Widths outside `1..64` are
  `Unsupported`.

Why: the corpus stays concrete and readable, and a generic rule can still be
checked at small widths, where brute force is cheap. The `-- shortcut:`
comment on `RuleWidth` names the limit and the upgrade.

This takes back the earlier plan to reject a rule whose widths can't be
inferred. The future rule parser will need syntax for marking a rule
`Generic`.

## 1. `Lozenge.VerifyBrute.renderVerdict`

Tests: `-p VerifyBrute.renderVerdict`.

- [ ] Hex. *Which function in `Numeric` shows an `Integer` in hex, and how many
  digits does a width-5 value need? Is that `w / 4` rounded up or down?*
- [ ] Variable order. *An `Env` is a `Map`. In what order does `Map.toList`
  give the keys, and is that already the order the spec wants?*
- [ ] Joining. *Which `Data.Text` function puts `", "` between a list of
  pieces, and what should happen to the `": "` when there are no variables?*

## 2. `Lozenge.Rule.instantiate`

Tests: `-p Rule.instantiate`.

- [ ] `Fixed`. *Why must a `Fixed` rule come back unchanged even for
  `w = 0`?*
- [ ] Range. *`TBV` holds a `Natural`. What does `fromIntegral (-1 :: Int) ::
  Natural` do, so which check must come before you build a `TBV w`?*
- [ ] Literals. *You need to rewrite every `Lit` inside an `Expr` and leave
  every other node alone. How many equations does that recursive function
  need, one per `Expr` constructor?*
- [ ] Variables. *Which `Data.Map.Strict` function changes every value in
  `ruleVars`, and what should it do to `TBool`?*

## 3. `Lozenge.VerifyBrute.verifyBrute`

Tests: `-p VerifyBrute.unsupported` first, then `valid`, `invalid`,
`precondition`, `width-dependent`.

- [ ] Errors as `Unsupported`. *`typecheck` returns `Either TypeError ...`
  but you need a `Verdict`. If you work in `Either Verdict` with `do` and
  return `Left (Unsupported ...)` on failure, what does a final `either id id`
  give you?*
- [ ] Sorts. *You hold two `SomeExpr`s, `SomeExpr s1 l` and
  `SomeExpr s2 r`. To compare their values you'd need `t1 ~ t2`. Do you need
  GHC to know that, or can you compare after converting each value to the
  untyped `Value`?*
- [ ] The cap. *Why must you compute the count before you build the list of
  assignments, and why compute it as an `Integer`? (A `TBV 64` variable has
  `2^64` values.)*
- [ ] Enumeration. *For one variable, write its list of values. In the list
  monad, which function turns a `Map Text [Value]` into a `[Map Text Value]`
  of every combination, and in which order does it vary the keys?*
- [ ] Each assignment. *`checkEnv` takes an untyped `Env` and gives a `TEnv`.
  Can it fail on an assignment you generated, and if it can't, how do you
  handle its `Left` without a partial function?*
- [ ] First difference. *Which `Data.Maybe` or `Data.List` function gives the
  first element of a list that satisfies a test, or `Nothing`, and why does
  laziness mean you never build all `2^20` assignments when a counterexample
  comes early?*
- [ ] Width-dependent. Tests: `shl-4-zero` at 4 and at 8. *Which row of
  `docs/SEMANTICS.md` makes the rule valid at width 4?*
- [ ] Speed. Test: `exactly 2^20 assignments is allowed`. *If it takes more
  than a few seconds, what work are you redoing for every assignment that
  could be done once per rule?*

## 4. The property

Test: `-p VerifyBrute.Valid`.

- [ ] *It checks `verifyBrute` against Phase 1's `eval`, not `evalT`. Why is
  that a stronger check than comparing against the evaluator `verifyBrute`
  itself uses?*
- [ ] *If it fails, the counterexample includes the instantiated rule. Is
  the bug in `instantiate`, in your enumeration (a value never tried), or in
  your precondition handling?*

## Reference script

`test/ref/brute.py` re-derives the semantics in Python and prints the
verdict for every hand-picked rule; the expected strings in
`test/Lozenge/VerifyBruteSpec.hs` match its output. Run
`python3 test/ref/brute.py` if you doubt an expected string.
