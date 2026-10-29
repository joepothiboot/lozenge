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
