# Phase 4a TODO: SMT-LIB emission

Spec: the `## Spec` entries below. Run a group with, e.g.,
`stack test --test-arguments='-p Smt.toSmt'`. Hints are rung 1 (a question).
Ask for the next rung when you want it.

**Prerequisites.** `ruleQuery` needs Phase 2's `typecheck`. The balanced
property generates rules with `erase`. `smtName` and `toSmt` (steps 1 and 2)
stand alone.

## Decisions

- **Variable names get a `v_` prefix.** `?x` is in fact a legal SMT-LIB
  symbol (`?` is allowed), and the rule parser drops the `?` anyway. The real
  danger is a name SMT-LIB already uses: z3 rejects
  `(declare-const and (_ BitVec 8))` and `(declare-const _ ...)`. No reserved
  word or `QF_BV` function starts with `v_`, and a prefix is easy to strip from
  a `get-value` model in Phase 4b. The golden `de-morgan-awkward-names` uses
  variables called `_` and `and`.
- **`ruleQuery :: Rule -> Either Text Text`**, not `Rule -> Text`. It has to
  typecheck the rule to get the `TExpr`s that `toSmt` takes, and a `Rule` built
  by hand can be ill-typed. `verifyBrute` returns `Unsupported` for the same
  cases.
- **No `get-value` without variables.** z3 rejects `(get-value ())`.
- **Generic rules are emitted at their written width.** Call `instantiate`
  first to get another width. Phase 4b chooses the widths.
- **The z3 test runs on the golden files, not on your output.** It already
  passes, which shows the spec is right. The golden tests then tie your output
  to those files. After `unsat`, z3 prints `(error "... model is not
  available")` for `get-value`. The test allows that error, and only that one.

## 1. `smtName`

Tests: `-p Smt.smtName`.

- [ ] *Why a prefix rather than checking each name against a list of reserved
  words? What would you have to keep up to date with the other approach?*
- [ ] *Suppose two different lozenge names gave the same SMT name. What would
  go wrong in the `declare-const`s and in reading back a `get-value` model?*

## Spec: smtName

```haskell
smtName :: Text -> Text
```

- **Behaviour.** The SMT-LIB symbol for a lozenge variable: the name with
  the prefix `v_`. So `x` is `v_x`, `and` is `v_and`, `_` is `v__`.
- **Laws.** Injective: two different names give two different symbols, so
  a `get-value` model reads back unambiguously.
- **Tests.** `-p Smt.smtName`: "x", "a builtin name", "a reserved word".

## 2. `toSmt`

Tests: `-p Smt.toSmt`.

- [ ] Shape. *Does `toSmt` need to know `t`? Which constructors carry a
  `SingTy` or `SNat`, and do you need it for any of them except a literal's
  width?*
- [ ] Literals. *`VBV` holds an `SNat w`, not an `Int`. Which function did
  Phase 2 (or `test/TExprGen.hs`) use to get the number back?* Test:
  `(_ bv18446744073709551615 64)`. *Which `show` gives that, and could an
  `Int` hold it?*
- [ ] Operators. *If you write the operator names as a separate function per
  operator type (`UnOp`, `BinOp`, `CmpOp`), what does `-Wall` tell you when
  someone adds a constructor? Would it tell you if you used a wildcard
  pattern?*
- [ ] Parentheses. *Every non-leaf is `(op arg ...)`. Is one helper that takes
  the head and the arguments and adds the parentheses and spaces less
  error-prone than writing `"(" <> ... <> ")"` in every equation? Which
  `Data.Text` function puts spaces between a list of pieces?*

## Spec: toSmt

```haskell
toSmt :: TExpr t -> Text
```

- **Behaviour.** One SMT-LIB term, on one line, with single spaces:
  - `TVar _ x` is `smtName x`;
  - `true`, `false`;
  - `VBV w v` is `(_ bvV W)`, both in decimal: `(_ bv255 8)`,
    `(_ bv18446744073709551615 64)`;
  - operators by the SMT-LIB column of SEMANTICS.md: `bvnot`, `bvneg`,
    `bvadd`, `bvsub`, `bvmul`, `bvand`, `bvor`, `bvxor`, `bvshl`, `bvlshr`,
    `=`, `bvult`, `bvslt`, `ite`, each as `(op arg ...)`.
