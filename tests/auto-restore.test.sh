#!/bin/bash
set -euo pipefail
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
mkdir -p "$root/bin" "$root/runtime" "$root/state" "$root/config" "$root/sysfs"
chmod 700 "$root/runtime"
source "$(dirname "$0")/lib/fake-hyprctl.sh"
install_fake_hyprctl "$root/bin"
# Capture the real Omarchy API argv without contacting the desktop bus.
printf '%s\n' '#!/bin/bash' 'printf "%s\\n" "$@" >> "$NOTIFY_LOG"' > "$root/bin/omarchy"
chmod +x "$root/bin/omarchy"
export NOTIFY_LOG="$root/notifications"
export PATH="$root/bin:$PATH" XDG_RUNTIME_DIR="$root/runtime" XDG_STATE_HOME="$root/state" XDG_CONFIG_HOME="$root/config"
export HYPRCTL_LOG="$root/log" HYPRCTL_MONITORS="$root/monitors" MONITOR_SYSFS_ROOT="$root/sysfs" LAYOUT_WATCHDOG_DISABLED=1
script="$(dirname "$0")/../apply-layout.sh"
store="$XDG_STATE_HOME/omarchy/displays/profiles.json"
live_x() { jq -r --arg name "${1:-DP-1}" '.[] | select(.name == $name) | .x' "$HYPRCTL_MONITORS"; }
generation() {
  bash -c 'source "$1/monitor-snapshot-lib.sh"; monitor_snapshot' _ "$(dirname "$script")" | jq -r .hardwareGeneration
}
observe() { bash "$script" auto-restore "$(generation)" "${1:-allow}"; }
last_undo_id() { grep -o 'auto-[0-9]*' "$NOTIFY_LOG" | tail -n 1; }

printf '%s' '[{"name":"DP-1","serial":"unique","make":"Test","model":"A","width":1920,"height":1080,"refreshRate":60,"x":0,"y":0,"scale":1,"availableModes":["1920x1080@60Hz"]}]' > "$HYPRCTL_MONITORS"
proposal='[{"name":"DP-1","width":1920,"height":1080,"refreshRate":60,"x":0,"y":0,"scale":1,"transform":0}]'
bash "$script" preview seed "$proposal" "$proposal" '{}'
bash "$script" keep seed
cp "$store" "$root/saved-store"

# A known set whose live layout drifted is restored and kept immediately:
# no preview, no Keep needed. The notification offers Undo only.
jq '.[0].x=100' "$HYPRCTL_MONITORS" > "$root/tmp"; mv "$root/tmp" "$HYPRCTL_MONITORS"
cp "$HYPRCTL_MONITORS" "$root/drifted-monitors"
gen=$(generation)
bash "$script" auto-restore "$gen" allow
test "$(live_x)" = 0
test "$(bash "$script" pending)" = '{}'
grep -Fx -- '--exec' "$NOTIFY_LOG"
grep -Fx 'restore-undo' "$NOTIFY_LOG"
grep -Fx 'Displays restored' "$NOTIFY_LOG"
cmp "$store" "$root/saved-store"
id=$(last_undo_id)

# Undo puts the previous live layout back and changes no profile.
bash "$script" restore-undo "$id"
test "$(live_x)" = 100
cmp "$store" "$root/saved-store"
# The same generation is handled once; Undo is not immediately overridden.
bash "$script" auto-restore "$gen" allow
test "$(live_x)" = 100
# A used Undo is gone.
bash "$script" restore-undo "$id"
test "$(live_x)" = 100

# Unknown identities are left alone and never create profiles.
for mutation in '.[0].serial="other"' '.[0].serial=""'; do
  jq "$mutation" "$root/drifted-monitors" > "$HYPRCTL_MONITORS"
  observe
  test "$(live_x)" = 100
  cmp "$store" "$root/saved-store"
done

# The same monitor on another connector follows its layout, and that is
# remembered as a profile for the new connector. Undo forgets it again.
jq '.[0].name="DP-2"' "$root/drifted-monitors" > "$HYPRCTL_MONITORS"
observe
test "$(live_x DP-2)" = 0
test "$(bash "$script" pending)" = '{}'
jq -e '.profiles | length == 2 and any(.[]; .connectedSet == ["DP-2"])' "$store" >/dev/null
moved_id=$(last_undo_id)
bash "$script" restore-undo "$moved_id"
test "$(live_x DP-2)" = 100
cmp "$store" "$root/saved-store"

