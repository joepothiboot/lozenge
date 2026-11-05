# Phase 6b TODO: e-graph core

Spec: the `## Spec` entries below. Run a group with, e.g.,
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
- **`EGraph` is an empty type in the stub**, so it builds `-Wall` clean. The
  `newEGraph` Spec gives the representation: the `UF`, and `STRef`s to the hash-cons
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
  not the value itself. Why no repair would fix it is an open question.
- **`f` is `neg` and `h` is `not`** in the tests; `a`, `b`, `c` are `VarF`s.
  Two unary symbols check that the operator is part of a node.
- **The random tests have a model.** An invariant checker alone would pass an
  e-graph that never merges anything. So the property "equiv agrees with a
  naive congruence closure" replays the program on a list of blocks of terms,
  closes it under congruence by brute force, and compares every pair of added
  terms. About 1 program in 4 has a congruence the program didn't name; the
  test requires 10% (`checkCoverage`).
- `OverloadedStrings` in `EGraph`: for the `Text` literals in `checkInvariants`.
- **Invariant 1 is the converse of invariant 2:** every canonical node of a
  class is in the hash-cons, under that class. So `addNode` can always find a
  node that exists. The brief's wording is not in the repo, so this is a choice.
- **Hash-cons keys may be stale after `rebuild`, so invariant 2 canonicalises
  the key too.** A node with two children is repaired through whichever child
  changed, and the form that child's parent list holds may not be the current
  key, so an older key can stay behind. It is harmless: every lookup uses a
  canonical node, and a stale key has a child that is not a root, so no lookup
  can reach it.
- **Invariant 4 calls `parents`**, the one use outside the tests, because the
  module exports no other way to list every element.
- **A node with a repeated child is recorded as a parent twice**, once per
  child in `Foldable` order. `repair` removes the duplicate the first time it
  runs, so it costs one extra visit at most.
- **`repair` is one pass over the parents.** For each one it deletes the old key
  if canonicalising changed it, merges with whatever the hash-cons holds for the
  new key, and writes the new key. The delete is skipped for an unchanged key,
  which is rewritten straight away. No test pins that: always deleting passes
  them all, because a stale parent finds the key and merges while it is there.
- **`repair` empties the class's parent list first and adds the repaired ones
  to the current root at the end**, because a merge during the pass can move
  the class, and writing the list back would lose what the other class brought.

## 1. `newEGraph` and the representation

No test passes yet; the first ones pass after step 3.

- [ ] *Write the record and `EClass`. Should an `EClass`'s nodes be a list or
  a `Set (ExprF ClassId)`? What happens to duplicates when two classes merge
  and their nodes are canonicalised?*
- [ ] *Why is the class map keyed by `Int` in an `IntMap`, but the hash-cons a
  `Map` and not a `HashMap`? What instance does `ExprF ClassId` have that
  `Map` needs?*

## Spec: newEGraph

```haskell
type ClassId = Int
type Language f = (Traversable f, Ord (f ClassId), Show (f ClassId))
data EGraph (f :: Type -> Type) s      -- abstract
newEGraph :: ST s (EGraph f s)
```

- **Behaviour.** An empty e-graph: no classes, no nodes.
- **Representation.** The `UF s` from 6a, and `STRef`s to the hash-cons
  `Map (f ClassId) ClassId`, the class map `IntMap EClass` and the worklist.
  `EClass` (its nodes and parents) is yours to define and need not be
  exported. Class ids are union-find elements.
- **Tests.** `-p EGraph.checkInvariants`: "an empty graph has no
  violations".

## 2. `equiv`

- [ ] *Is there anything to write here beyond two calls to 6a's `find`?*

## Spec: equiv

```haskell
equiv :: (Language f) => EGraph f s -> ClassId -> ClassId -> ST s Bool
```

- **Behaviour.** Whether the two ids are in one class now: their `find`s
  are equal. Right after `merge`, before `rebuild`, the merged ids are
  already equivalent, but their parents are not yet.
- **Tests.** Used by nearly every `-p EGraph` test; first in "different
  terms are different classes".

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

## Spec: addNode

```haskell
addNode :: (Language f) => EGraph f s -> f ClassId -> ST s ClassId
```

- **Behaviour.** Canonicalise the node's children (`find` each). If the
  hash-cons already has the canonical node, return its class's root.
  Otherwise make a new class with a fresh union-find element, holding just
  this node; record it in the hash-cons and the class map, and as a parent
  in each child class.
- **Tests.** `-p "EGraph.addTerm and addNode"`: "subterms are shared:
  addNode finds (add a a) from a's id"; `-p "EGraph.merge and rebuild"`:
  "addNode canonicalises children: neg of b's old id finds f(a)'s class".

## Spec: addTerm

```haskell
addTerm :: (Language f) => EGraph f s -> Fix f -> ST s ClassId
```

