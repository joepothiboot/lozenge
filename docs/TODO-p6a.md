# Phase 6a TODO: union-find

Spec: the `## Spec` entries below. Run a group with, e.g.,
`stack test --test-arguments='-p UnionFind.makeSet'`. Hints are rung 1 (a
question). Ask for the next rung when you want it.

## Decisions

- **Elements are `0, 1, 2, ...`, in `makeSet` order.** The e-graph uses them
  as dense class ids, and `parents` can be a plain list. They are bare
  `Int`s; the `-- shortcut:` on `find` names the ceiling.
- **`UF` is an empty type in the stub**, so the stub builds `-Wall` clean.
  The `newUF` Spec gives the representation: `STRef`s to a parent `STUArray`, a
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

## Spec: newUF

```haskell
data UF s      -- abstract: exported without (..)
newUF :: ST s (UF s)
```

- **Behaviour.** An empty union-find: no elements.
- **Representation.** `STRef`s to a parent `STUArray`, a rank `STUArray`
  and a count. The arrays sit behind `STRef`s because growing one replaces
  it.
- **Tests.** `-p "UnionFind.makeSet.an empty"`: "an empty structure has no
  elements".

## Spec: parents

```haskell
parents :: UF s -> ST s [Int]
```

- **Behaviour.** The parent of each element `0 .. count - 1`, in order. It
  reads up to the count, not the array's capacity, and does not compress.
  For tests only.
- **Tests.** `-p UnionFind.parents`: "after two unions of pairs and a union
  of the pairs" (`[0, 0, 0, 2]`), and every test that checks a tree's
  shape.

## 2. `makeSet`

Tests: `-p UnionFind.makeSet`.

- [ ] *When the count equals the capacity, what has to happen to both arrays
  before you write element `n`? Why does doubling give amortised O(1) per
  call, where growing by one would cost O(n)?*
- [ ] *After you grow the parent array, which reference still points at the
  old one? What would `find` read if you forgot `writeSTRef`?*

## Spec: makeSet

```haskell
makeSet :: UF s -> ST s Int
```

- **Behaviour.** Add a new singleton and return its number. Elements are
  numbered `0, 1, 2, ...` in `makeSet` order. A new element is its own
  parent, with rank 0. When the arrays are full, both double, so a call is
  amortised O(1).
- **Tests.** `-p UnionFind.makeSet`: "numbers elements 0, 1, 2 and makes
  each its own parent", "grows past any initial capacity" (1000 elements).

## 3. `find`

Tests: `-p UnionFind.find`.

- [ ] *Write `find` first without compression and run the tests. Which test
  fails, and why does the model test still pass?*
- [ ] *Compression must set every element on the path to point at the root,
  not only the argument. In a recursive `find`, at what point do you know the
  root: on the way down or on the way back up?*
- [ ] *`find` changes the parent array but not the partition. Why is that safe
  to do inside what looks like a query?*

## Spec: find

```haskell
find :: UF s -> Int -> ST s Int
```

- **Behaviour.** The root of the element's set. With full path compression:
  afterwards every element on the path from the argument to the root points
  directly at the root, and no other parent changes. The partition does not
  change.
- **Tests.** `-p UnionFind.find`: "a singleton is its own root", "compresses
  the whole path, and only it" (`(0, [0, 0, 0, 0, 4])`), property "after
  find, every element on the old path has depth <= 1" (which also checks
  that roots and the other parents are unchanged).

## 4. `union`

Tests: `-p UnionFind.union`, then `-p "UnionFind.against a model"`.

- [ ] *Why must `union` link the two roots and not the two elements? Read
  `runBuggy` in the spec: what goes wrong, and on which shrunk 5-step
  program?*
- [ ] *Only a tie raises a rank. Why does linking a smaller rank under a
  larger one leave the larger root's rank unchanged?*
- [ ] *The rank law says `2 ^ depth <= size`. Why does path compression not
  break it, even though compression never lowers a rank?*

## Spec: union

```haskell
union :: UF s -> Int -> Int -> ST s Int
```

- **Behaviour.** Join the two elements' sets and return the new root.
  Union by rank on the two roots (not the two elements): the root of
  smaller rank goes under the other, whose rank is unchanged. On a tie, the
  first argument's root wins and its rank goes up by one. If both are
  already in one set, return its root and change nothing.
- **Laws.** Union by rank: `2 ^ depth <= ` the size of the element's set,
  for every element.
- **Tests.** `-p UnionFind.union`: "a tie: the first argument's root wins",
  "a tie the other way round", "the smaller rank goes under the larger,
  whatever the order", "already in one set: returns the root, changes
  nothing", property "union by rank: 2 ^ depth <= the size of the element's
  set". Then `-p "UnionFind.against a model"`: "find agrees with a list of
  sets after every step" (each step's result too: `makeSet` returns the new
  element, `union a b` and `find a` return `a`'s root after the step), and
  "shrinking: a known bug fails in at most 5 steps", which passes already.

## 5. Why ST

- [ ] *Why is `UF` in `ST` and not `State`? Could the e-graph
  (6b) still expose a pure API? Which function lets it, and what stops a
  `UF s` from escaping?*

## Shortcuts

- **`find`: elements are bare `Int`s.** Ceiling: nothing stops a caller
  passing an `Int` that is not an element of this union-find. Upgrade: not
  recorded (the `-- shortcut:` comment was removed before it was
  committed).

## Open questions

- `find`, `union`: what an element outside `0 .. count - 1` does. No test
  passes one.
- Why `ST` and not `State`: the module Haddock gave the reason, and it was
  removed before it was committed.
