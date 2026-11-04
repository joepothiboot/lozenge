# Phase 3 TODO: brute-force rule verifier

Spec: the `## Spec` entries below. Each step names the tests that should go
green; run a group with, e.g.,
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

## Spec: renderVerdict

```haskell
renderVerdict :: Verdict -> Text
```

- **Behaviour.**
  - `Valid` is `valid`.
  - `Unsupported msg` is `unsupported: ` followed by `msg`.
  - `Counterexample env l r` is the assignment, `: `, then
    `lhs = <l>, rhs = <r>`. The assignment is `name = value` for each
    variable in ascending order of name, joined by `, `. With no variables
    the `: ` is dropped too: `lhs = true, rhs = false`.
- **Values.** A `Bool` is `true` or `false`. `VBV w v` is `0x` followed by
  `v` in lowercase hex, zero-padded to `ceiling (w / 4)` digits: width 1 is
  `0x1`, width 5 is `0x03`, width 64 is 16 digits.
- **Tests.** `-p VerifyBrute.renderVerdict`: "valid", "unsupported", "the
  example format, variables in name order", "padding to ceiling (w / 4)
  digits", "Bool values", "no variables".

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

## Spec: instantiate

```haskell
instantiate :: Int -> Rule -> Maybe Rule
```

- **Behaviour** (see "Decision: rule widths" above).
  - `Fixed`: `Just r`, unchanged, for every `w`.
  - `Generic` with `w` outside `1..64`: `Nothing`.
  - `Generic` with `w` in range: every `TBV _` in `ruleVars` becomes
    `TBV w` (a `TBool` stays), and every literal `VBV _ v` in the lhs, rhs
    and precondition becomes `VBV w (v mod 2^w)`, keeping the low `w` bits.
    Everything else stays: name, `ruleWidth`, Bool literals, the shape of
    each side.
- **Laws.** A `Generic` rule at its written width comes back unchanged.
  All-ones stays all-ones; the sign bit does not (128 at width 4 is 0).
- **Tests.** `-p Rule.instantiate`: "Fixed ignores the width", "Generic at
  its own width is unchanged", "Generic at 4 rewrites variable widths and
  keeps the low bits of literals", "Generic at width 1", "Generic outside
  1..64 is Nothing".

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

## Spec: verifyBrute

```haskell
assignmentCap :: Integer   -- 2^20
verifyBrute :: Int -> Rule -> Verdict
```

- **Behaviour.**
  1. `instantiate w`; `Nothing` is `Unsupported`.
  2. Typecheck the lhs, rhs and precondition against `ruleVars`. Any
     `TypeError`, an lhs and rhs of different sorts, or a precondition that
     is not `Bool`, is `Unsupported`.
  3. Count the assignments of `ruleVars`, as an `Integer`, before building
     any: 2 for each `Bool` variable and `2^w` for each `BV w`, over every
     declared variable, used or not. More than `assignmentCap` is
     `Unsupported`; exactly `2^20` is allowed.
  4. Try every assignment, skipping those where the precondition is
     `false`. The first one where lhs and rhs differ gives
     `Counterexample assignment lhsValue rhsValue`, with Phase 1 `Value`s.
     If there is none, `Valid`.
- **Order of assignments.** Variables in ascending order of name, with the
  last one varying fastest; values ascending, `false` before `true`. This
  decides which counterexample is first: `sub-comm` at width 8 gives
  `x = 0x00, y = 0x01`. `test/ref/brute.py` re-derives every expected string.
- **Edge cases.** A `Fixed` rule ignores `w`, even `w = 0`. A `Generic`
  rule at width 0 or 65 is `Unsupported`.
- **Laws.** If `verifyBrute w r == Valid`, then `instantiate w r` is
  `Just r'`, and for every assignment where the precondition holds, Phase
  1's `eval` gives lhs and rhs the same value.
- **Tests.** `-p VerifyBrute`: `valid` (6 rules at width 8), `invalid` (4,
  with the exact counterexample strings), `precondition` (2), and
  `width-dependent` (5), each named `"<rule>" at width <w>`; `unsupported`
  ("exactly 2^20 assignments is allowed", "2^22 assignments", "three 8-bit
  variables", "a 64-bit variable", "Generic at width 0", "Generic at width
  65", "lhs Bool, rhs BV", "precondition is not Bool", "ill-typed lhs",
  "undeclared variable"); and the property "Valid means lhs and rhs evaluate
  equal on random assignments". Also `-p Corpus` (step 8).

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

## Spec: lexeme

```haskell
type Parser = Parsec Void Text
lexeme :: Parser a -> Parser a
```

