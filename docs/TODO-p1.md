# Phase 1 TODO: untyped IR

Spec: [SEMANTICS.md](SEMANTICS.md). Each step names the tests that should go
green. Run a group with, e.g., `stack test --test-arguments='-p Eval'`.
Hints are rung 1 (a question). Ask for the next rung when you want it.

## 1. `Lozenge.Expr.validValue`

Tests: `Expr/validValue`.

- [ ] `validValue`. *Which three inequalities must hold for a `VBV`, and what
  does `VBV (-1) 0` tell you about the order you check them in?*

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

## 3. `Lozenge.Pretty.render`

Tests: `Pretty/*`.

- [ ] `render`. *Which prettyprinter combinator puts its arguments on one line
  if they fit and on separate lines otherwise, and which `layout*` function
  plus `Prettyprinter.Render.Text` function turn a `Doc` into `Text`?*
- [ ] Operator names. *`Parse` will need the same name-to-operator table in
  reverse. Where can the table live so that the two can never disagree?*

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
