# Phase 8 TODO: graph IR, fusion, e-graph optimiser, C backend

Spec: the Haddock in `src/Lozenge/Graph.hs`, `src/Lozenge/Fusion.hs` and
`src/Lozenge/TensorOpt.hs`. Run a group with, e.g.,
`stack test --test-arguments='-p /Graph.shapeStep/'`. Hints are rung 1 (a
question). Ask for the next rung when you want it.

**What is yours and what is done.** STUB, yours: `Lozenge.Graph`,
`Lozenge.Fusion` and `Lozenge.TensorOpt`. BUILD, done: `Lozenge.EmitC` (the C
emitter) and the test harness (`test/CHarness.hs` and
`test/Lozenge/EmitCSpec.hs`), which compiles the C with `cc` and compares
its output with `evalTensor`.

**Prerequisites.**
- `lower` needs Phase 7's `shapeVal`.
- The C-against-interpreter properties also need Phase 7's `evalTensor`.
- `optimise` needs 6b (`EGraph`) and 6c's `extract`. It doesn't need
  `ematch` or `saturate`.

## Decisions

- **Three STUB modules and one BUILD module.** The graph IR, fusion and the
  optimiser are separate passes with separate tests. `EmitC` depends only on
  `Fusion`'s types, so it was written and tested now, against hand-built
  programs.
- **The graph is untyped (`Shape = [Int]`), unlike `Tensor s`.** Rewrites
  work on untyped nodes, as in Phase 5. `inferShapes` is what catches a rule
  that changes a shape. This is the `TExpr`/`Fix ExprF` split again.
- **Hash-consing is pure: `Graph` is a value, and `insert` returns a new
  one.** The e-graph is in `ST` because `merge` and `rebuild` mutate it. A
  graph is only ever extended, so a pure `Map (Op NodeId) NodeId` is enough.
  `Graph` is an empty type in the stub, so you choose its representation, as
  with `EGraph`.
- **Phase 6 is now generic over the node functor.** The signatures are
  `EGraph f s`, `addNode :: Language f => EGraph f s -> f ClassId -> ...`
  and `CostFn f c = f c -> c` with `Ord c`. This was the only way to use the
  Phase 6 e-graph for `Op` nodes rather than writing a second one. Only
  signatures changed, since all of Phase 6 is still TODO. `ematch` and
  `saturate` stay `ExprF`-only. For Phase 6, read `f` as `ExprF` and `c` as
  `Int`.
- **The extraction cost carries the shape (`Costed Int Shape`).** A matmul's
  traffic needs `k`, and one layer of `Op` doesn't hold it. So the cost
  algebra also infers shapes with `shapeStep`, and `IllShaped` is the
  largest cost.
- **Rules are Haskell functions, not 5b patterns.** They have to bind and
  rebuild `Int` and `Shape` fields (an axis, a reshape target), and 5b
  patterns only have variables for children. A rule sees a snapshot of the
  classes and one e-node, and returns right sides (`Rhs`) to merge with that
  e-node's class. All six rules hold for every shape, with no conditions.
- **Cost model: `kernelWeight * kernels + traffic`**, with traffic counted in
  elements read plus written. `kernelWeight = 1000` is a guess and is marked
  `-- shortcut:`.
- **Extraction minimises a tree cost, and `optimise` checks the real cost.**
  A tree cost counts a shared node once per use, and it can't see where
  fusion will cut a chain. So `optimise` fuses both the input and the
  extracted graph and keeps the cheaper one (the input on a tie). That makes
  "never worse" true by construction.
- **No backoff scheduler.** The six rules don't blow up the way assoc/comm
  do, so `optimise` uses a round limit. Phase 6's scheduler is the upgrade.
- **Fusion rule: an `Add`/`Mul` is inlined into its user only if it has
  exactly one use and that user is an `Add`/`Mul`.** Otherwise it is written
  to a buffer. A node with two uses is stored once, not computed twice.
  `Reshape` is an alias with no kernel, and it ends a chain (step 10 asks
  why that is a choice).
- **Kernel `i` writes `TmpBuf i`.** There's no output field to keep
  consistent.
- **The C checks: `emitC` validates before it emits.** Every buffer must
  exist and be written before it is read, and every size and offset must fit.
  So a bug in `fuse` comes back as a `Left`, not as an out-of-bounds read in
  C. C names are generated (`in0`, `t3`), so an input name never reaches the
  source. `cc` runs with `-Wall -Wextra -Werror`.
- **The differential test uses small integers.** Inputs are in `[-5, 5]`, so
  every value is an exact `Double`. The optimiser's reassociation
  (`x y + x y'` into `x (y + y')`) can't change the result, and the
  comparison is exact equality, with no tolerance. Each program compiles once
  (tasty `withResource`) and runs 50 times, unoptimised and optimised.
- **No `cc` on PATH means SKIPPED, not FAILED**, as with z3. `Z3.requireExe`
  is now the general form of `requireZ3`.

## 1. `emptyGraph`, `insert`, `graphNodes`

Tests: `-p '/Graph.insert and graphNodes/'`.

- [ ] *Choose the representation. Hash-consing needs "node to id". What does
  `graphNodes` need, and can one more field give it in id order without
  sorting?*
- [ ] *What does `Map.lookup` on the node give you, and what are the two
  cases of `insert`?*

