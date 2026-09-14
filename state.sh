#!/bin/bash

script_dir=$(cd "$(dirname "$0")" && pwd)
source "$script_dir/monitor-state-lib.sh"
source "$script_dir/monitor-snapshot-lib.sh"
source "$script_dir/profile-store-lib.sh"
source "$script_dir/edid-modes-lib.sh"
state_root="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/displays"

monitors_json=$(hyprctl monitors all -j)
monitors_json=$(normalize_monitor_mirror_sources "$monitors_json")
focused_monitor=$(printf '%s\n' "$monitors_json" | jq -r '[.[] | select(.focused == true)][0].name // ""')
preferred_resolutions='{}'

while IFS= read -r monitor_name; do
  preferred_resolution=$(preferred_resolution_for "$monitor_name")
  [[ -n $preferred_resolution ]] || continue
  preferred_resolutions=$(jq -c --arg name "$monitor_name" --arg resolution "$preferred_resolution" \
    '. + {($name): $resolution}' <<<"$preferred_resolutions")
done < <(jq -r '.[].name' <<<"$monitors_json")

# The monitor's EDID is decoded per output so the panel can offer its native
# mode even when Hyprland's advertised list is stale or incomplete.
edid_infos='{}'
while IFS= read -r monitor_name; do
  edid_infos=$(jq -c --arg name "$monitor_name" --argjson info "$(edid_display_info "$monitor_name")" \
    '. + {($name): $info}' <<<"$edid_infos")
done < <(jq -r '.[] | .name' <<<"$monitors_json")

{ omarchy-brightness-display --monitor "$focused_monitor" 2>/dev/null; echo; } | head -n 1

printf '%s\n' "$monitors_json" | jq -r '
  def internal: test("^(eDP|LVDS|DSI)-");
  ([.[] | select(.name | internal)][0].name // ""),
  ([.[] | select((.name | internal) | not)][0].name // ""),
  ([.[] | select((.name | internal) and .disabled != true)][0].name // ""),
  ([.[] | select(.mirrorOf != "none") | if (.name | internal) then .mirrorOf else .name end][0] // "")
'

printf '%s\n' "$focused_monitor"
omarchy-hyprland-monitor-scaling 2>/dev/null || echo

printf '%s\n' "$monitors_json" | jq -c --argjson preferred "$preferred_resolutions" --argjson edid "$edid_infos" '
  def transport:
    if test("^(eDP|LVDS|DSI)-") then "internal"
    elif test("^DP-") then "displayport"
    elif test("^HDMI-") then "hdmi"
    elif test("^VGA-") then "vga"
    else "unknown" end;
  [.[] | {
    name,
    transport:(.name | transport),
    enabled:(.disabled != true),
    focused:(.focused == true),
    width,
    height,
    refreshRate: (. as $m
      | ((.availableModes // []) | map(capture("^(?<w>[0-9]+)x(?<h>[0-9]+)@(?<r>[0-9.]+)")
          | {w: (.w | tonumber), h: (.h | tonumber), r: (.r | tonumber)})) as $adv
      | if any($adv[]; .w == $m.width and .h == $m.height and ((.r - $m.refreshRate) | fabs) <= 0.05)
        then $m.refreshRate
        else ([($edid[$m.name].modes // [])[]
                | select(.width == $m.width and .height == $m.height
                    and ((.refreshRate - $m.refreshRate) | fabs) <= 0.5)]
              | sort_by((.refreshRate - $m.refreshRate) | fabs) | .[0].refreshRate) // $m.refreshRate
        end),
    scale,
    transform:(.transform // 0),
    mirrorOf:(if (.mirrorOf // "none") == "none" then null else .mirrorOf end),
    x,
    y,
    description,
    make,
    model,
    serial,
    physicalWidth,
    physicalHeight,
    advertisedModes: (.availableModes // []),
    availableModes: ((.availableModes // []) as $hypr
      | ($hypr | map(capture("^(?<w>[0-9]+)x(?<h>[0-9]+)@(?<r>[0-9.]+)")
          | {w: (.w | tonumber), h: (.h | tonumber), r: (.r | tonumber)})) as $parsed
      | $hypr + [($edid[.name].modes // [])[] | . as $m
          | select(any($parsed[]; .w == $m.width and .h == $m.height
              and ((.r - $m.refreshRate) | fabs) <= 0.05) | not) | .mode]),
    edidModes: [($edid[.name].modes // [])[] | {mode, width, height, refreshRate}],
    nativeMode: ($edid[.name].native // null),
    recommendedResolution: ($preferred[.name]
      // (($edid[.name].native // null) | if . == null then "" else "\(.width)x\(.height)" end))
  }]
'

hyprctl workspaces -j 2>/dev/null | jq -c '.' || printf '%s\n' '[]'
hyprctl workspacerules -j 2>/dev/null | jq -c '.' || printf '%s\n' '[]'
bash "$script_dir/apply-layout.sh" pending 2>/dev/null || printf '%s\n' '{}'
snapshot=$(monitor_snapshot "$monitors_json" 2>/dev/null) || snapshot='{}'
printf '%s\n' "$snapshot"
if profile_store_load && status=$(profile_store_status "$(<"$(profile_store_file)")" "$snapshot" 2>/dev/null); then
  jq -cn --argjson store "$(<"$(profile_store_file)")" --argjson match "$status" '
    {activeProfileId: $store.activeProfileId,
     activeAnchor: ([ $store.profiles[]
       | select(.id == $store.activeProfileId) | .topology.anchor // "" ][0] // ""),
     activeVariants: ([ $store.profiles[]
       | select(.id == $store.activeProfileId) | .topology.variants // {} ][0] // {}),
     profiles: [$store.profiles[] | {id, name, connectedSet}], match: $match}'
else
  printf '%s\n' '{"activeProfileId":"","activeAnchor":"","activeVariants":{},"profiles":[],"match":{"status":"new","profileId":"","matches":[]}}'
fi