- **Behaviour.** Add a term bottom-up: add each child, then `addNode` the
  layer of child ids. The same term twice gives the same id; shared
  subterms are one class.
- **Tests.** `-p "EGraph.addTerm and addNode"`: "the same term twice gives
  the same id", "different terms are different classes", "the operator is
  part of the node: neg a and not a differ".

## 4. `checkInvariants`

Tests: `-p EGraph.checkInvariants` (the first two now; the last two after
steps 5 and 6).

- [ ] *Invariant 3 asks whether one canonical node is in two classes. Can you
  check it by building a `Map` from canonical node to class and noticing a
  clash?*
- [ ] *The tests can break invariants 2 and 3 from outside (merge without
  rebuild), but not 1 or 4. How would you convince yourself your checks for 1
  and 4 can fail? (A temporary bug in `merge` is one way.)*

## Spec: checkInvariants

```haskell
checkInvariants :: (Language f) => EGraph f s -> ST s [Text]
```

- **Behaviour.** One message per violated invariant; `[]` when the graph is
  consistent. The wording is yours. Of the four invariants (see
  Decisions), the TODO records:
  - **2.** Every hash-cons entry `node -> c` agrees with the class map,
    comparing the `find` of `c`, not `c` itself (hash-cons values may be
    stale).
  - **3.** No canonical node is in two classes (congruence).
  - **4.** The class map is keyed by exactly the union-find roots.
- **When it must be empty.** On an empty graph; after any `addTerm`s; after
  `merge` of a class with itself; after every `rebuild`.
- **When it must not be.** After `merge a b` with `f(a)` and `f(b)` in the
  graph and no `rebuild`: `f(a)` and `f(b)` break congruence.
- **Tests.** `-p EGraph.checkInvariants`: "an empty graph has no
  violations", "adding terms keeps the invariants", "merge a b without
  rebuild: f(a), f(b) break congruence and are reported", "rebuild clears
  them"; `-p EGraph.random`: "checkInvariants is [] after every rebuild".

## 5. `merge`

Tests: `-p "EGraph.merge and rebuild"` (those that don't `rebuild`).

- [ ] *6a's `union` returns the new root. Which class's entry do you keep,
  which do you delete, and what goes on the worklist?*
- [ ] *Why must `merge` call `find` on both ids first, even though `union`
  already does?*

## Spec: EGraph.merge

```haskell
merge :: (Language f) => EGraph f s -> ClassId -> ClassId -> ST s ()
```

- **Behaviour.** Deferred, as in egg: `find` both ids and, if they differ,
  `union` them, combine the two classes under the new root (the class map
  stays keyed by the roots), and queue the merge on the worklist.
  Congruence is not restored here; `rebuild` does that. Merging a class
  with itself changes nothing.
- **Tests.** `-p "EGraph.merge and rebuild"`: "merge makes the two ids
  equivalent at once", "before rebuild, f(a) and f(b) are still two
  classes", "merging a class with itself changes nothing".

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

## Spec: rebuild

```haskell
rebuild :: (Language f) => EGraph f s -> ST s ()
```

- **Behaviour.** Restore congruence by repairing the classes on the
  worklist until it is empty. Repairing re-canonicalises the parent nodes
  in the hash-cons; two parents that canonicalise to the same node are
  congruent, so their classes are merged, which may queue more work.
  Afterwards `checkInvariants` is `[]`.
- **Laws.** After `rebuild`, two ids are `equiv` exactly when the closure of
  the merges under congruence puts them together: no fewer and no more.
- **Tests.** `-p "EGraph.merge and rebuild"`: "merge a b, then rebuild: f(a)
  and f(b) are equivalent", "congruence climbs: merge a b gives f(f(a)) =
  f(f(b))", "no over-merging: merge a b leaves f(a) and f(c) apart";
  `-p "EGraph.congruence closure"`: "f(f(f(a))) = a and f(f(a)) = a imply
  f(a) = a", "the same, with both merges before one rebuild";
  `-p "EGraph.random programs"`: "checkInvariants is [] after every
  rebuild", "equiv agrees with a naive congruence closure".

## 7. Afterwards

- [ ] *Count how often `rebuild` repairs a class in the textbook example
  (`f³(a) = a`, `f²(a) = a`). What would an eager e-graph, which restores
  congruence inside `merge`, have done instead, and why does egg defer?*

## Shortcuts

- **`ClassId` is a bare `Int`**, because it is a union-find element and an
  `IntMap` key. Ceiling: any `Int` type-checks as a class id, from another
  graph or none. Upgrade: not recorded (the `-- shortcut:` comment was
  removed before it was committed).

## Open questions

- Hash-cons values may be stale: the Haddock said why no repair would fix
  that, and it was removed before it was committed.
