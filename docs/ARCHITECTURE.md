# Architecture

## Module map

| Layer | Module | Role |
|---|---|---|
| Untyped IR | `Lozenge.Expr` | `Expr`, `Value`, operators |
| | `Lozenge.Parse`, `Lozenge.Pretty` | S-expression syntax in and out (megaparsec, prettyprinter) |
| | `Lozenge.Eval` | reference evaluator, every error explicit ([SEMANTICS.md](SEMANTICS.md)) |
| Typed IR | `Lozenge.Typed` | `TExpr t`, a GADT indexed by sort and width |
| | `Lozenge.Typecheck` | `Expr -> Either TypeError SomeExpr` |
| | `Lozenge.EvalT` | total evaluator for well-typed terms |
| Rules | `Lozenge.Rule`, `Lozenge.RuleParse` | `Rule`, `Fixed`/`Generic` widths, the `.rules` syntax |
| Verification | `Lozenge.VerifyBrute` | every assignment, up to 2^20 |
| | `Lozenge.Smt`, `Lozenge.Solver`, `Lozenge.VerifySmt` | SMT-LIB emission, the z3 subprocess, the `Verify` monad |
| | `Lozenge.SymExec` | a tiny symbolic executor over `TExpr` |
| Rewriting | `Lozenge.Fix`, `Lozenge.ExprF` | `Fix ExprF`, recursion schemes, `FixRule` |
| | `Lozenge.Rewrite` | matching, unification, greedy `normalise` |
| | `Lozenge.Critical` | critical pairs, joinability, z3 check |
| E-graphs | `Lozenge.UnionFind`, `Lozenge.EGraph` | union-find and hash-consed e-graph in `ST` |
| | `Lozenge.EMatch`, `Lozenge.Saturate`, `Lozenge.Extract` | e-matching, saturation with a backoff scheduler, cheapest-term extraction |
| Tensors | `Lozenge.Tensor`, `Lozenge.TensorEval` | shape-typed `Tensor '[m, k]`, reference evaluator |
| | `Lozenge.Graph` | hash-consed untyped graph IR, shape inference, `lower` |
| | `Lozenge.Fusion` | elementwise chains into kernels; kernel count + traffic cost |
| | `Lozenge.TensorOpt` | tensor rules and extraction on the generic e-graph |
| | `Lozenge.EmitC` | checked C code for a fused program |
| | `Lozenge.Grad` | reverse-mode AD: gradient of a `Tensor` program's summed output |
| | `Lozenge.Mlp` | the demo: 2-layer ReLU MLP, gradient descent, loss CSV and SVG (`app/Train.hs`) |
| CLI | `Lozenge.Cli`, `Lozenge.Json` | the three commands; the JSON schema types |
| | `app/Main.hs` | argument parsing only (optparse-applicative) |

## Data flow

1. **Text to `Expr`/`Rule`.** `Parse` and `RuleParse` share one expression
   parser (`exprWith`); a rule's variable sorts are inferred, and a rule that
   writes `(const w v)` is `Generic`.
2. **Checking.** `instantiate w` fixes a generic rule's width.
   `Typecheck` turns each side into a `TExpr`; `VerifyBrute` evaluates both
   sides with `EvalT` on every assignment, and `VerifySmt` sends
   `(assert (not (= lhs rhs)))` to z3 and re-checks any model with `EvalT`.
   Both return the same `Verdict`.
3. **Rewriting.** `ruleToFix` turns a rule into patterns over `Fix ExprF`.
   `Rewrite.normalise` rewrites greedily; `Critical` unifies left-hand sides
   to find overlaps and joins them with `normalise`, then asks z3.
4. **Saturation.** `Saturate.loadRules` admits only rules that verify at the
   graph's width (the `CheckedRule` type records that). `saturate` e-matches
   all rules, then applies them, until a fixpoint or a limit; `extract` picks
   the cheapest term under a `CostFn`.
5. **CLI.** `Cli.run` strings these together and returns text or JSON plus
   an exit code; `Main` only parses arguments and prints.

## Why GADTs here and `Fix` there

**`TExpr t` is a GADT** because its job is to make wrong terms
unrepresentable. Indexing by sort and width means `(add x true)` and an
8-bit/16-bit mix don't type in Haskell, so `EvalT` and the SMT emitter are
total: no `WidthMismatch` cases, no `Either`. The cost is that every term
built from text goes through `Typecheck` and comes back existentially
wrapped (`SomeExpr`), which suits code that consumes checked terms.

**`Fix ExprF` is a plain functor fixpoint** because rewriting works on
shapes, not types. Patterns need a constructor (`PVar`) that has no sort, and
matching, unification, positions and e-graph nodes all want "one layer with
holes": `ExprF ClassId` is an e-node, `ExprF Int` a costed node, and `cata`,
`traverse` and `Foldable` give generic traversals for free. Doing this on
the GADT would need type-indexed substitutions and existential children at
every node. The price is that rewriting ignores sorts, so `loadRules` checks
rules before they reach the graph, and `toTyped` converts back to check a
result.
