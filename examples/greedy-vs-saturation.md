# Greedy rewriting vs equality saturation

Greedy rewriting (Phase 5b's `normalise`) applies the first rule that matches,
commits to it, and repeats. Its result can depend on the order of the rules.
Equality saturation (Phase 6c) applies every rule to an e-graph without
discarding anything, then extracts the cheapest term, so rule order shouldn't
matter. This page looks for evidence of both on the rules in
`rules/bitvector.rules`, and measures what each costs.

## Running it

```
stack run lozenge-demo
stack run lozenge-demo -- --csv bench.csv     # also write the timings as CSV
```

The source is `app/Demo.hs`. In order, it:

1. loads the corpus and verifies it,
2. runs the search and prints the witness,
3. prints the result-size table,
4. runs the tasty-bench benchmarks.

It uses these functions:

- `parseRules`, `render`, `ruleToFix`, `size`, `normalise` and their
  prerequisites (Phases 1–5);
- all of Phase 6: `loadRules`, `saturate`, `extract`, `astSize`, and through
  them `verifyBrute`, `instantiate`, `eval`, the union-find and the e-graph.

## Method

**Rules.** The corpus is parsed and passed through `loadRules 8`. Every rule
is checked by brute force at width 8 and refused unless it is `Valid`, so the
8 deliberately wrong rules never reach either engine. The demo prints the
refused rules and why.

Rules with a precondition are then left out of both engines. `normalise`
skips them (a Phase 5b decision), so keeping them for saturation alone would
compare two different rule sets.

**Greedy.** `normalise 100` runs twice: once with the rules in corpus order,
once reversed. A term counts only if both runs reach `Done`.

**Saturation.** `saturate` runs on a fresh e-graph holding the term, with
`Limits {limIters = 10, limNodes = 10000, limMatches = 1000, limBan = 2}`.
Then `extract astSize` picks the result. It also runs in both rule orders,
to check that its result really doesn't depend on order.

**Search.** Every well-typed term of 1 to 5 nodes, in increasing size, is a
candidate. The leaves are `x`, `y`, `0`, `1` and `2` (width 8), plus `true` and
`false`. The operators are those the corpus uses: `not`, `neg`, `add`, `sub`,
`mul`, `and`, `or`, `xor`, `shl`, `lshr`, `=`, `ult`, `slt` and `ite`.
Counted by the demo's enumerator, that is 7, 10, 295, 1590 and 28080
candidates of sizes 1 to 5.

Each candidate gets one verdict:

| verdict | meaning |
|---|---|
| `NoNormalForm` | `normalise` ran out of fuel or cycled in one order |
| `SameGreedy` | both orders gave the same normal form |
| `SatDiffers` | saturation gave different terms in the two orders |
| `SatNotSmaller` | saturation is no smaller than the larger greedy result |
| `SatBeatsOne` | saturation is no larger than either greedy result and smaller than one |
| `SatBeatsBoth` | saturation is smaller than both greedy results |

The search stops at the first size that has a witness. A `SatBeatsBoth`
witness is preferred to a `SatBeatsOne`, and within a verdict the first in
enumeration order is taken.

The brief asks for "the same, smaller result" from saturation. The table above
separates the two readings of that: smaller than both greedy results
(`SatBeatsBoth`), or smaller than the worse one and no larger than the better
(`SatBeatsOne`).

If no candidate up to 5 nodes were a witness, the next step would be to add 2
valid rules to the corpus that create one, re-verify the corpus, and record
that here. That wasn't needed: the search found a witness at size 3, and no
rules were added.

**Benchmark.** 100 random bitvector terms of exactly 10, 20 and 40 nodes are
generated with a fixed seed per size, so every run uses the same 300 terms.
The leaves are `x`, `y`, `0`, `1`, `2` and `255`, under unary and binary
operators only. Each benchmark processes all 100 terms of one size:

- *greedy* is `normalise` in corpus order;
- *saturation* is a fresh e-graph, then `saturate`, then `extract astSize`.

Both results are forced by summing their `size`. `Fix ExprF` has no `NFData`
instance, and an orphan instance isn't allowed.

## Results

### Search

| size | terms | NoNormalForm | SameGreedy | SatDiffers | SatNotSmaller | SatBeatsOne | SatBeatsBoth |
|---|---|---|---|---|---|---|---|
| 1 | 7 | 0 | 7 | 0 | 0 | 0 | 0 |
| 2 | 10 | 0 | 10 | 0 | 0 | 0 | 0 |
| 3 | 295 | 0 | 284 | 0 | 0 | 11 | 0 |

The search stops at the first size with a witness, so sizes 4 and 5 did not
run. At size 3, saturation was never smaller than both greedy results.

### Witness

```
witness: (neg (neg x)) (3 nodes)
  greedy, corpus order: 
    => x (1 nodes)
  greedy, reversed: 
    => (add (not (add (not x) (const 8 1))) (const 8 1)) (7 nodes)
  saturation, corpus order: Saturated after 2 iterations, 8 nodes
    => x (1 nodes)
  saturation, reversed: Saturated after 2 iterations, 8 nodes
    => x (1 nodes)
```

This is a `SatBeatsOne` witness. Saturation matches greedy in corpus order and
beats greedy in reversed order, and it gives the same term in both rule orders.

The text after `greedy, ...:` is the first result of `normalise`: the rules it
skipped for having a precondition. It is empty because those rules were already
left out. The demo doesn't print which rules fired.

### Result sizes on the benchmark terms

`result sizes on 3 x 100 random BV terms (mean nodes; saturation: Limits {limIters = 10, limNodes = 10000, limMatches = 1000, limBan = 2})`

| size | greedy, corpus order | greedy, reversed | saturation | no greedy normal form | saturation hit a limit |
|---|---|---|---|---|---|
| 10 | 11.7 | 12.6 | 9.2 | 0 | 0 |
| 20 | 24.0 | 25.6 | 18.6 | 0 | 0 |
| 40 | 48.9 | 52.3 | 37.4 | 0 | 0 |

### Time

tasty-bench reports a mean time per benchmark and two standard deviations.
Each benchmark covers 100 terms. The last column is the ratio of the two means,
computed from this table.

| term size | greedy, 100 terms | saturation + extraction, 100 terms | saturation / greedy |
|---|---|---|---|
| 10 | 672 μs ± 29 μs | 10.8 ms ± 852 μs | 16.1x |
| 20 | 2.19 ms ± 211 μs | 24.1 ms ± 1.1 ms | 11.0x |
| 40 | 7.91 ms ± 469 μs | 56.0 ms ± 5.4 ms | 7.1x |

### Machine

| | |
|---|---|
| CPU | Apple M2, 8 cores |
| memory | 8 GB |
| OS | macOS 27.2 |
| compiler | GHC 9.10.3 (the demo prints its own compiler on its first line) |
| build | Stack 3.11.1, resolver lts-24.65, tasty-bench 0.4.1 |
| optimisation | `-O1`, Stack's default; the cabal file sets no `-O` |

## What the benchmark shows, and what it doesn't

It **shows**:

- the wall-clock time of the two pipelines, on these 300 terms, on this
  machine, with these saturation limits;
- next to the size table, what each engine bought for that time on the same
  terms.

It **does not show**:

- **Behaviour on real programs.** Random terms over two variables aren't
  compiler IR. They have far more redexes like `x xor x` than real code,
  which flatters both engines.
- **How the gap grows with size.** Three sizes give no asymptotic trend.
  Saturation's cost is bounded mostly by `limIters` and `limNodes`, not by the
  term. Change the limits and the saturation column changes with them.
- **Best-case saturation.** A run that hit a limit (counted in the size table)
  was extracted from a partial e-graph. Its result may be worse than full
  saturation would give, and its time is the limit's, not the term's.
- **Best-case greedy.** Only two rule orders were tried. Some other order may
  do better, and a good order is cheaper to find once than to saturate every
  time.
- **Precondition rules.** They were left out of both engines.
- **Correctness.** The test suite checks that (the extraction property in
  `test/Lozenge/SaturateSpec.hs`). A benchmark only times what it is given.
- **Measurement quality beyond one run.** This is one machine at `-O1`, with
  tasty-bench's defaults (no `-A32m` RTS heap setting, no CPU pinning), on a
  laptop with other processes running. Treat differences under about 2x as
  noise until they're repeated.
