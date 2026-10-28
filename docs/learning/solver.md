# Lozenge.Solver

Runs `z3 -in -smt2` on an SMT-LIB script and reads its answer. Code:
`src/Lozenge/Solver.hs`; tests: `test/Lozenge/SolverSpec.hs`.

## How this works

1. `createProcess` starts z3 and returns four values: `Maybe Handle` for stdin, stdout and stderr, plus a `ProcessHandle`. Each handle is `Just` only when its `std_*` field is `CreatePipe`. We pipe stdin and stdout; stderr is `Inherit`, so z3 shares ours.
2. A `Handle` is our end of a pipe. A `ProcessHandle` is the child process itself: we use it to signal z3 (`terminateProcess`) and to wait for it (`waitForProcess`).
3. `bracket acquire release body` runs `release` however `body` ends: by returning, by throwing, or by being interrupted by an asynchronous exception. `release` also runs with async exceptions masked, so a second interrupt can't cut the cleanup short.
4. Here acquire is `createProcess`, so once z3 has started, `release` always runs. If `createProcess` itself throws, there is no process yet, so nothing needs releasing.
5. The body writes the script, then calls `hClose` on stdin. Closing stdin is how z3 learns the input has ended: it answers and exits. Without the close, z3 would keep waiting for more commands.
6. `hGetContents` (from `Data.Text.IO`, which is strict) reads stdout until z3 closes it, which z3 does when it exits.
7. `timeout (ms * 1000)` wraps the write and the read; `System.Timeout` counts in microseconds. It returns `Just output`, or `Nothing` if the time runs out. To stop the body, it throws an asynchronous exception into it.
8. That exception unwinds the inner action. `timeout` catches it and returns `Nothing`, so the bracket body ends normally, then `release` runs.
9. `release` first calls `cleanupProcess`, which sends SIGTERM and closes all three pipes. Closing the pipes also matters on the normal path.
10. A process that has died stays in the process table as a zombie until its parent waits for it (calls `waitpid`). `cleanupProcess` does that wait only on a forked thread. So `release` then calls `waitForProcess` itself, and when `runZ3` returns, z3 is gone.
11. The timeout test checks this with `ps`, not `pgrep`, because macOS `pgrep` doesn't list zombies. Without the forked reaper, an unwaited z3 would show up there as a zombie, state `Z`.
12. A missing z3 is checked first with `findExecutable`, so the result is a `SolverError` value, not an exception. `try @IOException` also turns a failed exec or a broken pipe into a `SolverError`.
13. The version line is printed once per run. A top-level `IORef` made with `unsafePerformIO` remembers whether it has been printed, and the `NOINLINE` pragma stops GHC from making a new `IORef` at each use.
14. `atomicModifyIORef'` reads and sets that flag in one step, so two threads can't both print the version.
15. `withCreateProcess` in `System.Process` is the same `bracket` around `createProcess` with `cleanupProcess`. We write the bracket out so that `release` can add the synchronous `waitForProcess`.
