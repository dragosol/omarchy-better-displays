import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Ui
import qs.Commons
import "Model.js" as Model
import "TopologyModel.js" as Topology
import "DisplayEventModel.js" as DisplayEvents
import "StudioModel.js" as Studio
import "SessionGuard.js" as SessionGuard

Panel {
  id: root
  moduleName: "omarchy.monitor"
  ipcTarget: "omarchy.monitor"
  manageIpc: false

  // manageIpc: false so this panel can own the single IpcHandler the target
  // permits — needed for the brightness + state methods below.
  property int brightnessPercent: 0
  property int pendingBrightnessPercent: 0
  property bool brightnessSetQueued: false
  property bool brightnessAvailable: false
  property string internalMonitor: ""
  property string externalMonitor: ""
  property string focusedMonitor: ""
  property string selectedMonitorName: ""
  property bool internalEnabled: false
  property bool mirrorEnabled: false
  property string monitorScale: ""
  property var displays: []
  property int enabledDisplayCount: 0
  property var layoutPreview: []
  property real layoutScale: 1
  property bool arrangementDirty: false
  property var stagedDisplaySettings: ({})
  readonly property bool settingsDirty: Object.keys(stagedDisplaySettings).length > 0
  property var workspaceAssignmentsActual: ({})
  property var stagedWorkspaceAssignments: ({})
  property bool workspaceAssignmentsManaged: false
  readonly property bool workspaceDirty: !Model.workspaceAssignmentsEqual(
    workspaceAssignmentsActual, stagedWorkspaceAssignments)
  readonly property bool layoutDirty: arrangementDirty || settingsDirty || workspaceDirty || anchorDirty
  readonly property var workspaceNumbers: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
  property string expandedSettingsSection: ""
  property bool layoutDragging: false
  property bool layoutApplying: false
  property bool layoutConfirmationPending: false
  property int layoutConfirmationSeconds: 0
  property string layoutTransactionId: ""
  property string layoutProcessAction: ""
  property string layoutTransactionScope: ""
  property var displaySettingsBeforePreview: ({})
  property bool arrangementEditing: false
  property bool expandedLayoutOpen: false
  property string layoutError: ""
  property var displayEventState: DisplayEvents.initialState("")
  property bool displayTransitioning: false
  property bool staleCancellationRequested: false
  property bool stateRefreshQueued: false
  property string stateRefreshQueuedReason: ""
  property bool stateProcHotplugScan: false
  property double scanEventAt: 0
  property string scanRestorePermission: "block"
  property bool autoRestoreOwnsBusy: false
  property bool burstRestoreBlocked: false
  property string observedRestoreGeneration: ""
  property var healthSnapshot: ({})
  property bool identifyActive: false
  property string confirmationScreenName: ""
  property int confirmationWorkspaceId: 0
  readonly property var confirmationAvailableScreens: {
    var names = []
    for (var i = 0; i < Quickshell.screens.length; i++) {
      var candidate = Quickshell.screens[i]
      if (candidate && candidate.name) names.push(String(candidate.name))
    }
    return names
  }
  readonly property string confirmationWorkspaceScreenName: {
    if (confirmationWorkspaceId <= 0) return ""
    var monitors = Hyprland.monitors.values
    for (var i = 0; i < monitors.length; i++) {
      var monitor = monitors[i]
      if (monitor && monitor.activeWorkspace
          && Number(monitor.activeWorkspace.id) === confirmationWorkspaceId)
        return String(monitor.name || "")
    }
    return ""
  }
  readonly property string confirmationFocusedScreenName:
    Hyprland.focusedMonitor ? String(Hyprland.focusedMonitor.name || "") : ""
  readonly property string confirmationTargetScreenName:
    Model.confirmationTargetScreen(
      confirmationScreenName, confirmationWorkspaceScreenName,
      confirmationFocusedScreenName, confirmationAvailableScreens)
  readonly property bool ownsDisplayConfirmation: Model.ownsDisplayConfirmation(
    panel.screen ? String(panel.screen.name || "") : "",
    confirmationScreenName, confirmationWorkspaceScreenName,
    confirmationFocusedScreenName, confirmationAvailableScreens)
  readonly property bool ownsDisplayIpc: Model.ownsDisplayIpc(
    panel.screen ? String(panel.screen.name || "") : "",
    confirmationAvailableScreens)
  property var profiles: []
  property string activeProfileId: ""
  property var activeTopologyVariants: ({})
  property string anchorDisplayName: ""
  property string storedAnchorDisplayName: ""
  property bool anchorDirty: false
  property var profileMatch: ({ status: "new", profileId: "", matches: [] })
  property string sessionGuardId: SessionGuard.register()
  readonly property bool blocksAutoRestore: root.layoutDirty || root.layoutDragging
    || root.arrangementEditing || root.expandedLayoutOpen || root.layoutApplying
    || root.layoutConfirmationPending || root.profileActionBusy || root.healthOpen
  onBlocksAutoRestoreChanged: {
    SessionGuard.setBlocked(root.sessionGuardId, root.blocksAutoRestore)
    if (root.blocksAutoRestore && root.displayTransitioning) root.burstRestoreBlocked = true
  }
  Component.onDestruction: SessionGuard.remove(root.sessionGuardId)

  property bool healthOpen: false
  property string healthCopyStatus: ""
  readonly property var displayHealth: Studio.displayHealth(root.displays, root.profileMatch,
    root.workspaceAssignmentsActual, root.displayTransitioning, Topology)

  function copyHealthReport() {
    if (healthCopyProc.running) return
    root.healthCopyStatus = ""
    healthCopyProc.command = ["wl-copy", "--type", "text/plain", "--",
      Studio.sanitizedReport(root.displays, root.profileMatch,
        root.workspaceAssignmentsActual, root.displayTransitioning, Topology)]
    healthCopyProc.running = true
  }

  property string dismissedSetupGeneration: ""
  readonly property bool setupSuggested: {
    var generation = root.healthSnapshot ? String(root.healthSnapshot.hardwareGeneration || "") : ""
    return String((root.profileMatch || {}).status || "new") === "new"
      && root.displays.length > 0 && !root.displayTransitioning
      && generation !== "" && root.dismissedSetupGeneration !== generation
  }
  readonly property var recommendedExtend: Studio.recommendedSetup(root.displays, "extend", Topology)
  readonly property var recommendedMirror: Studio.recommendedSetup(root.displays, "mirror", Topology)
  readonly property bool assistanceBusy: root.layoutApplying || root.layoutConfirmationPending
    || root.profileActionBusy || root.layoutDirty || root.layoutDragging || root.displayTransitioning
    || restoreLayoutProc.running

  function applyRecommendedSetup(kind) {
    if (root.assistanceBusy) return
    var plan = kind === "mirror" ? root.recommendedMirror : root.recommendedExtend
    if (!plan.valid) { root.layoutError = plan.reason; return }
    root.anchorDisplayName = plan.anchor
    root.beginDisplayPreview(plan.proposed, plan.previous, "topology", "",
      Topology.workspacePayloadForPreset(root.workspacePayload(), plan.proposed, plan.anchor))
  }

  function arrangeNewSetManually() {
    root.dismissedSetupGeneration = String(root.healthSnapshot.hardwareGeneration || "")
    root.expandedSettingsSection = "monitors"
    root.openExpandedLayout()
  }

  property bool profileSectionOpen: false
  property bool profileActionBusy: false
  property string pendingProfileDeleteId: ""
  readonly property var displayConfirmationPolicy:
    Model.displayConfirmationPolicy(profileMatch)
  readonly property real layoutPadding: Style.space(10)
  readonly property real expandedLayoutPadding: Style.space(24)
  readonly property int layoutConfirmationDuration: 15
  readonly property var activeArrangementCanvas: expandedLayoutOpen
    ? expandedWorkspace.canvasItem : arrangementCanvas
  readonly property real activeLayoutPadding: expandedLayoutOpen
    ? expandedLayoutPadding : layoutPadding
  readonly property real activeLayoutUtilization: expandedLayoutOpen
    ? Model.responsiveDisplayUtilization(enabledDisplayCount) : 0.8
  readonly property var selectedDisplay: {
    var focused = null
    var first = null
    for (var i = 0; i < displays.length; i++) {
      var display = displays[i]
      if (!display || !display.enabled) continue
      if (!first) first = display
      if (display.name === selectedMonitorName) return display
      if (display.focused) focused = display
    }
    return focused || first
  }
  readonly property var previewDisplays: Model.displaysWithSettings(
    displays, stagedDisplaySettings)
  readonly property var anchorOptions: {
    var result = []
    for (var i = 0; i < displays.length; i++) {
      var display = displays[i]
      if (display && display.enabled)
        result.push({
          value: display.name,
          label: display.name + (display.mirrorOf && display.mirrorOf !== "none" ? " (mirroring " + display.mirrorOf + ")" : "")
        })
    }
    return result
  }
  readonly property var identifyEntries: DisplayEvents.identifyEntries(displays)
  readonly property var duplicatePlan: Topology.prepareDuplicatePreview(
    displays, stagedDisplaySettings, anchorDisplayName)
  readonly property string currentTopologyPreset: Topology.isDuplicateTopology(previewDisplays)
    ? "duplicate" : Topology.currentPreset(previewDisplays)
  readonly property bool internalPresetAvailable: Topology.presetAvailable(displays, "internal")
  readonly property bool externalPresetAvailable: Topology.presetAvailable(displays, "external")
  readonly property bool extendPresetAvailable: Topology.presetAvailable(displays, "extend")
  readonly property var selectedDisplayPreview: {
    for (var i = 0; i < previewDisplays.length; i++) {
      if (previewDisplays[i] && previewDisplays[i].name === selectedMonitorName)
        return previewDisplays[i]
    }
    return selectedDisplay
  }
  readonly property var resolutionOptions: Model.resolutionChoices(
    selectedDisplay ? selectedDisplay.availableModes : [],
    selectedDisplay ? (selectedDisplay.advertisedModes || selectedDisplay.availableModes) : [],
    selectedDisplay ? selectedDisplay.nativeMode : null,
    selectedDisplay ? selectedDisplay.recommendedResolution : "")
  readonly property string resolutionValue: selectedDisplayPreview
    ? Model.matchingResolutionValue(resolutionOptions, selectedDisplayPreview.width,
                                    selectedDisplayPreview.height)
    : ""
  readonly property var rotationOptions: [
    { value: "0", label: "0°", tooltip: "Landscape" },
    { value: "1", label: "90°", tooltip: "Portrait, rotated clockwise" },
    { value: "2", label: "180°", tooltip: "Landscape, upside down" },
    { value: "3", label: "270°", tooltip: "Portrait, rotated counter-clockwise" }
  ]
  readonly property string rotationValue: selectedDisplayPreview
    ? String(Model.cleanTransform(selectedDisplayPreview.transform)) : "0"
  readonly property var refreshRateOptions: selectedDisplayPreview
    ? Model.refreshChoices(selectedDisplay ? selectedDisplay.availableModes : [],
                           selectedDisplay ? (selectedDisplay.advertisedModes || selectedDisplay.availableModes) : [],
                           selectedDisplayPreview.width, selectedDisplayPreview.height)
    : []
  // Custom EDID modelines report a slightly drifted refresh, so the active
  // rate is the nearest option within half a hertz.
  readonly property string refreshRateValue: {
    if (!selectedDisplayPreview) return ""
    var target = Number(selectedDisplayPreview.refreshRate)
    var best = ""
    var bestDelta = 0.5
    for (var i = 0; i < refreshRateOptions.length; i++) {
      var delta = Math.abs(Number(refreshRateOptions[i].refreshRate) - target)
      if (delta <= bestDelta) { best = refreshRateOptions[i].value; bestDelta = delta }
    }
    return best
  }
  readonly property var modeInsight: Model.modeInsight(selectedDisplayPreview
    ? Object.assign({}, selectedDisplay, {
        width: selectedDisplayPreview.width, height: selectedDisplayPreview.height,
        refreshRate: selectedDisplayPreview.refreshRate })
    : null)
  readonly property bool settingsBusy: layoutApplying || layoutConfirmationPending
  readonly property string recommendedScaleValue: Model.recommendedScale(selectedDisplayPreview, scaleValues)

  // Carry sub-notch touchpad deltas between wheel events.
  property real wheelAccumulator: 0

  // Cursor model shared by keyboard and mouse. Sections:
  //   "brightness" - single slider row, selectedIndex = -1 sentinel
  //                  (mirrors Audio's slider rows). Only present if a
  //                  controllable backlight was detected.
  //   "scale"      - 6 Button scale presets; treated as a single
  //                  horizontal row from j/k's perspective. h/l moves
  //                  between presets, identical to bluetooth's header.
  //   "monitors"   - vertical display row list for enabling/disabling displays;
  //                  j/k walks each row.
  // Mouse hover on a target updates root state via the components' `hovered`
  // signal so keyboard cursor and pointer share one highlight.
  readonly property var scalePresets: ["1", "1.25", "1.6", "2", "3", "4"]
  readonly property var scaleValues: {
    if (selectedDisplayPreview)
      return Model.availableScales(scalePresets, selectedDisplayPreview.width,
                                   selectedDisplayPreview.height)
    return scalePresets
  }
  property string focusSection: "scale"
  property int selectedIndex: 0
  property bool cursorActive: false

  // Text size slider — curated macOS-style notches (px). The panel snaps to
  // these stops; the CLI (omarchy-display-text-size) accepts any integer in range.
  readonly property var textSizeStops: [9, 10, 11, 12, 14, 16, 20]
  // While a change is in flight, the chosen stop index overrides the live
  // base-size so the knob doesn't snap back during the file round-trip. -1 =
  // no pending change; follow Style.font.baseSize.
  property int textSizePreviewIndex: -1

  // A text-size change reflows the whole panel (both font and spacing scale),
  // which slides rows under a stationary pointer and fires synthetic hover.
  // While true, hover is not allowed to hijack the keyboard focus section —
  // otherwise h/l on the text-size slider can jump focus to another row.
  property bool reflowingText: false
  function markReflowing() {
    root.reflowingText = true
    reflowSettle.restart()
  }

  // Every control is on screen at once; j/k walks them in reading order
  // (left column, centre, right column) and h/l moves within a row.
  readonly property var visibleSections: {
    var list = []
    if (displays.length > 0) list.push("monitors")
    list.push("presets")
    if (brightnessAvailable) list.push("brightness")
    list.push("textsize")
    if (layoutPreview.length > 0) list.push("arrangement")
    if (selectedDisplay) {
      list.push("workspaces")
      if (resolutionOptions.length > 0) list.push("resolution")
      if (refreshRateOptions.length > 0) list.push("refreshRate")
      list.push("scale")
      list.push("rotation")
    }
    return list
  }

  function sectionCount(section) {
    if (section === "arrangement") return layoutPreview.length + 2
    if (section === "workspaces") return workspaceNumbers.length
    if (section === "refreshRate") return refreshRateOptions.length
    if (section === "rotation") return rotationOptions.length
    if (section === "scale") return scaleValues.length
    if (section === "presets") return 4
    if (section === "monitors") return displays.length
    return 0
  }

  function sectionIsSingleRow(section) {
    return section === "brightness" || section === "textsize"
      || section === "workspaces" || section === "resolution" || section === "scale"
      || section === "rotation" || section === "refreshRate" || section === "presets"
  }

  function sectionIsSlider(section) {
    return section === "brightness" || section === "textsize" || section === "resolution"
  }

  function sectionFirstIndex(section) {
    if (sectionIsSlider(section)) return -1
    if (section === "refreshRate")
      return Math.max(0, refreshRateOptions.findIndex(function(o) { return o.value === refreshRateValue }))
    if (section === "rotation") return Math.max(0, Number(rotationValue))
    if (section === "scale") return Math.max(0, activeScaleIndex())
    return 0
  }

  function moveCursor(delta) {
    arrangementEditing = false
    var sections = visibleSections
    if (!sections || sections.length === 0) return
    var sIdx = sections.indexOf(focusSection)
    if (sIdx < 0) {
      focusSection = sections[0]
      selectedIndex = sectionFirstIndex(focusSection)
      return
    }
    var inSingleRow = sectionIsSingleRow(focusSection)
    var max = inSingleRow ? 0 : sectionCount(focusSection) - 1

    if (delta > 0) {
      if (!inSingleRow && selectedIndex < max) { selectedIndex = selectedIndex + 1; return }
      if (sIdx < sections.length - 1) {
        focusSection = sections[sIdx + 1]
        selectedIndex = sectionFirstIndex(focusSection)
      }
    } else {
      if (!inSingleRow && selectedIndex > 0) { selectedIndex = selectedIndex - 1; return }
      if (sIdx > 0) {
        var prev = sections[sIdx - 1]
        focusSection = prev
        // Coming up from below — land on the last navigable row of the prev
        // section, or its sentinel for single-row sections.
        selectedIndex = sectionIsSingleRow(prev) ? sectionFirstIndex(prev) : sectionCount(prev) - 1
      }
    }
  }

  // h/l walks horizontal option rows. Sliders handle horizontal movement
  // separately through their adjustment helpers.
  function moveCursorH(delta) {
    if (sectionIsSlider(focusSection) || focusSection === "monitors"
        || focusSection === "arrangement") return
    var count = sectionCount(focusSection)
    var next = selectedIndex + delta
    if (next < 0) next = 0
    if (next > count - 1) next = count - 1
    selectedIndex = next
  }

  function adjustBrightness(delta) {
    if (focusSection !== "brightness") return
    if (!brightnessAvailable) return
    setBrightness(root.brightnessPercent + delta)
  }

  function activateCursor() {
    if (focusSection === "arrangement") {
      if (selectedIndex < layoutPreview.length) {
        selectedMonitorName = layoutPreview[selectedIndex].name
        if (!layoutConfirmationPending && !layoutApplying)
          arrangementEditing = !arrangementEditing
      } else if (selectedIndex === layoutPreview.length) {
        secondaryLayoutAction()
      } else if (selectedIndex === layoutPreview.length + 1) {
        primaryLayoutAction()
      }
      return
    }
    if (focusSection === "resolution") {
      resolutionDropdown.toggle()
      return
    }
    if (focusSection === "rotation" && selectedIndex >= 0 && selectedIndex < rotationOptions.length) {
      setRotation(rotationOptions[selectedIndex].value)
      return
    }
    if (focusSection === "refreshRate" && selectedIndex >= 0 && selectedIndex < refreshRateOptions.length) {
      setRefreshRate(refreshRateOptions[selectedIndex].value)
      return
    }
    if (focusSection === "workspaces" && selectedIndex >= 0
        && selectedIndex < workspaceNumbers.length) {
      toggleWorkspaceForSelected(workspaceNumbers[selectedIndex])
      return
    }
    if (focusSection === "scale" && selectedIndex >= 0 && selectedIndex < scaleValues.length) {
      setScale(scaleValues[selectedIndex])
      return
    }
    if (focusSection === "presets") {
      applyTopologyPreset(["internal", "extend", "external", "duplicate"][selectedIndex])
      return
    }
    if (focusSection === "monitors" && selectedIndex >= 0 && selectedIndex < displays.length) {
      var d = displays[selectedIndex]
      if (d && d.enabled) selectedMonitorName = d.name
    }
    // brightness: no separate action; the slider value is the action.
  }

  function clampCursor() {
    var sections = visibleSections
    if (!sections || !sections.length) return
    if (sections.indexOf(focusSection) < 0) {
      focusSection = sections[0]
      selectedIndex = sectionFirstIndex(focusSection)
      return
    }
    var count = sectionCount(focusSection)
    if (sectionIsSingleRow(focusSection)) {
      // brightness/text size use the -1 sentinel; scale clamps into the presets.
      if (sectionIsSlider(focusSection)) selectedIndex = -1
      else if (selectedIndex < 0 || selectedIndex >= count) selectedIndex = 0
      return
    }
    if (count === 0) {
      var sIdx = sections.indexOf(focusSection)
      focusSection = sIdx > 0 ? sections[sIdx - 1] : sections[0]
      selectedIndex = sectionFirstIndex(focusSection)
      return
    }
    if (selectedIndex > count - 1) selectedIndex = count - 1
    if (selectedIndex < 0) selectedIndex = 0
  }

  // Keep the keyboard-focused row inside the viewport when the panel grows
  // taller than its allotted height (lots of displays). Mirrors audio's
  // ensureCursorVisible helper.
  // Keep the keyboard-focused control inside its column when a column is
  // taller than the panel (large text sizes, many displays).
  function ensureCursorVisible(item) {
    if (!item) return
    var flick = item.parent
    while (flick && flick.contentY === undefined) flick = flick.parent
    if (!flick || !flick.contentItem) return
    var pt = item.mapToItem(flick.contentItem, 0, 0)
    var margin = Style.space(6)
    if (pt.y < flick.contentY + margin) flick.contentY = Math.max(0, pt.y - margin)
    else if (pt.y + item.height > flick.contentY + flick.height - margin)
      flick.contentY = pt.y + item.height + margin - flick.height
  }

  function brightnessIpc(percent) {
    var value = Number(percent)
    root.setBrightness(value)
    return "got " + root.pendingBrightnessPercent
  }

  function stateIpc() {
    return JSON.stringify({
      brightness: root.brightnessPercent,
      brightnessAvailable: root.brightnessAvailable,
      focusedMonitor: root.focusedMonitor,
      selectedMonitor: root.selectedMonitorName,
      displaySettingsDirty: root.settingsDirty,
      stagedDisplaySettings: root.stagedDisplaySettings,
      workspaceAssignments: root.stagedWorkspaceAssignments,
      workspaceAssignmentsDirty: root.workspaceDirty,
      expandedSettingsSection: root.expandedSettingsSection,
      scale: root.monitorScale,
      expandedLayoutOpen: root.expandedLayoutOpen,
      layoutConfirmationPending: root.layoutConfirmationPending,
      layoutConfirmationSeconds: root.layoutConfirmationSeconds,
      confirmationScreen: root.confirmationScreenName,
      confirmationWorkspace: root.confirmationWorkspaceId,
      confirmationTargetScreen: root.confirmationTargetScreenName,
      displays: root.displays,
      restoreDiagnostics: {
        instanceCreatedAt: root.instanceCreatedAt,
        reloadEvents: root.reloadEventCount,
        restoreRuns: root.reloadRestoreRunCount,
        lastRestoreExit: root.reloadRestoreLastExit,
        ownsIpc: root.ownsDisplayIpc
      }
    })
  }

  IpcHandler {
    enabled: root.ownsDisplayIpc
    target: "omarchy.monitor"

    function brightness(percent: string): string { return root.brightnessIpc(percent) }
    function state(): string { return root.stateIpc() }
    function open() { root.open() }
    function close() { root.close() }
    function toggle() { root.toggle() }
    function show() { root.open() }
    function hide() { root.close() }
    function fullscreen() {
      root.open()
      Qt.callLater(root.openExpandedLayout)
    }
    function revert(): string {
      if (emergencyRevertProc.running) return "busy"
      emergencyRevertProc.command = ["bash", root.pluginScript("apply-layout.sh"),
                                     "revert-pending"]
      emergencyRevertProc.running = true
      return "reverting"
    }
  }

  function refresh(reason) {
    var intent = DisplayEvents.refreshIntent(reason)
    if (stateProc.running) {
      if (intent.queueIfBusy) {
        root.stateRefreshQueued = true
        if (intent.bypassDebounce) {
          root.stateRefreshQueuedReason = "manual"
        } else if (intent.settleTransition
                   && root.stateRefreshQueuedReason !== "manual") {
          root.stateRefreshQueuedReason = "hotplug"
        } else if (!root.stateRefreshQueuedReason) {
          root.stateRefreshQueuedReason = "poll"
        }
      }
      return
    }
    if (intent.bypassDebounce) hotplugQuietTimer.stop()
    root.stateProcHotplugScan = intent.settleTransition
    root.scanEventAt = root.displayEventState.lastEventAt
    root.scanRestorePermission = DisplayEvents.autoRestorePermission({
      dirty: root.layoutDirty || SessionGuard.anyBlocked() || reason === "manual", dragging: root.layoutDragging,
      editing: root.arrangementEditing || root.expandedLayoutOpen,
      applying: root.layoutApplying, pending: root.layoutConfirmationPending,
      profileBusy: root.profileActionBusy
    })
    stateProc.running = true
  }

  function showIdentifyOverlay() {
    if (root.enabledDisplayCount < 1) return
    root.identifyActive = true
    identifyTimer.restart()
  }

  function noteDisplayHardwareEvent() {
    root.burstRestoreBlocked = root.burstRestoreBlocked || SessionGuard.anyBlocked()
    root.displayEventState = DisplayEvents.noteHardwareEvent(
      root.displayEventState, Date.now())
    root.displayTransitioning = root.displayEventState.transitioning
    hotplugQuietTimer.interval = Math.max(
      1, root.displayEventState.refreshAt - Date.now())
    hotplugQuietTimer.restart()
  }

  function handleMonitorSnapshot(raw) {
    var snapshot = null
    try { snapshot = JSON.parse(String(raw || "{}")) } catch (e) {}
    if (!snapshot || !snapshot.hardwareGeneration) return
    root.healthSnapshot = snapshot
    if (!root.displayEventState.transitioning
        && root.displayEventState.hardwareGeneration !== snapshot.hardwareGeneration) {
      root.burstRestoreBlocked = root.burstRestoreBlocked || root.scanRestorePermission === "block"
      root.noteDisplayHardwareEvent()
      return
    }
    if (root.displayEventState.transitioning
        && (!root.stateProcHotplugScan || root.scanEventAt !== root.displayEventState.lastEventAt
            || Date.now() - root.displayEventState.lastEventAt < DisplayEvents.QUIET_WINDOW_MS)) {
      hotplugQuietTimer.interval = DisplayEvents.QUIET_WINDOW_MS
      hotplugQuietTimer.restart()
      return
    }

    var settled = DisplayEvents.settleSnapshot(
      root.displayEventState, snapshot.hardwareGeneration)
    root.displayEventState = settled.state
    root.displayTransitioning = settled.state.transitioning
    if (settled.hardwareChanged && root.layoutConfirmationPending)
      root.cancelStaleDisplayPreview()
    if (root.ownsDisplayIpc && !restoreLayoutProc.running
        && root.observedRestoreGeneration !== snapshot.hardwareGeneration) {
      root.observedRestoreGeneration = snapshot.hardwareGeneration
      var permission = DisplayEvents.autoRestorePermission({
        dirty: root.layoutDirty || SessionGuard.anyBlocked() || root.burstRestoreBlocked || root.scanRestorePermission === "block",
        dragging: root.layoutDragging, editing: root.arrangementEditing || root.expandedLayoutOpen,
        applying: root.layoutApplying, pending: root.layoutConfirmationPending,
        profileBusy: root.profileActionBusy
      })
      restoreLayoutProc.command = ["bash", root.pluginScript("apply-layout.sh"),
        "auto-restore", snapshot.hardwareGeneration, permission]
      root.autoRestoreOwnsBusy = permission === "allow"
      if (root.autoRestoreOwnsBusy) root.layoutApplying = true
      restoreLayoutProc.running = true
    }
    root.burstRestoreBlocked = false
  }

  function cancelStaleDisplayPreview() {
    if (!root.layoutConfirmationPending || !root.layoutTransactionId) return
    if (root.layoutApplying) {
      root.staleCancellationRequested = true
      return
    }
    root.staleCancellationRequested = false
    root.layoutProcessAction = "cancel"
    root.layoutApplying = true
    root.layoutError = ""
    layoutApplyProc.command = ["bash", root.pluginScript("apply-layout.sh"),
                               "cancel-stale", root.layoutTransactionId]
    layoutApplyProc.running = true
  }

  function updateProfiles(raw) {
    var state = null
    try { state = JSON.parse(String(raw || "{}")) } catch (e) {}
    if (!state) return
    root.profiles = Array.isArray(state.profiles) ? state.profiles : []
    root.activeProfileId = String(state.activeProfileId || "")
    root.activeTopologyVariants = state.activeVariants || ({})
    root.storedAnchorDisplayName = Topology.validAnchor(
      root.displays, String(state.activeAnchor || ""))
    if (!root.anchorDirty)
      root.anchorDisplayName = root.storedAnchorDisplayName
    root.profileMatch = state.match || ({ status: "new", profileId: "", matches: [] })
  }

  function selectAnchorDisplay(name) {
    var selected = Topology.validAnchor(root.displays, String(name || ""))
    if (!selected || selected === root.anchorDisplayName) return
    root.anchorDisplayName = selected
    root.anchorDirty = selected !== root.storedAnchorDisplayName
    root.layoutError = ""
  }

  function runProfileAction(action, profileId, value) {
    if (root.profileActionBusy || !profileId) return
    var command = ["bash", root.pluginScript("apply-layout.sh"),
                   "profile-action", action, profileId]
    if (value !== undefined && value !== null) command.push(String(value))
    root.profileActionBusy = true
    profileActionProc.command = command
    profileActionProc.running = true
  }

  function requestProfileDelete(profileId) {
    root.pendingProfileDeleteId = profileId
    profileDeleteDialog.opened = true
  }

  function setBrightness(value) {
    var percent = Model.clampBrightness(value)
    root.brightnessPercent = percent
    root.pendingBrightnessPercent = percent

    if (setBrightnessProc.running) {
      root.brightnessSetQueued = true
      return
    }

    root.brightnessSetQueued = false
    setBrightnessProc.command = ["omarchy-brightness-display", "--no-osd", "--monitor", root.focusedMonitor, percent + "%"]
    setBrightnessProc.running = true
  }

  function previewBrightness(value) {
    root.brightnessPercent = Model.clampBrightness(value)
    brightnessDebounce.restart()
  }

  function showBrightnessOsd(percent) {
    if (!bar || !bar.shell) return
    bar.shell.summon("omarchy.osd", JSON.stringify({
      icon: "brightness",
      value: percent
    }))
  }

  function normalizeScale(scale) {
    return Model.normalizeScale(scale)
  }

  function activeScaleIndex() {
    if (selectedDisplayPreview)
      return Model.matchingScaleIndex(scaleValues, selectedDisplayPreview.scale,
                                      selectedDisplayPreview.width,
                                      selectedDisplayPreview.height)
    return -1
  }

  function effectiveScale(scale) {
    if (selectedDisplayPreview)
      return Model.cleanScale(scale, selectedDisplayPreview.width,
                              selectedDisplayPreview.height)
    return normalizeScale(scale)
  }

  // Playful mood-name for a given brightness percent. Bands intentionally
  // span ~10–20 points so casual tweaks change the label, while small
  // nudges within one band don't.
  function brightnessName(percent) {
    return Model.brightnessName(percent)
  }

  function updateDisplays(displaysJson) {
    var parsed = Model.parseDisplays(displaysJson)
    root.displays = parsed.displays
    root.enabledDisplayCount = parsed.enabledDisplayCount
    if (root.settingsDirty)
      root.stagedDisplaySettings = Model.retainDisplaySettings(
        parsed.displays, root.stagedDisplaySettings)
    var selectedStillAvailable = false
    var fallback = ""
    for (var i = 0; i < parsed.displays.length; i++) {
      var display = parsed.displays[i]
      if (!display || !display.enabled) continue
      if (!fallback || display.focused) fallback = display.name
      if (display.name === root.selectedMonitorName) selectedStillAvailable = true
    }
    if (!selectedStillAvailable) root.selectedMonitorName = fallback
    root.scheduleDisplayLayoutReset()
  }

  function updateWorkspaceAssignments(workspacesJson, rulesJson) {
    var workspaces = []
    var rules = []
    try { workspaces = JSON.parse(String(workspacesJson || "[]")) } catch (e) {}
    try { rules = JSON.parse(String(rulesJson || "[]")) } catch (e) {}
    var preserveStaged = root.workspaceDirty
    var hasMonitorRules = false
    for (var i = 0; i < rules.length; i++) {
      if (rules[i] && String(rules[i].monitor || "") !== "") {
        hasMonitorRules = true
        break
      }
    }
    var assignments = Model.workspaceAssignments(
      root.displays, workspaces, rules, root.workspaceNumbers.length)
    root.workspaceAssignmentsActual = assignments
    if (!preserveStaged) {
      root.stagedWorkspaceAssignments = assignments
      root.workspaceAssignmentsManaged = hasMonitorRules
    }
  }

  function workspacesForMonitor(name) {
    return Model.workspacesForMonitor(root.stagedWorkspaceAssignments, name)
  }

  function workspaceOwner(workspace) {
    return String(root.stagedWorkspaceAssignments[String(workspace)] || "")
  }

  function toggleWorkspaceForSelected(workspace) {
    if (!root.selectedDisplay || root.layoutApplying || root.layoutConfirmationPending) return
    root.stagedWorkspaceAssignments = Model.toggleWorkspaceAssignment(
      root.stagedWorkspaceAssignments, workspace, root.selectedDisplay.name)
    root.layoutError = ""
  }

  function workspacePayload() {
    return root.workspaceAssignmentsManaged || root.workspaceDirty
      ? root.stagedWorkspaceAssignments : ({})
  }

  function toggleSettingsSection(section) {
    var next = Model.nextExpandedSection(
      root.expandedSettingsSection, section)
    root.expandedSettingsSection = next
    if (next === "workspaces") {
      root.focusSection = "workspaces"
      root.selectedIndex = 0
    } else if (next === "display") {
      root.focusSection = root.resolutionOptions.length > 0 ? "resolution" : "scale"
      root.selectedIndex = root.focusSection === "resolution" ? -1 : 0
    } else if (next === "monitors") {
      root.focusSection = "monitors"
      root.selectedIndex = 0
    }
    Qt.callLater(root.clampCursor)
  }

  function pluginScript(name) {
    return String(Qt.resolvedUrl(name)).replace(/^file:\/\//, "")
  }

  function resetDisplayLayout() {
    var canvas = root.activeArrangementCanvas
    if (!canvas || canvas.width <= 0 || canvas.height <= 0) return
    var fitted = Model.fitDisplayLayout(root.displays, canvas.width,
                                        canvas.height, root.activeLayoutPadding,
                                        root.activeLayoutUtilization)
    root.layoutPreview = fitted.items
    root.layoutScale = fitted.scale
    root.arrangementDirty = false
    root.stagedDisplaySettings = ({})
    root.stagedWorkspaceAssignments = root.workspaceAssignmentsActual
    root.anchorDisplayName = Topology.validAnchor(root.displays, root.storedAnchorDisplayName)
    root.anchorDirty = false
    root.layoutDragging = false
    root.arrangementEditing = false
    root.layoutError = ""
  }

  function refitDisplayLayout() {
    var canvas = root.activeArrangementCanvas
    if (!canvas || canvas.width <= 0 || canvas.height <= 0) return
    var fitted = Model.refitDisplayLayout(root.previewDisplays, root.layoutPreview,
                                          canvas.width, canvas.height,
                                          root.activeLayoutPadding,
                                          root.activeLayoutUtilization)
    root.layoutPreview = fitted.items
    root.layoutScale = fitted.scale
  }

  function openExpandedLayout() {
    if (root.expandedLayoutOpen || root.enabledDisplayCount < 2) return
    root.expandedLayoutOpen = true
    root.cursorActive = true
    root.focusSection = "arrangement"
    if (root.selectedIndex < 0 || root.selectedIndex >= root.layoutPreview.length)
      root.selectedIndex = 0
    root.arrangementEditing = false
    Qt.callLater(root.refitDisplayLayout)
  }

  function closeExpandedLayout() {
    if (!root.expandedLayoutOpen) return
    if (root.layoutConfirmationPending) root.revertDisplayLayout()
    root.expandedLayoutOpen = false
    root.arrangementEditing = false
    Qt.callLater(root.refitDisplayLayout)
  }

  function shouldAutoResetDisplayLayout() {
    return Model.shouldAutoResetDisplayLayout({
      dirty: root.layoutDirty,
      dragging: root.layoutDragging,
      confirmationPending: root.layoutConfirmationPending,
      applying: root.layoutApplying
    })
  }

  function scheduleDisplayLayoutReset() {
    if (!root.shouldAutoResetDisplayLayout()) return
    Qt.callLater(function() {
      if (root.shouldAutoResetDisplayLayout()) root.resetDisplayLayout()
    })
  }

  function beginDisplayDrag() {
    if (root.layoutConfirmationPending || root.layoutApplying) return
    root.layoutDragging = true
    root.arrangementDirty = true
    root.layoutError = ""
  }

  function finishDisplayDrag(name, canvasX, canvasY) {
    if (!root.layoutDragging) return
    root.moveDisplay(name, canvasX, canvasY)
    root.layoutDragging = false
  }

  // Every move lands edge-to-edge with the other displays (never a gap the
  // cursor cannot cross, never an overlap); see Model.moveDisplayInCanvas.
  function moveDisplay(name, canvasX, canvasY, alignPixels) {
    if (root.layoutConfirmationPending || root.layoutApplying) return
    var canvas = root.activeArrangementCanvas
    if (!canvas) return
    root.arrangementDirty = true
    root.layoutPreview = Model.moveDisplayInCanvas(
      root.layoutPreview, name, canvasX, canvasY, root.layoutScale,
      root.activeLayoutPadding, canvas.width, canvas.height,
      alignPixels === undefined ? Style.space(12) : alignPixels)
    root.layoutError = ""
    // A drop left of or above everything goes negative; refit brings it back.
    Qt.callLater(root.refitDisplayLayout)
  }

  function nudgeSelectedDisplay(dx, dy) {
    if (root.selectedIndex < 0 || root.selectedIndex >= root.layoutPreview.length) return
    var item = root.layoutPreview[root.selectedIndex]
    // No alignment pull for arrow keys, or a step off an aligned edge would
    // snap straight back.
    root.moveDisplay(item.name, item.x + dx * Style.space(4), item.y + dy * Style.space(4), 0)
  }

  function selectAdjacentDisplay(direction) {
    root.cursorActive = true
    root.focusSection = "arrangement"
    root.arrangementEditing = false
    root.selectedIndex = Model.cycleDisplayIndex(
      root.selectedIndex, root.layoutPreview.length, direction)
    if (root.selectedIndex >= 0 && root.selectedIndex < root.layoutPreview.length)
      root.selectedMonitorName = root.layoutPreview[root.selectedIndex].name
  }

  function activeWorkspaceForScreen(screenName) {
    var wanted = String(screenName || "")
    var monitors = Hyprland.monitors.values
    for (var i = 0; i < monitors.length; i++) {
      var monitor = monitors[i]
      if (!monitor || String(monitor.name || "") !== wanted
          || !monitor.activeWorkspace) continue
      var workspace = Math.floor(Number(monitor.activeWorkspace.id))
      return isFinite(workspace) && workspace > 0 ? workspace : 0
    }
    return 0
  }

  function beginDisplayPreview(proposed, previous, scope, preset, workspaceOverride) {
    if (root.layoutApplying || root.layoutConfirmationPending) return
    if (proposed.length < 1 || previous.length < 1) {
      root.layoutError = "Could not build valid display settings"
      return
    }
    // Whatever built the proposal (drag, scale, resolution, rotation, enable,
    // preset), displays reach Hyprland touching and never overlapping.
    proposed = Model.snapTopologyPayload(proposed, previous)
    var anchor = Topology.validAnchor(proposed, root.anchorDisplayName)
    proposed = Topology.relativeToAnchor(proposed, anchor)
    root.anchorDisplayName = anchor
    root.layoutTransactionId = "display-" + Date.now()
    root.confirmationScreenName = panel.screen
      ? String(panel.screen.name || "") : String(root.focusedMonitor || "")
    root.confirmationWorkspaceId = root.activeWorkspaceForScreen(
      root.confirmationScreenName)
    root.layoutProcessAction = "preview"
    root.layoutTransactionScope = scope || "layout"
    root.layoutApplying = true
    root.layoutError = ""
    var workspaces = workspaceOverride === undefined
      ? root.workspacePayload() : workspaceOverride
    layoutApplyProc.command = ["bash", root.pluginScript("apply-layout.sh"),
                               "preview", root.layoutTransactionId,
                               JSON.stringify(proposed), JSON.stringify(previous),
                               JSON.stringify(workspaces),
                               root.layoutTransactionScope, anchor, String(preset || ""),
                               root.confirmationScreenName,
                               String(root.confirmationWorkspaceId)]
    layoutApplyProc.running = true
  }

  function applyTopologyPreset(preset) {
    if (root.layoutApplying || root.layoutConfirmationPending) return
    if (preset === "duplicate") {
      var duplicate = root.duplicatePlan
      if (!duplicate.changed || !duplicate.valid) {
        root.layoutError = duplicate.reason || "Duplicate is unavailable"
        return
      }
      root.anchorDisplayName = duplicate.source
      root.layoutError = ""
      root.beginDisplayPreview(
        duplicate.proposed, duplicate.previous, "topology", "duplicate",
        Topology.workspacePayloadForPreset(
          root.workspacePayload(), duplicate.proposed, duplicate.source))
      return
    }
    var transaction = Topology.preparePresetPreview(
      root.displays, root.stagedDisplaySettings, preset,
      root.activeTopologyVariants ? root.activeTopologyVariants[preset] : null)
    if (!transaction.changed || !transaction.valid) {
      root.layoutError = transaction.reason || "This display preset is unavailable"
      return
    }
    root.anchorDisplayName = Topology.validAnchor(transaction.proposed, transaction.anchor)
    var workspaces = transaction.restored
      ? transaction.workspaces
      : Topology.workspacePayloadForPreset(
          root.workspacePayload(), transaction.proposed, root.anchorDisplayName)
    root.layoutError = ""
    root.beginDisplayPreview(
      transaction.proposed, transaction.previous, "topology", preset, workspaces)
  }

  function recoverDisplayConfirmation(raw) {
    var pending = Model.parsePendingDisplayTransaction(raw)
    if (!pending) return false
    root.layoutTransactionId = pending.id
    root.layoutTransactionScope = pending.scope
    root.confirmationScreenName = pending.originScreen
    root.confirmationWorkspaceId = pending.originWorkspace
    root.layoutConfirmationSeconds = pending.remainingSeconds
    root.layoutConfirmationPending = true
    layoutConfirmationTimer.restart()
    Qt.callLater(root.refitDisplayLayout)
    return true
  }

  function applyDisplayLayout() {
    if (!root.layoutDirty || root.layoutApplying || root.layoutConfirmationPending
        || root.layoutPreview.length < 1) return
    var canvas = root.activeArrangementCanvas
    if (!canvas) return
    var positions = Model.normalizeDisplayLayout(root.layoutPreview)
    var proposed = Topology.withPositions(
      Topology.buildTopologyPayload(root.displays, root.stagedDisplaySettings), positions)
    var previous = Topology.buildTopologyPayload(root.displays, {})
    root.beginDisplayPreview(proposed, previous, "layout")
  }

  function saveWorkspaceAssignments() {
    if (!root.workspaceDirty || root.layoutApplying || root.layoutConfirmationPending) return
    var monitors = Topology.buildTopologyPayload(root.previewDisplays, root.stagedDisplaySettings)
    if (monitors.length < 1) {
      root.layoutError = "Could not build current display settings"
      return
    }
    root.layoutApplying = true
    root.layoutError = ""
    workspaceApplyProc.command = ["bash", root.pluginScript("apply-layout.sh"),
                                  "save-workspaces", JSON.stringify(monitors),
                                  JSON.stringify(root.stagedWorkspaceAssignments),
                                  root.anchorDisplayName]
    workspaceApplyProc.running = true
  }

  function keepDisplayLayout(profileChoice, profileId) {
    if (!root.layoutConfirmationPending || root.layoutApplying || !root.layoutTransactionId) return
    var status = String((root.profileMatch || {}).status || "new")
    if ((status === "weak" || status === "ambiguous") && !profileChoice) {
      root.layoutError = "Identify and map uncertain displays before keeping this profile."
      return
    }
    if (status === "moved" && !profileChoice) {
      root.layoutError = "Choose Update profile or Save as new in Profiles."
      root.profileSectionOpen = true
      return
    }
    root.layoutProcessAction = "keep"
    root.layoutApplying = true
    root.layoutError = ""
    layoutApplyProc.command = ["bash", root.pluginScript("apply-layout.sh"),
                               "keep", root.layoutTransactionId]
    if (profileChoice && profileId)
      layoutApplyProc.command.push(profileChoice, profileId)
    layoutApplyProc.running = true
  }

  function revertDisplayLayout() {
    if (!root.layoutConfirmationPending || root.layoutApplying || !root.layoutTransactionId) return
    root.layoutProcessAction = "revert"
    root.layoutApplying = true
    root.layoutError = ""
    layoutApplyProc.command = ["bash", root.pluginScript("apply-layout.sh"),
                               "revert", root.layoutTransactionId]
    layoutApplyProc.running = true
  }

  function secondaryLayoutAction() {
    if (root.layoutConfirmationPending) root.revertDisplayLayout()
    else root.resetDisplayLayout()
  }

  function primaryLayoutAction() {
    if (root.layoutConfirmationPending) root.keepDisplayLayout()
    else if (root.workspaceDirty && !root.arrangementDirty && !root.settingsDirty
             && !root.anchorDirty)
      root.saveWorkspaceAssignments()
    else root.applyDisplayLayout()
  }

  function toggleDisplay(name, enabled) {
    if (!name) return
    if (enabled && root.enabledDisplayCount <= 1) return
    if (root.layoutApplying || root.layoutConfirmationPending) return

    var transaction = Topology.prepareTogglePreview(
      root.previewDisplays, root.stagedDisplaySettings, name)
    if (!transaction.changed) return
    if (!transaction.valid) {
      root.layoutError = transaction.reason
      return
    }
    root.displaySettingsBeforePreview = root.stagedDisplaySettings
    root.stagedDisplaySettings = transaction.stagedSettings
    root.layoutError = ""
    Qt.callLater(root.refitDisplayLayout)
    root.beginDisplayPreview(transaction.proposed, transaction.previous, "settings")
  }

  function setScale(scale) {
    if (!root.selectedDisplayPreview) return
    var cleaned = Number(Model.cleanScale(scale, root.selectedDisplayPreview.width,
                                          root.selectedDisplayPreview.height))
    if (!isFinite(cleaned) || cleaned <= 0) return
    root.stageMonitorSetting({ scale: cleaned })
  }

  function setRotation(value) {
    var transform = Number(value)
    if (!isFinite(transform) || Math.floor(transform) !== transform
        || transform < 0 || transform > 3) return
    root.stageMonitorSetting({ transform: transform })
  }

  function setResolution(value) {
    if (!root.selectedDisplay) return
    var mode = Model.parseDisplayMode(value)
    if (!mode) return
    var rates = Model.refreshChoices(root.selectedDisplay.availableModes,
      root.selectedDisplay.advertisedModes || root.selectedDisplay.availableModes,
      mode.width, mode.height)
    if (rates.length === 0) return
    var current = Number(root.selectedDisplayPreview.refreshRate)
    var pick = null
    for (var i = 0; i < rates.length; i++) {
      if (!rates[i].edidOnly && Math.abs(rates[i].refreshRate - current) <= 0.5) { pick = rates[i]; break }
    }
    if (!pick) pick = rates.filter(function(r) { return !r.edidOnly })[0] || null
    if (!pick) {
      // Only EDID timings exist for this resolution: start with the gentlest.
      var gentle = rates.filter(function(r) { return r.refreshRate >= 50 })
      pick = gentle.length ? gentle[gentle.length - 1] : rates[rates.length - 1]
    }
    var cleanedScale = Number(Model.cleanScale(root.selectedDisplayPreview.scale,
                                                mode.width, mode.height))
    root.stageMonitorSetting({
      width: mode.width,
      height: mode.height,
      refreshRate: pick.refreshRate,
      scale: cleanedScale > 0 ? cleanedScale : 1
    })
  }

  function applyRecommendedMode() {
    var recommendation = root.modeInsight.recommendation
    if (!recommendation || !root.selectedDisplayPreview) return
    var cleanedScale = Number(Model.cleanScale(root.selectedDisplayPreview.scale,
                                                recommendation.width, recommendation.height))
    root.stageMonitorSetting({
      width: recommendation.width,
      height: recommendation.height,
      refreshRate: recommendation.refreshRate,
      scale: cleanedScale > 0 ? cleanedScale : 1
    })
  }

  function setRefreshRate(value) {
    var refreshRate = Number(value)
    if (!isFinite(refreshRate) || refreshRate <= 0) return
    root.stageMonitorSetting({ refreshRate: refreshRate })
  }

  function stageMonitorSetting(overrides) {
    if (!root.selectedDisplay || root.layoutApplying || root.layoutConfirmationPending) return
    var transaction = Model.prepareDisplaySettingPreview(
      root.displays, root.stagedDisplaySettings, root.selectedDisplay.name, overrides,
      function(displays, staged) {
        return Topology.buildTopologyPayload(displays, staged)
      })
    if (!transaction.changed) return
    root.displaySettingsBeforePreview = root.stagedDisplaySettings
    root.stagedDisplaySettings = transaction.stagedSettings
    root.layoutError = ""
    Qt.callLater(root.refitDisplayLayout)
    root.beginDisplayPreview(transaction.proposed, transaction.previous, "settings")
  }

  // ---- Text size (shell base font + GTK text-scaling, via one CLI) ----
  function nearestTextStop(px) {
    var best = 0
    var bestDist = 1e9
    for (var i = 0; i < textSizeStops.length; i++) {
      var d = Math.abs(textSizeStops[i] - px)
      if (d < bestDist) { bestDist = d; best = i }
    }
    return best
  }

  // Effective stop index: the pending choice while a change is in flight,
  // otherwise whatever Style's live base-size rounds to.
  function currentTextIndex() {
    return textSizePreviewIndex >= 0 ? textSizePreviewIndex : nearestTextStop(Style.font.baseSize)
  }

  // px shown in the header: the pending stop if any, else the true base-size
  // (which may be an off-notch value set from the CLI).
  function displayedTextPx() {
    return textSizePreviewIndex >= 0 ? textSizeStops[textSizePreviewIndex] : Style.font.baseSize
  }

  function setTextSize(px) {
    textScaleProc.command = ["omarchy-display-text-size", String(px)]
    if (!textScaleProc.running) textScaleProc.running = true
  }

  function adjustTextSize(deltaSteps) {
    var idx = currentTextIndex() + deltaSteps
    if (idx < 0) idx = 0
    if (idx > textSizeStops.length - 1) idx = textSizeStops.length - 1
    markReflowing()
    textSizePreviewIndex = idx
    setTextSize(textSizeStops[idx])
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: {
    SessionGuard.setBlocked(root.sessionGuardId, root.blocksAutoRestore)
    root.refresh()
    pendingTransactionProc.running = true
    // A shell restart or plugin reload sees the same displays as before, so
    // the hotplug path does not run. Put the remembered layout back anyway in
    // case the displays were reset while the shell was away.
    startupRestoreTimer.restart()
  }

  Timer {
    id: startupRestoreTimer
    interval: 3000
    repeat: false
    onTriggered: configReloadRestoreTimer.restart()
  }

  // KeyboardPanel primes focus at open-time, so SUPER-bound IPC summons land
  // with j/k ready to navigate. Keep a default landing point, but don't paint
  // the cursor until hover or the first navigation key.
  onOpenedChanged: {
    if (opened) {
      arrangementEditing = false
      layoutError = ""
      refresh()
      focusSection = displays.length > 0 ? "monitors" : "textsize"
      selectedIndex = focusSection === "monitors"
        ? Math.max(0, displays.findIndex(function(d) { return d && d.name === selectedMonitorName }))
        : -1
      cursorActive = false
    } else {
      root.expandedLayoutOpen = false
      // Keep the transaction alive when the panel is recreated by a monitor
      // change. The watchdog timer remains the safety fallback; a recovered
      // panel will reopen and expose Keep/Revert again.
    }
  }

  onBrightnessAvailableChanged: clampCursor()
  onDisplaysChanged: clampCursor()
  onScaleValuesChanged: clampCursor()
  onVisibleSectionsChanged: clampCursor()

  // Quickshell screen-list changes are the event-driven fast path. The event
  // model waits for a 1-second quiet window (3-second maximum) before asking
  // Hyprland for a stable snapshot. The udev DRM watch below covers hotplugs
  // that never reach the screen list.
  Connections {
    target: Quickshell
    function onScreensChanged() { root.noteDisplayHardwareEvent() }
  }

  // Saving anything under ~/.config/hypr, or changing the Omarchy theme,
  // reloads Hyprland, which resets every monitor to monitors.lua without any
  // hardware change. Put the remembered layout back once the reload settles.
  // The backend refuses while a preview is pending and is idempotent, so every
  // per-screen instance may ask; the restore lock serialises them.
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = event ? String(event.name || "") : ""
      if (name.indexOf("monitoradded") === 0 || name.indexOf("monitorremoved") === 0) {
        root.noteDisplayHardwareEvent()
        return
      }
      if (name !== "configreloaded") return
      root.reloadEventCount++
      configReloadRestoreTimer.restart()
    }
  }

  // Kernel DRM hotplug events cover what Quickshell.screens cannot see: a
  // connector that comes up while Hyprland keeps it disabled, or an EDID swap.
  // One idle udevadm per session (the IPC owner) replaces the old 5 s poll.
  Process {
    id: drmHotplugWatch
    command: ["stdbuf", "-oL", "udevadm", "monitor", "--udev", "--subsystem-match=drm"]
    running: root.ownsDisplayIpc
    stdout: SplitParser {
      onRead: function(line) {
        if (/\schange\s.*\(drm\)/.test(line)) root.noteDisplayHardwareEvent()
      }
    }
    onExited: if (root.ownsDisplayIpc) drmHotplugRespawn.restart()
  }

  Timer {
    id: drmHotplugRespawn
    interval: 5000
    repeat: false
    onTriggered: if (root.ownsDisplayIpc) drmHotplugWatch.running = true
  }

  Timer {
    id: configReloadRestoreTimer
    interval: 2000
    repeat: false
    onTriggered: {
      // Only wait out this panel's own apply or preview; retry shortly.
      if (reloadRestoreProc.running || root.layoutApplying || root.layoutConfirmationPending) {
        restart()
        return
      }
      root.reloadRestoreRunCount++
      reloadRestoreProc.running = true
    }
  }
  property string instanceCreatedAt: new Date().toISOString()
  property int reloadEventCount: 0
  property int reloadRestoreRunCount: 0
  property int reloadRestoreLastExit: -1

  Process {
    id: reloadRestoreProc
    command: ["bash", root.pluginScript("apply-layout.sh"), "restore-after-reload"]
    onExited: function(exitCode) {
      root.reloadRestoreLastExit = exitCode
      root.refresh("manual")
    }
  }

  Timer {
    id: hotplugQuietTimer
    interval: DisplayEvents.QUIET_WINDOW_MS
    repeat: false
    onTriggered: {
      if (DisplayEvents.refreshDue(root.displayEventState, Date.now()))
        root.refresh("hotplug")
      else if (root.displayEventState.transitioning) {
        interval = Math.max(1, root.displayEventState.refreshAt - Date.now())
        restart()
      }
    }
  }

  Timer {
    id: identifyTimer
    interval: 5000
    repeat: false
    onTriggered: root.identifyActive = false
  }

  // Only poll while the panel is open (external brightness changes stay live
  // there). With it closed, hotplug is event-driven: Quickshell.screens,
  // Hyprland monitor events, configreloaded, and the udev DRM watch above.
  Timer {
    interval: 5000
    running: root.opened || root.layoutConfirmationPending
    repeat: true
    onTriggered: root.refresh()
  }

  Process {
    id: stateProc
    command: ["bash", root.pluginScript("state.sh")]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text || "").split("\n")
        var brightness = String(lines[0] || "").trim()
        root.brightnessAvailable = brightness !== "unavailable" && brightness !== ""
        root.brightnessPercent = root.brightnessAvailable ? Math.max(0, Math.min(100, parseInt(brightness, 10))) : 0
        root.internalMonitor = String(lines[1] || "").trim()
        root.externalMonitor = String(lines[2] || "").trim()
        root.internalEnabled = String(lines[3] || "").trim() !== ""
        root.mirrorEnabled = String(lines[4] || "").trim() === root.externalMonitor && root.externalMonitor !== ""
        root.focusedMonitor = String(lines[5] || "").trim()
        root.monitorScale = root.normalizeScale(String(lines[6] || "").trim())
        root.updateDisplays(String(lines[7] || "[]").trim())
        root.updateWorkspaceAssignments(String(lines[8] || "[]").trim(),
                                        String(lines[9] || "[]").trim())
        root.recoverDisplayConfirmation(String(lines[10] || "{}").trim())
        root.handleMonitorSnapshot(String(lines[11] || "{}").trim())
        root.updateProfiles(String(lines[12] || "{}").trim())
      }
    }
    onRunningChanged: {
      if (running || !root.stateRefreshQueued) return
      var queuedReason = root.stateRefreshQueuedReason || "poll"
      root.stateRefreshQueued = false
      root.stateRefreshQueuedReason = ""
      Qt.callLater(function() { root.refresh(queuedReason) })
    }
  }

  Timer {
    id: brightnessDebounce
    interval: 180
    repeat: false
    onTriggered: root.setBrightness(root.brightnessPercent)
  }

  Process {
    id: setBrightnessProc
    stdout: StdioCollector { waitForEnd: true }
    // Do NOT call refresh() after a brightness set completes. The local
    // brightnessPercent we just wrote is authoritative; re-reading via
    // `omarchy-brightness-display` races the hardware/driver and can
    // return an empty string, which the parser then coerces to 0 —
    // visible as a "bounce to zero" after h/l keypresses. External
    // brightness changes are still picked up by the 5s periodic refresh,
    // the open-time refresh, and Component.onCompleted.
    onRunningChanged: {
      if (running) return
      if (root.brightnessSetQueued) {
        root.setBrightness(root.pendingBrightnessPercent)
      }
    }
  }

  Process {
    id: actionProc
    stdout: StdioCollector { waitForEnd: true }
    onRunningChanged: if (!running) root.refresh()
  }

  Process {
    id: emergencyRevertProc
    stderr: StdioCollector { id: emergencyRevertError; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        var message = Topology.explainBackendReport(emergencyRevertError.text)
        root.layoutError = message || "Emergency display revert failed"
      }
      root.layoutConfirmationPending = false
      root.layoutConfirmationSeconds = 0
      root.layoutTransactionId = ""
      root.confirmationScreenName = ""
      root.confirmationWorkspaceId = 0
      layoutConfirmationTimer.stop()
      root.refresh("manual")
    }
  }

  Process {
    id: healthCopyProc
    onExited: function(exitCode) {
      root.healthCopyStatus = exitCode === 0 ? "Sanitized report copied."
        : "Copy failed. Check that wl-copy and the Wayland clipboard are available."
    }
  }

  Process {
    id: restoreLayoutProc
    stderr: StdioCollector { id: restoreLayoutError; waitForEnd: true }
    onExited: function(exitCode) {
      if (root.autoRestoreOwnsBusy) root.layoutApplying = false
      root.autoRestoreOwnsBusy = false
      if (exitCode !== 0) {
        var message = String(restoreLayoutError.text || "").trim()
        root.layoutError = message || "Could not restore saved display layout"
      }
      root.refresh()
    }
  }

  Process {
    id: pendingTransactionProc
    command: ["bash", root.pluginScript("apply-layout.sh"), "pending"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var pending = String(text || "{}").trim()
        if (root.recoverDisplayConfirmation(pending)) root.refresh("manual")
      }
    }
  }

  Process {
    id: layoutApplyProc
    stderr: StdioCollector { id: layoutApplyError; waitForEnd: true }
    onExited: function(exitCode) {
      var completedAction = root.layoutProcessAction
      root.layoutApplying = false
      if (exitCode === 0) {
        if (completedAction === "preview") {
          if (root.layoutTransactionScope === "layout") root.arrangementDirty = false
          root.arrangementEditing = false
          root.layoutConfirmationPending = true
          root.layoutConfirmationSeconds = root.layoutConfirmationDuration
          layoutConfirmationTimer.restart()
          root.refresh()
          if (root.staleCancellationRequested)
            Qt.callLater(root.cancelStaleDisplayPreview)
          // The compact confirmation overlay is independent of the bar icon,
          // so close the full menu before per-screen bars are recreated.
          if (root.opened) Qt.callLater(root.close)
        } else {
          root.stagedDisplaySettings = ({})
          root.displaySettingsBeforePreview = ({})
          if (completedAction === "keep") {
            root.workspaceAssignmentsManaged = Object.keys(root.stagedWorkspaceAssignments).length > 0
            root.storedAnchorDisplayName = root.anchorDisplayName
          } else {
            root.anchorDisplayName = Topology.validAnchor(
              root.displays, root.storedAnchorDisplayName)
          }
          root.anchorDirty = false
          if (root.layoutTransactionScope === "layout") root.arrangementDirty = false
          root.layoutConfirmationPending = false
          root.layoutConfirmationSeconds = 0
          root.layoutTransactionId = ""
          root.layoutTransactionScope = ""
          root.confirmationScreenName = ""
          root.confirmationWorkspaceId = 0
          layoutConfirmationTimer.stop()
          root.staleCancellationRequested = false
          if (completedAction === "cancel")
            root.layoutError = "Displays changed. The preview was canceled and the available layout was restored."
          else if (completedAction === "keep") {
            var adjustment = Topology.explainBackendReport(layoutApplyError.text)
            if (adjustment) root.layoutError = adjustment
          }
          root.refresh()
        }
      } else {
        var message = Topology.explainBackendReport(layoutApplyError.text)
        root.layoutError = message || "Could not apply display layout"
        if (completedAction === "preview") {
          if (root.layoutTransactionScope === "settings") {
            root.stagedDisplaySettings = root.displaySettingsBeforePreview
            root.displaySettingsBeforePreview = ({})
            Qt.callLater(root.refitDisplayLayout)
          }
          root.layoutTransactionId = ""
          root.layoutTransactionScope = ""
          root.confirmationScreenName = ""
          root.confirmationWorkspaceId = 0
        }
      }
      root.layoutProcessAction = ""
    }
  }

  Process {
    id: workspaceApplyProc
    stderr: StdioCollector { id: workspaceApplyError; waitForEnd: true }
    onExited: function(exitCode) {
      root.layoutApplying = false
      if (exitCode === 0) {
        root.workspaceAssignmentsManaged = Object.keys(root.stagedWorkspaceAssignments).length > 0
        root.workspaceAssignmentsActual = root.stagedWorkspaceAssignments
        root.storedAnchorDisplayName = root.anchorDisplayName
        root.anchorDirty = false
        root.refresh()
      } else {
        var message = String(workspaceApplyError.text || "").trim()
        root.layoutError = message || "Could not save workspace assignments"
      }
    }
  }

  Process {
    id: profileActionProc
    stderr: StdioCollector { id: profileActionError; waitForEnd: true }
    onExited: function(exitCode) {
      root.profileActionBusy = false
      if (exitCode !== 0) {
        var message = String(profileActionError.text || "").trim()
        root.layoutError = message || "Could not update display profile"
      }
      root.refresh()
    }
  }

  Timer {
    id: layoutConfirmationTimer
    interval: 1000
    repeat: true
    onTriggered: {
      var next = Model.advanceDisplayConfirmation(root.layoutConfirmationSeconds)
      root.layoutConfirmationSeconds = next.remaining
      if (next.expired) {
        stop()
        root.revertDisplayLayout()
      }
    }
  }

  // Applies text size via the CLI, which rewrites the shell override file;
  // Style picks the new base-size up through its own file watch, so there's
  // nothing to refresh here.
  Process {
    id: textScaleProc
    stdout: StdioCollector { waitForEnd: true }
  }

  // Clears the hover-suppression flag once the reflow triggered by a text-size
  // change has settled.
  Timer {
    id: reflowSettle
    interval: 300
    repeat: false
    onTriggered: root.reflowingText = false
  }

  // Once Style's base-size catches up to the pending choice, drop the preview
  // so the slider tracks the live value again. The change itself reflows the
  // panel, so suppress hover for a beat while it lands.
  Connections {
    target: Style
    function onFontBaseSizeChanged() {
      root.markReflowing()
      if (root.textSizePreviewIndex >= 0
          && root.nearestTextStop(Style.font.baseSize) === root.textSizePreviewIndex)
        root.textSizePreviewIndex = -1
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: Quickshell.screens.length > 1 ? "󰍺" : "󰍹"
    onPressed: function(b) { root.toggle() }
    onWheelMoved: function(delta) {
      if (!root.brightnessAvailable) return
      var wheel = Util.wheelSteps(root.wheelAccumulator, delta)
      root.wheelAccumulator = wheel.remainder
      if (wheel.steps === 0) return
      root.setBrightness(root.brightnessPercent + wheel.steps * 5)
      root.showBrightnessOsd(root.brightnessPercent)
    }
  }
  // Whole panel on one wide card: displays and layout on the left, the
  // arrangement in the centre, the selected display's settings on the right.
  // Sized to fit a 1280×720 screen with the bar; columns scroll only when the
  // text size makes them taller than the card.
  readonly property int panelWidthCap: 1240
  readonly property int panelHeightCap: 660
  readonly property color mutedForeground: Qt.darker(root.bar.foreground, 1.4)

  function displayCaption(display) {
    if (!display) return ""
    if (!display.enabled) return display.name + " · off"
    if (display.mirrorOf && display.mirrorOf !== "none") return display.name + " · mirroring " + display.mirrorOf
    return display.name + " · " + display.width + "×" + display.height + " @ "
      + Model.refreshLabel(Number(display.refreshRate), [])
  }

  function presetHint() {
    if (root.displays.length < 2) return "Connect another display to extend or mirror."
    if (root.duplicatePlan.valid !== true) return root.duplicatePlan.summary || "Mirror is unavailable."
    return ""
  }

  function arrangementHintText() {
    if (root.layoutConfirmationPending) return "CONFIRM CHANGES"
    if (root.layoutApplying) return "APPLYING…"
    if (root.arrangementEditing) return "ARROWS MOVE · ENTER DROPS"
    if (root.layoutDirty) return "CHANGES READY"
    return root.enabledDisplayCount > 1 ? "DRAG TO ARRANGE" : ""
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(1200), root.panelWidthCap)
    contentHeight: panel.fittedContentHeight(Style.space(600), root.panelHeightCap)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (root.arrangementEditing && root.focusSection === "arrangement") {
          root.nudgeSelectedDisplay(dx, dy)
          return
        }
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dy !== 0) root.moveCursor(dy)
        else if (dx !== 0) {
          if (root.focusSection === "brightness") root.adjustBrightness(dx * 5)
          else if (root.focusSection === "textsize") root.adjustTextSize(dx)
          else if (root.focusSection === "arrangement") root.selectAdjacentDisplay(dx)
          else root.moveCursorH(dx)
        }
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: {
        if (root.arrangementEditing) root.arrangementEditing = false
        else root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Item {
        id: layoutRoot
        anchors.fill: parent
        readonly property real gap: Style.space(18)
        readonly property real sideWidth: Math.max(Style.space(250), Math.min(Style.space(300), width * 0.25))
        readonly property real settingsWidth: Math.max(Style.space(290), Math.min(Style.space(350), width * 0.29))

        // ---------- Header ----------
        Item {
          id: header
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, headerActions.implicitHeight)
          height: implicitHeight

          Text {
            id: heroIcon
            text: root.displays.length > 1 ? "󰍺" : "󰍹"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.display
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: headerActions.left
            anchors.rightMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              text: "Displays"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Text {
              width: parent.width
              text: {
                var parts = []
                parts.push(root.enabledDisplayCount + " of " + root.displays.length + " on")
                var preset = root.currentTopologyPreset
                if (root.displays.length > 1)
                  parts.push(preset === "duplicate" ? "mirrored" : (preset === "internal" ? "built-in only"
                    : (preset === "external" ? "external only" : "extended")))
                var status = String((root.profileMatch || {}).status || "new")
                parts.push(status === "exact" ? "saved profile" : (status === "new" ? "new setup" : "profile " + status))
                if (root.displayTransitioning) parts.push("connections changing…")
                return parts.join(" · ").toUpperCase()
              }
              color: root.mutedForeground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
            }
          }

          Row {
            id: headerActions
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.xs

            Button {
              text: root.identifyActive ? "Identifying…" : "Identify"
              iconText: "󰍹"
              tooltipText: "Show each display's name on its screen"
              bordered: true
              enabled: root.enabledDisplayCount > 0
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              fontSize: Style.font.caption
              onClicked: root.showIdentifyOverlay()
            }
            Button {
              text: "Rescan"
              iconText: "󰑐"
              tooltipText: "Re-read connected displays and their modes"
              bordered: true
              enabled: !stateProc.running
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              fontSize: Style.font.caption
              onClicked: root.refresh("manual")
            }
            Button {
              text: "Full screen"
              iconText: "󰊓"
              tooltipText: "Arrange displays in a full-screen editor"
              bordered: true
              enabled: root.enabledDisplayCount > 1 && !root.layoutApplying
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              fontSize: Style.font.caption
              onClicked: root.openExpandedLayout()
            }
          }
        }

        Rectangle {
          id: headerRule
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: header.bottom
          anchors.topMargin: Style.space(12)
          height: Math.max(1, Style.normalBorderWidth)
          color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.18)
        }

        // ---------- Left column: displays, layout, brightness, text ----------
        Flickable {
          id: leftScroll
          anchors.left: parent.left
          anchors.top: headerRule.bottom
          anchors.topMargin: Style.space(14)
          anchors.bottom: parent.bottom
          width: layoutRoot.sideWidth
          contentHeight: leftColumn.implicitHeight
          clip: true
          interactive: contentHeight > height
          boundsBehavior: Flickable.StopAtBounds

          Column {
            id: leftColumn
            width: leftScroll.width
            spacing: Style.space(14)

            Column {
              width: parent.width
              spacing: Style.space(6)

              ColumnHeader { text: "DISPLAYS"; caption: root.displayTransitioning ? "CHANGING…" : "CLICK TO SELECT" }

              Repeater {
                model: root.displays

                CursorSurface {
                  id: displayCard
                  required property var modelData
                  required property int index
                  readonly property bool isSelected: root.selectedDisplay && modelData.name === root.selectedDisplay.name
                  readonly property bool canToggle: !modelData.enabled || root.enabledDisplayCount > 1

                  width: parent.width
                  implicitHeight: cardRow.implicitHeight + Style.space(14)
                  hasCursor: root.cursorActive && root.focusSection === "monitors" && root.selectedIndex === index
                  onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(displayCard)
                  current: isSelected
                  bordered: true
                  foreground: root.bar.foreground
                  opacity: modelData.enabled ? 1 : 0.7

                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: displayCard.modelData.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onContainsMouseChanged: if (containsMouse && !root.reflowingText) {
                      root.cursorActive = true
                      root.focusSection = "monitors"
                      root.selectedIndex = displayCard.index
                    }
                    onClicked: if (displayCard.modelData.enabled) root.selectedMonitorName = displayCard.modelData.name
                  }

                  Row {
                    id: cardRow
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Style.space(10)
                    anchors.rightMargin: Style.space(6)
                    spacing: Style.space(10)

                    Text {
                      text: displayCard.modelData.transport === "internal" ? "󰌢" : "󰍹"
                      color: root.bar.foreground
                      font.family: root.bar.fontFamily
                      font.pixelSize: Style.font.title
                      width: Style.space(22)
                      horizontalAlignment: Text.AlignHCenter
                      anchors.verticalCenter: parent.verticalCenter
                    }

                    Column {
                      width: parent.width - Style.space(22) - cardSwitch.width - parent.spacing * 2
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: Style.space(1)

                      Text {
                        width: parent.width
                        text: Model.displayLabel(displayCard.modelData)
                        textFormat: Text.PlainText
                        color: root.bar.foreground
                        font.family: root.bar.fontFamily
                        font.pixelSize: Style.font.body
                        font.bold: displayCard.isSelected
                        elide: Text.ElideRight
                      }
                      Text {
                        width: parent.width
                        text: root.displayCaption(displayCard.modelData)
                        textFormat: Text.PlainText
                        color: root.mutedForeground
                        font.family: root.bar.fontFamily
                        font.pixelSize: Style.font.caption
                        elide: Text.ElideRight
                      }
                    }

                    ToggleSwitch {
                      id: cardSwitch
                      anchors.verticalCenter: parent.verticalCenter
                      checked: displayCard.modelData.enabled
                      interactive: displayCard.canToggle && !root.settingsBusy
                      cursorRing: false
                      foreground: root.bar.foreground
                      onToggled: root.toggleDisplay(displayCard.modelData.name, displayCard.modelData.enabled)

                      PanelToolTip {
                        visible: cardSwitch.containsMouse
                        text: !displayCard.canToggle ? "At least one display must stay on"
                          : (displayCard.modelData.enabled ? "Turn this display off" : "Turn this display on")
                      }
                    }
                  }
                }
              }
            }

            Column {
              width: parent.width
              spacing: Style.space(6)

              ColumnHeader { text: "LAYOUT" }

              Grid {
                id: presetGrid
                width: parent.width
                columns: 2
                spacing: Style.spacing.xs
                readonly property real cellWidth: (width - spacing) / 2

                Repeater {
                  model: [
                    { preset: "extend", label: "Extend", available: root.extendPresetAvailable,
                      tip: "Use every display as one large desktop" },
                    { preset: "duplicate", label: "Mirror", available: root.duplicatePlan.valid === true,
                      tip: "Show the same picture on every display" },
                    { preset: "internal", label: "Built-in only", available: root.internalPresetAvailable,
                      tip: "Turn off external displays" },
                    { preset: "external", label: "External only", available: root.externalPresetAvailable,
                      tip: "Turn off the built-in display" }
                  ]

                  Button {
                    required property var modelData
                    required property int index
                    width: presetGrid.cellWidth
                    text: modelData.label
                    tooltipText: modelData.tip
                    bordered: true
                    active: root.displays.length > 1 && root.currentTopologyPreset === modelData.preset
                    hasCursor: root.cursorActive && root.focusSection === "presets" && root.selectedIndex === index
                    enabled: !root.settingsBusy && modelData.available
                    foreground: root.bar.foreground
                    fontFamily: root.bar.fontFamily
                    fontSize: Style.font.caption
                    onClicked: root.applyTopologyPreset(modelData.preset)
                    onHovered: function(isHovered) {
                      if (!isHovered || root.reflowingText) return
                      root.cursorActive = true
                      root.focusSection = "presets"
                      root.selectedIndex = index
                    }
                  }
                }
              }

              Caption { visible: text !== ""; text: root.presetHint() }
            }

            Column {
              width: parent.width
              spacing: Style.space(4)

              ColumnHeader {
                text: "BRIGHTNESS"
                caption: root.brightnessAvailable
                  ? Math.round(brightnessSlider.dragging ? brightnessSlider.liveValue : root.brightnessPercent) + "%"
                  : ""
              }

              CursorSurface {
                id: brightnessRow
                visible: root.brightnessAvailable
                width: parent.width
                height: brightnessSlider.implicitHeight + Style.spacing.controlGap
                hasCursor: root.cursorActive && root.focusSection === "brightness"
                onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(brightnessRow)
                foreground: root.bar.foreground
                outline: true

                PanelSlider {
                  id: brightnessSlider
                  bar: root.bar
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(6)
                  anchors.rightMargin: Style.space(6)
                  minimum: 1
                  maximum: 100
                  step: 1
                  value: root.brightnessPercent
                  integer: true
                  onMoved: function(v) { root.previewBrightness(v) }
                  onReleased: function(v) {
                    brightnessDebounce.stop()
                    root.setBrightness(v)
                  }
                }

                HoverHandler {
                  onHoveredChanged: if (hovered && !root.reflowingText) {
                    root.cursorActive = true
                    root.focusSection = "brightness"
                    root.selectedIndex = -1
                  }
                }
              }

              Caption {
                visible: !root.brightnessAvailable
                text: "The focused display has no software brightness control. Use the monitor's own buttons."
              }
            }

            Column {
              width: parent.width
              spacing: Style.space(4)

              ColumnHeader {
                text: "TEXT SIZE"
                caption: (textSizeSlider.dragging
                  ? root.textSizeStops[Math.round(textSizeSlider.liveValue)]
                  : root.displayedTextPx()) + "px"
              }

              CursorSurface {
                id: textSizeRow
                width: parent.width
                height: textSizeSlider.implicitHeight + Style.spacing.controlGap
                hasCursor: root.cursorActive && root.focusSection === "textsize"
                onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(textSizeRow)
                foreground: root.bar.foreground
                outline: true

                PanelSlider {
                  id: textSizeSlider
                  bar: root.bar
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(6)
                  anchors.rightMargin: Style.space(6)
                  minimum: 0
                  maximum: root.textSizeStops.length - 1
                  step: 1
                  integer: true
                  tickCount: root.textSizeStops.length
                  value: root.currentTextIndex()
                  onReleased: function(v) { root.setTextSize(root.textSizeStops[Math.round(v)]) }
                }

                HoverHandler {
                  onHoveredChanged: if (hovered && !root.reflowingText) {
                    root.cursorActive = true
                    root.focusSection = "textsize"
                    root.selectedIndex = -1
                  }
                }
              }
            }
          }
        }

        ColumnRule { anchors.left: leftScroll.right; anchors.leftMargin: layoutRoot.gap / 2 }

        // ---------- Centre: arrangement, workspaces, profiles ----------
        Item {
          id: centerColumn
          anchors.left: leftScroll.right
          anchors.leftMargin: layoutRoot.gap
          anchors.right: rightScroll.left
          anchors.rightMargin: layoutRoot.gap
          anchors.top: headerRule.bottom
          anchors.topMargin: Style.space(14)
          anchors.bottom: parent.bottom

          Column {
            id: centerTop
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            spacing: Style.space(6)

            BorderSurface {
              visible: root.setupSuggested
              width: parent.width
              implicitHeight: setupColumn.implicitHeight + Style.space(16)
              color: Style.selectedFillFor(root.bar.foreground, Color.accent)
              borderSpec: Border.controlSpec("selected", root.bar.foreground, Color.accent)
              radius: Style.cornerRadius

              Column {
                id: setupColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(10)
                anchors.rightMargin: Style.space(10)
                spacing: Style.space(6)

                Text {
                  width: parent.width
                  text: "New display setup. Pick a starting point; every option previews first."
                  textFormat: Text.PlainText
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.Wrap
                }

                Row {
                  width: parent.width
                  spacing: Style.spacing.xs
                  readonly property real cellWidth: (width - spacing * 2) / 3

                  Button {
                    width: parent.cellWidth
                    text: "Recommended Extend"
                    tooltipText: root.recommendedExtend.valid ? root.recommendedExtend.summary : root.recommendedExtend.reason
                    bordered: true
                    enabled: root.recommendedExtend.valid && !root.assistanceBusy
                    foreground: root.bar.foreground
                    fontFamily: root.bar.fontFamily
                    fontSize: Style.font.caption
                    onClicked: root.applyRecommendedSetup("extend")
                  }
                  Button {
                    width: parent.cellWidth
                    text: "Mirror"
                    tooltipText: root.recommendedMirror.valid ? root.recommendedMirror.summary : root.recommendedMirror.reason
                    bordered: true
                    enabled: root.recommendedMirror.valid && !root.assistanceBusy
                    foreground: root.bar.foreground
                    fontFamily: root.bar.fontFamily
                    fontSize: Style.font.caption
                    onClicked: root.applyRecommendedSetup("mirror")
                  }
                  Button {
                    width: parent.cellWidth
                    text: "Arrange manually"
                    tooltipText: "Dismiss this suggestion and arrange the displays yourself"
                    bordered: true
                    foreground: root.bar.foreground
                    fontFamily: root.bar.fontFamily
                    fontSize: Style.font.caption
                    onClicked: root.dismissedSetupGeneration = String(root.healthSnapshot.hardwareGeneration || "")
                  }
                }
              }
            }

            ColumnHeader { text: "ARRANGEMENT"; caption: root.arrangementHintText() }
          }

          BorderSurface {
            id: arrangementCanvas
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: centerTop.bottom
            anchors.topMargin: Style.space(6)
            anchors.bottom: centerBottom.top
            anchors.bottomMargin: Style.space(10)
            clip: true
            radius: Style.cornerRadius
            color: Style.normalFillFor(root.bar.foreground)
            borderSpec: Border.controlSpec("normal", root.bar.foreground, Color.accent)
            onWidthChanged: root.scheduleDisplayLayoutReset()
            onHeightChanged: root.scheduleDisplayLayoutReset()

            Repeater {
              model: root.layoutPreview

              DisplayLayoutTile {
                required property var modelData
                required property int index

                display: modelData
                tileIndex: index
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                workspaceNumbers: root.workspacesForMonitor(modelData.name)
                selected: modelData.name === root.selectedMonitorName
                hasCursor: root.cursorActive && root.focusSection === "arrangement" && root.selectedIndex === index
                editing: root.arrangementEditing && root.focusSection === "arrangement" && root.selectedIndex === index
                interactionEnabled: !root.layoutConfirmationPending && !root.layoutApplying
                onDragBegan: root.beginDisplayDrag()
                onDragFinished: function(name, canvasX, canvasY) { root.finishDisplayDrag(name, canvasX, canvasY) }
                onPointerSelected: {
                  root.cursorActive = true
                  root.focusSection = "arrangement"
                  root.selectedIndex = index
                  if (dragStarted) root.arrangementEditing = false
                }
                onMonitorSelected: root.selectedMonitorName = modelData.name
              }
            }

            Text {
              visible: root.enabledDisplayCount < 2
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.bottom: parent.bottom
              anchors.bottomMargin: Style.space(10)
              text: "Turn on or connect another display to arrange them."
              color: root.mutedForeground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Column {
            id: centerBottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            spacing: Style.space(8)

            BorderSurface {
              visible: root.layoutConfirmationPending
              width: parent.width
              implicitHeight: confirmationText.implicitHeight + Style.spacing.controlPaddingY * 2
              color: Style.selectedFillFor(root.bar.foreground, Color.accent)
              borderSpec: Border.controlSpec("selected", root.bar.foreground, Color.accent)
              radius: Style.cornerRadius

              Text {
                id: confirmationText
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.spacing.controlPaddingX
                anchors.rightMargin: Style.spacing.controlPaddingX
                text: "Keep these display settings? Reverting in " + root.layoutConfirmationSeconds + " seconds."
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
              }
            }

            Text {
              visible: root.layoutError !== ""
              width: parent.width
              text: root.layoutError
              textFormat: Text.PlainText
              color: root.bar.urgent
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.Wrap
              maximumLineCount: 3
              elide: Text.ElideRight
            }

            Row {
              width: parent.width
              spacing: Style.spacing.xs
              readonly property real cellWidth: (width - spacing) / 2

              Button {
                width: parent.cellWidth
                text: root.layoutConfirmationPending
                  ? (root.layoutProcessAction === "revert" ? "Reverting…" : "Revert")
                  : "Reset"
                enabled: !root.layoutApplying && (root.layoutConfirmationPending || root.layoutDirty)
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                fontSize: Style.font.caption
                bordered: true
                hasCursor: root.cursorActive && root.focusSection === "arrangement"
                  && root.selectedIndex === root.layoutPreview.length
                onClicked: root.secondaryLayoutAction()
                onHovered: function(isHovered) {
                  if (!isHovered) return
                  root.cursorActive = true
                  root.focusSection = "arrangement"
                  root.selectedIndex = root.layoutPreview.length
                }
              }

              Button {
                width: parent.cellWidth
                text: root.layoutConfirmationPending
                  ? (root.layoutProcessAction === "keep" ? "Keeping…"
                     : root.displayConfirmationPolicy.kind === "choose-profile" ? "Choose a profile below"
                     : root.displayConfirmationPolicy.kind === "identify-first" ? "Identify first"
                     : "Keep (" + root.layoutConfirmationSeconds + ")")
                  : (root.layoutApplying ? "Applying…" : "Apply")
                enabled: !root.layoutApplying && (root.layoutConfirmationPending || root.layoutDirty)
                active: root.layoutDirty || root.layoutConfirmationPending
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                fontSize: Style.font.caption
                bordered: true
                hasCursor: root.cursorActive && root.focusSection === "arrangement"
                  && root.selectedIndex === root.layoutPreview.length + 1
                onClicked: root.primaryLayoutAction()
                onHovered: function(isHovered) {
                  if (!isHovered) return
                  root.cursorActive = true
                  root.focusSection = "arrangement"
                  root.selectedIndex = root.layoutPreview.length + 1
                }
              }
            }

            Column {
              visible: !!root.selectedDisplay
              width: parent.width
              spacing: Style.space(6)

              ColumnHeader {
                text: "WORKSPACES"
                caption: (root.selectedDisplay ? "ON " + Model.displayLabel(root.selectedDisplay).toUpperCase() + " · " : "")
                  + (root.workspaceDirty ? "PRESS APPLY" : "CLICK TO ASSIGN")
              }

              Row {
                id: workspaceRow
                width: parent.width
                spacing: Style.spacing.xs
                readonly property real cellWidth: (width - spacing * (root.workspaceNumbers.length - 1)) / root.workspaceNumbers.length

                Repeater {
                  model: root.workspaceNumbers

                  Button {
                    required property int modelData
                    required property int index
                    width: workspaceRow.cellWidth
                    text: modelData === 10 ? "0" : String(modelData)
                    tooltipText: "Toggle workspace " + (modelData === 10 ? "10 (0 key)" : modelData)
                      + " for the selected display"
                    selected: root.workspaceOwner(modelData) === root.selectedMonitorName
                    hasCursor: root.cursorActive && root.focusSection === "workspaces" && root.selectedIndex === index
                    enabled: !root.settingsBusy
                    foreground: root.bar.foreground
                    fontFamily: root.bar.fontFamily
                    fontSize: Style.font.caption
                    horizontalPadding: Style.space(2)
                    verticalPadding: Style.space(6)
                    bordered: true
                    onClicked: root.toggleWorkspaceForSelected(modelData)
                    onHovered: function(isHovered) {
                      if (!isHovered || root.reflowingText) return
                      root.cursorActive = true
                      root.focusSection = "workspaces"
                      root.selectedIndex = index
                    }
                  }
                }
              }
            }

            Column {
              width: parent.width
              spacing: Style.space(6)

              Item {
                width: parent.width
                implicitHeight: Math.max(profilesHeader.implicitHeight, anchorDropdown.implicitHeight)

                ColumnHeader {
                  id: profilesHeader
                  width: parent.width - (anchorDropdown.visible
                    ? anchorDropdown.width + anchorLabel.implicitWidth + Style.space(18) : 0)
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  text: "PROFILES"
                  caption: {
                    var status = String((root.profileMatch || {}).status || "new")
                    return status === "exact" ? "MATCHES A SAVED PROFILE"
                      : status === "moved" ? "DISPLAYS MOVED PORTS"
                      : status === "weak" || status === "ambiguous" ? "IDENTIFY DISPLAYS"
                      : "REMEMBERED WHEN YOU KEEP"
                  }
                }

                Text {
                  id: anchorLabel
                  anchors.right: anchorDropdown.left
                  anchors.rightMargin: Style.space(6)
                  anchors.verticalCenter: parent.verticalCenter
                  visible: root.anchorOptions.length > 1
                  text: "Measure from"
                  color: root.mutedForeground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                }

                Dropdown {
                  id: anchorDropdown
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(110)
                  visible: root.anchorOptions.length > 1
                  showLabel: false
                  options: root.anchorOptions
                  value: root.anchorDisplayName
                  enabled: !root.profileActionBusy && !root.layoutConfirmationPending
                  foreground: root.bar.foreground
                  fontFamily: root.bar.fontFamily
                  onChanged: function(value) { root.selectAnchorDisplay(String(value)) }
                }
              }

              Caption {
                visible: root.profiles.length === 0
                text: "No profiles yet. Keep a layout and it comes back by itself whenever these displays connect."
              }

              ListView {
                id: profileList
                visible: root.profiles.length > 0
                width: parent.width
                height: Math.min(contentHeight, Style.space(92))
                clip: true
                spacing: Style.space(4)
                interactive: contentHeight > height
                boundsBehavior: Flickable.StopAtBounds
                model: root.profiles

                delegate: BorderSurface {
                  required property var modelData
                  width: profileList.width
                  implicitHeight: profileRow.implicitHeight + Style.space(8)
                  color: modelData.id === root.activeProfileId
                    ? Style.selectedFillFor(root.bar.foreground, Color.accent)
                    : Style.normalFillFor(root.bar.foreground)
                  borderSpec: Border.controlSpec(modelData.id === root.activeProfileId ? "selected" : "normal",
                                                 root.bar.foreground, Color.accent)
                  radius: Style.cornerRadius

                  Row {
                    id: profileRow
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Style.space(6)
                    anchors.rightMargin: Style.space(4)
                    spacing: Style.spacing.xs

                    TextField {
                      width: parent.width - profileActions.implicitWidth - parent.spacing
                      text: String(modelData.name || "")
                      enabled: !root.profileActionBusy
                      foreground: root.bar.foreground
                      onAccepted: if (text !== modelData.name) root.runProfileAction("rename", modelData.id, text)
                    }

                    Row {
                      id: profileActions
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: Style.spacing.xs

                      PanelActionButton {
                        iconText: "󰄬"
                        tooltipText: modelData.id === root.activeProfileId ? "Active profile" : "Use this profile"
                        enabled: !root.profileActionBusy && modelData.id !== root.activeProfileId
                        foreground: root.bar.foreground
                        onClicked: root.runProfileAction("select", modelData.id)
                      }
                      PanelActionButton {
                        iconText: "󰆏"
                        tooltipText: "Duplicate profile"
                        enabled: !root.profileActionBusy
                        foreground: root.bar.foreground
                        onClicked: root.runProfileAction("duplicate", modelData.id, modelData.name + " Copy")
                      }
                      PanelActionButton {
                        iconText: "󰆴"
                        tooltipText: "Delete profile"
                        enabled: !root.profileActionBusy
                        foreground: root.bar.foreground
                        hoverColor: Color.urgent
                        onClicked: root.requestProfileDelete(modelData.id)
                      }
                    }
                  }
                }
              }

              Row {
                width: parent.width
                visible: root.layoutConfirmationPending && String((root.profileMatch || {}).status) === "moved"
                spacing: Style.spacing.xs
                readonly property real cellWidth: (width - spacing) / 2

                Button {
                  width: parent.cellWidth
                  text: "Update profile"
                  bordered: true
                  enabled: !root.profileActionBusy
                  foreground: root.bar.foreground
                  fontFamily: root.bar.fontFamily
                  fontSize: Style.font.caption
                  onClicked: root.keepDisplayLayout("update-profile", root.profileMatch.profileId)
                }
                Button {
                  width: parent.cellWidth
                  text: "Save as new"
                  bordered: true
                  enabled: !root.profileActionBusy
                  foreground: root.bar.foreground
                  fontFamily: root.bar.fontFamily
                  fontSize: Style.font.caption
                  onClicked: root.keepDisplayLayout("fork-profile", root.profileMatch.profileId)
                }
              }
            }
          }
        }

        ColumnRule { anchors.right: rightScroll.left; anchors.rightMargin: layoutRoot.gap / 2 }

        // ---------- Right column: the selected display ----------
        Flickable {
          id: rightScroll
          anchors.right: parent.right
          anchors.top: headerRule.bottom
          anchors.topMargin: Style.space(14)
          anchors.bottom: parent.bottom
          width: layoutRoot.settingsWidth
          contentHeight: rightColumn.implicitHeight
          clip: true
          interactive: contentHeight > height
          boundsBehavior: Flickable.StopAtBounds

          Column {
            id: rightColumn
            width: rightScroll.width
            spacing: Style.space(12)

            Caption {
              visible: !root.selectedDisplay
              text: "Turn on a display to change its settings."
            }

            Column {
              visible: !!root.selectedDisplay
              width: parent.width
              spacing: Style.space(2)

              Text {
                width: parent.width
                text: root.selectedDisplay ? Model.displayLabel(root.selectedDisplay) : ""
                textFormat: Text.PlainText
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.subtitle
                font.bold: true
                elide: Text.ElideRight
              }
              Text {
                width: parent.width
                text: root.selectedDisplay
                  ? [root.selectedDisplay.name, Topology.transportLabel(root.selectedDisplay.transport),
                     root.modeInsight.nativeLabel ? "native " + root.modeInsight.nativeLabel : ""]
                      .filter(function(part) { return part }).join(" · ")
                  : ""
                textFormat: Text.PlainText
                color: root.mutedForeground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }
            }

            // Mode insight: what the monitor can do, what it is doing, and
            // the one click that gets it there.
            BorderSurface {
              id: insightCard
              visible: !!root.selectedDisplay && root.modeInsight.title !== ""
              width: parent.width
              implicitHeight: insightColumn.implicitHeight + Style.space(16)
              radius: Style.cornerRadius
              color: root.modeInsight.level === "ok" ? Style.normalFillFor(root.bar.foreground)
                : Style.selectedFillFor(root.bar.foreground, Color.accent)
              borderSpec: Border.controlSpec(root.modeInsight.level === "ok" ? "normal" : "selected",
                                             root.bar.foreground, Color.accent)

              Column {
                id: insightColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(10)
                anchors.rightMargin: Style.space(10)
                spacing: Style.space(6)

                Row {
                  width: parent.width
                  spacing: Style.space(8)

                  Text {
                    id: insightIcon
                    text: root.modeInsight.level === "ok" ? "󰄬"
                      : root.modeInsight.level === "limited" ? "󰀦"
                      : root.modeInsight.level === "suggest" ? "󰁔" : "󰋽"
                    color: root.modeInsight.level === "limited" ? root.bar.urgent : root.bar.foreground
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.body
                  }
                  Text {
                    width: parent.width - insightIcon.width - parent.spacing
                    text: root.modeInsight.title
                    textFormat: Text.PlainText
                    color: root.bar.foreground
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                    wrapMode: Text.Wrap
                  }
                }

                Caption { text: root.modeInsight.detail; color: root.bar.foreground }

                Button {
                  visible: !!root.modeInsight.recommendation
                  width: parent.width
                  text: root.modeInsight.recommendation
                    ? (root.modeInsight.recommendation.tryOnly ? "Try " : "Use ") + Model.formatMode(root.modeInsight.recommendation.width,
                        root.modeInsight.recommendation.height, root.modeInsight.recommendation.refreshRate)
                    : ""
                  iconText: "󰁔"
                  bordered: true
                  enabled: !root.settingsBusy
                  foreground: root.bar.foreground
                  fontFamily: root.bar.fontFamily
                  fontSize: Style.font.caption
                  onClicked: root.applyRecommendedMode()
                }
              }
            }

            BorderSurface {
              visible: !!root.selectedDisplay && !!root.selectedDisplay.mirrorOf && root.selectedDisplay.mirrorOf !== "none"
              width: parent.width
              implicitHeight: mirrorInfoText.implicitHeight + Style.spacing.controlPaddingY * 2
              color: Style.selectedFillFor(root.bar.foreground, Color.accent)
              borderSpec: Border.controlSpec("selected", root.bar.foreground, Color.accent)
              radius: Style.cornerRadius

              Text {
                id: mirrorInfoText
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.spacing.controlPaddingX
                anchors.rightMargin: Style.spacing.controlPaddingX
                text: "󰍺 Mirroring " + (root.selectedDisplay ? root.selectedDisplay.mirrorOf : "")
                textFormat: Text.PlainText
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
              }
            }

            Column {
              visible: !!root.selectedDisplay && root.resolutionOptions.length > 0
              width: parent.width
              spacing: Style.space(4)

              ColumnHeader { text: "RESOLUTION" }

              Dropdown {
                id: resolutionDropdown
                width: parent.width
                showLabel: false
                options: root.resolutionOptions
                value: root.resolutionValue
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                hasCursor: root.cursorActive && root.focusSection === "resolution"
                enabled: !root.settingsBusy
                onChanged: function(value) { root.setResolution(value) }
                onHovered: function(isHovered) {
                  if (!isHovered || root.reflowingText) return
                  root.cursorActive = true
                  root.focusSection = "resolution"
                  root.selectedIndex = -1
                }
                onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(this)
              }
            }

            Column {
              visible: !!root.selectedDisplay && root.refreshRateOptions.length > 0
              width: parent.width
              spacing: Style.space(4)

              ColumnHeader {
                text: "REFRESH RATE"
                caption: root.refreshRateOptions.some(function(o) { return o.edidOnly }) ? "* FROM EDID" : ""
              }

              Flow {
                id: refreshFlow
                width: parent.width
                spacing: Style.spacing.xs
                readonly property int perRow: Math.max(1, Math.min(root.refreshRateOptions.length, 4))
                readonly property real cellWidth: (width - spacing * (perRow - 1)) / perRow

                Repeater {
                  model: root.refreshRateOptions

                  Button {
                    required property var modelData
                    required property int index
                    width: refreshFlow.cellWidth
                    text: modelData.label + (modelData.edidOnly ? " *" : "")
                    tooltipText: modelData.edidOnly
                      ? "Read from the monitor's EDID. Hyprland did not offer it, so the connection may not carry it; the preview reverts on its own."
                      : Number(modelData.refreshRate).toFixed(2) + " Hz"
                    bordered: true
                    active: root.refreshRateValue === modelData.value
                    hasCursor: root.cursorActive && root.focusSection === "refreshRate" && root.selectedIndex === index
                    enabled: !root.settingsBusy
                    foreground: root.bar.foreground
                    fontFamily: root.bar.fontFamily
                    fontSize: Style.font.caption
                    horizontalPadding: Style.space(4)
                    onClicked: root.setRefreshRate(modelData.value)
                    onHovered: function(isHovered) {
                      if (!isHovered || root.reflowingText) return
                      root.cursorActive = true
                      root.focusSection = "refreshRate"
                      root.selectedIndex = index
                    }
                  }
                }
              }
            }

            Column {
              visible: !!root.selectedDisplay
              width: parent.width
              spacing: Style.space(4)

              ColumnHeader {
                text: "SCALE"
                caption: root.recommendedScaleValue
                  ? "SUGGESTED " + root.effectiveScale(root.recommendedScaleValue) + "x FOR THIS SIZE"
                  : "SIZE OF EVERYTHING ON SCREEN"
              }

              Grid {
                id: scaleRow
                width: parent.width
                columns: Math.max(1, root.scaleValues.length)
                spacing: Style.spacing.xs
                readonly property real cellWidth: root.scaleValues.length > 0
                  ? (width - spacing * (columns - 1)) / columns : 0

                Repeater {
                  model: root.scaleValues

                  ScalePill {
                    required property string modelData
                    required property int index
                    scaleValue: modelData
                    scaleIndex: index
                    width: scaleRow.cellWidth
                  }
                }
              }
            }

            Column {
              visible: !!root.selectedDisplay
              width: parent.width
              spacing: Style.space(4)

              ColumnHeader { text: "ROTATION" }

              Row {
                id: rotationRow
                width: parent.width
                spacing: Style.spacing.xs
                readonly property real cellWidth: (width - spacing * 3) / 4

                Repeater {
                  model: root.rotationOptions

                  Button {
                    required property var modelData
                    required property int index
                    width: rotationRow.cellWidth
                    text: modelData.label
                    tooltipText: modelData.tooltip
                    bordered: true
                    active: root.rotationValue === modelData.value
                    hasCursor: root.cursorActive && root.focusSection === "rotation" && root.selectedIndex === index
                    enabled: !root.settingsBusy
                    foreground: root.bar.foreground
                    fontFamily: root.bar.fontFamily
                    fontSize: Style.font.caption
                    horizontalPadding: Style.space(4)
                    onClicked: root.setRotation(modelData.value)
                    onHovered: function(isHovered) {
                      if (!isHovered || root.reflowingText) return
                      root.cursorActive = true
                      root.focusSection = "rotation"
                      root.selectedIndex = index
                    }
                  }
                }
              }
            }

            Column {
              visible: root.displays.length > 0
              width: parent.width
              spacing: Style.space(4)

              ColumnHeader {
                text: "DISPLAY HEALTH"
                caption: root.displayHealth.issues.length ? root.displayHealth.issues.length + " TO REVIEW" : "ALL GOOD"
              }

              Caption { text: root.healthCopyStatus || root.displayHealth.summary }

              Row {
                width: parent.width
                spacing: Style.spacing.xs
                readonly property real cellWidth: (width - spacing) / 2

                Button {
                  width: parent.cellWidth
                  text: "Copy report"
                  tooltipText: "Copies a report without display names, serials, profile names or paths"
                  bordered: true
                  enabled: !healthCopyProc.running
                  foreground: root.bar.foreground
                  fontFamily: root.bar.fontFamily
                  fontSize: Style.font.caption
                  onClicked: root.copyHealthReport()
                }
                Button {
                  width: parent.cellWidth
                  text: "Preview safe repair"
                  tooltipText: "Turns every display on side by side at advertised modes and clears mirroring. Reverts in 15 seconds unless kept."
                  bordered: true
                  enabled: root.displayHealth.repairable && !root.assistanceBusy
                  foreground: root.bar.foreground
                  fontFamily: root.bar.fontFamily
                  fontSize: Style.font.caption
                  onClicked: root.applyRecommendedSetup("extend")
                }
              }
            }
          }
        }
      }
    }
  }

  FullScreenArrangement {
    id: expandedWorkspace
    controller: root
    targetScreen: panel.screen
    foreground: root.bar.foreground
    urgent: root.bar.urgent
    fontFamily: root.bar.fontFamily
    onCloseRequested: root.closeExpandedLayout()
  }

  IdentifyOverlay {
    entries: root.identifyEntries
    displays: root.displays
    fontFamily: root.bar.fontFamily
    open: root.identifyActive
  }

  DisplayConfirmationOverlay {
    preferredScreenName: root.confirmationTargetScreenName
    remainingSeconds: root.layoutConfirmationSeconds
    busy: root.layoutApplying
    keepPolicy: root.displayConfirmationPolicy
    foreground: root.bar.foreground
    urgent: root.bar.urgent
    fontFamily: root.bar.fontFamily
    open: root.layoutConfirmationPending && root.ownsDisplayConfirmation
    onKeepRequested: function(profileChoice, profileId) {
      root.keepDisplayLayout(profileChoice, profileId)
    }
    onRevertRequested: root.revertDisplayLayout()
  }

  ConfirmDialog {
    id: profileDeleteDialog
    parent: keyCatcher
    anchors.fill: parent
    z: 100
    message: "Delete this display profile? The live display layout will not change."
    confirmText: "Delete"
    onCanceled: {
      opened = false
      root.pendingProfileDeleteId = ""
    }
    onConfirmed: {
      opened = false
      root.runProfileAction("delete", root.pendingProfileDeleteId, "confirmed")
      root.pendingProfileDeleteId = ""
    }
  }

  // Section title with an optional right-aligned hint.
  component ColumnHeader: Item {
    id: columnHeader
    property string text: ""
    property string caption: ""
    width: parent ? parent.width : implicitWidth
    implicitHeight: Math.max(headerLabel.implicitHeight, headerCaption.implicitHeight)

    PanelSectionHeader {
      id: headerLabel
      anchors.left: parent.left
      anchors.right: headerCaption.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      text: columnHeader.text
      foreground: root.bar.foreground
      fontFamily: root.bar.fontFamily
    }

    Text {
      id: headerCaption
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: Math.min(implicitWidth, columnHeader.width * 0.55)
      text: columnHeader.caption
      textFormat: Text.PlainText
      color: root.mutedForeground
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      horizontalAlignment: Text.AlignRight
      elide: Text.ElideRight
    }
  }

  component Caption: Text {
    width: parent ? parent.width : implicitWidth
    textFormat: Text.PlainText
    color: root.mutedForeground
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.Wrap
  }

  component ColumnRule: Rectangle {
    anchors.top: headerRule.bottom
    anchors.topMargin: Style.space(14)
    anchors.bottom: parent.bottom
    width: Math.max(1, Style.normalBorderWidth)
    color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.12)
  }

  component ScalePill: Button {
    id: pill
    required property string scaleValue
    required property int scaleIndex

    text: root.effectiveScale(scaleValue) + "x" + (root.recommendedScaleValue === scaleValue ? " •" : "")
    tooltipText: root.recommendedScaleValue === scaleValue
      ? "Suggested for this display's pixel density" : ""
    fontSize: Style.font.caption
    foreground: root.bar.foreground
    fontFamily: root.bar.fontFamily
    horizontalPadding: Style.space(2)
    verticalPadding: Style.spacing.controlPaddingY
    bordered: true
    enabled: !root.settingsBusy

    active: root.activeScaleIndex() === scaleIndex
    hasCursor: root.cursorActive && root.focusSection === "scale" && root.selectedIndex === scaleIndex

    onClicked: root.setScale(scaleValue)
    onHovered: function(isHovered) {
      if (!isHovered || root.reflowingText) return
      root.cursorActive = true
      root.focusSection = "scale"
      root.selectedIndex = pill.scaleIndex
    }
  }
}
