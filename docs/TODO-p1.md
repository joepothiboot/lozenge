# Phase 1 TODO: untyped IR

Spec: the `## Spec` entries below, which follow [SEMANTICS.md](SEMANTICS.md).
Each step names the tests that should go green. Run a group with, e.g.,
`stack test --test-arguments='-p Eval.'` (the dot keeps out Phase 2's `EvalT`
group). Hints are rung 1 (a question). Ask for the next rung when you want it.

## 1. `Lozenge.Expr.validValue`

Tests: `Expr/validValue`.

- [ ] `validValue`. *Which three inequalities must hold for a `VBV`, and what
  does `VBV (-1) 0` tell you about the order you check them in?*

## Spec: validValue

```haskell
validValue :: Value -> Bool
```

- **Behaviour.** `VBool _` is always valid. `VBV w v` is valid exactly when
  `1 <= w <= 64` and `0 <= v < 2^w` (SEMANTICS.md, "Sorts and values").
- **Edge cases.** `VBV 0 0`, `VBV 65 0` and `VBV (-1) 0` are invalid, and the
  last one must return `False`, not throw (`2 ^ (-1)` throws at `Integer`).
  `VBV 64 (2^64 - 1)` is valid.
- **Tests.** `-p Expr.validValue`: 11 cases, each named by its value, e.g.
  `VBV 8 255`, `VBV 8 256`, `VBV (-1) 0`.

## 2. `Lozenge.Eval.eval`

Write it in this order; each step turns on more of `Eval/*`.

- [ ] Leaves (`Var`, `Lit`). Tests: `Eval/leaves`, the `InvalidValue` and
  `UnboundVar` cases. *Which function from step 1 do both leaves need, and
  what does `Data.Map.Strict` give you for a lookup that might miss?*
- [ ] Unwrapping operands. *You will repeatedly need "this `Value` must be a
  `VBV`; give me its width and payload, or fail". What type would that helper
  have, and which monad lets you chain it with `do`?*
- [ ] `Un` and `Bin` arithmetic. Tests: `Eval/arithmetic wraps`.
  *Is Haskell's `mod` or `rem` the right one when `a - b` is negative?*
- [ ] Bitwise ops. Tests: `Eval/bitwise`. *`Data.Bits` also exports
  constructors named `And` and `Xor`; how will you import it so they don't
  clash with `Lozenge.Expr`'s?*
- [ ] Shifts. Tests: `Eval/shifts` and the `eval never throws` property.
  *If `b` is `2^64 - 1`, what happens when you compute `2^b` or
  `shiftL a (fromInteger b)`, and which test decides before you do either?*
- [ ] `Cmp`. Tests: `Eval/comparisons`. *For `slt`, how do you get the signed
  reading of an unsigned value at width `w`?*
- [ ] `Ite`. Tests: `Eval/ite`. *Why must both branches be evaluated even
  though only one is returned?*
- [ ] Error order. Tests: `Eval/errors`, `Eval/error order`. *If you
  evaluate every operand in one `do` block before inspecting any of them,
  which ordering rule do you get for free?*
- [ ] Property `eval results are valid values`. *Is there any operation whose
  result you did not reduce into `[0, 2^w)`?*

## Spec: eval

```haskell
eval :: Env -> Expr -> Either EvalError Value
```

- **Behaviour.** Each operation means what the table in SEMANTICS.md,
  "Operations", says. Every bitvector result is in `[0, 2^w)`. A shift by
  `w` or more gives 0, and the shift amount can be up to `2^64 - 1`, so
  `2^b` must not be computed for a large `b`. `slt` reads both operands as
  two's complement at width `w`. `Var x` is the value `env` binds to `x`.
- **Errors** (SEMANTICS.md, "Errors and evaluation order"):
  - `UnboundVar x`: `x` is not in `env`.
  - `ExpectedBV`: a `Bool` is an operand of an operator or comparison, or
    an `ite` branch. `=` on booleans is this error, and `ite` never selects
    between booleans.
  - `ExpectedBool w`: an `ite` condition is a `BV w`.
  - `WidthMismatch l r`: operands, or `ite` branches, of widths `l /= r`, in
    the order written.
  - `InvalidValue v`: a literal, or a value read from `env`, is not
    `validValue`.
- **Order.** Evaluate every operand left to right (`ite`: condition, then,
  else; both branches always). The first operand that fails decides. Only
  then check the node: operand sorts left to right, then widths.
- **Laws.** Total: never throws and never hangs. Every `Right v` has
  `validValue v`.
- **Tests.** `-p Eval.`, against `testEnv` from `test/ExprGen.hs`
  (`p = true`, `q = false`, `b = BV 1 1`, `x = BV 8 200`, `y = BV 8 7`,
  `z = BV 64 (2^64 - 1)`). Groups `leaves` (4), `arithmetic wraps` (14),
  `bitwise` (7), `shifts` (15), `comparisons` (12), `ite` (3), `errors` (23)
  and `error order` (11), each case named by its expression; and
  `properties`: "eval never throws" (1 s per term) and "eval results are
  valid values" (at least 40% of generated terms evaluate).

## 3. `Lozenge.Pretty.render`

