# Learning log

## 2026-10-26 REVIEW p1 (no implementation found)
- State: working tree clean at 86f91af; validValue, eval, render, parseExpr are all still `error "TODO"` stubs.
- Tests: 181/185 fail, all from the TODO stubs; build is -Wall clean; z3 5.1.0 found.
- Next: implement docs/TODO-p1.md step 1 (validValue), save, then re-run REVIEW on the uncommitted diff.

## 2026-10-27 REVIEW p2 (no implementation found)
- State: working tree clean at 69340a5 with no other branch, stash or worktree, and open editors match disk; all 8 stubs (P1 and P2) are still `error "TODO"`.
- Tests: 316/320 fail, all from the TODO stubs; build is -Werror clean; z3 found; Haddock is 0% on every module, P2 included.
- Next: finish P1 validValue and eval (3 of the 4 P2 properties compare against eval), save the P2 work to disk, then re-run REVIEW on the uncommitted diff.

## 2026-10-28 REVIEW p3 (no implementation found)
- State: working tree clean at aed066d (not pushed); verifyBrute, renderVerdict and instantiate are still `error "TODO"`, and so are all P1/P2 stubs.
- Build: broken. src/Lozenge/Rule.hs declares `module Lozenge.Rules`, but the file and lozenge.cabal say `Lozenge.Rule`. Haddock was also removed from Rule.hs and VerifyBrute.hs, which were the P3 spec (docs/TODO-p3.md points to it) and which the CI docs job needs at 100%.
- Next: fix the module name and restore the Haddock, then implement; re-run REVIEW on the uncommitted diff.

## 2026-10-29 REVIEW p5 (no implementation found)
- State: working tree clean at 19eb903 with no other branch, stash or worktree. All 19 Phase 5 functions (Fix 3, ExprF 6, Rewrite 5, Critical 5) are still `error "TODO"`. The commits stripped every comment from the four Phase 5 modules: Haddock (the spec the TODO files point to), the `-- shortcut:` comments and the pragma justifications.
- Tests: 599/630 fail, all from the TODO stubs (ExprF 31/37, Rewrite 42/42, Critical 21/21); z3 found. `stack build --ghc-options=-Werror` fails: the committed test/Lozenge/CriticalSpec.hs is a mid-session snapshot (unused `counterexample` import, defaulted type in `genRules`), so CI's build job will fail.
- Mutation: not run, because there is no occurs check to mutate. By inspection, dropping it fails "occurs check", "occurs check through another variable" and the unify soundness property.
- Test gaps found: no lhs or generated rule has `ite` or a comparison, so a position walk that skips IteF/CmpF children passes every critical-pair test. No normalise test has two distinct terms of the same shape in a row, so a cycle check on a weaker equality could slip past.
- Next: restore the Haddock and comments, fix the two CriticalSpec warnings, then implement 5a step 1 (cata) and re-run REVIEW on the uncommitted diff.

## 2026-10-30 REVIEW p6 (no implementation found)
- State: working tree clean at 25bffd4 with no other branch or stash. All 20 Phase 6 functions (UnionFind 5, EGraph 8, EMatch 1, Extract 3, Saturate 3) are still `error "TODO"`. The 6a–6c commits stripped every comment from the five Phase 6 modules: the Haddock (the spec the TODO files point to), the representation notes and the `-- shortcut:` comments.
- Tests: 665/697 fail, all from TODO stubs (UnionFind 13/14, EGraph 21/21, Saturate 32/32; the UnionFind pass checks the model against a built-in buggy union-find, so it passes by design). `-Werror` build clean.
- Asked to check: laziness leaks, `rebuild` termination, extraction of a class that contains itself. There's no code to check yet, so these became rung-1 questions to take into the implementation.
- Test gaps found: no tasty timeout, so a looping `rebuild` or `extract` hangs the suite instead of failing it; extraction is tested on a one-class cycle but not on a cycle through two classes (merge `a` with `f(f(a))`); no test can detect a space leak (`+RTS -s` is the tool).
- Next: restore the Phase 6 Haddock, implement 6a, then run `+RTS -s` on `-p /UnionFind/` and `-p /EGraph/` and compare with a baseline taken now.

## 2026-11-03 REVIEW p7–p9 (no implementation found)
- State: working tree clean at 5ba0eb4. All 21 Phase 7–9 stub sites (Tensor 2, TensorEval 1, Graph 6, Fusion 3, TensorOpt 8, Grad 1) are still `error "TODO"`, and so is every Phase 1–6 stub.
- Tests: 920/990 fail, all from TODO stubs (evalTensor 63, fuse 48, grad 38 among them). `stack run lozenge-train` crashes at once on `TODO: evalTensor`, so it can't be timed yet.
- Mutation: not run, because there's no grad to mutate. By inspection, dropping the transpose of the adjoint fails "transpose, weighted" and the finite-difference property. The `seed` makes the root adjoint non-uniform; with an all-ones adjoint, a transposed and an untransposed flat vector are equal.
- Checked against the tests: slice/concat cover axis 0 and the last axis (2-D and 3-D). programCost pins `Cost kernels traffic`, so a node count fails. Grad sums on `a + a`, `a * a` and one name at two shapes.
- Test gaps found: (1) no fuse test or shared program has an intermediate node with one Add/Mul consumer and one non-elementwise consumer (for example `s = a + b` feeding both `s * a` and `matmul s c`), which is exactly the "consumer reads a buffer never written". (2) No optimise test fails if `optimise` skips the final `totalCost . programCost` comparison; "never more expensive" only bites if some program gets worse under the tree cost. (3) Slice/concat on axis 0 of a 3-D tensor with a non-zero start isn't tested.
- Next: implement TODO-p7 step 1 (shapeVal), then evalTensor, and re-run REVIEW on the uncommitted diff.
