"""Reference brute-force verifier for the Phase 3 hand-picked rules.

Independent of the Haskell code: it re-derives the semantics from
docs/SEMANTICS.md and prints one line per test case, in the same format as
renderVerdict. The expected strings in test/Lozenge/VerifyBruteSpec.hs were
copied from this output. Run: python3 test/ref/brute.py
"""

from itertools import product

CAP = 2**20


def add(w, a, b): return (a + b) % 2**w
def sub(w, a, b): return (a - b) % 2**w
def mul(w, a, b): return (a * b) % 2**w
def shl(w, a, b): return 0 if b >= w else (a << b) % 2**w
def lshr(w, a, b): return 0 if b >= w else a >> b
def bnot(w, a): return 2**w - 1 - a
def band(w, a, b): return a & b
def bor(w, a, b): return a | b
def signed(w, a): return a - 2**w if a >= 2**(w - 1) else a
def ult(w, a, b): return a < b
def slt(w, a, b): return signed(w, a) < signed(w, b)


def show(w, v):
    if isinstance(v, bool):
        return "true" if v else "false"
    return "0x" + format(v, "x").zfill((w + 3) // 4)


def verify(vars_, w, lhs, rhs, pre=None):
    """vars_: list of (name, width or "bool"); lhs/rhs/pre: env -> value."""
    names = sorted(n for n, _ in vars_)
    sorts = dict(vars_)
    domains = [[False, True] if sorts[n] == "bool" else range(2**sorts[n]) for n in names]
    count = 1
    for d in domains:
        count *= len(d)
    if count > CAP:
        return "unsupported"
    for values in product(*domains):
        env = dict(zip(names, values))
        if pre is not None and not pre(env):
            continue
        l, r = lhs(env), rhs(env)
        if l != r:
            ins = ", ".join(f"{n} = {show(sorts[n], env[n])}" for n in names)
            out = f"lhs = {show(w, l)}, rhs = {show(w, r)}"
            return f"{ins}: {out}" if ins else out
    return "valid"


def bv8(*names): return [(n, 8) for n in names]


cases = [
    # valid
    ("add-zero @8", verify(bv8("x"), 8, lambda e: add(8, e["x"], 0), lambda e: e["x"])),
    ("add-comm @8", verify(bv8("x", "y"), 8, lambda e: add(8, e["x"], e["y"]), lambda e: add(8, e["y"], e["x"]))),
    ("shl-1-to-add @8", verify(bv8("x"), 8, lambda e: shl(8, e["x"], 1), lambda e: add(8, e["x"], e["x"]))),
    *[(f"de-morgan @{w}", verify([("x", w), ("y", w)], w,
                                 lambda e, w=w: bnot(w, band(w, e["x"], e["y"])),
                                 lambda e, w=w: bor(w, bnot(w, e["x"]), bnot(w, e["y"]))))
      for w in (4, 8)],
    ("ult-self @8", verify(bv8("x"), 8, lambda e: ult(8, e["x"], e["x"]), lambda e: False)),
    ("ite-same @8", verify([("p", "bool"), ("x", 8)], 8, lambda e: e["x"] if e["p"] else e["x"], lambda e: e["x"])),
    # invalid
    ("sub-comm @8", verify(bv8("x", "y"), 8, lambda e: sub(8, e["x"], e["y"]), lambda e: sub(8, e["y"], e["x"]))),
    ("shl-1-to-mul-self @8", verify(bv8("x"), 8, lambda e: shl(8, e["x"], 1), lambda e: mul(8, e["x"], e["x"]))),
    ("ult-to-slt @8", verify(bv8("x", "y"), 8, lambda e: ult(8, e["x"], e["y"]), lambda e: slt(8, e["x"], e["y"]))),
    ("ite-swap @8", verify([("p", "bool"), ("x", 8), ("y", 8)], 8,
                           lambda e: e["x"] if e["p"] else e["y"], lambda e: e["y"] if e["p"] else e["x"])),
    # precondition
    ("shl-lshr :if ult x 128 @8", verify(bv8("x"), 8, lambda e: lshr(8, shl(8, e["x"], 1), 1), lambda e: e["x"],
                                         pre=lambda e: ult(8, e["x"], 128))),
    ("shl-lshr no precondition @8", verify(bv8("x"), 8, lambda e: lshr(8, shl(8, e["x"], 1), 1), lambda e: e["x"])),
    # width-dependent: generic (shl x 4) => 0
    *[(f"shl-4-zero @{w}", verify([("x", w)], w, lambda e, w=w: shl(w, e["x"], 4), lambda e: 0)) for w in (4, 8)],
    # the cap: 2^20 assignments is allowed, 2^22 is not
    ("add-comm generic @10", verify([("x", 10), ("y", 10)], 10,
                                    lambda e: add(10, e["x"], e["y"]), lambda e: add(10, e["y"], e["x"]))),
    ("three vars @8", verify(bv8("x", "y", "z"), 8, lambda e: 0, lambda e: 0)),
]

for name, verdict in cases:
    print(f"{name}: {verdict}")
