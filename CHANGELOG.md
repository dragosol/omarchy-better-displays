# Changelog

All notable user-visible changes to Better Displays Pro will be documented here.

## [1.0.0] - 2026-09-14

First release of Better Displays Pro (`io.github.dragosol.better-displays-pro`), forked from Monitor
Studio (commit `0fe80be`).

### Added

- A single wide panel, sized to fit a 1280×720 screen, with every control
  visible: display cards with on/off switches, layout presets, brightness and
  text size on the left; arrangement, workspaces and profiles in the centre;
  the selected display's settings on the right.
- EDID modeline decoding (`edid-decode -X`, cached per EDID hash). The native
  resolution and timings Hyprland did not advertise are offered and marked
  "from EDID".
- Native-mode insight per display (native, better mode available, limited by
  the connection) with a one-click recommended mode.
- EDID-only modes are applied as exact Hyprland modelines, validated, kept and
  restored like advertised modes.
- A density-based scale suggestion from the monitor's physical size.
- Refresh rate and rotation as one-click buttons; resolutions sorted native
  first, then by size.
- Displays remember their last kept state. A known set is restored and kept
  when it connects (no 15-second confirmation), a set whose monitors moved
  ports follows them, and a new combination gets each recognised monitor's last
  mode, scale, rotation and relative position. It is saved automatically, with
  a one-click Undo notification.
- The remembered layout also comes back after a Hyprland config reload (saving
  a file in `~/.config/hypr`, changing the Omarchy theme) and after the shell
  restarts, re-checking until Hyprland's reloaded monitor rules have settled.
- Kept layouts are written as Hyprland rules to
  `~/.local/state/omarchy/toggles/hypr/displays-remembered.lua`, so events
  that re-apply config monitor rules (switching a workspace between dwindle
  and scrolling, config reloads) keep the layout instead of blanking the
  displays twice.

### Changed

- When several profiles match a connected set, the most recently updated one
  wins after the active profile.

### Fixed

- Hyprland no longer reloads its whole config every two seconds. The
  remembered-layout rules file was rewritten on every restore check even when
  nothing changed; Hyprland watches that file, so each rewrite reloaded the
  config and triggered the next check. The file is now replaced only when its
  rules change.

- Settings changes on a display running a custom modeline no longer fail with
  "not advertised by this output": the drifted refresh the compositor reports
  maps back to the EDID timing.
- The native-mode card never suggests a lower refresh rate than the one
  running; a faster EDID-only timing is offered as "Try".
- Arrangement tiles show the real mode and scale (for example
  `3440 × 1440 · 2x`) instead of the scaled logical size.

## Monitor Studio history

## [Unreleased]

### Added

- Exact trusted connected-set restore after settled hotplug and startup through
  the normal 15-second preview/watchdog, with per-generation loop suppression
  and cross-panel editing guards. Connector-only legacy matches are excluded.
- Separate actionable Undo/Open restore notifications using the installed Omarchy
  single-click argv API. Neither action silently confirms a preview.
- Read-only Display Health, allowlisted sanitized clipboard reports, and explicit
  side-by-side repair through the existing confirmation transaction.
- New connected-set Extend/Mirror/manual recommendations based only on advertised
  modes, conservative refresh selection and valid existing scale/rotation.
- Fake-compositor and pure/QML-control-flow regression coverage for these paths.

- Public release documentation, security boundary, and aggregate verification.
- Per-display rotation controls for landscape, portrait, and inverted orientations.
- Per-display refresh-rate selection, filtered to modes supported at the chosen resolution.
- Coalesced display hot-plug refreshes with automatic cancellation and safe
  recovery when hardware changes during a layout confirmation.
- Identity-aware connected-set profiles: exact sets restore automatically,
  moved monitors require confirmation, and confirmed moves can update or fork
  a profile explicitly.
- Profile management for naming, selecting, duplicating, and confirmed deletion,
  with plain-language exact, moved, weak, ambiguous, and new-set guidance.
- Persistent anchor-display selection with signed, anchor-relative profile
  coordinates that remain independent of transient keyboard or pointer focus.
- Keyboard-accessible display identification overlays, an immediate read-only
  Refresh action, and explicit active, disabled, and transitioning status.
- Internal only, External only, and Extend presets using the same guarded
  preview transaction, with remembered per-profile topology variants.
- Duplicate mode with advertised-mode validation, an up-front compatibility
  summary, and exact rollback to the previous extended or mirrored grouping.
- Connector transport and structured constraint explanations, including saved
  compositor adjustments, plus an independent emergency-revert IPC command.

### Fixed

- Normalize Hyprland's numeric mirror-source IDs before they reach the panel,
  so Duplicate can reliably return to Extend, Internal only, or External only.
- Preserve each display's current advertised mode for mixed-aspect Duplicate,
  and warn that Hyprland's mirror path may stretch or crop the image.
- Show profile update and save-as-new actions directly in the display
  confirmation overlay when known monitors move connectors, and explain when
  uncertain matches must be identified instead of silently disabling Keep.
- Keep the 15-second display confirmation and applied geometry visible when a
  display change recreates the shell's per-screen monitor panel.
- Clear Duplicate mirroring when switching to Extend, Internal only, or
  External only, including recovery from previously saved mirrored variants.
- Recover pending confirmations as soon as a replacement bar widget loads,
  queue state refreshes instead of dropping them while a read is in flight, and
  avoid a full Hyprland reload when keeping a display layout.
- Register the custom monitor IPC handler on one deterministic screen instance,
  avoiding duplicate-handler races when per-screen bar widgets are rebuilt.

### Security

- Render monitor-provided make, model, description, and connector labels as
  plain text, and exclude them from tooltips that use automatic text parsing.
- Reject symbolic links and foreign-owned runtime paths, and enforce private
  permissions before creating display transaction or restore-lock files.

## [1.0.0] - Unreleased

### Added

- Responsive drag-and-drop monitor arrangement with a full-screen editor.
- Friendly monitor labels and recommended per-display resolutions.
- Per-display resolution and scale previews with a 15-second safety rollback.
- Workspace-to-monitor assignment for workspaces 1–10.
- Self-contained persistence that does not edit Hyprland user configuration.