- **Behaviour.** Run the parser, then skip the whitespace (space, tab,
  newline) after it, so that every token parser eats its own trailing
  whitespace. It does not skip `;` comments: inside a rule a comment is a
  parse error.
- **Tests.** None call it directly. It is checked through the whitespace
  cases of `-p Parse.accepts` (`"  x \n"`, `"( add\n\tx\n  y )"`) and
  `-p RuleParse`.

## Spec: identifier

```haskell
identifier :: Parser Text
```

- **Behaviour.** One identifier, `[A-Za-z_][A-Za-z0-9_]*` (SEMANTICS.md,
  "Concrete syntax"), as a whole word: `x_1` and `_tmp` are identifiers,
  `1x` is not. `parseExpr` uses it for variables, and RuleParse after `?`.
- **Tests.** None call it directly: `-p Parse` (`x_1`, `_tmp`, `true1`,
  `1x`) and `-p RuleParse` (`?1x` is rejected).

## Spec: constBody

```haskell
constBody :: Parser Expr
```

- **Behaviour.** The part of a `(const w v)` form after the word `const`:
  two decimal naturals, leading zeros allowed, with `1 <= w <= 64` and
  `0 <= v < 2^w`, giving `Lit (VBV w v)`. RuleParse tries the placeholder
  word `w` first and falls back to `constBody`, so a concrete constant in a
  rule is range-checked exactly as in `parseExpr`.
- **Tests.** None call it directly: the `const` cases of `-p Parse` and
  "(rule r (add ?x (const 8 256)) => ?x)" in `-p RuleParse.rejects`.

## Spec: exprWith

```haskell
exprWith :: Parser Expr -> Parser Expr -> Parser Expr
```

- **Behaviour.** The expression parser of SEMANTICS.md, shared by
  `parseExpr` and `parseRules`. Its two arguments are the two places where
  plain expressions and rule patterns differ: the variable leaf
  (`identifier` for `parseExpr`, `?x` for rules) and the body of a
  `(const ...)` form (`constBody`, or the placeholder `w` for rules).
  Everything else (`true`, `false`, the operator forms, arity) is the same.
- **Tests.** None call it directly: all of `-p Parse` and `-p RuleParse`.

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

## Spec: mkRule

```haskell
mkRule :: Text -> Expr -> Expr -> Maybe Expr -> Either Text Rule
```

- **Input.** A name, lhs, rhs and optional precondition as parsed, where a
  pattern variable `?x` is `Var "x"` and the placeholder `(const w v)` is
  `Lit (VBV 0 v)`.
- **Widths.** Collect the widths of every literal. One concrete width `n`
  gives a `Fixed` rule at width `n`. Only the placeholder, or no literal at
  all, gives a `Generic` rule at width 64, and every placeholder literal
  becomes `VBV 64 v`. Errors:
  - `rule r: mixes the width placeholder w with width 8`;
  - `rule r: uses widths 8 and 16; a rule uses one width`.
- **Binding.** Every variable of the rhs and of the precondition must occur
  in the lhs:
  - `rule r: rhs uses ?y, which the lhs does not bind`;
  - `rule r: precondition uses ?z, which the lhs does not bind`.
- **Sorts.** Each variable's sort comes from its positions: an `ite`
  condition is `Bool`; an operand of an operator or comparison, or an `ite`
  branch, is `BV` at the rule's width. Errors:
  - `rule r: ?p is used as both Bool and BV`;
  - `rule r: cannot infer the sort of ?x` (a variable with no constraint,
    as in `?x => ?x`).
- **Typing.** Then each part is typechecked against the inferred
  `ruleVars`, and the error is shown with `show`. Errors:
  - `rule r: lhs is ill-typed: ExpectedBV` (likewise `rhs`);
  - `rule r: lhs has sort Bool but rhs has sort BV w` (a `Generic` sort
    prints as `BV w`, a `Fixed` one as `BV 8`);
  - `rule r: precondition has sort BV w, expected Bool`.
- **Order.** Widths before binding: an lhs at width 8 with an rhs at width
  16 that uses an unbound `?y` reports the widths.
- **Tests.** `-p "RuleParse.mkRule rejects"`: 14 cases, each named by its
  message. Then `-p RuleParse.accepts` checks the rules it builds.

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

## Spec: parseRules

```haskell
parseRules :: FilePath -> Text -> Either ParseError [Rule]
```

