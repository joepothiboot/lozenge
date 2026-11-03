# Phase 8 TODO: graph IR, fusion, e-graph optimiser, C backend

Spec: the `## Spec` entries below. Run a group with, e.g.,
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

## Spec: emptyGraph

```haskell
type Shape = [Int]
type NodeId = Int
data Op a = Input Text Shape | Add a a | Mul a a | Relu a | MatMul a a
          | Transpose a | Reshape Shape a | Concat Int a a | Slice Int Int Int a
data Graph      -- abstract; the representation is yours
emptyGraph :: Graph
```

- **Behaviour.** A graph with no nodes.
- **Tests.** `-p '/Graph.insert and graphNodes/'`: "empty".

## Spec: insert

```haskell
insert :: Op NodeId -> Graph -> (NodeId, Graph)
```

- **Behaviour.** Hash-consing. If an equal node (derived `Eq` on
  `Op NodeId`) is already in the graph, return its id and the graph
  unchanged. Otherwise add it with the next id, counting up from 0, and
  return the new graph. It does not check that the children exist.
- **Edge cases.** `Add 0 1` and `Add 1 0` are two nodes. An `Input` with the
  same name and another shape is a new node.
- **Tests.** `-p '/Graph.insert and graphNodes/'`: "ids count up from 0",
  "an equal node is found, not added", "an input is found again", "Add 0 1
  and Add 1 0 are two nodes", "same name, another shape: a new node".

## Spec: graphNodes

```haskell
graphNodes :: Graph -> [(NodeId, Op NodeId)]
```

- **Behaviour.** Every node with its id, in ascending order of id.
- **Tests.** `-p '/Graph.insert and graphNodes/'`, and every test that
  compares a graph.

## 2. `shapeStep`

Tests: `-p /Graph.shapeStep/`.

- [ ] *It's one layer: the children are already shapes. Which cases need
  more than one line, and can `splitAt ax` do the "every axis but `ax`"
  check for both `Concat` and `Slice`?*
- [ ] *Line it up with `ConcatAt` and `SliceAt` in `Tensor.hs`. Which
  equation of the type family does each `Left` match?*

## Spec: shapeStep

```haskell
shapeStep :: Op Shape -> Either Text Shape
```

- **Behaviour.** One node's shape from its children's shapes, mirroring the
  type families in `Tensor.hs`:
  - `Input _ s`: `s`, if no dimension is negative.
  - `Add a b`, `Mul a b`: `a`, if `a == b`. `Relu a`: `a`.
  - `MatMul [m, k] [k, n]`: `[m, n]`; both rank 2 and the inner dimensions
    equal.
  - `Transpose [m, n]`: `[n, m]`; rank 2 only.
  - `Reshape t s`: `t`, if no dimension of `t` is negative and
    `product t == product s`.
  - `Concat ax a b`: `a` with dimension `ax` replaced by the sum, if
    `0 <= ax < rank`, both have the same rank, and every other dimension
    agrees.
  - `Slice ax start len s`: `s` with dimension `ax` replaced by `len`, if
    `0 <= ax < rank`, `start >= 0`, `len >= 0` and `start + len` is at most
    that dimension. `len = 0` is allowed, even at `start` equal to the
    dimension.
- **Errors.** Every other case is a `Left`.
- **Tests.** `-p /Graph.shapeStep/`: 14 accepted cases, each named by the
  node, and 16 rejected ones named "<node> is ill-shaped".

## 3. `inferShapes`

Tests: `-p /Graph.inferShapes/`.

- [ ] *Walk `graphNodes` in order. Why are the children's shapes always
  ready by the time you reach a node, and what does that make the fold's
  accumulator?*
- [ ] *Turning `Op NodeId` into `Either Text (Op Shape)` with one lookup per
  child: which `Traversable` function is that? (6c asked the same question
  about extraction.)*

## Spec: inferShapes

```haskell
inferShapes :: Graph -> Either Text (IntMap Shape)
```

- **Behaviour.** The shape of every node, by id, computed in `graphNodes`
  order with `shapeStep`. `Left` if any node is ill-shaped or names a child
  that is not in the graph.
- **Tests.** `-p /Graph.inferShapes/`: "every node", "an ill-shaped node", "a
  child that isn't there".

## 4. `lower`

Tests: `-p /Graph.lower/`, then `-p '/lower: the root/'`.

- [ ] *`lower` threads a `Graph` through a recursion. Is that `State Graph`,
  and what does each equation return?*
