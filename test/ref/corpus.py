"""Reference verdicts for rules/bitvector.rules at widths 1-6.

Independent of the Haskell code: its own reader for the .rules syntax and its
own semantics (docs/SEMANTICS.md). It prints the same lines the golden test
test/golden/corpus-verdicts.txt should hold, and checks every rule against its
comment: "WRONG at widths ..." must list exactly the widths where the rule
fails, and a rule without one must be valid everywhere.

Run: python3 test/ref/corpus.py [--check]
"""

import re
import sys
from itertools import product

WIDTHS = range(1, 7)


def read_rules(text):
    """Yield (name, fixed_width_or_None, vars, lhs, rhs, pre, wrong_comment)."""
    comment = []
    tokens = []
    for line in text.splitlines():
        code, _, note = line.partition(";")
        if not tokens and not code.strip():
            comment = comment + [note.strip()] if note else []
            continue
        tokens += re.findall(r"[()]|[^\s()]+", code)
        depth = tokens.count("(") - tokens.count(")")
        if depth == 0 and tokens:
            yield to_rule(sexpr(tokens), " ".join(comment))
            tokens, comment = [], []


def sexpr(tokens):
    stack = [[]]
    for t in tokens:
        if t == "(":
            stack.append([])
        elif t == ")":
            done = stack.pop()
            stack[-1].append(done)
        else:
            stack[-1].append(t)
    return stack[0][0]


def to_rule(form, comment):
    assert form[0] == "rule" and form[3] == "=>", form
    name, lhs, rhs = form[1], form[2], form[4]
    pre = form[6] if len(form) > 5 and form[5] == ":if" else None
    widths = {e[1] for e in walk([lhs, rhs, pre]) if isinstance(e, list) and e[0] == "const"}
    concrete = {int(w) for w in widths if w != "w"}
    assert len(concrete) <= 1 and not (concrete and "w" in widths), name
    fixed = concrete.pop() if concrete else None
    sorts = {}
    infer(lhs, None, sorts)
    infer(rhs, None, sorts)
    infer(pre, "bool", sorts)
    wrong = re.search(r"WRONG at (.*?):", comment)
    return name, fixed, sorts, lhs, rhs, pre, wrong.group(1) if wrong else None


def walk(e):
    yield e
    if isinstance(e, list):
        for x in e:
            yield from walk(x)


def infer(e, pos, sorts):
    """The sort of a variable comes from its position: ite condition -> bool,
    any other operand -> bv; a whole lhs/rhs gives no information."""
    if isinstance(e, str):
        if e.startswith("?"):
            assert sorts.get(e, pos) == pos or pos is None or e not in sorts, e
            if pos is not None:
                sorts[e] = pos
        return
    if e is None or e[0] == "const":
        return
    if e[0] == "ite":
        infer(e[1], "bool", sorts)
        infer(e[2], "bv", sorts)
        infer(e[3], "bv", sorts)
    else:
        for a in e[1:]:
            infer(a, "bv", sorts)


def ev(e, env, w):
    if isinstance(e, str):
        return {"true": True, "false": False}.get(e, env.get(e))
    op, args = e[0], e[1:]
    m = 2**w
    if op == "const":
        return int(args[1]) % m
    v = [ev(a, env, w) for a in args]
    if op == "ite":
        return v[1] if v[0] else v[2]
    if op == "not":
        return m - 1 - v[0]
    if op == "neg":
        return (m - v[0]) % m
    a, b = v
    signed = lambda x: x - m if x >= m // 2 else x
    return {
        "add": lambda: (a + b) % m,
        "sub": lambda: (a - b) % m,
        "mul": lambda: (a * b) % m,
        "and": lambda: a & b,
        "or": lambda: a | b,
        "xor": lambda: a ^ b,
        "shl": lambda: 0 if b >= w else (a << b) % m,
        "lshr": lambda: 0 if b >= w else a >> b,
        "=": lambda: a == b,
        "ult": lambda: a < b,
        "slt": lambda: signed(a) < signed(b),
    }[op]()


def show(w, v):
    if isinstance(v, bool):
        return "true" if v else "false"
    return "0x" + format(v, "x").zfill((w + 3) // 4)


def verify(rule, w):
    _, fixed, sorts, lhs, rhs, pre, _ = rule
    w = fixed or w
    names = sorted(sorts)
    domains = [[False, True] if sorts[n] == "bool" else range(2**w) for n in names]
    for values in product(*domains):
        env = dict(zip(names, values))
        if pre is not None and not ev(pre, env, w):
            continue
        l, r = ev(lhs, env, w), ev(rhs, env, w)
        if l != r:
            ins = ", ".join(f"{n[1:]} = {show(1 if sorts[n] == 'bool' else w, env[n])}" for n in names)
            out = f"lhs = {show(w, l)}, rhs = {show(w, r)}"
            return f"{ins}: {out}" if ins else out
    return "valid"


def claimed(wrong):
    """'widths 2-6' / 'widths 1-2 and 5-6' / 'every width ...' -> set of widths."""
    if wrong is None:
        return set()
    if wrong.startswith("every width"):
        return set(WIDTHS)
    ws = set()
    for lo, hi in re.findall(r"(\d+)-(\d+)", wrong):
        ws |= set(range(int(lo), int(hi) + 1))
    return ws


rules = list(read_rules(open("rules/bitvector.rules").read()))
mismatches = []
for rule in rules:
    fails = set()
    for w in WIDTHS:
        verdict = verify(rule, w)
        if verdict != "valid":
            fails.add(w)
        if "--check" not in sys.argv:
            print(f"{rule[0]} @{w}: {verdict}")
    if fails != claimed(rule[6]):
        mismatches.append(f"{rule[0]}: comment says {sorted(claimed(rule[6]))}, actually fails at {sorted(fails)}")

print(f"{len(rules)} rules, {sum(1 for r in rules if r[6] is None)} claimed valid", file=sys.stderr)
for m in mismatches:
    print("MISMATCH " + m, file=sys.stderr)
sys.exit(1 if mismatches else 0)