- **Syntax.** Zero or more rules, `(rule NAME LHS => RHS)` or
  `(rule NAME LHS => RHS :if PRE)`, with whitespace and `;` line comments
  before, between and after the rules (never inside one). `=>` needs no
  space around it. LHS, RHS and PRE are `exprWith` expressions, where:
  - a variable is `?` immediately followed by an identifier (`? x`, `?1x`
    and a bare `x` are rejected);
  - `(const w v)` with exactly the word `w` is the width placeholder (`wx`,
    `W` and `(const w)` are rejected); any other constant is checked as in
    `parseExpr`.
- **Names.** Names in the tests: `add-zero`, `shl-1-to-add`, `a_1`, `B-2`.
  `r!` is rejected.
- **Rules.** Each rule goes through `mkRule`. A `Left msg` is a parse error
  at the rule's `(` carrying `msg`; a second rule with the same name is
  `duplicate rule name r`, at the second rule's `(`. The `FilePath` names the
  file in error positions (`t.rules:2:3:`).
- **Errors.** Also rejected: an incomplete rule, a missing `=>` or rhs,
  unbalanced parentheses, `rulex`, a top-level expression, `:when`, `:if`
  with nothing after it, two `:if`s, and junk after the last rule.
- **Tests.** `-p RuleParse`: `accepts` (11 inputs, named by the source),
  `parseRules reports mkRule errors` (4, with position and message),
  `rejects` (24), and the golden `error messages`
  (`test/golden/rule-errors.txt`, written on the first passing run).

## 8. The corpus

Test: `-p Corpus`. `test/golden/corpus-verdicts.txt` was written by
`test/ref/corpus.py`, not by your code. If the golden test fails, look at the
first differing line: *which is wrong, your `verifyBrute`, `instantiate`,
`mkRule`'s sort inference, or the Python? Check by hand at that width.* Do not
run `--accept` until you know.

## Decisions

- `OverloadedStrings` in `RuleParse` and `VerifyBrute`: for `Text` literals.
- `Rule` exports `mapLiterals`: `instantiate` and `mkRule` both rewrite every
  literal of an `Expr`.
- `Typed` exports `someSort` and `eraseValue`: `mkRule` and `verifyBrute` need a
  term's sort as a `Ty`, and `verifyBrute` needs Phase 1 values. They are not
  named `tyOf` or `untyped`, which `test/TExprGen.hs` defines and would clash with.
- `Parse` exports `failAt` and `natural`, so rule errors and the placeholder
  value work as in `constBody`.
- `verifyBrute`: checks every declared width with `checkTy` before counting. An
  unused `TBV 0` is `Unsupported`, and a huge declared width can't blow up `2^w`.
- `verifyBrute`: a `Counterexample`'s assignment holds every declared variable,
  used or not, as in `test/ref/brute.py`.
- `verifyBrute`: `Unsupported` holds a short sentence, or `show` of the
  `TypeError`. The tests only check the constructor.
- `renderVerdict`: assumes valid values, which is all `verifyBrute` produces;
  `showHex` throws on a negative payload in a hand-built `Counterexample`.
- `mkRule`: with more than two widths it reports the two smallest. With several
  unbound variables it reports the first by name, rhs before precondition. An
  ill-typed precondition is `rule r: precondition is ill-typed: <error>`.
- `mkRule`: a variable that is the whole precondition is `Bool`, as in
  `test/ref/corpus.py`. A whole lhs or rhs still gives no sort.
- `mkRule`: a negative literal width is `rule r: width -1 is not between 1 and
  64`, because it would otherwise underflow `TBV`'s `Natural`. The parser can't
  produce one.
- `parseRules`: a rule name is `[A-Za-z0-9_-]+`, including a leading digit or
  `-`. `rule`, `w` and `:if` must not be followed by a name character, so
  `(rule-x ...)` is rejected.
- `parseRules`: a rule that fails `mkRule` and also repeats a name reports the
  `mkRule` error.

## Shortcuts

- **`instantiate` / `RuleWidth`: a `Generic` rule is written at one width
  and checked by instantiating it.** Ceiling: a literal keeps only its low
  `w` bits, so a constant whose meaning depends on the width (the sign bit,
  `128` at width 8) is not carried over, and a generic rule is only ever
  checked at the widths you try. Upgrade: not recorded (the `-- shortcut:`
  comment on `RuleWidth` was removed before it was committed).
- **`verifyBrute`: at most `2^20` assignments**, which is two variables at
  width 10. Ceiling: wider rules are `Unsupported`. Upgrade: the SMT
  verifier, Phase 4b (README, "Limitations").

## Open questions

`exprWith`, `identifier` and `constBody` are decided: see "Decisions" in
[TODO-p1.md](TODO-p1.md).

- `parseRules`: the wording of each syntax error, until you accept
  `test/golden/rule-errors.txt`.
