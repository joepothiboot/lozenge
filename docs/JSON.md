# JSON output

With `--json`, each `lozenge` command prints one JSON object on one line,
followed by a newline. The schema is the types in `src/Lozenge/Json.hs`: one
Haskell type per object, with instances derived through `GHC.Generics`. Field
names drop the Haskell prefix (`vrWidth` is `width`), constructor tags are
kebab-case, and a field marked *optional* below is left out, not `null`.

Errors (an unreadable file, a parse error, z3 missing) are not JSON: they go
to stderr as text and the exit code is 2. Exit codes:

| Code | Meaning                                         |
|------|-------------------------------------------------|
| 0    | done                                            |
| 1    | `verify` only: some rule has a counterexample   |
| 2    | bad arguments, or an error as above             |

Terms (`input`, `peak`, ...) are strings in the expression syntax of
[SEMANTICS.md](SEMANTICS.md), as `render` prints them; pattern variables are
written `?x`.

## Shared objects

**Value.** A bitvector is `{"width": w, "value": n}` with `n` the unsigned
value as a JSON integer (exact; at widths above 53, a JavaScript reader loses
precision). A Bool is `true` or `false`.

**Verdict**, tagged by `"verdict"`:

| `verdict`       | Other fields                                                  |
|-----------------|---------------------------------------------------------------|
| `"valid"`       | none                                                          |
| `"invalid"`     | `assignment`: object from variable name to Value; `lhs`, `rhs`: Value |
| `"unsupported"` | `reason`: string                                              |

## `lozenge verify RULES.rules [--width N] [--solver brute|smt|both] [--json]`

```json
{"width": 6, "rules": [
  {"name": "add-zero", "brute": {"verdict": "valid"}},
  {"name": "sub-comm", "brute": {"verdict": "invalid",
    "assignment": {"x": {"width": 6, "value": 0}, "y": {"width": 6, "value": 1}},
    "lhs": {"width": 6, "value": 63}, "rhs": {"width": 6, "value": 1}}}
]}
```

| Field   | Type    | Meaning                                                     |
|---------|---------|-------------------------------------------------------------|
| `width` | integer | `--width`. A rule with concrete widths is checked at its own width, which its Values show. |
| `rules` | array   | one object per rule, in file order                          |
| `rules[].name`  | string  | the rule's name                                     |
| `rules[].brute` | Verdict, optional | present unless `--solver smt`             |
| `rules[].smt`   | Verdict, optional | present unless `--solver brute` (the default) |

## `lozenge optimize EXPR.ir --rules RULES.rules [--width N] [--cost size|shifts] [--engine greedy|egraph] [--json]`

`EXPR.ir` holds one expression. Every variable in it is `BV N`, and every
constant must have width `N`. Only the rules that verify by brute force at
width `N` are used.

```json
{"width": 8, "input": "(mul x (const 8 2))", "output": "(shl x (const 8 1))",
 "inputCost": 6, "outputCost": 3, "stop": "saturated",
 "refused": [{"rule": "sub-comm", "reason": "x = 0x00, y = 0x01: lhs = 0xff, rhs = 0x01"}]}
```

| Field        | Type    | Meaning                                                   |
|--------------|---------|-----------------------------------------------------------|
| `width`      | integer | `--width`                                                 |
| `input`      | term    | the parsed expression                                     |
| `output`     | term    | the result                                                |
| `inputCost`, `outputCost` | integer | under `--cost`, also for `--engine greedy`, which ignores the cost |
| `stop`       | string  | greedy: `"done"`, `"cycle"` or `"out-of-fuel"` (then `output` is the last term reached); egraph: `"saturated"`, `"iter-limit"` or `"node-limit"` |
| `refused`    | array   | rules not used: `{"rule", "reason"}`. The reason is the brute-force verdict, or, for greedy, that the rule has a precondition |

## `lozenge critical-pairs RULES.rules [--width N] [--json]`

Every rule is instantiated at `--width`, wrong ones included, so an unsound
rule shows up as an `"invalid"` check. Pairs whose two sides don't join are
checked with z3, so this command needs z3.

```json
{"width": 8, "pairs": [
  {"outer": "not-not", "inner": "de-morgan-and", "position": [0],
   "peak": "(not (not (and ?x_1 ?y_2)))", "left": "(and ?x_1 ?y_2)",
   "right": "(not (or (not ?x_1) (not ?y_2)))",
   "join": {"result": "not-joined", "left": "(and ?x_1 ?y_2)", "right": "(not (or (not ?x_1) (not ?y_2)))"},
   "check": {"verdict": "valid"}}
]}
```

| Field      | Type            | Meaning                                              |
|------------|-----------------|------------------------------------------------------|
| `outer`, `inner` | string    | the rule rewriting at the root, and the one rewriting at `position` |
| `position` | array of integers | child indices from the root of `peak`              |
| `peak`, `left`, `right` | term | the overlap and its two one-step reducts       |
| `join`     | object          | tagged by `"result"`: `"joined"` with `normalForm`; `"not-joined"` with the two normal forms `left`, `right`; `"unknown"` when either side has no normal form within the budget |
| `check`    | Verdict, optional | z3 on `left = right`, present unless the pair joined. `"valid"`: different terms, same meaning; `"invalid"`: a rule is unsound; `"unsupported"`: not checked |
