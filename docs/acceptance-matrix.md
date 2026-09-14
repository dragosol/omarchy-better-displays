# Acceptance Matrix

Validated on 2026-08-24 against Hyprland 0.56.2. The aggregate command is
`./scripts/verify-release`; every automated evidence item below is part of that
gate. Fixture and fake-compositor checks are intentionally used for disruptive
failure cases so release verification does not alter the live desktop.

## Windows-like acceptance scenarios

| # | Scenario | Evidence | Result |
|---:|---|---|---|
| 1 | Never-seen monitor gets a safe layout without disturbing other profiles | `tests/profile-store.test.sh`, `tests/profile-management.test.sh`, preset fallback tests in `tests/topology-model.test.js` | Pass (automated) |
| 2 | Known monitor on the same connector restores exact topology and enabled state | v2 exact restore in `tests/profile-store.test.sh` and full topology round-trip in `tests/apply-layout.test.sh` | Pass (automated) |
| 3 | Strongly identified monitor moved to another connector is revalidated and confirmed | moved-match, fork, and update cases in `tests/profile-store.test.sh` and `tests/profile-matching.test.js` | Pass (automated) |
| 4 | Identical serial-less monitors never silently swap | ambiguous tie cases in `tests/profile-matching.test.js`; Keep guard and Identify UI lint/static audit | Pass (automated) |
| 5 | Unplug during preview cancels safely and retains a usable display | stale hot-plug recovery cases in `tests/apply-layout.test.sh` | Pass (automated fake compositor) |
| 6 | Two dock events 500 ms apart are coalesced | deterministic quiet-window sequence in `tests/display-events.test.js` | Pass (automated clock) |
| 7 | Runtime link/GPU resource conflict is actionable | forced compositor rejection in `tests/apply-layout.test.sh` plus reason-code checks in `tests/topology-model.test.js` | Pass (automated fake compositor) |
| 8 | Unlike clone targets use a disclosed common mode | common-mode table and rejection tests in `tests/topology-model.test.js`; mirror apply/revert in `tests/apply-layout.test.sh` | Pass (automated) |
| 9 | Rotated mixed-DPI scale changes preserve logical geometry | rotated logical-size, seam, and settings tests in `tests/topology-model.test.js` and `tests/layout-model.test.js` | Pass (automated) |
| 10 | Rightmost anchor preserves negative left/top coordinates | anchor/focus tests in `tests/topology-model.test.js` and persisted signed coordinates in `tests/profile-store.test.sh` | Pass (automated) |
| 11 | Rejected or timed-out risky modes restore exact prior topology | bad-mode, Revert, watchdog, and mirrored-group rollback cases in `tests/apply-layout.test.sh` | Pass (automated fake compositor) |
| 12 | Wireless/virtual target appears only after driver enumeration | unknown `Virtual-1` enumeration in `tests/monitor-snapshot.test.sh`; arrangement consumes only enumerated records | Pass (automated fixture) |
| 13 | Brief EDID/KVM identity loss never deletes or overwrites a saved profile | observation-only mismatch and retained migration/profile state in `tests/profile-store.test.sh`; weak/ambiguous matcher cases | Pass (automated) |
| 14 | Connector changes during Apply/Keep abort stale assumptions | hardware-generation rejection and stale-cancel tests in `tests/apply-layout.test.sh` | Pass (automated fake compositor) |

## Next-release assistance (automated, not hardware certification)

| Scenario | Evidence | Result |
|---|---|---|
| Settled hotplug/startup only, owner dispatch, busy/dirty/pending suppression and no repeat | Real QML snapshot handler executed in `tests/next-release.test.js`; event clock tests | Pass (automated seams) |
| Exact trusted restore preview, Undo fence, reconnect re-arm, moved/weak/legacy exclusion, unchanged store | `tests/auto-restore.test.sh` with stateful fake compositor | Pass (automated) |
| Manual preview serialized with auto restore | Shared-lock timeout regression in `tests/auto-restore.test.sh` | Pass (automated) |
| Undo/Open notifications preserve argv and never confirm | Fake `omarchy` argv capture; stale transaction-specific Undo test | Pass (automated API boundary only) |
| Health diagnostics and report contain no identity/path text | `tests/studio-model.test.js` including hostile strings | Pass (automated) |
| Supported-mode Extend/Mirror plans and unavailable-mode rejection | `tests/studio-model.test.js`; existing backend preview/revert tests | Pass (automated) |
| Health repair and recommendations use the real preview UI path | QML wiring tests and `qmllint` | Pass (static integration; live interaction pending) |

### Required manual checks before release

- Dock/undock with the panel closed, KVM identity churn, disabled-output return,
  rapid bursts and multi-GPU systems. Verify one preview, not a restore loop.
- Edit on a non-IPC-owner screen while docking; ensure no automatic mutation.
- Test actual Omarchy notification Undo, Open, dismissal, DND, shell recreation
  and stale history entries. Two entries are intentional: the installed API has
  one persisted click action per notification, no two-button action API.
- Let an automatic preview expire; verify watchdog rollback without Keep, then
  explicitly Keep another preview and check saved workspaces and anchor.
- Review Display Health, copy with/without `wl-copy`, inspect the copied report,
  and exercise safe repair/revert on overlapping, disabled and mirrored layouts.
- On a genuinely new set, exercise Extend, common-mode Mirror and manual setup;
  check mixed scale/rotation, unlike aspect ratios and missing advertised modes.
- Visually verify compact/full-screen layout, scrolling and keyboard focus.

No live display mutation, plugin install, shell restart or hardware validation was
performed for this implementation. The historical validation above does not
constitute physical acceptance of the new features.

## Validation scope

Automated validation passed using sanitized monitor fixtures. Physical
hot-plug, dock, projector, pointer-seam, and live-preview scenarios still
require manual verification on representative hardware.
