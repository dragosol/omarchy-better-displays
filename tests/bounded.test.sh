#!/bin/bash
# bounded.sh: the panel's runner for finite helpers. Overall deadline, capped
# stdout/stderr, the helper's descendants ended with it, and a runner that
# returns even when a daemon the helper left keeps its output open.
set -euo pipefail
root=$(mktemp -d)
trap 'pkill -f "bounded-test-$$" 2>/dev/null || true; rm -rf "$root"' EXIT
runner="$(dirname "$0")/../bounded.sh"
tag="bounded-test-$$"
alive() { pgrep -f "$tag-$1" >/dev/null; }

# The helper's status, stdout and stderr pass through.
out=$(bash "$runner" 5 100 100 bash -c 'echo out; echo err >&2; exit 3' 2>"$root/err") && exit 1 || status=$?
test "$status" = 3
test "$out" = out
test "$(<"$root/err")" = err

# Output past either cap is cut off.
test "$(bash "$runner" 5 10 100 bash -c 'yes | head -c 100000' | wc -c)" = 10
test "$(bash "$runner" 5 100 10 bash -c 'yes >&2' 2>&1 >/dev/null | wc -c)" = 10

# The deadline ends the helper and everything it started.
start=$(date +%s)
set +e
bash "$runner" 1 100 100 bash -c "exec -a $tag-a sleep 60 & exec -a $tag-b sleep 61"
status=$?
set -e
test "$status" = 124
test $(( $(date +%s) - start )) -le 4
sleep 0.3
! alive a && ! alive b

# Stopping the runner early ends the helper's group too.
bash "$runner" 60 100 100 bash -c "exec -a $tag-c sleep 62 & exec -a $tag-d sleep 63" &
runner_pid=$!
sleep 0.5
kill -TERM "$runner_pid"
set +e; wait "$runner_pid"; status=$?; set -e
test "$status" = 143
sleep 0.3
! alive c && ! alive d

# A daemon holding the helper's stdout does not keep the runner alive.
start=$(date +%s)
out=$(bash "$runner" 10 100 100 bash -c "(setsid bash -c 'exec -a $tag-e sleep 64' &); echo hi")
test "$out" = hi
test $(( $(date +%s) - start )) -le 5
pkill -f "$tag-e" || true

# Malformed limits are refused before anything runs.
! bash "$runner" 0 100 100 true
! bash "$runner" 5 x 100 true
! bash "$runner" 5 100 100

echo "bounded runner tests passed"
