#!/bin/bash

# Runs one finite helper for the panel with an overall deadline and capped
# output, and ends everything it started with it.
#
#   bounded.sh SECONDS STDOUT_BYTES STDERR_BYTES COMMAND [ARG...]
#
# `timeout` leads its own process group and signals that whole group when the
# deadline passes, so programs the helper started (hyprctl, jq, edid-decode,
# ddcutil) end with it. When the shell stops this runner early, the same
# group is ended here. stdout and stderr each pass through `head -c`; a helper
# that writes past its cap gets SIGPIPE. The exit status is the helper's, or
# 124 when the deadline passed.

set -u

seconds=${1:-} out_bytes=${2:-} err_bytes=${3:-}
[[ $seconds =~ ^[1-9][0-9]{0,3}$ && $out_bytes =~ ^[1-9][0-9]{0,8}$ && $err_bytes =~ ^[1-9][0-9]{0,8}$ ]] || exit 2
shift 3
(( $# > 0 )) || exit 2

child="" out_pid="" err_pid=""

stop() {
  if [[ -n $child ]]; then
    kill -TERM -- "-$child" 2>/dev/null
    kill -TERM "$child" 2>/dev/null
  fi
}
trap 'stop; exit 143' TERM INT HUP

exec 4> >(exec stdbuf -o0 head -c "$out_bytes")
out_pid=$!
exec 5> >(exec stdbuf -o0 head -c "$err_bytes" >&2)
err_pid=$!

timeout -k 2 "$seconds" "$@" >&4 2>&5 &
child=$!
exec 4>&- 5>&-
wait "$child"
status=$?
child=""

# A helper that left a daemon holding its output (wl-copy serves the
# clipboard from a background child) must not keep this runner alive.
( sleep 2; kill "$out_pid" "$err_pid" 2>/dev/null ) &
reaper=$!
wait "$out_pid" "$err_pid" 2>/dev/null
kill "$reaper" 2>/dev/null
exit "$status"
