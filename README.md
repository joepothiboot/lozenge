# lozenge

A small expression language written in Haskell.

## Testing

```sh
stack test                                           # everything
stack test --test-arguments='-p "/harness/"'         # one group (tasty pattern)
stack test --test-arguments="--accept"               # regenerate golden files in test/golden/
stack test --test-arguments="--quickcheck-tests 1000" # more QuickCheck cases (default 200)
```

Tests that need `z3` are reported as `SKIPPED` when `z3` is not on `PATH`.