- [ ] *Where do the shapes for `Input` and `Reshape` come from? Why did
  `Reshape` gain a `KnownShape t` constraint in this phase?*
- [ ] *Why does hash-consing make `lower (Mul (Add a b) (Add a b))` produce
  one `Add` node, with nothing extra in `lower`?*

## Spec: lower

```haskell
lower :: Tensor s -> (Graph, NodeId)
```

- **Behaviour.** The graph of a `Tensor` program and its root's id. Children
  are inserted first, left to right, then the node, through `insert`, so a
  common subexpression is one node. `Var name` becomes `Input name` at its
  shape; `Reshape` keeps its target shape; `Concat` and `Slice` keep their
  axis (and start and length) as numbers; the other constructors map to
  the `Op` of the same name.
- **Laws.** The root's inferred shape is `shapeVal` of the program.
- **Tests.** `-p /Graph.lower/`: "a", "a + a shares the input", "a + b",
  "children first, left to right", "a common subexpression is one node",
  "reshape keeps its target", "relu", "transpose", "concat keeps its axis",
  "slice keeps axis, start and length", "one name at two shapes is two
  inputs". Then `-p '/lower: the root/'`, one case per program in
  `test/TensorPrograms.hs`.

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

## Spec: fuse

```haskell
data Buf = InBuf Int | TmpBuf Int
data Ew = Load Buf | EwAdd Ew Ew | EwMul Ew Ew | EwRelu Ew
data Kernel = Elementwise Int Ew | MatMulK Buf Buf Int Int Int | TransposeK Buf Int Int
            | ConcatK Buf Buf Int Int Int | SliceK Buf Int Int Int Int
data Program = Program {progInputs :: [(Text, Int)], progKernels :: [Kernel], progOutput :: Buf}
fuse :: Graph -> NodeId -> Either Text Program
```

- **Behaviour.** Compile the nodes reachable from the root into kernels.
  Unreachable nodes are ignored.
  - **Inputs.** `progInputs` lists each reachable `Input` as `(name, number
    of elements)`; `InBuf i` is entry `i`.
  - **Fusion rule.** An `Add`, `Mul` or `Relu` is inlined into its user only
    if it has exactly one use and that user is also an `Add`, `Mul` or
    `Relu`. Otherwise it is written to a buffer. Uses count edges, so
    `Mul s s` uses `s` twice and stores it once.
  - **`Reshape`** is an alias: no kernel, the same buffer as its child. It
    ends a chain.
  - **Kernels.** Kernel `i` writes `TmpBuf i`, and every buffer is written
    before it is read. Fields:
    - `Elementwise n body`: `n` elements;
    - `MatMulK a b m k n`: `[m, k]` times `[k, n]`;
    - `TransposeK a m n`: the input is `[m, n]`;
    - `ConcatK a b blocks blockA blockB`: `blocks` is the product of the
      dimensions before the axis, and `blockA`, `blockB` are the products
      of each input's dimensions from the axis on;
    - `SliceK a blocks blockIn from count`: `blockIn` is the product of the
      input's dimensions from the axis on; `from` and `count` are the start
      and the length times the product of the dimensions after the axis.
  - **Output.** `progOutput` is the root's buffer: an `InBuf` if the root
    is an input (or a reshape of one), and with no kernels.
- **Errors.** `Left` for an ill-shaped graph or a root that isn't there.
- **Laws.** `emitC` accepts every fused program, and the C it emits computes
  what `evalTensor` does.
- **Tests.** `-p /Fusion.fuse/`: "a chain of adds and muls is one kernel",
  "relu joins a chain", "a node used twice is materialised", "an add
  feeding a matmul is materialised", "reshape is an alias: no kernel",
  "reshape breaks a chain", "unreachable nodes are ignored", "concat, slice
  and transpose fields", "concat along axis 0 is one block", "an ill-shaped
  graph", "a root that isn't there". Then `-p '/emitC accepts/'`, one case
  per program, and, with Phase 7 done and `cc` on PATH, `-p '/unoptimised/'`.

## 6. `programCost` and `totalCost`

Tests: `-p /Fusion.programCost/`. At this point, with Phase 7 done,
`-p '/unoptimised/'` runs your compiler against `evalTensor` through C.

- [ ] *"Distinct buffers loaded" in an elementwise body: which `Data.Set` or
  `nub` gives you that?*

## Spec: programCost

