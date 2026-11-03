# lozenge

[![CI](https://github.com/joepothiboot/lozenge/actions/workflows/ci.yml/badge.svg)](https://github.com/joepothiboot/lozenge/actions/workflows/ci.yml)

lozenge is a small Haskell workbench for bitvector rewrite rules. You write
rules such as `(rule add-zero (add ?x (const w 0)) => ?x)`, and lozenge checks
each one at a chosen width, by brute force or with the Z3 SMT solver, and
prints a concrete counterexample when a rule is wrong. It finds the rules'
critical pairs (two rules that overlap on the same term) and checks with Z3
whether each one joins. It also optimises expressions with the rules that
pass, either by greedy rewriting or by equality saturation on an e-graph, so
you can see where the two give different results. The expressions are a
typed IR over booleans and bitvectors of 1 to 64 bits, with SMT-LIB
semantics.

## 20-second demo

> **Pending.** The output below must come from a real run, and it can't yet:
> the library functions are still being written (see `docs/TODO-p*.md`), so
> every command currently stops at `TODO: parseRules`. Once they pass their
> tests, run `scripts/demo.sh` and paste its output here.

A wrong rule refuted with a counterexample:

```
$ lozenge verify rules/bitvector.rules --width 8 --solver both
(pending: paste the sub-comm lines and the summary from scripts/demo.sh)
```

Greedy rewriting vs equality saturation (`examples/strength.ir`; the full
experiment is in [examples/greedy-vs-saturation.md](examples/greedy-vs-saturation.md)):

```
$ lozenge optimize examples/strength.ir --rules rules/bitvector.rules --engine greedy --cost shifts
(pending)
$ lozenge optimize examples/strength.ir --rules rules/bitvector.rules --engine egraph --cost shifts
(pending)
```

## Training demo: a small MLP

lozenge also has a tensor IR with shapes in the types (`Tensor '[m, k]`),
reverse-mode automatic differentiation over it (`Lozenge.Grad`), and a
2-layer ReLU network written as a tensor program (`Lozenge.Mlp`).
`lozenge-train` trains the network by gradient descent, first on XOR (4
points), then on two moons (200 generated points). It writes each loss curve
to `docs/demo/*-loss.csv` and plots it as `docs/demo/*-loss.svg`.

> **Pending.** `grad` and the tensor evaluator are still being written (see
> [docs/TODO-p9.md](docs/TODO-p9.md)), so `lozenge-train` stops at
> `TODO: evalTensor`. Once they pass their tests, run
> `stack run lozenge-train`, commit `docs/demo/`, and put the two plots and
> the printed lines here.

### Not competitive with real frameworks

This demo shows how the pieces fit together. It is not built for speed or
scale, and PyTorch or JAX beat it on every point below:

- **Tensors are Haskell lists of `Double`**, with no unboxed arrays, BLAS,
  SIMD or GPU. Training runs in the interpreter. The C backend
  (`Lozenge.EmitC`) compiles only the forward program, not the training
  loop.
- **`grad` recomputes forward values**, with no tape, so its cost grows with
  the depth of the program, not just its size.
- **The IR is minimal.** It has no subtraction, broadcasting, constants,
  reductions, `exp` or `log`. So the targets come in negated, a bias is
  added as `ones × b`, the loss is mean squared error rather than
  cross-entropy, and the only nonlinearity is ReLU.
- **Shapes are fixed at compile time**, so the batch size is part of the
  program's type, and there is no mini-batching.
- **Training is plain full-batch gradient descent** at a fixed rate, with no
  momentum, Adam, schedules or regularisation. The random numbers come from
  a linear congruential generator.
- **The datasets are tiny**, and both are generated in code (XOR and two
  moons).


You need [Stack](https://docs.haskellstack.org/). Install
[z3](https://github.com/Z3Prover/z3) as well for `--solver smt|both` and
`critical-pairs` (`brew install z3` or `apt-get install z3`).

```sh
git clone https://github.com/joepothiboot/lozenge && cd lozenge
stack build
stack exec -- lozenge verify rules/bitvector.rules [--width N] [--solver brute|smt|both] [--json]
stack exec -- lozenge optimize EXPR.ir --rules RULES.rules [--width N] [--cost size|shifts] [--engine greedy|egraph] [--json]
stack exec -- lozenge critical-pairs RULES.rules [--width N] [--json]
scripts/demo.sh                                       # the demo above, step by step
stack run lozenge-demo                                # the greedy-vs-saturation experiment
stack run lozenge-train -- [DIR]                      # the MLP demo; writes DIR/*-loss.csv and .svg (default docs/demo)
```

`verify` exits with 1 when a rule has a counterexample, and 2 on bad
arguments or an error. The `--json` output is described in
[docs/JSON.md](docs/JSON.md), the IR in [docs/SEMANTICS.md](docs/SEMANTICS.md).

## Architecture

```
 .rules / .ir text
        │  Parse, RuleParse (megaparsec)
        ▼
 Expr, Rule ──Typecheck──▶ TExpr t (GADT) ──EvalT──▶ VerifyBrute ─┐
        │                       │                                 ├─▶ Verdict
        │                       └──Smt──▶ Solver (z3) ─▶ VerifySmt ┘
        │ ruleToFix
        ▼
 Fix ExprF ──▶ Rewrite (match, unify, normalise) ──▶ Critical (pairs, joinability)
        │
        └────▶ EGraph + UnionFind ─▶ EMatch ─▶ Saturate ─▶ Extract (cost)
                                                           │
 Cli (all commands) ◀──────────────────────────────────────┘   app/Main.hs only parses arguments
```

[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) has the module map and the
design choices behind it.

## Testing

```sh
stack test                                           # everything
stack test --test-arguments='-p "/harness/"'         # one group (tasty pattern)
stack test --test-arguments="--accept"               # regenerate golden files in test/golden/
stack test --test-arguments="--quickcheck-tests 1000" # more QuickCheck cases (default 200)
```

Tests that need `z3` are reported as `SKIPPED` when `z3` is not on `PATH`.

## Who wrote what

The owner writes lozenge to learn Haskell, with Claude (Anthropic's AI
coding assistant, through Claude Code) working in one of two modes:

- **The owner's code.** Every library function marked `error "TODO: ..."`
  in a phase's stub, from the parser and type checker (phases 1–2) through
  the verifiers, rewriting, e-graph, tensor evaluator, graph IR, fusion,
  optimiser and `grad` (phases 3–9). `docs/TODO-p*.md` lists them in order.
- **Written by Claude, in "STUB" sessions.** For each phase: the types,
  signatures, Haddock specs, the tests (unit, QuickCheck and golden), the
  compile-fail tests, and the `docs/TODO-p*.md` guides. Claude writes no
  implementation in these sessions.
- **Written by Claude, in "BUILD" sessions.** The z3 wrapper
  (`Lozenge.Solver`), the command line (`Lozenge.Cli`, `Lozenge.Json`,
  `app/Main.hs`), the greedy-vs-saturation experiment (`app/Demo.hs`), the
  C emitter and its `cc` test harness (`Lozenge.EmitC`, `test/CHarness.hs`),
  and the MLP demo (`Lozenge.Mlp`, `app/Train.hs`).

## What I learned

TODO (owner): write this section.

## Limitations

- **No division or remainder**, and no signed shift right, rotations,
  extraction or extension. Booleans have no connectives.
- **Widths are 1 to 64 bits.** Brute force also refuses more than 2^20
  assignments, which is two variables at width 10, so wider rules need z3.
- **z3 is required for SMT.** `--solver smt|both` and `critical-pairs` stop
  with an error when z3 is not on `PATH`.
- **E-matching is naive.** Patterns are matched top-down against every
  e-class, with no indexing and no relational e-matching, so saturation slows
  down quickly as the e-graph grows; node and iteration limits stop it.
- **Conditional rules are partial.** Greedy rewriting and critical pairs skip
  rules with a precondition; saturation applies them only when the variables
  are bound to literals.
- **Critical pairs** are joined along one rewriting path and checked only at
  the chosen width. An `.ir` file can't declare a Bool variable.
