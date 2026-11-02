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

## Install and run

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
