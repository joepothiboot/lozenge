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

## 5. Shared expression parser (`Lozenge.Parse`)

`Parse.hs` now exports `Parser`, `lexeme`, `identifier`, `constBody` and
`exprWith`, so RuleParse reuses your expression parser instead of copying it.
Write them as part of Phase 1 step 4; `parseExpr` becomes a thin wrapper.

- [ ] `exprWith`. *Your form parser reads `(`, an operator word, then
  operands. Which two places in it change between plain expressions and rule
  patterns, and why is passing those two as arguments enough?*
- [ ] `parseExpr`. Tests: all of `-p Parse`. *Given `exprWith`, what is left
  for `parseExpr` to do?*

## 6. `Lozenge.RuleParse.mkRule`

Tests: `-p "RuleParse.mkRule rejects"`, then `-p RuleParse.accepts`.

- [ ] Widths. *Which `Set` operations tell you "only 0", "exactly one
  n > 0" and "0 plus something else"? Why is 0 a safe stand-in for `w`?*
- [ ] Binding. *How do you collect the variables of an `Expr` into a
  `Set Text`, and which `Set` function gives the ones in the rhs but not in
  the lhs, already in ascending order?*
- [ ] Sorts. *Write a function that walks an `Expr` and returns, for each
  variable occurrence, the sort its position demands. What does it need to
  know about its parent to tell an `ite` condition from an `ite` branch?*
- [ ] Types and messages. *`typecheck` gives you a `SomeExpr`. Which Phase 2
  helper turns its `SingTy` back into a `Ty`, and how do you print `BV w`
  instead of `BV 64` for a generic rule?*

## 7. `Lozenge.RuleParse.parseRules`

Tests: `-p RuleParse`, then read `test/golden/rule-errors.txt`. That file is
written on the first passing run and does not exist yet. Read every message:
*would a newcomer understand it?*

- [ ] Rule-level tokens. *`rule`, `=>`, `:if` and the parentheses use
  `Lozenge.Parse.lexeme`, but between rules you also skip comments. Which
  `Text.Megaparsec.Char.Lexer` function builds a space consumer that skips
  `;` comments?*
- [ ] `?x`. *Why must `?` and the identifier be adjacent, and which parser
  combinators make `? x` fail?*
- [ ] The placeholder. *How do you parse the word `w` so that `wx` is
  rejected, and then try `constBody` when it isn't `w`?*
- [ ] Reporting `mkRule` errors. *A `Left msg` from `mkRule` must point at
  the rule's `(`. Which megaparsec functions read the current offset before
  you parse the rule, and fail at a saved offset afterwards?*
- [ ] Duplicates. *Can you check names while you parse, or only after? Which
  one lets the error point at the second rule?*

## 8. The corpus

Test: `-p Corpus`. `test/golden/corpus-verdicts.txt` was written by
`test/ref/corpus.py`, not by your code. If the golden test fails, look at the
first differing line: *which is wrong, your `verifyBrute`, `instantiate`,
`mkRule`'s sort inference, or the Python? Check by hand at that width.* Do not
run `--accept` until you know.