```haskell
data Cost = Cost {costKernels :: Int, costTraffic :: Int}
programCost :: Program -> Cost
```

- **Behaviour.** The number of kernels and the memory traffic, in elements
  read plus written, summed over the kernels:
  - `Elementwise n body`: `n` for each distinct buffer the body loads,
    plus `n` written;
  - `MatMulK _ _ m k n`: `m*k + k*n + m*n`;
  - `TransposeK _ m n`: `2*m*n`;
  - `ConcatK _ _ blocks ba bb`: `2 * blocks * (ba + bb)`;
  - `SliceK _ blocks _ _ count`: `2 * blocks * count` (only the slice is
    read).
- **Tests.** `-p /Fusion.programCost/`: "no kernels" (`Cost 0 0`),
  "elementwise counts distinct loads" (`Cost 1 18`), "add then matmul"
  (`Cost 2 34`), "concat, slice, transpose" (`Cost 3 52`).

## Spec: totalCost

```haskell
kernelWeight :: Int   -- 1000
totalCost :: Cost -> Int
```

- **Behaviour.** `kernelWeight * costKernels + costTraffic`.
- **Tests.** `-p /Fusion.programCost/`: "totalCost".

## 7. `localCost`

Tests: `-p /TensorOpt.localCost/`.

- [ ] *The children arrive as `Costed` values. How do you get an `Op Shape`
  out of an `Op Costed`, failing if any child is `IllShaped`? Is that a
  `traverse` too?*
- [ ] *Why must the cost of every non-leaf node be at least 1 more than the
  sum of its children's? Which law of 6c's `extract` depends on it?*

## Spec: localCost

```haskell
data Costed = Costed Int Shape | IllShaped     -- derived Ord: IllShaped is the largest
localCost :: CostFn Op Costed
```

- **Behaviour.** The tree cost used by extraction, with the shape carried
  along. If any child is `IllShaped`, or `shapeStep` rejects the node, the
  result is `IllShaped`. Otherwise `Costed (children + own) shape`, where
  `own` is:
  - `Input`: 0 (and no children);
  - `Add`, `Relu`, `Reshape`: 1;
  - `MatMul [m, k] [k, n]`: `kernelWeight + m*k + k*n + m*n`;
  - `Transpose [m, n]`: `kernelWeight + 2*m*n`;
  - `Concat`: `kernelWeight` plus both inputs' sizes plus the result's;
  - `Slice`: `kernelWeight + 2 * ` the result's size.
- **Laws.** Every non-leaf node costs at least 1 more than the sum of its
  children, so `extract` stays out of cycles.
- **Tests.** `-p /TensorOpt.localCost/`: "input", "add is the children plus
  1", "relu is the child plus 1", "reshape", "matmul", "transpose", "concat",
  "slice", "ill-shaped node", "ill-shaped child", "IllShaped is the most
  expensive".

## 8. The six rules

Tests: `-p /TensorOpt.rules/`.

- [ ] *`transposeTranspose` first. The node is `Transpose c`. Where do you
  look up `c`, and what is `[Class x | Transpose x <- nodes]` doing?*
- [ ] *For the two-child rules (`factorLeft`, `transposeAdd`), list
  comprehensions over both child classes give "every combination" for free.
  Where does the "same left operand" condition go?*
- [ ] *A missing class must give `[]`, not an error. Which `IntMap`
  function gives a default?*

## Spec: transposeTranspose

```haskell
data Rhs = Class ClassId | Node (Op Rhs)
type Snapshot = IntMap [Op ClassId]
data TensorRule = TensorRule {ruleName :: Text, ruleApply :: Snapshot -> Op ClassId -> [Rhs]}
transposeTranspose :: TensorRule      -- "transpose-transpose"
```

- **Behaviour.** `Transpose (Transpose x) = x`. On a node `Transpose c`,
  one `Class x` for each node `Transpose x` in class `c`, in the snapshot's
  order. On any other node, or a class missing from the snapshot, `[]`.
- **Tests.** `-p /TensorOpt.rules.transpose-transpose/`: "matches", "no inner
  transpose", "one result per matching node, in order", "a missing class
  matches nothing", "another operation".

## Spec: transposeMatMul

```haskell
transposeMatMul :: TensorRule         -- "transpose-matmul"
```

- **Behaviour.** `(a b)^T = b^T a^T`. On `Transpose c`, for each `MatMul a b`
  in class `c`: `Node (MatMul (Node (Transpose (Class b))) (Node (Transpose
  (Class a))))`.
