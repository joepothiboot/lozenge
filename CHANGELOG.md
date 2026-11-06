# Changelog

## 0.1.0 (unreleased)

lozenge is a Haskell workbench for bitvector rewrite rules.

Status: `Lozenge.Tensor`, `Lozenge.TensorEval`, `Lozenge.TensorOpt`,
`Lozenge.Grad`, `Lozenge.Graph`, `Lozenge.Fusion` and `Lozenge.SymExec` are
still `error "TODO"` stubs (see `docs/TODO-p*.md`). `lozenge-train` and the
tests that reach those modules cannot pass yet.

- Typed bitvector/boolean IR (widths 1 to 64, SMT-LIB semantics) with a
  parser, a pretty-printer and two evaluators.
- A rule language with width-generic rules, and a 30-rule corpus in which 8
  rules are deliberately wrong.
- Verification by brute force (up to 2^20 assignments) and with z3, with
  readable counterexamples; z3's models are re-checked.
- Matching, unification, greedy rewriting, and critical pairs checked with z3.
- Equality saturation on an e-graph with a backoff scheduler, and extraction
  by cost (`size`, `shifts`).
- A CLI with `verify`, `optimize` and `critical-pairs`, each with `--json`
  (schema in [docs/JSON.md](docs/JSON.md)).

Limitations: no division or remainder, widths up to 64, naive e-matching, and
z3 is required for SMT. This is a source release only: the binary statically
links GMP (LGPL-3).
