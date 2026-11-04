#!/usr/bin/env python3
"""Run `stack test`; fail unless every failing test is a `TODO:` stub error."""
import os
import re
import subprocess
import sys

FAIL = re.compile(r"^( *)(.*?):\s+FAIL\b")
STUB = re.compile(
    r"^(\*\*\* Failed! [^\n]*\n\s*)?(Exception:\s+)?TODO: [^\n]+\n"
    r"\s*CallStack \(from HasCallStack\):\n\s*error, called at src/"
)
ALL_PASSED = re.compile(r"^All (\d+) tests passed", re.M)
SOME_FAILED = re.compile(r"^(\d+) out of (\d+) tests failed", re.M)


def failures(lines):
    i = 0
    while i < len(lines):
        m = FAIL.match(lines[i])
        i += 1
        if m:
            body = []
            while i < len(lines) and (
                not lines[i].strip() or len(lines[i]) - len(lines[i].lstrip()) > len(m.group(1))
            ):
                body.append(lines[i])
                i += 1
            yield m.group(2).strip(), "\n".join(body).strip()


def report(line):
    print(line)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as f:
            f.write(line + "\n\n")


def main():
    run = subprocess.run(
        ["stack", "test", "--test-arguments=--color=never"],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        encoding="utf-8",
        errors="replace",
    )
    log = run.stdout
    print(log)

    passed, failed = ALL_PASSED.search(log), SOME_FAILED.search(log)
    if not passed and not failed:
        report(f"test gate: no tasty summary (stack exit {run.returncode}): the tests did not finish")
        return 1
    total = int(passed.group(1)) if passed else int(failed.group(2))
    expected = 0 if passed else int(failed.group(1))

    found = list(failures(log.split("\n")))
    if len(found) != expected:
        report(f"test gate: tasty reports {expected} failures but {len(found)} were parsed")
        return 1
    real = [name for name, body in found if not STUB.match(body)]
    pending = len(found) - len(real)
    skipped = len(re.findall(r":\s+SKIPPED\b", log))

    report(f"{pending} tests pending on stubs")
    report(f"{total - len(found) - skipped} of {total} tests passed, {skipped} skipped, {len(real)} real failures")
    for name in real:
        report(f"real failure: {name}")
    return 1 if real or (passed and run.returncode != 0) else 0


if __name__ == "__main__":
    sys.exit(main())