# A blocked observation consumes its generation; it is not retried later.
cp "$root/drifted-monitors" "$HYPRCTL_MONITORS"
observe block
observe allow
test "$(live_x)" = 100

# A genuinely observed disconnect followed by the trusted set restores again.
printf '[]' > "$HYPRCTL_MONITORS"; observe
cp "$root/drifted-monitors" "$HYPRCTL_MONITORS"; observe
test "$(live_x)" = 0
new_id=$(last_undo_id)
test "$new_id" != "$id"

# A stale Undo cannot act after the displays changed since its restore.
printf '[]' > "$HYPRCTL_MONITORS"; observe
cp "$root/drifted-monitors" "$HYPRCTL_MONITORS"
jq '.[0].x=0' "$root/drifted-monitors" > "$HYPRCTL_MONITORS"
jq '.[0].serial="replaced"' "$HYPRCTL_MONITORS" > "$root/tmp"; mv "$root/tmp" "$HYPRCTL_MONITORS"
bash "$script" restore-undo "$new_id"
test "$(live_x)" = 0
cp "$root/drifted-monitors" "$HYPRCTL_MONITORS"

# Legacy connector-only exact matches are not trusted for auto restore.
printf '[]' > "$HYPRCTL_MONITORS"; observe
jq '.profiles[0].matchPolicy.identities=[]' "$root/saved-store" > "$store"
cp "$root/drifted-monitors" "$HYPRCTL_MONITORS"; observe
test "$(live_x)" = 100
cp "$root/saved-store" "$store"

# Identity can change after matching but before applying. Inject that race at
# the fake compositor boundary; no settings may be applied.
printf '[]' > "$HYPRCTL_MONITORS"; observe
cp "$root/drifted-monitors" "$HYPRCTL_MONITORS"
gen=$(generation)
mv "$root/bin/hyprctl" "$root/bin/hyprctl-real"
printf '%s\n' '#!/bin/bash' \
  'if [[ $1 == monitors ]]; then' \
  '  n=$(<"$RACE_COUNT"); n=$((n+1)); printf "%s" "$n" > "$RACE_COUNT"' \
  '  if [[ $n == 2 ]]; then jq '\''.[0].serial="replacement"'\'' "$HYPRCTL_MONITORS" > "$HYPRCTL_MONITORS.tmp"; mv "$HYPRCTL_MONITORS.tmp" "$HYPRCTL_MONITORS"; fi' \
  'fi' \
  'exec "$(dirname "$0")/hyprctl-real" "$@"' > "$root/bin/hyprctl"
chmod +x "$root/bin/hyprctl"
export RACE_COUNT="$root/race-count"
printf 0 > "$RACE_COUNT"
cp "$HYPRCTL_LOG" "$root/before-race-log"
if bash "$script" auto-restore "$gen" allow; then
  echo 'identity race was not rejected' >&2; exit 1
fi
cmp "$HYPRCTL_LOG" "$root/before-race-log"
mv "$root/bin/hyprctl-real" "$root/bin/hyprctl"
cp "$root/drifted-monitors" "$HYPRCTL_MONITORS"

# A Hyprland config reload resets outputs without a hardware change. Restoring
# after it re-arms the fence for the current set and does not notify.
jq '.[0].x=100' "$root/drifted-monitors" > "$HYPRCTL_MONITORS"
observe
jq '.[0].x=250' "$root/drifted-monitors" > "$HYPRCTL_MONITORS"
notifications_before=$(wc -l < "$NOTIFY_LOG")
bash "$script" restore-after-reload
test "$(live_x)" = 0
test "$(wc -l < "$NOTIFY_LOG")" = "$notifications_before"
cp "$root/drifted-monitors" "$HYPRCTL_MONITORS"

# Manual preview and automatic restore share the snapshot/apply lock.
set +e
( flock -x 9
  timeout 5 bash "$script" preview locked "$proposal" "$proposal" '{}'
) 9>"$XDG_RUNTIME_DIR/omarchy-displays/restore.lock"
lock_result=$?
set -e
test "$lock_result" = 124

echo 'auto restore tests passed'
