#!/bin/bash

set -euo pipefail

plugin_dir=$(cd "$(dirname "$0")/.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT

source "$plugin_dir/edid-modes-lib.sh"

mkdir -p "$test_root/sys/card0-DP-1" "$test_root/sys/card0-HDMI-A-1" "$test_root/bin"
printf 'connected\n' >"$test_root/sys/card0-DP-1/status"
printf 'samsung-edid\n' >"$test_root/sys/card0-DP-1/edid"
printf 'disconnected\n' >"$test_root/sys/card0-HDMI-A-1/status"
printf 'stale-edid\n' >"$test_root/sys/card0-HDMI-A-1/edid"

# edid-decode -X output for an ultrawide behind a DP-to-HDMI dock: a
# duplicate timing, an interlaced timing and three native-resolution rates.
cat >"$test_root/bin/edid-decode" <<'SCRIPT'
#!/bin/bash
cat <<'OUT'
      Modeline "3440x1440_99.98" 543.500  3440 3488 3520 3600  1440 1443 1453 1510  +HSync -VSync
      Modeline "1920x1080_60.00" 148.500  1920 2008 2052 2200  1080 1084 1089 1125  +HSync +VSync
      Modeline "1920x1080i_60.00" 74.250  1920 2008 2052 2200  1080 1084 1094 1125  interlace +HSync +VSync
      Modeline "2560x1440_59.95" 241.500  2560 2608 2640 2720  1440 1443 1448 1481  +HSync -VSync
      Modeline "3440x1440_59.97" 319.750  3440 3488 3520 3600  1440 1443 1453 1481  +HSync -VSync
      Modeline "3440x1440_59.97" 319.750  3440 3488 3520 3600  1440 1443 1453 1481  +HSync -VSync
      Modeline "3440x1440_49.99" 265.250  3440 3488 3520 3600  1440 1443 1453 1474  +HSync -VSync
OUT
SCRIPT
chmod +x "$test_root/bin/edid-decode"

export MONITOR_SYSFS_ROOT="$test_root/sys"
export MONITOR_EDID_DECODER="$test_root/bin/edid-decode"
export MONITOR_EDID_MODES_CACHE="$test_root/cache"

info=$(edid_display_info DP-1)
jq -e '.native == {width: 3440, height: 1440, refreshRate: 99.98}' <<<"$info" >/dev/null
jq -e '[.modes[].mode] == ["3440x1440@99.98Hz", "1920x1080@60.00Hz", "2560x1440@59.95Hz",
                           "3440x1440@59.97Hz", "3440x1440@49.99Hz"]' <<<"$info" >/dev/null
jq -e '.modes[3].modeline == "modeline 319.750 3440 3488 3520 3600 1440 1443 1453 1481 +hsync -vsync"' \
  <<<"$info" >/dev/null

# Results are cached per EDID hash; a broken decoder does not lose them.
printf '#!/bin/bash\nexit 1\n' >"$test_root/bin/edid-decode"
test "$(edid_display_info DP-1)" = "$info"

# Disconnected, unknown and unsafe names yield an empty description.
jq -e '. == {native: null, modes: []}' <<<"$(edid_display_info HDMI-A-1)" >/dev/null
jq -e '. == {native: null, modes: []}' <<<"$(edid_display_info DP-9)" >/dev/null
jq -e '. == {native: null, modes: []}' <<<"$(edid_display_info '../x')" >/dev/null

# The compositor reports a drifted refresh for a live modeline; the nearest
# EDID timing within half a hertz is still found, and nothing beyond it.
test "$(edid_modeline_for "$info" 3440 1440 59.831)" \
  = "modeline 319.750 3440 3488 3520 3600 1440 1443 1453 1481 +hsync -vsync"
test -z "$(edid_modeline_for "$info" 3440 1440 144)"
test -z "$(edid_modeline_for "$info" 2560 1080 60)"

infos=$(edid_infos_json '[{"name":"DP-1"},{"name":"HDMI-A-1"}]')
jq -e '.["DP-1"].native.width == 3440 and .["HDMI-A-1"].native == null' <<<"$infos" >/dev/null

echo "edid modes tests passed"
