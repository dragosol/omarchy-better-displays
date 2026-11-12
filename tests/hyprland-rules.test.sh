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

rm -f "$rules"
# Identical monitors without serials share one description (#1). A desc: rule
# would land on both, so they are written by connector; the unique one keeps desc:.
printf '%s' '[
 {"name":"HDMI-A-1","description":"LG Electronics 23MB35 0x01010101","serial":"0x01010101","make":"LG Electronics","model":"23MB35","width":1920,"height":1080,"refreshRate":60,"x":0,"y":0,"scale":1,"availableModes":["1920x1080@60Hz"]},
 {"name":"DP-3","description":"LG Electronics 23MB35 0x01010101","serial":"0x01010101","make":"LG Electronics","model":"23MB35","width":1920,"height":1080,"refreshRate":60,"x":1920,"y":0,"scale":1,"availableModes":["1920x1080@60Hz"]},
 {"name":"DP-2","description":"Dell Inc. DELL U2720Q 1234ABC","serial":"1234ABC","make":"Dell Inc.","model":"DELL U2720Q","width":1920,"height":1080,"refreshRate":60,"x":3840,"y":0,"scale":1,"availableModes":["1920x1080@60Hz"]}
]' > "$HYPRCTL_MONITORS"
twins='[{"name":"HDMI-A-1","width":1920,"height":1080,"refreshRate":60,"x":1920,"y":0,"scale":1,"transform":0},{"name":"DP-3","width":1920,"height":1080,"refreshRate":60,"x":0,"y":0,"scale":1,"transform":0},{"name":"DP-2","width":1920,"height":1080,"refreshRate":60,"x":3840,"y":0,"scale":1,"transform":0}]'
bash "$script" preview twins "$twins" "$twins" '{"1":"DP-3"}'
bash "$script" keep twins
grep -Fq 'hl.monitor({ output = "HDMI-A-1", disabled = false, mode = "1920x1080@60", position = "1920x0"' "$rules"
grep -Fq 'hl.monitor({ output = "DP-3", disabled = false, mode = "1920x1080@60", position = "0x0"' "$rules"
grep -Fq 'hl.monitor({ output = "desc:Dell Inc. DELL U2720Q 1234ABC", disabled = false' "$rules"
grep -Fq 'hl.workspace_rule({ workspace = "1", monitor = "DP-3", default = true, persistent = true })' "$rules"
! grep -q 'desc:LG Electronics' "$rules"

# The built-in panel kept off with only an external on (#3). Hyprland loads
# the rules plugged in or not, so the panel may only be switched off while the
# external is connected, and comes back when the external is unplugged.
printf '%s' '[
 {"name":"eDP-1","description":"LG Display 0x07C6","serial":"","make":"LG Display","model":"0x07C6","width":2880,"height":1800,"refreshRate":120,"x":0,"y":0,"scale":2,"availableModes":["2880x1800@120Hz"]},
 {"name":"DP-1","description":"LG Electronics LG TV SSCR2 0x01010101","serial":"0x01010101","make":"LG Electronics","model":"LG TV SSCR2","width":3840,"height":2160,"refreshRate":120,"x":1440,"y":0,"scale":1.6,"availableModes":["3840x2160@120Hz"]}
]' > "$HYPRCTL_MONITORS"
external_only='[{"name":"eDP-1","enabled":false},{"name":"DP-1","width":3840,"height":2160,"refreshRate":120,"x":0,"y":0,"scale":1.6,"transform":0}]'
bash "$script" preview lidopen "$external_only" "$external_only" '{}'
bash "$script" keep lidopen
grep -Fq 'local kept_on = { "DP-1" }' "$rules"
grep -Fxq '  hl.monitor({ output = "desc:LG Display 0x07C6", disabled = true })' "$rules"
# Never an unconditional disable.
! grep -q '^hl.monitor({ .*disabled = true' "$rules"

if command -v lua >/dev/null; then
  drm="$root/drm"
  cat >"$root/run-rules.lua" <<'LUA'
local rules, drm, removed = arg[1], arg[2], arg[3]
local source = assert(io.open(rules)):read("a"):gsub("/sys/class/drm", drm)
local calls, handlers = {}, {}
hl = {
  monitor = function(rule)
    calls[#calls + 1] = rule.output .. (rule.disabled and " off" or " on")
  end,
  workspace_rule = function() end,
  get_monitors = function() return {} end,
  on = function(event, fn) handlers[event] = fn end,
}
assert(load(source))()
if removed ~= "" then
  calls = {}
  handlers["monitor.removed"]({ name = removed })
end
print(table.concat(calls, ";"))
LUA
  run_rules() { lua "$root/run-rules.lua" "$rules" "$drm" "${1:-}"; }
  mkdir -p "$drm/card1-eDP-1" "$drm/card1-DP-1"
  echo connected >"$drm/card1-eDP-1/status"
  # Docked: the panel is switched off as kept.
  echo connected >"$drm/card1-DP-1/status"
  run_rules | grep -Fq 'desc:LG Display 0x07C6 off'
  # The panel's own disable fires monitor.removed for it; that changes nothing.
  test -z "$(run_rules eDP-1)"
  # Booting or reloading without the external: the panel is never switched off.
  echo disconnected >"$drm/card1-DP-1/status"
  ! run_rules | grep -q 'desc:LG Display 0x07C6 off'
  # Unplugged at runtime: the panel is switched back on.
  test "$(run_rules DP-1)" = 'desc:LG Display 0x07C6 on'
else
  echo "lua not installed: skipping the generated-rules execution check" >&2
fi

cp "$rules" "${DUMP_RULES:-/dev/null}"
echo "hyprland rules tests passed"