- **Tests.** `-p Smt.toSmt`: 22 cases, each named by the expected text, e.g.
  `(ite (bvult v_x v_y) (bvadd (bvmul v_x v_y) (bvnot (_ bv1 8))) (bvneg v_y))`.

## 3. `ruleQuery`

Tests: `-p Smt.ruleQuery` (the exact-text cases and the rejects), then
`-p "Smt.ruleQuery golden"`, then `-p "Smt.every query"`.

- [ ] Declarations. *Where does a variable's sort come from: `typecheck`, or
  something already in the `Rule`? How do you print `TBool` and `TBV w`?*
- [ ] Errors. *`typecheck` returns `Either TypeError SomeExpr`. How did you
  turn those into `Unsupported` in `verifyBrute`, and does the same `do` in
  `Either` work here with `Text` on the left?*
- [ ] Sorts. *You hold `SomeExpr s1 l` and `SomeExpr s2 r`. You can print
  `(= l r)` without knowing `t1 ~ t2`. So why must you still check that the
  sorts agree, and what would z3 say if you didn't?*
- [ ] Precondition. *Which sort must it have, and how do you check that
  without a type-equality proof? Is it the same check as for lhs and rhs?*
- [ ] Optional lines. *The precondition `assert` and the `get-value` each
  appear zero or one time. Which list idiom gives zero or one lines without an
  `if` that returns an empty `Text` (which would leave a blank line)?*
- [ ] Order. *`Map.toList` gives keys in ascending order. Is `"_"` before or
  after `"and"`? Check the `de-morgan-awkward-names` golden file.*

## Spec: ruleQuery

```haskell
ruleQuery :: Rule -> Either Text Text
```

- **Behaviour.** The SMT-LIB script that asks z3 for a counterexample to
  the rule at its written width (call `instantiate` first for another
  width). One command per line, each line ending in a newline:

  ```
  (set-option :produce-models true)
  (set-logic QF_BV)
  (declare-const v_x (_ BitVec 4))       one per ruleVars entry, by name
  (assert (bvult v_x (_ bv8 4)))         only if there is a precondition
  (assert (not (= LHS RHS)))
  (check-sat)
  (get-value (v_x))                      only if there are variables
  ```

  A `Bool` variable is declared `Bool`. Every variable in `ruleVars` is
  declared, even one that neither side uses. Declarations are in ascending
  order of the lozenge name (`_` before `and`).
- **Errors.** `Left` when the lhs, rhs or precondition does not typecheck
  against `ruleVars`, when lhs and rhs have different sorts, or when the
  precondition is not `Bool`: the cases where `verifyBrute` says
  `Unsupported`.
- **Laws.** Every line of every query has balanced parentheses. z3 answers
  `unsat` exactly when the rule is valid.
- **Tests.** `-p Smt.ruleQuery`: "no variables: no get-value" (exact text),
  "an unused variable is still declared", and the rejects "lhs Bool, rhs
  BV", "precondition is not Bool", "ill-typed lhs", "undeclared variable".
  `-p "Smt.ruleQuery golden"`: 8 goldens in `test/golden/smt/`. The property
  `-p "Smt.every query"`. `-p "Smt.z3 accepts"` runs z3 on the golden files
  themselves, so it passes already (skipped without z3).

## 4. Read the goldens

`test/golden/smt/*.smt2` were written by hand and checked with z3. Run
`z3 test/golden/smt/sub-comm.smt2` and read the model. *Which two values does
it give, and does `x - y = y - x` fail for them at width 8?* Do not run
`--accept` until your output and the golden file differ only in a way you
understand.

## Shortcuts

None recorded for this phase.

## Open questions

- `ruleQuery`: the text of each `Left`. The tests only check that it is a
  `Left`.
