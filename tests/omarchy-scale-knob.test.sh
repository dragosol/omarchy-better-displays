#!/bin/bash
# sync_omarchy_scale_knob keeps Omarchy's omarchy_monitor_scale knob in step with
# the internal panel's kept scale, so omarchy-hyprland-monitor-clamshell stops
# resetting it on idle-wake. It must never touch a hand-written monitors.lua.
set -euo pipefail
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
mkdir -p "$root/bin" "$root/config/hypr"
export PATH="$root/bin:$PATH" XDG_CONFIG_HOME="$root/config"
lua="$XDG_CONFIG_HOME/hypr/monitors.lua"

# Load only the function under test; the script itself is not sourceable.
source <(awk '/^sync_omarchy_scale_knob\(\) \{/,/^\}/' "$(dirname "$0")/../apply-layout.sh")

internal() { printf '%s\n' '#!/bin/bash' "echo '$1'" > "$root/bin/omarchy-hyprland-monitor-laptop"; chmod +x "$root/bin/omarchy-hyprland-monitor-laptop"; }
stock() {
  printf '%s\n' \
    'local omarchy_gdk_scale = 2' \
    'local omarchy_monitor_scale = 2' \
    'hl.monitor({ output = "", mode = "preferred", position = "auto", scale = omarchy_monitor_scale })' > "$lua"
}
knob() { sed -n 's/^local omarchy_monitor_scale = //p' "$lua"; }
gdk() { sed -n 's/^local omarchy_gdk_scale = //p' "$lua"; }
payload() { printf '[{"name":"eDP-1","enabled":%s,"scale":%s},{"name":"DP-1","enabled":true,"scale":1}]' "$2" "$1"; }

internal eDP-1

# Kept fractional scale reaches the knob; GTK's integer scale rounds.
stock; sync_omarchy_scale_knob "$(payload 1.6 true)"
[[ $(knob) == 1.6 && $(gdk) == 2 ]] || { echo "1.6 not synced: $(knob)/$(gdk)"; exit 1; }

# Already in step: the file is not rewritten (a write reloads Hyprland).
before=$(stat -c %y "$lua"); sleep 1.1
sync_omarchy_scale_knob "$(payload 1.6 true)"
[[ $(stat -c %y "$lua") == "$before" ]] || { echo "rewrote an unchanged knob"; exit 1; }

# Changing scale at will follows along, down to a GTK scale of 1.
sync_omarchy_scale_knob "$(payload 1.25 true)"
[[ $(knob) == 1.25 && $(gdk) == 1 ]] || { echo "1.25 not synced: $(knob)/$(gdk)"; exit 1; }

# An external monitor's scale is never mistaken for the panel's.
stock; sync_omarchy_scale_knob '[{"name":"DP-1","enabled":true,"scale":1.5}]'
[[ $(knob) == 2 ]] || { echo "took an external's scale"; exit 1; }

# A disabled panel (docked, lid shut) is clamshell's business, not ours.
stock; sync_omarchy_scale_knob "$(payload 1.6 false)"
[[ $(knob) == 2 ]] || { echo "synced a disabled panel"; exit 1; }

# A hand-written monitors.lua without Omarchy's knob is never edited.
printf '%s\n' 'hl.monitor({ output = "eDP-1", scale = 1.5 })' > "$lua"
cp "$lua" "$root/handwritten"
sync_omarchy_scale_knob "$(payload 1.6 true)"
cmp -s "$lua" "$root/handwritten" || { echo "edited a hand-written monitors.lua"; exit 1; }

# An internal name that is not a plain connector is refused.
stock; internal 'eDP-1; rm -rf /'
sync_omarchy_scale_knob "$(payload 1.6 true)"
[[ $(knob) == 2 ]] || { echo "accepted an unsafe connector name"; exit 1; }
internal eDP-1

# No monitors.lua at all: nothing to do, and no file is created.
rm -f "$lua"; sync_omarchy_scale_knob "$(payload 1.6 true)"
[[ ! -e $lua ]] || { echo "created a monitors.lua"; exit 1; }

echo "omarchy scale knob tests passed"
