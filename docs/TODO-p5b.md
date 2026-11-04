# Phase 5b TODO: matching, unification, rewriting

Spec: the `## Spec` entries below. Run a group with, e.g.,
`stack test --test-arguments='-p Rewrite.match'`. Hints are rung 1 (a
question). Ask for the next rung when you want it.

**Prerequisites.** Phase 5a's `cata` (or plain recursion) is all you need. The
tests build their rules as `FixRule`s by hand, so nothing here waits on
`typecheck`, `ruleToFix` or `parseRules`.

## Decisions

- **`[Rule]` means `[FixRule]`**, as Phase 5a decided.
- **Only `PVar` is a variable.** `VarF a` is a constant symbol, like a literal.
  In `match`, a `PVar` in the *subject* is a constant too: only the pattern's
  variables get bound.
- **Preconditions are ignored in this phase.** `rewriteOnce` and `normalise`
  skip every rule that has one, so they never rewrite with a rule they can't
  check. `normalise` returns the names of the skipped rules, so its type is
  `([Text], NormalForm)`, not `NormalForm`. Phase 5c skips them too; no phase
  handles conditional rules yet.
- **`NormalForm` has three constructors:** `Done`, `Cycle k ts` and
  `OutOfFuel ts`. A cycle is a repeat of *any* earlier term, not just the
  input. The repeat check comes before the fuel check, and `Done` wins when
  the last step the fuel allows reaches a normal form.
- **`unify` returns an idempotent most general unifier.** Then one
  `applySubst` pass is enough, and "most general" can be tested as
  `u . s = u` for every unifier `u`. The same `PVar` name on both sides is one
  variable. Phase 5c renames rules apart before unifying them.
- **`match` ignores sorts.** The `-- shortcut:` comment names the ceiling and
  the upgrade.
- **A Generic rule matches only at its written width**, because its literals
  carry that width. Run `instantiate w` on the `Rule` before `ruleToFix` to
  rewrite at width `w`.
- **The most-general test is a brute-force check.** For pairs of terms of
  depth 3 or less over `?x` and `?y`, it tries all 225 bindings of the two
  variables to ground terms of depth 2 or less. Every one that unifies the
  pair must factor through your answer, and if you say `Nothing`, none may
  unify.

## 1. `applySubst`

Tests: `-p Rewrite.applySubst`.

- [ ] *Which leaf is the only one that changes? Can you write it as a
  `cata` whose algebra handles one case and rebuilds every other layer as it
  is?*
- [ ] *The "one pass" test maps `?x` to `?y` and `?y` to `a`. Why does a
  `cata` give `?y` there and not `a`?*

## Spec: applySubst

```haskell
type Subst = Map Text (Fix ExprF)
applySubst :: Subst -> Fix ExprF -> Fix ExprF
```

- **Behaviour.** Replace every `PVar x` that the substitution binds by its
  value. A `VarF`, and a `PVar` it does not bind, stay. One pass: a value
  put in is not substituted again.
- **Tests.** `-p Rewrite.applySubst`: "replaces a bound PVar everywhere",
  "leaves VarF and unbound PVar", "one pass".

## 2. `match`

Tests: `-p Rewrite.match`.

- [ ] *Matching walks the pattern and the subject together. When the pattern
  is not a `PVar`, what must be true of the two top layers before you look at
  the children? Is there a way to compare "same constructor, same operator,
  same leaf" without writing one case per constructor?*
- [ ] *A `PVar x` is reached a second time. You already have a binding for
  `x`. What do you compare, and with which `Eq` instance?*
- [ ] *The children's matches must agree with each other. Do you thread one
  `Subst` through the children in order, or match each child separately and
  combine the maps? With the second way, what goes wrong when two maps bind
  the same variable?*
- [ ] *Which `Foldable` or `Traversable` function walks the children of two
  layers in step? If there is none, what can you zip?*

## Spec: match

```haskell
match :: Fix ExprF -> Fix ExprF -> Maybe Subst
```

