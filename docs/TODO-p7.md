# Phase 7 TODO: shape-typed tensors

Spec: the Haddock in `src/Lozenge/Tensor.hs` and `src/Lozenge/TensorEval.hs`.
Run a group with, e.g., `stack test --test-arguments='-p /Tensor.eval.matmul/'`.
Hints are rung 1 (a question). Ask for the next rung when you want it.

**Prerequisites.** None. Phase 7 imports nothing from phases 1–6, so these
tests pass end to end as soon as you implement this phase.

## Decisions

- **Two modules.** `Lozenge.Tensor` is the sort: the shape families, the
  `Tensor` GADT and `KnownShape`. `Lozenge.TensorEval` is the evaluator. This
  is the same split as `Typed`/`EvalT`, and the compile-fail tests only need
  to compile `Tensor`.
- **A separate IR, not a `TTensor` constructor in `Ty`.** Tensor elements are
  numbers, not bitvectors. A new `Ty` constructor would also touch every
  module from Phase 2 to Phase 6.
- **The type-level half is already written.** `Product`, `ConcatAt` and
  `SliceAt` are part of the types, and a type family can't be
  `error "TODO"`: an empty family would stop every well-typed test from
  compiling. You write the value level, which is `shapeVal` and `evalTensor`.
  Step 8 asks you to read the families closely.
- **The element type is chosen at evaluation.** `Tensor s` has no element
  type, and `evalTensor :: Num a => ...` runs one program at `Integer` (so the
  laws hold exactly) and at `Double`.
- **Values are flat row-major lists**, last index fastest. This makes reshape
  free, and every other operation is index arithmetic on a flat buffer, as in
  real tensor libraries.
- **Constructors carry the dimensions the evaluator needs**, as `KnownNat` or
  `KnownShape` constraints. Matching on the constructor brings them into
  scope. `Reshape` and `Add` carry none because they don't need a shape.
- **Axis, start and length are type-level `SNat` arguments**, written
  `Concat (natSing @1) a b`. If you passed the axis only as a type
  application, it would be ambiguous: it appears only under `ConcatAt`, which
  isn't injective.
- **`transpose` is rank 2 only.** It's a shortcut. The upgrade is a
  type-level permutation `p` and `Tensor s -> Tensor (Permute p s)`, once a
  program needs rank 3 or more.
- **Custom `TypeError`s are used for concat and slice only.** Add, matmul,
  transpose and reshape keep the signatures you asked for
  (`Tensor '[m, k] -> Tensor '[k, n] -> ...`), and GHC's
  "Couldn't match type ‘4’ with ‘3’" already names the dimensions. The
  `ConcatAt`/`SliceAt` messages are static text without the shapes, because
  at the recursion depth where they fire only part of the shape is left. GHC
  prints the whole expression underneath anyway.
- **Inputs are a `Map Text [a]`, checked at each `Var`**, so `evalTensor`
  returns `Either`. There is no up-front `checkEnv` as in `EvalT`, which
  keeps it to one function.
- **Dimensions are `[Int]`**, because `take`, `splitAt` and `replicate` want
  an `Int`.

### Compile-fail tests: a GHC subprocess, not `should-not-typecheck`

Each file in `test/should-fail/` is one program with one shape error.
`TensorSpec.shouldNotCompile` runs `ghc -fno-code -isrc` on it, requires a
non-zero exit, and requires that GHC's message contains every
`-- expect: ...` line in the file. Quote characters are ignored, because GHC
prints `‘x’` in a UTF-8 locale and `'x'` otherwise.

I rejected `should-not-typecheck` (`-fdefer-type-errors`) because it passes
on *any* type error. It also defers out-of-scope names, so a typo passes too,
and it can't say which error happened. This bit me while writing these files:
the first run of 4 of the 9 programs failed on `String` vs `Text` (I had left
out `OverloadedStrings`), not on the shape. A deferred test would have
counted all 4 as passes, and the `-- expect:` check caught them. Two more
reasons: `should-not-typecheck` would be a new dependency and would need an
`NFData` instance for `Tensor`.

