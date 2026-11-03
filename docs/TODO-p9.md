# Phase 9 TODO: reverse-mode AD and the MLP demo

Spec: the `## Spec` entry below. Run a group with, e.g.,
`stack test --test-arguments='-p /Grad.unit/'`. Hints are rung 1 (a
question). Ask for the next rung when you want it.

**What is yours and what is done.** STUB, yours: `grad`, plus the `Relu`
case in each function you already own (`evalTensor`, `shapeStep`, `lower`,
`fuse`, `localCost`). BUILD, done: `Lozenge.Mlp` (the model, data,
initialisation, training loop, CSV and SVG), `app/Train.hs` (the
`lozenge-train` executable), and `Relu` in `EmitC`.

**Prerequisites.** `grad` needs Phase 7's `evalTensor`, because the backward
pass needs forward values. The demo needs both. The `Relu` cases in Phase 8
only matter once Phase 8 is done.

## Decisions

- **AD over `Tensor s`, not over the graph IR.** The demo trains in the
  interpreter, and `grad` is an interpreter too: it computes numbers, not a
  new program. Differentiating the graph IR instead (adding adjoint nodes to
  the `Graph`) would let gradients be fused and compiled to C. But it would
  need a constant op for the seed and for slice's zeros. Step 10 asks about it.
- **`grad` differentiates the sum of the output.** A loss is a scalar, but
  the IR has no reduction op, and "sum of every element" is the reduction
  `grad` needs anyway. A weighted sum is `Mul t (Var "w")`, which is how the
  tests get a non-uniform adjoint.
- **One new op: `Relu`.** An MLP needs a nonlinearity, and without one XOR
  can't be learned. ReLU needs only `Ord`, so `evalTensor` went from `Num a`
  to `(Ord a, Num a)` and still runs at `Integer`. `tanh` would need
  `Floating`, which drops the exact `Integer` tests. Relu goes through every
  layer: `Tensor`, `Op`, `Ew`, and `EmitC`'s `relu()` helper.
- **No `Sub`, no bias broadcasting, no constants.** The demo works around
  each one, and each shortcut is marked: targets come in negated
  (`minus y`), a bias is `MatMul ones b`, and `ones` is an input.
- **Finite differences, with a weight and a kink guard.** The QuickCheck
  property compares `grad` with `(f (e + h) - f (e - h)) / 2h` for every
  input element, on random `Double`s in `[-2, 2]`, with `h = 1e-4` and
  tolerance `1e-4 * (1 + |g|)`. Each program is multiplied by a random
  `seed` input first. With an all-ones adjoint, a transpose that forgot to
  transpose its adjoint would pass. A case is discarded when a ReLU input is
  within 0.01 of 0, because there the step can cross the kink.
- **The unit tests are exact, at `Integer`.** Each expected gradient was
  worked out by hand, and the weighted ones use distinct weights, so a
  mixed-up index changes the answer.
- **The demo's numbers were checked against numpy.** A numpy version of the
  same data, initialisation and loss, written once and not kept in the repo,
  chose the seeds and rates. `MlpSpec` checks the first draws, the first
  weights and the initial loss against it. Once your `evalTensor` passes, the
  "initial loss" tests confirm the forward pass. Once `grad` passes, "XOR:
  500 steps" confirms training.

## 1. `Relu` in the functions you already own

Tests: `-p relu` (every test with relu in its name).

- [ ] *`evalTensor` now needs `Ord a`. Which `Prelude` function is ReLU on
  one element?*
- [ ] *In `fuse`, is a `Relu` an elementwise node like `Add` and `Mul`?
  Read the test "relu joins a chain" before you decide.*

## 2. `grad`: `Var` and `Add`

Tests: `-p '/an input is all ones/'`, `-p '/add/'`.

- [ ] *Write a helper that takes a subterm and the adjoint of its output (a
  flat list), and returns a `Map Text [a]`. What is the adjoint of the root,
  given that `grad` differentiates the sum?*
- [ ] *Two subterms can read the same name. Which `Data.Map` function merges
  their maps, and what goes in its combining function?*
- [ ] *The errors must be `evalTensor`'s. What is the cheapest way to get
  exactly those?*

## Spec: grad

```haskell
grad :: (Ord a, Num a) => Inputs a -> Tensor s -> Either InputError (Map Text [a])
```

- **Behaviour.** `grad env t` is the gradient of `sum (evalTensor env t)`,
  the sum of every element of the output, with respect to every input that
  `t` reads.
  - **Keys.** One entry for each name in a `Var` of `t`, and no others. A
    name in `env` that `t` never reads has no entry.
  - **Values.** A flat row-major list, the same length as the input in
    `env`, where entry `i` is the partial derivative with respect to input
    element `i`.
  - **A name read twice.** When `t` reads one name at two places, even at
    two shapes of the same length, the two contributions are added
    elementwise, so `grad env (Mul x x)` is `2 * x`.
  - **`Relu`.** Its derivative is 1 where the input is positive and 0
    elsewhere, including at exactly 0, as in PyTorch.
  - **A weighted sum.** To get the gradient of `sum (w * t)`, which is what
    a loss needs, differentiate `Mul t (Var "w")`.
- **Errors.** `grad env t` is `Left e` exactly when `evalTensor env t` is
  `Left e`, with the same `e`.
