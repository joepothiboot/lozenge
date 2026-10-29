# Phase 5a TODO: `Fix ExprF`

Spec: the Haddock in `src/Lozenge/Fix.hs` and `src/Lozenge/ExprF.hs`. Run a
group with, e.g., `stack test --test-arguments='-p ExprF.Fix'`. Hints are rung
1 (a question). Ask for the next rung when you want it.

**Prerequisites.** Steps 1 to 3 stand alone. `toTyped` and `ruleToFix` need
Phase 2's `typecheck`. The `ruleToFix` property generates rules with `erase`,
and the corpus test needs `parseRules`.

## Decisions

- **`ExprF` mirrors `Expr`, not one constructor per operator.** `UnF UnOp r`,
  `BinF BinOp r r` and `CmpF CmpOp r r` reuse the Phase 1 operator enums.
  Every function then has 7 cases instead of 16, and a new operator is one
  enum constructor, not a new `ExprF` constructor plus a case in every
  function. An e-graph node still compares its operator, because the derived
  `Eq` and `Ord` include it.
- **Two variable leaves.** `VarF x` is a term's input and `PVar x` is a
  pattern's `?x`. `fromTyped` makes only `VarF`; `ruleToFix` turns every
  variable into a `PVar`. `toTyped` types both the same way, by looking the
  name up in the `Context`, so a rule's sides typecheck against `frVars`.
- **`Lozenge.Fix` is its own module.** It knows nothing about lozenge, and
  its derived instances need `UndecidableInstances`. Keeping it separate keeps
  that extension out of `Lozenge.ExprF`.
- **`para` is in.** Phase 5c's critical pairs visit every subterm of an lhs,
  and `para` gives each node its original children next to the folded
  results.
- **`Ord` on `Value`, `UnOp`, `BinOp` and `CmpOp`.** Deriving `Ord` for
  `ExprF` needs it. An orphan instance is not allowed, so it is derived in
  `Lozenge.Expr`.
- **`ruleToFix :: Rule -> Either Text FixRule`**, like `ruleQuery`.
  `TypeError` has no constructor for "lhs and rhs have different sorts".
- **From Phase 5b on, `[Rule]` means `[FixRule]`.** The rewrite engine and the
  e-graph read the same corpus through `ruleToFix`.
- **The derived-instance tests already pass.** They spot-check what
  `deriving stock` generates (child order, `traverse Identity`), so they pass
  before you write anything. They are there to show the order your folds will
  see.
- **`SomeExpr` is compared by `show`**, as in Phase 4c, because `TExpr` has
  no `Eq` instance.

## 1. `cata`, `ana`, `para`

Tests: `-p ExprF.Fix`.

- [ ] *Look at the types. `cata` has to turn a `Fix f` into an `a`, and the
  algebra wants an `f a`. What do you get by unwrapping the `Fix`, and which
  class method turns the children into `a`s?*
- [ ] *`ana`'s type is `cata`'s with the arrows reversed. Can you get its
  definition the same way, reading `cata`'s from right to left?*
- [ ] *For `para`, each child must become a pair. What is the first part, and
  what is the second? Can you write it so it never calls `cata`?*
- [ ] *Why can `ana` loop forever but `cata` on a finite term cannot?*

## 2. `size`, `depth`, `vars`

Tests: `-p "ExprF.size, depth, vars"`.

- [ ] *Write each algebra's type first: `ExprF Int -> Int` for `size`. Which
  `Foldable` functions on one layer give "the sum of the children" and "the
  largest child", and what does each give for a leaf?*
- [ ] *For `vars`, which cases are not "combine the children"? Can the rest
  share one equation?*
- [ ] *The test's hand-written `children` lists a layer's children with
  explicit cases. Why does your algebra not need it?*

## 3. `fromTyped`

Tests: `-p ExprF.fromTyped`.

- [ ] *Phase 2's `erase` already goes from `TExpr t` to `Expr`. Is
  `fromTyped` closer to writing a second `erase`, or to converting an `Expr`?
  Which choice leaves less code, and which one checks your `erase`?*
- [ ] *Which `GHC.TypeNats` function did `erase` use to get the width of a
  literal back as a number?*

## 4. `toTyped`

Tests: `-p ExprF.toTyped`.

- [ ] *The spec says "the same rules and the same errors as `typecheck`". Can
  you get that without writing a second typechecker? What would you convert
  the `Fix ExprF` into first?*
- [ ] *Which function from step 1 does that conversion, and what does it do
  with a `PVar`?*
- [ ] *Why is the round-trip law stated for well-typed terms only? What does
  `toTyped` do for `fromTyped` of an ill-typed term, and can such a term
  exist?*

## 5. `ruleToFix`

Tests: `-p ExprF.ruleToFix`.

- [ ] *Phase 4a's `ruleQuery` already typechecks a rule's three parts and
  checks their sorts. Which part of it can you share, and where should the
  shared code live so that `Lozenge.ExprF` does not import `Lozenge.Smt`?*
- [ ] *Turning every `VarF` into a `PVar` is a function `Fix ExprF -> Fix
  ExprF`. Which scheme from step 1 writes it, and what is the algebra's
  carrier type?*
- [ ] *`typecheck` and `fromTyped` together give `Expr -> Fix ExprF` for a
  well-typed rule. Why go through the typed IR at all instead of converting
  the `Expr` directly? What would a direct conversion miss?*
- [ ] *The corpus test checks that every variable of a `FixRule` side is in
  `ruleVars`. Which part of the conversion guarantees that already?*
