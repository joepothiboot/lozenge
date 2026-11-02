
set -u
cd "$(dirname "$0")/.."

step() {
  printf '\n$ %s\n' "$*"
  sleep "${DEMO_PAUSE:-1}"
  "$@"
}

stack build --verbosity warn || exit 1

step stack exec -- lozenge verify rules/bitvector.rules --width 8 --solver both

step cat examples/strength.ir
step stack exec -- lozenge optimize examples/strength.ir --rules rules/bitvector.rules --engine greedy --cost shifts
step stack exec -- lozenge optimize examples/strength.ir --rules rules/bitvector.rules --engine egraph --cost shifts

step stack exec -- lozenge critical-pairs rules/bitvector.rules