- **Tests.** `-p /TensorOpt.rules/`: "transpose-matmul".

## Spec: transposeAdd

```haskell
transposeAdd :: TensorRule            -- "transpose-add"
```

- **Behaviour.** `a^T + b^T = (a + b)^T`. On `Add c1 c2`, for each
  `Transpose a` in `c1` and `Transpose b` in `c2`:
  `Node (Transpose (Node (Add (Class a) (Class b))))`.
- **Tests.** `-p /TensorOpt.rules.transpose-add/`: "matches", "one side isn't
  a transpose".

## Spec: factorLeft

```haskell
factorLeft :: TensorRule              -- "factor-left"
```

- **Behaviour.** `x y + x w = x (y + w)`. On `Add c1 c2`, for each
  `MatMul a b` in `c1` and `MatMul a' d` in `c2` with `a == a'`:
  `Node (MatMul (Class a) (Node (Add (Class b) (Class d))))`.
- **Tests.** `-p /TensorOpt.rules.factor-left/`: "shared left operand",
  "different left operands".

## Spec: factorRight

```haskell
factorRight :: TensorRule             -- "factor-right"
```

- **Behaviour.** `x y + x' y = (x + x') y`. On `Add c1 c2`, for each
  `MatMul a b` in `c1` and `MatMul d b'` in `c2` with `b == b'`:
  `Node (MatMul (Node (Add (Class a) (Class d))) (Class b))`.
- **Tests.** `-p /TensorOpt.rules.factor-right/`: "shared right operand",
  "different right operands".

## Spec: reshapeReshape

```haskell
reshapeReshape :: TensorRule          -- "reshape-reshape"
```

- **Behaviour.** A reshape of a reshape is one reshape. On `Reshape s c`, for
  each `Reshape _ x` in class `c`: `Node (Reshape s (Class x))`.
- **Tests.** `-p /TensorOpt.rules.reshape-reshape/`: "matches", "no inner
  reshape". `-p /TensorOpt.rules/` also checks "the rule list": the six
  names in `tensorRules` order.

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

## Spec: optimise

```haskell
optimise :: Int -> Graph -> NodeId -> (Graph, NodeId)
```

- **Behaviour.** Optimise the program at the root with the six rules on the
  Phase 6 e-graph, for at most the given number of rounds:
  1. Copy the graph into an e-graph.
  2. Each round: take a snapshot of the classes, collect every rule's
     results on every node before applying any, then add each `Rhs` and
     merge it with its node's class, and `rebuild`.
  3. `extract` the root's class with `localCost`, and turn the term back
     into a `Graph`.
  4. Fuse both the input and the extracted graph, and keep the one with the
     lower `totalCost . programCost`; on a tie, the input.
- **Edge cases.** An ill-shaped graph comes back unchanged.
- **Laws.** The result's root has the input root's shape, and its cost is
  never higher ("never worse" holds by construction, from step 4).
- **Tests.** `-p /TensorOpt.optimise/`: "transpose (transpose (x + x')): 3
  kernels to 1", "x y + x y': 3 kernels to 2", "x y + x' y: 3 kernels to 2",
  "transpose z + transpose z': 3 kernels to 2", "a tie returns the input",
  "an ill-shaped graph comes back unchanged". Then `-p '/optimise: same
  shape/'`, one case per program, and, with `cc`, `-p '/optimised/'`.

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

## Shortcuts

- **`kernelWeight = 1000` is a guess.** Ceiling: one constant prices every
  kernel launch against every element moved, on any hardware. Upgrade: not
  recorded (the `-- shortcut:` comment was removed before it was
  committed); step 10 asks how a GPU and a CPU core would differ.
- **`optimise` has no backoff scheduler**, only a round limit. Ceiling:
  fine for the six rules, which don't blow up as assoc and comm do.
  Upgrade: Phase 6's scheduler.

## Open questions

- `shapeStep`, `inferShapes`, `fuse`: the text of each `Left`.
- `inferShapes`: which error is reported when several nodes are bad.
- `fuse`: the order of `progInputs` and of independent kernels. In every
  test it is ascending node id, but no test tells that apart from the order
  a walk from the root would give.
- `localCost`: the cost of `Mul`. Only `Add` is tested; the Decisions treat
  `Add` and `Mul` alike.
- `optimise`: whether it stops early when a round changes nothing; whether
  it copies only the nodes reachable from the root.
