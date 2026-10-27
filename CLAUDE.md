# CLAUDE.md

## 1. Project

lozenge: a typed bitvector expression IR; a rule language like `(add ?x 0) => ?x`; a brute-force verifier and an SMT (Z3) verifier that print counterexamples; a rewrite engine with matching, unification and critical pairs; an e-graph optimiser; a CLI. Later (not now): a tensor compiler. The owner is learning Haskell through this project, and this repo is public.

## 2. Modes

Every prompt begins with `Mode: BUILD|STUB|REVIEW|QUIZ`.

- **BUILD**: you write the code.
- **STUB**: you write ONLY types, signatures with bodies `error "TODO: <function>"`, Haddock stating intended behaviour and laws, and tests (unit, QuickCheck properties, golden). Do NOT write any implementation, not even "just a hint". The package must compile, and the new tests must fail only because of the TODOs. List the functions to implement, in the order to do them, in `docs/TODO-<phase>.md`.
- **REVIEW**: the owner wrote the implementation. Run the tests, read `git diff`, and give feedback using the hint ladder. Never rewrite the owner's code unless they type `show solution`.
- **QUIZ**: ask 5 multiple-choice questions (4 options, A–D, one correct, plausible distractors), one at a time, wait for my letter, then grade it, giving the correct answer and why each distractor is wrong. At least 3 of the 5 questions ask about purpose, design trade-offs, or alternatives rejected; the rest test the Haskell mechanics. Append questions, my answers and scores to `docs/LEARNING-LOG.md`.

Hint ladder: (1) a question, (2) a pointer to the concept or the exact GHC User's Guide / Haddock page, (3) a skeleton with holes, (4) a full solution only on `show solution`. Start at rung 1; go up only when asked.

## 3. Definition of done

- `stack build` and `stack test` pass; `-Wall` is warning-free.
- Formatted with fourmolu and hlint-clean, if installed (say so if not).
- Report test results honestly: if something fails or was skipped, say it.
- Do not commit or push; suggest a Conventional Commit message only.

## 4. Haskell conventions

- GHC2021; explicit export lists; small modules.
- `Text` for text, not `String`, except in tests.
- No partial functions (`head`, `fromJust`, `!!`) in `src/`.
- No orphan instances.
- Each extension enabled per file with a `LANGUAGE` pragma and a one-line comment on why.
- Haddock on every exported name.

## 5. Tests

- tasty with HUnit, QuickCheck and golden tests. Golden files live in `test/golden/`.
- Tests that need z3 must skip (not fail) when z3 is not on PATH, and print why.

## 6. Scope discipline

- No new dependency, extension, or module without saying why in one line.
- No abstractions for a single use. Prefer the standard library.
- Mark deliberate shortcuts with a `-- shortcut:` comment that names the ceiling and the upgrade.

## 7. Public-repo rules

No files from any private repo, no academic paper PDFs, no code copied from other projects (cite and re-derive instead), no personal paths or secrets in any file.
