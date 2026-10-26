# Semantics of the Phase 1 IR

Phase 1 is an **untyped** expression IR over booleans and fixed-width
bitvectors. Code: `Lozenge.Expr` (syntax), `Lozenge.Parse`, `Lozenge.Pretty`,
`Lozenge.Eval`.

## Sorts and values

| Sort   | Values                                   | Haskell                |
|--------|------------------------------------------|------------------------|
| `Bool` | true, false                              | `VBool Bool`           |
| `BV w` | integers `v` with `0 <= v < 2^w`, `1 <= w <= 64` | `VBV w v` (width, value) |

A `VBV` value is stored as its **unsigned** value. Its signed reading, used only
by `slt`, is two's complement:

    signed_w(v) = v          if v <  2^(w-1)
                = v - 2^w    if v >= 2^(w-1)

`VBV w v` outside those bounds is *ill formed* (`validValue` is false). The
parser never produces one; `eval` rejects one with `InvalidValue`, whether it
comes from a literal or from the environment.

## Concrete syntax

S-expressions. Whitespace (space, tab, newline) may appear between tokens and
around the whole input, and is required only to separate two adjacent words.

    expr   ::= ident | "true" | "false" | "(" form ")"
    form   ::= "const" nat nat
             | unop expr
             | binop expr expr
             | cmpop expr expr
             | "ite" expr expr expr
    unop   ::= "not" | "neg"
    binop  ::= "add" | "sub" | "mul" | "and" | "or" | "xor" | "shl" | "lshr"
    cmpop  ::= "=" | "ult" | "slt"
    ident  ::= [A-Za-z_][A-Za-z0-9_]*      -- except "true" and "false"
    nat    ::= [0-9]+                      -- decimal, leading zeros allowed

- `(const w v)` requires `1 <= w <= 64` and `0 <= v < 2^w`. There is no
  bare-number or hex literal syntax: a constant always states its width.
- Operator names are words: `(addx y z)` is the unknown operator `addx`.
- Operator names are special only in head position: `(add add const)` adds
  the variables `add` and `const`. Only `true` and `false` are reserved.
- The parser checks arity, not sorts: `(add true (const 16 0))` parses.
- No comments yet.

`render` prints the canonical form: `(op arg ...)` with single spaces, e.g.
`(ite (ult x y) x y)`; anything that fits in 80 columns is on one line.
Round trip: `parseExpr (render e) == Right e` for every `e` with well-formed
literals and valid identifiers.

## Operations

Let `a`, `b` be the unsigned values of the operands, `w` their common width,
and `m = 2^w`. Every bitvector result is reduced into `[0, m)`.

| Syntax       | Sort                    | Result                                  | SMT-LIB     |
|--------------|-------------------------|-----------------------------------------|-------------|
| `(add a b)`  | BV w, BV w → BV w       | `(a + b) mod m`                         | `bvadd`     |
| `(sub a b)`  | BV w, BV w → BV w       | `(a - b) mod m` (non-negative mod)      | `bvsub`     |
| `(mul a b)`  | BV w, BV w → BV w       | `(a * b) mod m`                         | `bvmul`     |
| `(and a b)`  | BV w, BV w → BV w       | bitwise and                             | `bvand`     |
| `(or a b)`   | BV w, BV w → BV w       | bitwise or                              | `bvor`      |
| `(xor a b)`  | BV w, BV w → BV w       | bitwise xor                             | `bvxor`     |
| `(shl a b)`  | BV w, BV w → BV w       | `0` if `b >= w`, else `(a * 2^b) mod m` | `bvshl`     |
| `(lshr a b)` | BV w, BV w → BV w       | `0` if `b >= w`, else `a div 2^b`       | `bvlshr`    |
| `(not a)`    | BV w → BV w             | `m - 1 - a`                             | `bvnot`     |
| `(neg a)`    | BV w → BV w             | `(m - a) mod m`                         | `bvneg`     |
| `(= a b)`    | BV w, BV w → Bool       | `a == b`                                | `=`         |
| `(ult a b)`  | BV w, BV w → Bool       | `a < b`                                 | `bvult`     |
| `(slt a b)`  | BV w, BV w → Bool       | `signed_w(a) < signed_w(b)`             | `bvslt`     |
| `(ite c t e)`| Bool, BV w, BV w → BV w | `t` if `c` else `e`                     | `ite`       |
| `(const w v)`| BV w                    | `v`                                     | `(_ bvV w)` |
| `true`/`false` | Bool                  | itself                                  | `true`/`false` |
| `x`          | whatever `env` binds    | `env(x)`                                | declared const |

**Shifts must match SMT-LIB.** SMT-LIB defines `bvshl s t` as
`bv2nat(s) * 2^bv2nat(t) mod 2^w` and `bvlshr s t` as
`bv2nat(s) div 2^bv2nat(t)`; both are 0 once `bv2nat(t) >= w`. Phase 4 checks
`eval` against Z3 on these, so the "shift amount `>= w` gives 0" rule is
mandatory. Note that the shift amount is unsigned and can be as large as
`2^64 - 1`, so an implementation must not compute `2^b` for large `b`. Both
operands of a shift have the same width, as in SMT-LIB.

Every other row is also the SMT-LIB definition (with `bvnot`/`bvneg`
written arithmetically), so Phase 4 can compare all of them.

**Bool is deliberately minimal.** `Bool` values come only from `true`, `false`,
variables and comparisons, and are consumed only by `ite`'s condition. There
are no boolean connectives, `=` on booleans is a sort error, and `ite` does not
select between booleans. Add these when a rule needs them.

## Errors and evaluation order

`eval :: Env -> Expr -> Either EvalError Value` is total: for every input it
returns, never throws and never hangs. Errors:

| Error               | When                                                        |
|---------------------|-------------------------------------------------------------|
| `UnboundVar x`      | `x` is not in the environment                               |
| `ExpectedBV`        | a `Bool` is an operand of a BV operation/comparison, or an `ite` branch |
| `ExpectedBool w`    | an `ite` condition is a `BV w`                              |
| `WidthMismatch l r` | operands (or `ite` branches) have widths `l` and `r`, `l /= r` |
| `InvalidValue v`    | a literal or environment value is ill formed                |

Order is fixed so that tests can name *the* error:

1. Evaluate every operand, left to right (for `ite`: condition, then, else).
   **Both `ite` branches are always evaluated**, so an ill-sorted term is
   rejected whatever its condition is, as a type checker would.
2. The first operand that fails decides the result.
3. Only then check the node itself: sorts of the operands left to right,
   then widths.

Example: `(add true u)` with `u` unbound is `UnboundVar "u"`, not
`ExpectedBV`, because step 1 finishes before step 3.

These errors exist because the IR is untyped. Phase 2 moves to a GADT indexed
by sort and width, and all errors except `UnboundVar` become unrepresentable.

## Out of scope for Phase 1

- **Division and remainder** (`udiv`, `urem`, `sdiv`, `srem`, …). SMT-LIB makes
  them total with specific results for a zero divisor (`bvudiv s 0` is all
  ones, `bvurem s 0` is `s`), and the signed variants need care. They are
  left out until we choose to match that exactly.
- Signed shift right, rotations, concatenation, extraction, extension.
- Boolean connectives; widths above 64; comments in the syntax.
