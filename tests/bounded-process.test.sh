#!/bin/bash
# Runs BoundedProcess.qml in a real, windowless Quickshell instance: a normal
# exit with output, a capped output, a deadline, and a program that never
# starts (Quickshell reports no exit for it) must each finish exactly once with
# the right code. Needs `qs` and a Wayland session; skipped otherwise.
set -euo pipefail
command -v qs >/dev/null && [[ -n ${WAYLAND_DISPLAY:-} ]] || {
  echo "bounded process tests skipped: no qs or Wayland session" >&2
  exit 0
}
plugin_dir=$(cd "$(dirname "$0")/.." && pwd)
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
cp "$plugin_dir/BoundedProcess.qml" "$plugin_dir/bounded.sh" \
  "$plugin_dir/tests/fixtures/bounded-process/shell.qml" "$root/"
RESULT_FILE="$root/result.json" timeout 40 qs -p "$root/shell.qml" >"$root/qs.log" 2>&1 || {
  cat "$root/qs.log" >&2
  exit 1
}
jq -e '.normal == "3:hi" and .capped == 7 and .deadline == 124 and .nostart == 127' "$root/result.json" >/dev/null || {
  cat "$root/result.json" "$root/qs.log" >&2
  exit 1
}
echo "bounded process tests passed"
