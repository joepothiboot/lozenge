# Phase 6b TODO: e-graph core

Spec: the Haddock in `src/Lozenge/EGraph.hs`. Run a group with, e.g.,
`stack test --test-arguments='-p "EGraph.addTerm and addNode"'`. Hints are
rung 1 (a question). Ask for the next rung when you want it.

**Prerequisites.** All of Phase 6a (`Lozenge.UnionFind`): class ids are its
elements. `addTerm` is shortest with 5a's `cata`, but a direct recursion works
too. The tests build terms with the `Fix` constructor, so they don't need 5a.

## Decisions

- **Generic since Phase 8.** `EGraph f s` works over any node functor with
  `Language f` (`Traversable`, `Ord`, `Show`), and `CostFn f c = f c -> c`
  takes any `Ord c`, so that Phase 8 can put tensor `Op` nodes in the same
  e-graph. In this phase, read `f` as `ExprF` and `c` as `Int`: the
  implementation is the same code.

- **Every operation takes the `EGraph s` first**, like `UF s` in 6a. The
  phase brief wrote `addTerm :: Fix ExprF -> ST s ClassId`; without the graph
  argument the graph would have to come from a `ReaderT`, which no other
  module uses.
- **`checkInvariants` returns `[Text]`, not `[String]`**, by the `Text` rule
  in CLAUDE.md. The tests only check whether the list is empty, so the wording
  is yours.
- **`newEGraph` is added**, the counterpart of `newUF`. Nothing else is.
- **`ClassId` is `Int`** (an alias), because it is a union-find element and an
  `IntMap` key. The `-- shortcut:` on it names the ceiling.
- **`EGraph` is an empty type in the stub**, so it builds `-Wall` clean. Its
  Haddock gives the representation: the `UF`, and `STRef`s to the hash-cons
  `Map (ExprF ClassId) ClassId`, the `IntMap EClass` and the worklist. `EClass`
  (nodes and parents) is yours to define, and doesn't need to be exported.
- **Rebuilding is deferred**, as in egg (Willsey et al., POPL 2021; read the
  paper's §3, don't copy egg's code). `merge` unions and queues; only
  `rebuild` restores congruence. A test pins this: after `merge a b` and before
  `rebuild`, `f(a)` and `f(b)` are still two classes, and `checkInvariants`
  reports it.
- **Four invariants, not three.** The brief's three, plus "the class map is
  keyed by exactly the roots", which the other three take for granted.
- **Hash-cons values may be stale.** Invariant 2 compares the value's `find`,
  not the value itself. The Haddock says why no repair would fix it.
- **`f` is `neg` and `h` is `not`** in the tests; `a`, `b`, `c` are `VarF`s.
  Two unary symbols check that the operator is part of a node.
- **The random tests have a model.** An invariant checker alone would pass an
  e-graph that never merges anything. So the property "equiv agrees with a
  naive congruence closure" replays the program on a list of blocks of terms,
  closes it under congruence by brute force, and compares every pair of added
  terms. About 1 program in 4 has a congruence the program didn't name; the
  test requires 10% (`checkCoverage`).

## 1. `newEGraph` and the representation

No test passes yet; the first ones pass after step 3.

- [ ] *Write the record and `EClass`. Should an `EClass`'s nodes be a list or
  a `Set (ExprF ClassId)`? What happens to duplicates when two classes merge
  and their nodes are canonicalised?*
- [ ] *Why is the class map keyed by `Int` in an `IntMap`, but the hash-cons a
  `Map` and not a `HashMap`? What instance does `ExprF ClassId` have that
  `Map` needs?*

## 2. `equiv`

- [ ] *Is there anything to write here beyond two calls to 6a's `find`?*

## 3. `addNode`, then `addTerm`

Tests: `-p "EGraph.addTerm and addNode"`.

- [ ] *"Canonicalise the children" is one traversal. Which class gives you a
  monadic `fmap` over `ExprF`, and what is its type at
  `ExprF ClassId -> ST s (ExprF ClassId)`?*
- [ ] *A fresh node needs a fresh id. Which 6a function gives one, and why
  must the new class get an entry in the class map at the same time?*
- [ ] *A node with children `[x, x]` (as in `(add a a)`) is a parent of `x`
  once or twice? Does it matter, given what `rebuild` will do with parents?*
- [ ] *For `addTerm`: `cata` takes an `ExprF r -> r`. If `r` is
  `ST s ClassId`, what does the algebra receive, and which function turns
  `ExprF (ST s ClassId)` into `ST s (ExprF ClassId)`?*

## 4. `checkInvariants`

Tests: `-p EGraph.checkInvariants` (the first two now; the last two after
steps 5 and 6).

- [ ] *Invariant 3 asks whether one canonical node is in two classes. Can you
  check it by building a `Map` from canonical node to class and noticing a
  clash?*
- [ ] *The tests can break invariants 2 and 3 from outside (merge without
  rebuild), but not 1 or 4. How would you convince yourself your checks for 1
  and 4 can fail? (A temporary bug in `merge` is one way.)*

## 5. `merge`

Tests: `-p "EGraph.merge and rebuild"` (those that don't `rebuild`).

- [ ] *6a's `union` returns the new root. Which class's entry do you keep,
  which do you delete, and what goes on the worklist?*
- [ ] *Why must `merge` call `find` on both ids first, even though `union`
  already does?*

## 6. `rebuild`

Tests: the rest of `-p EGraph`, then `-p "EGraph.random programs"`.

- [ ] *Repairing a class walks its parents. For each parent node, which
  hash-cons entry is stale and must be removed, and which must be added?*
- [ ] *Two parents canonicalise to the same node: that is a new congruence.
  Why is calling `merge` from inside the repair safe, given that `merge` only
  touches the worklist and the class map?*
- [ ] *The worklist may hold ids that a later merge made non-canonical, or the
  same class twice. What should you do with it before repairing?*
- [ ] *"Congruence climbs" needs two rounds. Trace `merge a b` with
  `f(f(a))` and `f(f(b))` in the graph: what is on the worklist after each
  round?*
- [ ] *If a random test fails, the counterexample is a shrunk program. Replay
  it by hand: which step first makes `checkInvariants` non-empty?*

## 7. Afterwards

- [ ] *Count how often `rebuild` repairs a class in the textbook example
  (`f³(a) = a`, `f²(a) = a`). What would an eager e-graph, which restores
  congruence inside `merge`, have done instead, and why does egg defer?*
