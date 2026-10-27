# Learning log

## 2026-10-26 REVIEW p1 (no implementation found)
- State: working tree clean at 86f91af; validValue, eval, render, parseExpr are all still `error "TODO"` stubs.
- Tests: 181/185 fail, all from the TODO stubs; build is -Wall clean; z3 5.1.0 found.
- Next: implement docs/TODO-p1.md step 1 (validValue), save, then re-run REVIEW on the uncommitted diff.

## 2026-10-27 REVIEW p2 (no implementation found)
- State: working tree clean at 69340a5 with no other branch, stash or worktree, and open editors match disk; all 8 stubs (P1 and P2) are still `error "TODO"`.
- Tests: 316/320 fail, all from the TODO stubs; build is -Werror clean; z3 found; Haddock is 0% on every module, P2 included.
- Next: finish P1 validValue and eval (3 of the 4 P2 properties compare against eval), save the P2 work to disk, then re-run REVIEW on the uncommitted diff.