- **Exact.** At `Integer` the result is exact, so the laws hold with `==`.
  At `Double` it agrees with central finite differences up to rounding,
  away from the kink of `Relu`.
- **Laws**, for programs `p` and `q` of the same shape:

  ```haskell
  grad env (Add p q) == Map.unionWith (zipWith (+)) <$> grad env p <*> grad env q
  grad env (Var n)   == Right (Map.singleton n (map (const 1) xs))   -- where env ! n == xs
  ```

- **Tests.** `-p /Grad.unit/`: "an input is all ones", "a + a: one entry,
  twice the gradient", "add", "mul swaps the operands", "a * a is 2a",
  "matmul", "matmul, weighted", "transpose, weighted", "reshape, weighted",
  "concat along axis 1, weighted", "concat along axis 0", "slice: zero
  outside the slice", "slice, weighted", "relu: 0 at and below 0", "relu,
  weighted", "one name at two shapes adds up", "unbound", "wrong length",
  "leftmost error wins". `-p '/Grad.laws at Integer/'`: "keys are the names
  the program reads", "each gradient has its input's length", "grad (p + q)
  = grad p + grad q", "grad (3 p) = 3 grad p", "Integer and Double agree".
  `-p '/central finite differences/'`: one property per program in
  `test/TensorPrograms.hs`, plus "MLP squared errors, n = 4, h = 3"; each
  multiplies the program by a random `seed` input, so the adjoint is not
  all ones.

## 3. `Mul` and `Relu`

Tests: `-p '/mul/'`, `-p '/relu/'`.

- [ ] *To send an adjoint into `Mul a b`'s left child, you need `b`'s value.
  Where does it come from, and what does that cost if you call it at every
  node?*
- [ ] *Relu's derivative at exactly 0 is 0 in the spec. Which comparison
  gives you that?*

## 4. `Reshape` and `Transpose`

Tests: `-p '/reshape/'`, `-p '/transpose/'`.

- [ ] *Reshape doesn't move any element in the flat list. What does it do to
  the adjoint?*
- [ ] *Transpose moves element `(i, j)` to `(j, i)`. Which way do you move
  the adjoint, and can you reuse the forward code?*

## 5. `MatMul`

Tests: `-p '/matmul/'`.

- [ ] *For `C = A B`, write `C_ik` as a sum over `j` and differentiate by
  `A_ij`. Which matrix product of the adjoint `G` and `B` (or `Bᵀ`) is
  that?*
- [ ] *Check the shapes: the adjoint of `A` must be `[m, k]`. Does that
  pick the product for you?*

## 6. `Concat` and `Slice`

Tests: `-p '/concat/'`, `-p '/slice/'`.

- [ ] *Concat's adjoint has the output's shape. Which forward operation
  cuts it back into the two inputs' pieces?*
- [ ] *Slice's adjoint is the size of the slice, but its input is bigger.
  What goes in the positions the slice didn't read? Can you write it with
  the same `outer` and block sizes as the forward slice?*

## 7. The laws and finite differences

Tests: `-p /Grad/`.

- [ ] *If a finite-difference case fails, the message names the input and
  the index. How do you turn that into a unit test at `Integer`?*

## 8. Training

Tests: `-p /Mlp/`, then `stack run lozenge-train`.

- [ ] *Run `lozenge-train` and look at `docs/demo/moons-loss.svg`. In
  the numpy run, the curve had a few spikes after step 800. Is that a bug in `grad`, or
  something gradient descent does at rate 0.1? How would you find out?*
- [ ] *Time it. Where does the time go: `evalTensor`, or `grad` calling
  `evalTensor` on every subterm?*

## 9. README

- [ ] *Commit `docs/demo/*.svg` and `*.csv`, and replace the "Pending" note
  in the README's training section with the plots and the two printed
  lines.*

## 10. Afterwards

- [ ] *Your `grad` recomputes forward values. What is its cost on a chain
  of `n` `Mul`s, and what would a tape (store each node's value once) make
  it?*
- [ ] *Differentiate the graph IR instead: `gradGraph :: Graph -> NodeId ->
  (Graph, Map Text NodeId)`, which adds adjoint nodes. Which ops would
  `Op` need, and what would `fuse` do with the backward pass?*
- [ ] *The loss is MSE on 0/1 targets. Why is cross-entropy the usual
  choice for classification, and which op is missing to write it?*
- [ ] *Replace `Relu` with `tanh`. What happens to `evalTensor`'s
  constraint, and which tests would you lose?*

## Shortcuts

These are in the BUILD code for the demo (`Lozenge.Mlp`), not in `grad`:

- **`squaredErrors`: the IR has no subtraction**, so the targets come in
  negated, as the input `minus y`. Upgrade: a `Sub` constructor in `Tensor`,
  `Graph`, `Fusion` and `EmitC`, once a second program needs one.
- **No bias broadcasting and no constants.** A bias is `MatMul ones b`, and
  `ones` is an input. Upgrade: not recorded.
- **`uniforms`: an LCG** is fine for initial weights and toy data, not for
  statistics. Upgrade: the `random` package.
- **`train`: plain gradient descent at a fixed rate.** Upgrade: momentum or
  Adam, which need per-parameter state carried next to `Params`.

## Open questions

None. The tests and the Phase 9 Haddock that survived in git history pin
every case.