## 2. `shapeStep`

Tests: `-p /Graph.shapeStep/`.

- [ ] *It's one layer: the children are already shapes. Which cases need
  more than one line, and can `splitAt ax` do the "every axis but `ax`"
  check for both `Concat` and `Slice`?*
- [ ] *Line it up with `ConcatAt` and `SliceAt` in `Tensor.hs`. Which
  equation of the type family does each `Left` match?*

## 3. `inferShapes`

Tests: `-p /Graph.inferShapes/`.

- [ ] *Walk `graphNodes` in order. Why are the children's shapes always
  ready by the time you reach a node, and what does that make the fold's
  accumulator?*
- [ ] *Turning `Op NodeId` into `Either Text (Op Shape)` with one lookup per
  child: which `Traversable` function is that? (6c asked the same question
  about extraction.)*

## 4. `lower`

Tests: `-p /Graph.lower/`, then `-p '/lower: the root/'`.

- [ ] *`lower` threads a `Graph` through a recursion. Is that `State Graph`,
  and what does each equation return?*
- [ ] *Where do the shapes for `Input` and `Reshape` come from? Why did
  `Reshape` gain a `KnownShape t` constraint in this phase?*
- [ ] *Why does hash-consing make `lower (Mul (Add a b) (Add a b))` produce
  one `Add` node, with nothing extra in `lower`?*

## 5. `fuse`

Tests: `-p /Fusion.fuse/`, then `-p '/emitC accepts/'`.

- [ ] *Three passes over the reachable nodes: reachability, use counts, then
  materialised or not. Which can share a single walk down from the root?*
- [ ] *A node's buffer depends on its children's buffers, and an inlined
  body depends on its children's bodies. In which order do you visit the
  nodes so everything you need already exists?*
- [ ] *For kernel `i` to write `TmpBuf i`, you need a map from
  materialised `NodeId` to kernel index. How do you build it before you emit
  any kernel?*
- [ ] *`emitC` refusing your program is a useful error. Which of its checks
  would catch a wrong `blockIn` in a `SliceK`?*

## 6. `programCost` and `totalCost`

Tests: `-p /Fusion.programCost/`. At this point, with Phase 7 done,
`-p '/unoptimised/'` runs your compiler against `evalTensor` through C.

- [ ] *"Distinct buffers loaded" in an elementwise body: which `Data.Set` or
  `nub` gives you that?*

## 7. `localCost`

Tests: `-p /TensorOpt.localCost/`.

- [ ] *The children arrive as `Costed` values. How do you get an `Op Shape`
  out of an `Op Costed`, failing if any child is `IllShaped`? Is that a
  `traverse` too?*
- [ ] *Why must the cost of every non-leaf node be at least 1 more than the
  sum of its children's? Which law of 6c's `extract` depends on it?*

## 8. The six rules

Tests: `-p /TensorOpt.rules/`.

- [ ] *`transposeTranspose` first. The node is `Transpose c`. Where do you
  look up `c`, and what is `[Class x | Transpose x <- nodes]` doing?*
- [ ] *For the two-child rules (`factorLeft`, `transposeAdd`), list
  comprehensions over both child classes give "every combination" for free.
  Where does the "same left operand" condition go?*
- [ ] *A missing class must give `[]`, not an error. Which `IntMap`
  function gives a default?*

## 9. `optimise`

Tests: `-p /TensorOpt.optimise/`, then `-p '/optimised/'`.

- [ ] *Copy the graph into the e-graph: each `Op NodeId` becomes an
  `Op ClassId`. Why do you need a map from `NodeId` to `ClassId`, and why is
  `fmap` with a lookup enough when you go in `graphNodes` order?*
- [ ] *Applying an `Rhs`: `Class c` is `c`, and `Node op` adds its children
  then `addNode`. That is `addTerm` with one more case. Could you write it
  as a fold?*
- [ ] *Why take a snapshot and collect every match before you apply any of
  them? (6c asked this too.)*
- [ ] *`extract` gives a `Fix Op`. How do you turn it back into a `Graph`,
  and could `lower`'s `State Graph` helper do it?*
- [ ] *The last step compares two fused programs. Why compare
  `totalCost . programCost` and not `localCost`?*

## 10. Afterwards

- [ ] *`kernelWeight` is 1000. Find a program where 10 picks a different
  result. Which of the two is right on a GPU, and which on one CPU core?*
- [ ] *Fusion treats `Reshape` as the end of a chain. Row-major order means
  `Add (Reshape (Add x y)) z` could be one kernel. What would `fuse` need to
  change, and what would `programCost` save?*
- [ ] *Recompute versus store: `Mul s s` with `s = Add x y` stores `s`.
  Inlining it twice saves a buffer but costs two adds per element. When does
  that win, and which number in the cost model would decide it?*
- [ ] *Add the rule `Slice (Concat a b) = a` (for the matching range). Why
  does it need shapes, which none of the six rules do, and where would they
  come from? (Look up "e-class analysis".)*
- [ ] *Break `factorLeft` on purpose by swapping the `Add` operands on the
  right side, so that it computes `MatMul a (Add d b)`. Which test catches it, and why
  can't the type checker? Then make it build `MatMul (Add b d) a`. What
  catches that one?*
