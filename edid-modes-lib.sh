#!/bin/bash

# EDID-derived display modes.
#
# Hyprland only offers the modes it read when an output was first set up, and
# that list can be stale or incomplete (a monitor that enumerated mid-hotplug,
# a DP-to-HDMI dock that answered with a partial EDID). The monitor's own EDID
# is the source of truth for its native mode, so this library decodes it into
# exact modelines that can be applied even when Hyprland's list lacks them.
#
# edid_display_info <monitor-name>
#   Prints {native, modes:[{mode, width, height, refreshRate, modeline}]} for a
#   connected output, or {native:null, modes:[]} when no EDID is readable.
#
# Inputs are injectable for tests: MONITOR_SYSFS_ROOT overrides /sys/class/drm
# and MONITOR_EDID_DECODER overrides edid-decode.

edid_empty_info() {
  printf '%s\n' '{"native":null,"modes":[]}'
}

edid_display_info() {
  local monitor_name=${1:-}
  local sysfs_root=${MONITOR_SYSFS_ROOT:-/sys/class/drm}
  local decoder=${MONITOR_EDID_DECODER:-edid-decode}
  local connector output

  [[ $monitor_name =~ ^[A-Za-z0-9._-]+$ ]] || { edid_empty_info; return 0; }
  if [[ $decoder == */* ]]; then
    [[ -x $decoder ]] || { edid_empty_info; return 0; }
  else
    command -v "$decoder" >/dev/null 2>&1 || { edid_empty_info; return 0; }
  fi

  for connector in "$sysfs_root"/card*-"$monitor_name"; do
    [[ -r $connector/status && -r $connector/edid ]] || continue
    [[ $(<"$connector/status") == connected ]] || continue
    edid_cached_info "$connector/edid" "$decoder"
    return 0
  done
  edid_empty_info
}

# Decoding runs on every snapshot poll, so results are cached per EDID hash in
# the private runtime directory; a different monitor on the same connector
# has a different hash and is decoded afresh.
edid_cached_info() {
  local edid_file="$1" decoder="$2"
  local cache_root=${MONITOR_EDID_MODES_CACHE:-${XDG_RUNTIME_DIR:-/tmp}/omarchy-displays-edid-modes}
  local hash cache_file info stage

  hash=$(sha256sum "$edid_file" 2>/dev/null | awk '{ print $1 }')
  cache_file="$cache_root/$hash.json"
  if [[ -n $hash && -r $cache_file ]] && info=$(<"$cache_file") && jq -e '.modes' >/dev/null 2>&1 <<<"$info"; then
    printf '%s\n' "$info"
    return 0
  fi
  info=$(LC_ALL=C "$decoder" -X "$edid_file" 2>/dev/null | edid_modes_from_xmodelines) || info=""
  [[ -n $info ]] || { edid_empty_info; return 0; }
  if [[ -n $hash ]]; then
    ( umask 077; mkdir -p "$cache_root" \
      && stage=$(mktemp "$cache_root/.modes.XXXXXX") \
      && printf '%s\n' "$info" >"$stage" && mv "$stage" "$cache_file" ) 2>/dev/null || true
  fi
  printf '%s\n' "$info"
}

# edid_infos_json <monitors-json>
# Prints {name: edid-info} for every output in a `hyprctl monitors all -j` list.
edid_infos_json() {
  local infos='{}' name
  while IFS= read -r name; do
    [[ -n $name ]] || continue
    infos=$(jq -c --arg name "$name" --argjson info "$(edid_display_info "$name")" \
      '. + {($name): $info}' <<<"$infos")
  done < <(jq -r '.[].name // empty' <<<"$1")
  printf '%s\n' "$infos"
}

# Reads `edid-decode -X` output on stdin. The first progressive modeline is the
# EDID preferred timing, which is the panel's native mode.
edid_modes_from_xmodelines() {
  awk '
    $1 == "Modeline" && NF >= 11 && tolower($0) !~ /interlace|doublescan/ {
      clock = $3 + 0
      hdisp = $4 + 0; htotal = $7 + 0
      vdisp = $8 + 0; vtotal = $11 + 0
      if (clock <= 0 || hdisp <= 0 || vdisp <= 0 || htotal <= 0 || vtotal <= 0) next
      refresh = clock * 1000000 / (htotal * vtotal)
      sync = ""
      for (i = 12; i <= NF; i++) sync = sync " " tolower($i)
      gsub(/hsync/, "hsync", sync); gsub(/vsync/, "vsync", sync)
      modeline = sprintf("%.3f %d %d %d %d %d %d %d %d%s", clock, $4, $5, $6, $7, $8, $9, $10, $11, sync)
      printf "%d\t%d\t%.2f\t%s\n", hdisp, vdisp, refresh, modeline
    }
  ' | jq -Rsc '
    [split("\n")[] | select(length > 0) | split("\t")
      | {width: (.[0] | tonumber), height: (.[1] | tonumber),
         refreshRate: (.[2] | tonumber), modeline: ("modeline " + .[3])}
      | . + {mode: "\(.width)x\(.height)@\(.refreshRate)Hz"}]
    | reduce .[] as $m ([]; if any(.[]; .width == $m.width and .height == $m.height
        and ((.refreshRate - $m.refreshRate) | fabs) <= 0.05) then . else . + [$m] end)
    | {native: (.[0] // null | if . == null then null else {width, height, refreshRate} end),
       modes: .}'
}

# edid_modeline_for <edid-info-json> <width> <height> <refresh>
# Prints the modeline of the EDID mode nearest to the request, allowing the
# small refresh drift compositors report for custom modes. Empty when none.
edid_modeline_for() {
  jq -r --argjson w "$2" --argjson h "$3" --argjson r "$4" '
    [.modes[] | select(.width == $w and .height == $h
       and ((.refreshRate - $r) | fabs) <= 0.5)]
    | sort_by((.refreshRate - $r) | fabs) | .[0].modeline // ""
  ' <<<"$1"
}