- **Behaviour.** One-way matching of a pattern against a subject. Only the
  pattern's `PVar`s bind; anything else in the pattern must equal the
  subject layer by layer: the same constructor, the same operator, the same
  `VarF` name, the same literal (width included). A `PVar` in the subject
  is a constant, but a pattern `PVar` can bind to it. A variable that occurs
  twice must bind equal subterms.
- **Laws.**
  - If `match p t == Just s`, then `applySubst s p == t`.
  - For every ground substitution `s`, `match p (applySubst s p)` succeeds
    and binds exactly the pattern's variables.
- **Tests.** `-p Rewrite.match`: "binds every variable", "a variable that
  would need two values", "a repeated variable with equal subterms",
  "constants must agree", "a VarF in the pattern is a constant", "a PVar in
  the subject is a constant", "a PVar matches a PVar", "literal widths must
  agree", "operators must agree", and the two laws as properties.

## 3. `unify`

Tests: `-p Rewrite.unify`.

- [ ] *How is `unify` different from `match`? Which side may now contain
  variables, and what happens when both sides are variables?*
- [ ] *You are about to bind `x` to `t`. Which two checks must come first, and
  what is the occurs check protecting against?*
- [ ] *Idempotence: after binding `x` to `t`, some values in your `Subst` may
  still contain `x`. What must you do to them, and to `t` itself, so that no
  bound variable appears in any value?*
- [ ] *Why must you apply the current `Subst` to both children before you
  unify the next pair? Which test fails if you don't?*
- [ ] *The textbook algorithm works on a list of equations. Is that easier
  here than recursing on the two terms?*

## Spec: unify

```haskell
unify :: Fix ExprF -> Fix ExprF -> Maybe Subst
```

- **Behaviour.** A most general unifier of two terms, if there is one.
  `PVar`s on both sides are variables, and the same name on both sides is
  one variable. `VarF`s and literals are constants. Binding `x` to a term
  that contains `x` fails (the occurs check), also through another
  variable.
- **Laws.**
  - If `unify l r == Just s`, then `applySubst s l == applySubst s r`.
  - The result is idempotent: `applySubst s t == t` for every value `t` in
    `s`, so one `applySubst` pass is enough.
  - Most general: every unifier `u` factors through `s`
    (`u . s = u` on the variables). `Nothing` only when no unifier exists.
- **Edge cases.** `unify px px` is `Just empty`.
- **Tests.** `-p Rewrite.unify`: "occurs check", "occurs check through
  another variable", "a variable with itself", "both sides bind", "the
  result is idempotent", "operators clash", "VarFs clash"; properties
  "Just s: applySubst s a == applySubst s b, and s is idempotent" and "most
  general, checked against every small ground unifier".

## 4. `rewriteOnce`

Tests: `-p Rewrite.rewriteOnce`.

- [ ] *At one position, "try the rules in order, take the first that works" is
  a fold over a list of `Maybe`s. Is there already a function that picks
  the first `Just`, and which class is it from?*
- [ ] *Going into the children: you want to rewrite only the first child that
  can be rewritten and leave the rest. Why does `traverse` with `Maybe` not do
  that? What would it do instead?*
- [ ] *Is `para` useful here? At each node you need both the rewritten child
  and the original children.*

## Spec: rewriteOnce

```haskell
rewriteOnce :: [FixRule] -> Fix ExprF -> Maybe (Fix ExprF)
```

- **Behaviour.** One rewrite step, outermost then leftmost. At the root, try
  the rules in list order; the first whose lhs matches gives
  `applySubst s rhs`. If none applies at the root, rewrite the first child,
  in `Foldable` order, that can be rewritten (its whole subtree before the
  next child), and leave the others. Position comes before rule order.
  `Nothing` if no rule applies anywhere.
- **Edge cases.** A rule with a precondition (`frPre /= Nothing`) is
  skipped. A non-linear lhs such as `(xor ?x ?x)` applies only to equal
  subterms.
