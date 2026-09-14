#!/bin/bash
set -euo pipefail
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
mkdir -p "$root/bin" "$root/runtime" "$root/state" "$root/config" "$root/sysfs"
chmod 700 "$root/runtime"
source "$(dirname "$0")/lib/fake-hyprctl.sh"
install_fake_hyprctl "$root/bin"
printf '%s\n' '#!/bin/bash' 'exit 0' > "$root/bin/omarchy"; chmod +x "$root/bin/omarchy"
export PATH="$root/bin:$PATH" XDG_RUNTIME_DIR="$root/runtime" XDG_STATE_HOME="$root/state" XDG_CONFIG_HOME="$root/config"
export HYPRCTL_LOG="$root/log" HYPRCTL_MONITORS="$root/monitors" MONITOR_SYSFS_ROOT="$root/sysfs" LAYOUT_WATCHDOG_DISABLED=1
script="$(dirname "$0")/../apply-layout.sh"
rules="$XDG_STATE_HOME/omarchy/toggles/hypr/displays-remembered.lua"

# One trustworthy description and one crafted to break out of a Lua string.
printf '%s' '[
 {"name":"eDP-1","description":"LG Display 0x0778","serial":"","make":"LG","model":"P","width":2880,"height":1800,"refreshRate":59.99,"x":0,"y":0,"scale":2,"availableModes":["2880x1800@59.99Hz"]},
 {"name":"DP-1","description":"Evil\" }) os.execute(\"touch /tmp/pwned\") --","serial":"S1","make":"E","model":"M","width":1920,"height":1080,"refreshRate":60,"x":1440,"y":0,"scale":1,"availableModes":["1920x1080@60Hz"]}
]' > "$HYPRCTL_MONITORS"
proposal='[{"name":"eDP-1","width":2880,"height":1800,"refreshRate":59.99,"x":0,"y":0,"scale":2,"transform":0},{"name":"DP-1","width":1920,"height":1080,"refreshRate":60,"x":1440,"y":0,"scale":1,"transform":0}]'
bash "$script" preview seed "$proposal" "$proposal" '{"4":"DP-1","5":"DP-1"}'
# Nothing is written while a change is only a preview.
test ! -e "$rules"
bash "$script" keep seed
test -f "$rules"
grep -Fq 'hl.monitor({ output = "desc:LG Display 0x0778", disabled = false, mode = "2880x1800@59.99", position = "0x0", scale = 2, transform = 0 })' "$rules"
# The unsafe description falls back to the validated connector name.
grep -Fq 'hl.monitor({ output = "DP-1", disabled = false, mode = "1920x1080@60", position = "1440x0", scale = 1, transform = 0 })' "$rules"
! grep -q 'os.execute\|pwned\|Evil' "$rules"
grep -Fq 'hl.workspace_rule({ workspace = "4", monitor = "DP-1", default = true, persistent = true })' "$rules"
grep -Fq 'hl.workspace_rule({ workspace = "5", monitor = "DP-1", default = false, persistent = true })' "$rules"
# Every generated statement is one of the two allowed shapes.
grep -v '^--' "$rules" | grep -Ev '^hl\.(monitor|workspace_rule)\(\{ .* \}\)$' && { echo "unexpected rule line" >&2; exit 1; }

# Re-syncing a settled layout must not touch the file: Hyprland watches it,
# and every replacement reloads the whole config (a reload feedback loop).
before=$(stat -c '%i %Y.%N' "$rules" 2>/dev/null || stat -c '%i %Y' "$rules")
sleep 1
RELOAD_RESTORE_SETTLE=0 bash "$script" restore-after-reload
RELOAD_RESTORE_SETTLE=0 bash "$script" restore-after-reload
bash "$script" preview seed3 "$proposal" "$proposal" '{"4":"DP-1","5":"DP-1"}'
bash "$script" keep seed3
test "$(stat -c '%i %Y.%N' "$rules" 2>/dev/null || stat -c '%i %Y' "$rules")" = "$before"
test -z "$(find "${rules%/*}" -name '.displays-remembered.*')"

# A real change still rewrites it.
changed='[{"name":"eDP-1","width":2880,"height":1800,"refreshRate":59.99,"x":0,"y":0,"scale":2,"transform":0},{"name":"DP-1","width":1920,"height":1080,"refreshRate":60,"x":1440,"y":0,"scale":1.25,"transform":0}]'
bash "$script" preview seed4 "$changed" "$proposal" '{"4":"DP-1","5":"DP-1"}'
bash "$script" keep seed4
grep -Fq 'scale = 1.25' "$rules"

# Opting out leaves an existing file alone and writes nothing new.
rm -f "$rules"
DISPLAYS_HYPRLAND_RULES=0 bash "$script" preview seed2 "$proposal" "$proposal" '{}'
DISPLAYS_HYPRLAND_RULES=0 bash "$script" keep seed2
test ! -e "$rules"

echo "hyprland rules tests passed"
