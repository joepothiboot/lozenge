# Phase 6a TODO: union-find

Spec: the Haddock in `src/Lozenge/UnionFind.hs`. Run a group with, e.g.,
`stack test --test-arguments='-p UnionFind.makeSet'`. Hints are rung 1 (a
question). Ask for the next rung when you want it.

## Decisions

- **Elements are `0, 1, 2, ...`, in `makeSet` order.** The e-graph uses them
  as dense class ids, and `parents` can be a plain list. They are bare
  `Int`s; the `-- shortcut:` on `find` names the ceiling.
- **`UF` is an empty type in the stub**, so the stub builds `-Wall` clean.
  Its Haddock gives the representation: `STRef`s to a parent `STUArray`, a
  rank `STUArray` and a count. The arrays sit behind `STRef`s because growing
  one replaces it. Keep `UF` abstract: export it without `(..)`.
- **`array` is a new library dependency**, for `STUArray` (unboxed, mutable,
  O(1)). **`QuickCheck` is a new test dependency**, because tasty-quickcheck
  does not re-export `quickCheckWithResult`, which the shrinking test needs.
- **The tie in `union` is fixed**: the first argument's root wins and its
  rank goes up. The unit tests check exact parent arrays, so this has to be
  deterministic.
- **`union` returns the new root**, not a `Bool`. The e-graph can compare two
  `find`s first if it needs to know whether anything changed.
- **`parents` is exported for tests.** It shows the tree's shape and does not
  compress. Nothing outside tests should need it.
- **The model test checks every step**: the `find` of every element against
  a list of sets, that each `find` lies in its element's set, and what each
  step returned. It only uses `find`, so it cannot see the tree's shape; the
  path-compression and rank laws read `parents` for that.
- **Shrinking is tested too.** "a known bug fails in at most 5 steps" runs the
  model test against a buggy union-find written in the test file, and checks
  that QuickCheck shrinks it to 5 steps. It passes now, before you write
  anything. If it ever fails, the shrinker broke, not your code.

## 1. `newUF` and `parents`

Tests: `-p "UnionFind.makeSet.an empty"`.

- [ ] Fill in `UF`'s fields. *What initial capacity can `newArray_` take
  without a special case? Is a capacity of 0, with bounds `(0, -1)`, easier
  or harder to double later?*
- [ ] *`parents` must stop at the count, not at the array's capacity. Which
  `Data.Array.MArray` function would read the whole array, and why is it the
  wrong one here?*

## 2. `makeSet`

Tests: `-p UnionFind.makeSet`.

- [ ] *When the count equals the capacity, what has to happen to both arrays
  before you write element `n`? Why does doubling give amortised O(1) per
  call, where growing by one would cost O(n)?*
- [ ] *After you grow the parent array, which reference still points at the
  old one? What would `find` read if you forgot `writeSTRef`?*

## 3. `find`

Tests: `-p UnionFind.find`.

- [ ] *Write `find` first without compression and run the tests. Which test
  fails, and why does the model test still pass?*
- [ ] *Compression must set every element on the path to point at the root,
  not only the argument. In a recursive `find`, at what point do you know the
  root: on the way down or on the way back up?*
- [ ] *`find` changes the parent array but not the partition. Why is that safe
  to do inside what looks like a query?*

## 4. `union`

Tests: `-p UnionFind.union`, then `-p "UnionFind.against a model"`.

- [ ] *Why must `union` link the two roots and not the two elements? Read
  `runBuggy` in the spec: what goes wrong, and on which shrunk 5-step
  program?*
- [ ] *Only a tie raises a rank. Why does linking a smaller rank under a
  larger one leave the larger root's rank unchanged?*
- [ ] *The rank law says `2 ^ depth <= size`. Why does path compression not
  break it, even though compression never lowers a rank?*

## 5. Why ST

- [ ] *The module Haddock says why `ST` and not `State`. Could the e-graph
  (6b) still expose a pure API? Which function lets it, and what stops a
  `UF s` from escaping?*