- **Tests.** `-p Rewrite.rewriteOnce`: "outermost: the root first",
  "leftmost: the left child before the right", "the whole left subtree
  before the right child", "rules in order at one position", "position
  before rule order", "a non-linear rule", "a normal form", "a rule with a
  precondition is skipped".

## 5. `normalise`

Tests: `-p Rewrite.normalise`.

- [ ] *The loop's state is the fuel left, the terms seen so far, and the
  current term. Which data structure answers "seen before?" quickly, and which
  instance from Phase 5a makes that possible?*
- [ ] *You need a set for the check and a list for the result. Can one value
  serve both, or do you keep both?*
- [ ] *Write down the order of the three checks (normal form? repeat? fuel
  left?) and walk the "fuel 2 is just enough" and "cycle that closes on the
  last step" tests through it.*
- [ ] *The cycle check catches a repeat. Give a rule that never terminates
  and never repeats a term. What does the "growing term" test use?*
- [ ] *Run "two terms of the same shape in a row are not a cycle" and "two
  terms that differ only in a literal are not a cycle". What exactly does your
  "seen before?" compare?*

## Spec: normalise

```haskell
data NormalForm = Done (Fix ExprF) | Cycle Int [Fix ExprF] | OutOfFuel [Fix ExprF]
normalise :: Int -> [FixRule] -> Fix ExprF -> ([Text], NormalForm)
```

- **Behaviour.** Apply `rewriteOnce` repeatedly, using at most `fuel`
  steps. The first component names the rules skipped for having a
  precondition, in list order. Before each step, in this order:
  1. If no rule applies, `Done t`.
  2. If `fuel` steps are used up, `OutOfFuel ts`, where `ts` is every term
     seen, from the input on (`fuel + 1` terms).
  3. Otherwise step to `u`. If `u` was seen before (any earlier term, not
     only the input), `Cycle k (ts ++ [u])`, where `k` is the number of
     steps taken (the list has `k + 1` terms and ends with the repeat).
- **Edge cases.** So `Done` wins when the last step the fuel allows reaches
  a normal form, and a cycle that closes on that step is still a `Cycle`.
  Fuel 0 or less: `Done t` if `t` is a normal form, else `OutOfFuel [t]`.
- **Laws.** In `Cycle` and `OutOfFuel`, each term is `rewriteOnce` of the
  one before. `OutOfFuel` terms are all distinct. With terminating rules
  the result is `Done u` and nothing applies to `u`.
- **Tests.** `-p Rewrite.normalise`: "add-zero twice", "comm on (add a b) is
  a cycle", "a cycle that closes on the last step", "the repeat need not be
  the start", "fuel 1 is too little for add-zero twice", "fuel 2 is just
  enough", "fuel 0", "a growing term runs out of fuel", "a rule with a
  precondition is skipped and named", "two terms of the same shape in a row
  are not a cycle", "two terms that differ only in a literal are not a
  cycle"; properties "terminating rules: Done,
  and nothing applies" and "each term seen is rewriteOnce of the one
  before".
- **Derivation of the two same-shape tests.** `swap-a-b` is `(add a b) =>
  (add b a)`. Its only match is at the root of `(add a b)`, and nothing matches
  `(add b a)`, so the terms are `(add a b), (add b a)` and the result is
  `Done (add b a)`. They have the same size, depth, root operator and variables
  but are not equal. `zero-to-one` is `(add a 0) => (add a 1)`, which gives
  `Done (add a 1)` the same way; those two terms differ only in a literal.

## Shortcuts

- **`match` ignores sorts.** Ceiling: a pattern variable can bind a term of
  any sort or width, so a rule is applied wherever its shape fits.
  Upgrade: not recorded (the `-- shortcut:` comment was removed before it
  was committed).
- **`rewriteOnce`, `normalise`: rules with a precondition are skipped.**
  Ceiling: conditional rules never fire in greedy rewriting. Upgrade: not
  recorded (README, "Limitations": "Conditional rules are partial").

## Open questions

- `normalise`: when a rule with a precondition is named twice in the list,
  whether its name appears twice. The test uses two different names.