Tests: `Pretty/*`.

- [ ] `render`. *Which prettyprinter combinator puts its arguments on one line
  if they fit and on separate lines otherwise, and which `layout*` function
  plus `Prettyprinter.Render.Text` function turn a `Doc` into `Text`?*
- [ ] Operator names. *`Parse` will need the same name-to-operator table in
  reverse. Where can the table live so that the two can never disagree?*

## Spec: render

```haskell
render :: Expr -> Text
```

- **Behaviour.** The canonical form: `(op arg ...)` with single spaces,
  `true` and `false`, `(const w v)` in decimal, and a variable as its name.
  Operator names are the words in SEMANTICS.md, "Concrete syntax". A term
  that fits in 80 columns is on one line.
- **Laws.** `parseExpr (render e) == Right e` for every `e` with
  well-formed literals and valid identifiers.
- **Tests.** `-p Pretty`: 19 cases named by the expected text, e.g.
  `(ite (ult x y) x y)` and `(neg (not (add x (neg y))))`, plus "fits in 80
  columns => one line" (a 72-character term). The round trip is the
  property in `-p Parse`.

## 4. `Lozenge.Parse.parseExpr`

Tests: `Parse/*`.

- [ ] Imports. *`Text.Megaparsec` exports its own `ParseError`; how will you
  keep it from clashing with ours?*
- [ ] Lexing: whitespace, `lexeme`, `symbol`. Tests: whitespace cases in
  `Parse/accepts`. *If every token parser eats the whitespace after itself,
  where is the only place you still need to skip whitespace explicitly?*
- [ ] Identifiers, `true` and `false`. *How do you parse a word so that
  `true1` is a variable but `true` is a literal?*
- [ ] `(const w v)`. Tests: the `const` cases. *When `v` is out of range, how
  do you make the error point at `v` rather than at the end of the form?*
- [ ] The forms. Tests: the operator cases, `(addx y z)`, the arity cases.
  *After reading the operator word, how can the rest of the parse depend on
  which word it was?*
- [ ] Whole input. Tests: `"x y"`, `"(add x y))"`, `""`. *What should come
  after the expression?*
- [ ] Error messages. The golden test `Parse/error messages` writes
  `test/golden/parse-errors.txt` on its first passing run (it does not exist
  yet). Read every message in it. *Would a newcomer understand each one? If
  not, which `label` (`<?>`) or `fail` would fix it?* Rerun with
  `--test-arguments=--accept` after changing messages, and commit the file.
- [ ] Property `parseExpr (render e) == Right e`. *When it fails, QuickCheck
  shrinks the counterexample. Does the smallest one fail in `render` or in
  `parseExpr`?*

## Spec: parseExpr

```haskell
type ParseError = ParseErrorBundle Text Void
parseExpr :: Text -> Either ParseError Expr
```

- **Behaviour.** Parses exactly one `expr` of the grammar in SEMANTICS.md,
  "Concrete syntax", with optional whitespace (space, tab, newline) around
  it and between tokens. Whitespace is required only between two adjacent
  words.
  - Identifiers are `[A-Za-z_][A-Za-z0-9_]*`, except `true` and `false`;
    `true1` is a variable.
  - Operator names are special only in head position: `(add add const)`
    adds the variables `add` and `const`. `(addx y z)` is an unknown
    operator.
  - `(const w v)`: two decimal naturals (leading zeros allowed) with
    `1 <= w <= 64` and `0 <= v < 2^w`.
  - Arity is checked, sorts are not: `(add true (const 16 0))` parses.
- **Errors.** `Left` for: empty or blank input, `()`, unbalanced
  parentheses, two expressions (`x y`), a bare number, `1x`, `(x)`, an
  unknown operator, a wrong arity, a malformed or out-of-range `const`, and
  a `;` comment.
- **Laws.** `parseExpr (render e) == Right e` (see `render`). From Phase 3
  on it is a thin wrapper over `exprWith` (TODO-p3, step 5).
- **Tests.** `-p Parse`: `accepts` (29 cases, named by the source text),
  `rejects` (28), the golden `error messages`
  (`test/golden/parse-errors.txt`, written on the first passing run), and
  the property `parseExpr (render e) == Right e`.

## Shortcuts

- **`eval`, `parseExpr`: no division or remainder**, no signed shift right,
  rotations, concatenation, extraction or extension, and no Boolean
  connectives. Ceiling: rules over those operations can't be written.
  Upgrade: add `udiv`/`urem` (and the signed forms) with SMT-LIB's total
  results for a zero divisor (`bvudiv s 0` is all ones, `bvurem s 0` is
  `s`), and connectives when a rule needs them (SEMANTICS.md, "Out of scope
  for Phase 1"; README, "Limitations").
- **`validValue`: widths 1 to 64.** Ceiling: no bitvector wider than 64
  bits. Upgrade: not recorded.

## Open questions

- `render`: the layout of a term wider than 80 columns (where it breaks and
  how it indents). The tests only require that it parses back.
- `parseExpr`: the wording and position of each error message, until you
  accept `test/golden/parse-errors.txt`. Step 4 asks you to make the
  out-of-range `v` error point at `v`.