The costs of the subprocess approach: it needs `ghc` on PATH (`stack test`
provides it), it adds about 0.15 s per file, and it relies on the working
directory being the package root, as the golden tests already do. I checked
that it can fail: removing the `Product s ~ Product t` guard from `Reshape`,
or the bound check from `SliceAt`, fails `ReshapeProduct.hs` and
`SliceBounds.hs` with "ghc accepted a program with a shape error".

To add a case, write a new file with a `-- expect:` line copied from GHC's
output, then add its name to the list in `TensorSpec`.

## 1. `shapeVal`

Tests: `-p /Tensor.shapeVal/`.

- [ ] *In the `n ': ns` instance you have a proxy for the whole list. What
  do you pass to `natVal` for `n`, and to the recursive `shapeVal` for `ns`?
  Why are `n` and `ns` in scope in the instance body at all?*

## 2. `evalTensor`: `Var`, `Add`, `Mul`

Tests: `-p /Tensor.eval.var/` and `-p '/Tensor.eval.add and mul/'`. Leave a
temporary catch-all equation for the constructors you haven't written yet.

- [ ] *`Var name` needs its shape, so it needs a `proxy s`. Which value of
  type `Tensor s` do you already have in that equation, and how do you name
  it in the pattern?*
- [ ] *"Errors come from the leftmost failing `Var`." Which `Applicative`
  gives you that with no extra code?*
- [ ] *Which list function combines two lists pairwise, and why can you skip
  checking that they have the same length?*

## 3. `Reshape`

Tests: `-p /Tensor.eval.reshape/`.

- [ ] *Write out the flat list for a `'[2, 3]` and for the same elements
  read as `'[3, 2]`. What does that make the `Reshape` equation?*

## 4. `Transpose`

Tests: `-p /Tensor.eval.transpose/`.

- [ ] *Split the flat list into rows. How long is a row, and how do you name
  that type variable in the equation? (What can a pattern signature like
  `(a :: Tensor '[m, n])` do?)*
- [ ] *`base` has no `chunksOf`. Can you write it with `splitAt`, and what
  should it return for `[]`?*
- [ ] *Once you have rows, which `Data.List` function finishes the job?*

## 5. `MatMul`

Tests: `-p /Tensor.eval.matmul/`.

- [ ] *If `a` is a list of rows of length `k`, and `b` is turned into a list
  of columns, what is entry `(i, j)` of the product? Can step 4 give you the
  columns?*
- [ ] *Which of `m`, `k`, `n` do you actually need?*

## 6. `Concat`

Tests: `-p /Tensor.eval.concat/`.

- [ ] *How many blocks are there, and how long is one block of `a`? Write
  both in terms of `shapeVal` of `a`'s shape and the axis.*
- [ ] *Which `GHC.TypeLits` function turns the `SNat ax` into a number?*
- [ ] *You never need the result shape `ConcatAt ax s t`. Why not?*

## 7. `Slice`

Tests: `-p /Tensor.eval.slice/`, then the whole group, including `-p /Tensor.laws/`.

- [ ] *The blocks are the same as for concat. Inside a block, one index of
  axis `ax` covers how many elements? Which `take` and `drop` keep indices
  `start .. start + len - 1`?*
- [ ] *The "length 0" test slices from start 3 on an axis of size 3. Does
  `SliceAt` allow that, and does your `take`/`drop` handle it?*

## 8. Afterwards: read the type level

- [ ] *In `ConcatAt`, why does `ConcatAt 0 s t = TypeError ...` come before
  the recursive equation? What would `ConcatAt 0 '[2, 3] '[2, 5]` reduce to
  if they were swapped?*
- [ ] *`Tensor.hs` needs `UndecidableInstances`. Which equation needs it, and
  what gets smaller on every step, so that it terminates anyway?*
- [ ] *Does `f :: Tensor '[m, 3] -> Tensor '[n, 3] -> Tensor '[m + n, 3]`
  with `f = Concat (natSing @0)` compile? If not, what is missing from the
  signature?*
- [ ] *Why can't GHC prove `Product '[m, n] ~ Product '[n, m]` for an
  unknown `m` and `n`, even though it is true? What does a type-checker plugin
  such as `ghc-typelits-natnormalise` add?*
- [ ] *Add a tenth file to `test/should-fail/`, say `MatMul` of a
  `'[2, 3]` with a `'[3]`. Predict GHC's message before you run it.*
