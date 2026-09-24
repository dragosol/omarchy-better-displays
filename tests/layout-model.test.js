const assert = require("node:assert/strict")
const Model = require("../Model.js")

function display(overrides) {
  return Object.assign({
    name: "DP-1",
    enabled: true,
    focused: false,
    width: 1920,
    height: 1080,
    refreshRate: 60,
    scale: 1,
    transform: 0,
    x: 0,
    y: 0
  }, overrides || {})
}

{
  assert.deepEqual(Model.displayConfirmationPolicy({ status: "exact", profileId: "desk" }), {
    kind: "keep",
    profileId: "desk",
    message: ""
  })
  assert.deepEqual(Model.displayConfirmationPolicy({ status: "moved", profileId: "desk" }), {
    kind: "choose-profile",
    profileId: "desk",
    message: "These displays moved connectors. Update the existing profile or save this layout as a new profile."
  })
  assert.deepEqual(Model.displayConfirmationPolicy({ status: "ambiguous", profileId: "desk" }), {
    kind: "identify-first",
    profileId: "desk",
    message: "Displays cannot safely match these displays. Revert, then use Identify before applying again."
  })
  assert.deepEqual(Model.displayConfirmationPolicy({ status: "weak" }), {
    kind: "identify-first",
    profileId: "",
    message: "Displays cannot safely match these displays. Revert, then use Identify before applying again."
  })
  assert.deepEqual(Model.displayConfirmationPolicy(), {
    kind: "keep",
    profileId: "",
    message: ""
  })

  assert.equal(Model.ownsDisplayIpc("DP-2", ["eDP-1", "DP-2"]), true)
  assert.equal(Model.ownsDisplayIpc("eDP-1", ["DP-2", "eDP-1", "DP-2"]), false)
  assert.equal(Model.ownsDisplayIpc("", ["eDP-1"]), false)
}

{
  assert.equal(Model.nextExpandedSection("", "workspaces"), "workspaces")
  assert.equal(Model.nextExpandedSection("workspaces", "display"), "display")
  assert.equal(Model.nextExpandedSection("display", "display"), "")
}

{
  const assignments = Model.workspaceAssignments(
    [display({ name: "DP-4" }), display({ name: "DP-6" }), display({ name: "eDP-1" })],
    [
      { id: 1, name: "1", monitor: "eDP-1" },
      { id: 2, name: "2", monitor: "DP-4" },
      { id: 4, name: "4", monitor: "DP-6" }
    ],
    [
      { workspaceString: "2", monitor: "DP-6" },
      { workspaceString: "3", enabled: true },
      { workspaceString: "special:scratchpad", monitor: "DP-4" }
    ],
    10
  )

  assert.deepEqual(assignments, {
    "1": "eDP-1",
    "2": "DP-6",
    "4": "DP-6"
  })
  assert.deepEqual(Model.workspacesForMonitor(assignments, "DP-6"), [2, 4])
  assert.deepEqual(Model.toggleWorkspaceAssignment(assignments, 1, "DP-4"), {
    "1": "DP-4",
    "2": "DP-6",
    "4": "DP-6"
  })
  assert.deepEqual(Model.toggleWorkspaceAssignment(assignments, 2, "DP-6"), {
    "1": "eDP-1",
    "4": "DP-6"
  })
  assert.equal(Model.workspaceAssignmentsEqual(assignments, {
    "4": "DP-6",
    "2": "DP-6",
    "1": "eDP-1"
  }), true)
}

{
  const resolutions = Model.availableResolutions([
    "1920x1080@60.00Hz",
    "1920x1080@74.97Hz",
    "1600x900@60.00Hz",
    "not-a-mode"
  ], "1600x900")

  assert.deepEqual(resolutions, [
    { value: "1600x900@60", label: "1600 × 900 (Recommended)", width: 1600, height: 900, refreshRate: 60, recommended: true },
    { value: "1920x1080@60", label: "1920 × 1080", width: 1920, height: 1080, refreshRate: 60, recommended: false }
  ])
  assert.equal(Model.matchingResolutionValue(resolutions, 1920, 1080), "1920x1080@60")
  assert.equal(Model.matchingResolutionValue(resolutions, 1280, 720), "")
}

{
  const resolutions = Model.availableResolutions([
    "2560x1440@60.00Hz",
    "1920x1080@60.00Hz"
  ], "")

  assert.equal(resolutions[0].label, "2560 × 1440 (Recommended)")
  assert.equal(resolutions[0].recommended, true)
}

{
  assert.deepEqual(Model.parseDisplayMode("2560x1440@143.97Hz"), {
    width: 2560,
    height: 1440,
    refreshRate: 143.97,
    value: "2560x1440@143.97"
  })
  assert.equal(Model.parseDisplayMode("preferred"), null)
}

{
  const rates = Model.availableRefreshRates([
    "2560x1440@60.00Hz",
    "2560x1440@143.97Hz",
    "2560x1440@120.00Hz",
    "1920x1080@240.00Hz",
    "2560x1440@143.97Hz",
    "not-a-mode"
  ], 2560, 1440)

  assert.deepEqual(rates, [
    { value: "143.97", refreshRate: 143.97, label: "143.97 Hz" },
    { value: "120", refreshRate: 120, label: "120 Hz" },
    { value: "60", refreshRate: 60, label: "60 Hz" }
  ])
  assert.equal(Model.matchingRefreshRateValue(rates, 120), "120")
  assert.equal(Model.preferredRefreshRate(rates, 120), "120")
  assert.equal(Model.preferredRefreshRate(rates, 165), "143.97")
}

{
  const displays = [
    display({ name: "DP-4", x: -1920, y: 0 }),
    display({ name: "eDP-1", width: 2880, height: 1800, scale: 2, x: 0, y: 180 }),
    display({ name: "DP-9", enabled: false, x: 4000 })
  ]

  assert.deepEqual(Model.buildMonitorSettingPayload(displays, "DP-4", {
    width: 1600,
    height: 900,
    refreshRate: 60,
    scale: 1
  }), [
    { name: "DP-4", x: 0, y: 0, width: 1600, height: 900, refreshRate: 60, scale: 1, transform: 0 },
    { name: "eDP-1", x: 1920, y: 180, width: 2880, height: 1800, refreshRate: 60, scale: 2, transform: 0 }
  ])
}

{
  const displays = [
    display({ name: "DP-4", x: -1920, y: 0 }),
    display({ name: "eDP-1", width: 2880, height: 1800, scale: 2, x: 0, y: 180 })
  ]

  assert.deepEqual(Model.prepareDisplaySettingPreview(displays, {}, "DP-4", {
    width: 1600,
    height: 900,
    refreshRate: 60,
    scale: 1
  }), {
    changed: true,
    stagedSettings: { "DP-4": { width: 1600, height: 900 } },
    previous: [
      { name: "DP-4", x: 0, y: 0, width: 1920, height: 1080, refreshRate: 60, scale: 1, transform: 0 },
      { name: "eDP-1", x: 1920, y: 180, width: 2880, height: 1800, refreshRate: 60, scale: 2, transform: 0 }
    ],
    proposed: [
      { name: "DP-4", x: 0, y: 0, width: 1600, height: 900, refreshRate: 60, scale: 1, transform: 0 },
      { name: "eDP-1", x: 1920, y: 180, width: 2880, height: 1800, refreshRate: 60, scale: 2, transform: 0 }
    ]
  })

  assert.deepEqual(Model.prepareDisplaySettingPreview(displays, {}, "DP-4", {
    width: 1920,
    height: 1080,
    refreshRate: 60,
    scale: 1
  }), {
    changed: false,
    stagedSettings: {},
    previous: [],
    proposed: []
  })
}

{
  const displays = [
    display({ name: "DP-4", width: 2560, height: 1440, refreshRate: 60, scale: 1 }),
    display({ name: "eDP-1", width: 2880, height: 1800, refreshRate: 60, scale: 2 })
  ]

  assert.deepEqual(Model.prepareDisplaySettingPreview(displays, {}, "DP-4", {
    refreshRate: 143.97
  }).proposed, [
    { name: "DP-4", x: 0, y: 0, width: 2560, height: 1440, refreshRate: 143.97, scale: 1, transform: 0 },
    { name: "eDP-1", x: 0, y: 0, width: 2880, height: 1800, refreshRate: 60, scale: 2, transform: 0 }
  ])
}

{
  const displays = [
    display({ name: "DP-4", width: 1920, height: 1080, refreshRate: 60, scale: 1 }),
    display({ name: "eDP-1", width: 2880, height: 1800, refreshRate: 60, scale: 2 })
  ]
  const staged = Model.stageDisplaySettings(displays, {}, "DP-4", {
    width: 1600,
    height: 900,
    refreshRate: 60,
    scale: 1
  })

  assert.deepEqual(staged, {
    "DP-4": { width: 1600, height: 900 }
  })
  assert.deepEqual(Model.displaysWithSettings(displays, staged).map(item => ({
    name: item.name,
    width: item.width,
    height: item.height
  })), [
    { name: "DP-4", width: 1600, height: 900 },
    { name: "eDP-1", width: 2880, height: 1800 }
  ])
  assert.deepEqual(Model.stageDisplaySettings(displays, staged, "DP-4", {
    width: 1920,
    height: 1080,
    refreshRate: 60,
    scale: 1
  }), {})
  assert.deepEqual(Model.retainDisplaySettings([
    display({ name: "DP-4", enabled: false }),
    display({ name: "eDP-1", enabled: true })
  ], {
    "DP-4": { width: 1600 },
    "eDP-1": { scale: 1.6 }
  }), {
    "eDP-1": { scale: 1.6 }
  })
}

{
  const displays = [
    display({ name: "DP-4", x: 0, y: 0 }),
    display({ name: "eDP-1", width: 2880, height: 1800, scale: 2, x: 1920, y: 180 })
  ]
  const preview = [
    { name: "DP-4", logicalX: 0, logicalY: 0 },
    { name: "eDP-1", logicalX: 1920, logicalY: 180 }
  ]

  assert.deepEqual(Model.buildDisplayLayoutPayload(displays, preview, {
    "DP-4": { width: 1600, height: 900, scale: 1.25 }
  }), [
    { name: "DP-4", x: 0, y: 0, width: 1600, height: 900, refreshRate: 60, scale: 1.25, transform: 0 },
    { name: "eDP-1", x: 1920, y: 180, width: 2880, height: 1800, refreshRate: 60, scale: 2, transform: 0 }
  ])
}

{
  const two = Model.responsiveDisplayUtilization(2)
  const four = Model.responsiveDisplayUtilization(4)
  const eight = Model.responsiveDisplayUtilization(8)
  const sixteen = Model.responsiveDisplayUtilization(16)

  assert.ok(two > four)
  assert.ok(four > eight)
  assert.ok(eight > sixteen)
  assert.ok(1 / (four * four) > 4)
  assert.ok(1 / (eight * eight) > 8)
  assert.ok(sixteen >= 0.1)
}

{
  const displays = Array.from({ length: 8 }, (_, index) =>
    display({ name: "DP-" + (index + 1), x: 0, y: 0 }))
  const fitted = Model.fitDisplayLayout(
    displays, 1400, 800, 24,
    Model.responsiveDisplayUtilization(displays.length)
  )
  const workspaceWidth = (1400 - 48) / fitted.scale
  const workspaceHeight = (800 - 48) / fitted.scale
  const columns = Math.floor(workspaceWidth / 1920)
  const rows = Math.floor(workspaceHeight / 1080)

  assert.ok(columns * rows >= displays.length)
}

{
  const displays = [
    display({ name: "DP-1", x: 0, y: 0 }),
    display({ name: "DP-2", x: 0, y: 0 })
  ]
  const fitted = Model.fitDisplayLayout(
    displays, 1400, 800, 24,
    Model.responsiveDisplayUtilization(displays.length)
  )
  const anchor = fitted.items[0]
  const moved = Model.moveDisplayInCanvas(
    fitted.items, "DP-2", anchor.x + anchor.width, anchor.y,
    fitted.scale, 24, 1400, 800, 12
  )
  const placed = moved.find(item => item.name === "DP-2")

  assert.equal(placed.logicalX, anchor.logicalX + anchor.logicalWidth)
}

{
  assert.equal(Model.cycleDisplayIndex(0, 6, -1), 5)
  assert.equal(Model.cycleDisplayIndex(5, 6, 1), 0)
  assert.equal(Model.cycleDisplayIndex(-1, 6, 1), 0)
}

{
  assert.equal(Model.displayLabel(display({
    name: "eDP-1",
    make: "Apple Inc.",
    model: "Color LCD"
  })), "Built-in Display")
}

{
  assert.equal(Model.displayLabel(display({
    name: "DP-4",
    make: "Samsung Electric Company",
    model: "LF24T35"
  })), "Samsung LF24T35")
}

{
  assert.equal(Model.displayLabel(display({
    name: "HDMI-A-1",
    make: "",
    model: "",
    description: ""
  })), "HDMI-A-1")
}

{
  const fitted = Model.fitDisplayLayout([
    display({ name: "DP-1" }),
    display({ name: "eDP-1", width: 2880, height: 1800, scale: 2, x: 1920 })
  ], 320, 160, 10)

  assert.equal(fitted.items.length, 2)
  assert.equal(fitted.items[0].label, "DP-1")
  assert.equal(fitted.items[1].label, "Built-in Display")
  assert.equal(fitted.items[0].logicalWidth, 1920)
  assert.equal(fitted.items[1].logicalWidth, 1440)
  assert.equal(fitted.items[1].logicalHeight, 900)
  assert.ok(fitted.items[1].x > fitted.items[0].x + fitted.items[0].width - 0.01)
}

{
  const displays = [
    display({ name: "DP-1", x: 0, y: 0 }),
    display({ name: "eDP-1", width: 2880, height: 1800, scale: 2, x: 1920, y: 180 }),
    display({ name: "DP-3", x: 0, y: 180 })
  ]
  const compact = Model.fitDisplayLayout(displays, 320, 170, 10)
  const moved = Model.moveDisplayInCanvas(
    compact.items, "DP-3", compact.items[2].x, compact.items[2].y + 12,
    compact.scale, 10, 320, 170, 0
  )
  const expanded = Model.refitDisplayLayout(displays, moved, 1400, 800, 24, 0.4)
  const right = expanded.items.find(item => item.name === "eDP-1")
  const placedRight = Model.moveDisplayInCanvas(
    expanded.items, "DP-3", right.x + right.width, right.y,
    expanded.scale, 24, 1400, 800, 12
  )
  const third = placedRight.find(item => item.name === "DP-3")

  assert.deepEqual(
    Model.normalizeDisplayLayout(expanded.items),
    Model.normalizeDisplayLayout(moved)
  )
  assert.ok(expanded.items[0].width > compact.items[0].width * 1.5)
  for (const item of expanded.items) {
    assert.ok(item.x >= 24)
    assert.ok(item.y >= 24)
    assert.ok(item.x + item.width <= 1400 - 24)
    assert.ok(item.y + item.height <= 800 - 24)
  }
  assert.equal(third.logicalX, right.logicalX + right.logicalWidth)
}

{
  const normalized = Model.normalizeDisplayLayout([
    { name: "left", logicalX: -1920, logicalY: 120 },
    { name: "right", logicalX: 0, logicalY: 0 }
  ])

  assert.deepEqual(normalized, [
    { name: "left", x: 0, y: 120 },
    { name: "right", x: 1920, y: 0 }
  ])
}

{
  const snapped = Model.snapDisplayPosition(
    { name: "moving", logicalX: 1912, logicalY: 7, logicalWidth: 1440, logicalHeight: 900 },
    [{ name: "anchor", logicalX: 0, logicalY: 0, logicalWidth: 1920, logicalHeight: 1080 }],
    12
  )

  assert.deepEqual(snapped, { x: 1920, y: 0 })
}

{
  const items = [
    { name: "anchor", logicalX: 0, logicalY: 0, logicalWidth: 1920, logicalHeight: 1080, width: 160, height: 90, x: 10, y: 10 },
    { name: "moving", logicalX: 1920, logicalY: 0, logicalWidth: 1440, logicalHeight: 900, width: 120, height: 75, x: 170, y: 10 }
  ]
  const moved = Model.moveDisplayInCanvas(items, "moving", 168, 16, 1 / 12, 10, 320, 160, 12)
  const moving = moved.find(item => item.name === "moving")

  assert.equal(moving.logicalX, 1920)
  assert.equal(moving.logicalY, 0)
  assert.equal(moving.x, 170)
  assert.equal(moving.y, 10)
}

{
  const fitted = Model.fitDisplayLayout([
    display({ name: "eDP-1", width: 2880, height: 1800, scale: 2, x: 0 }),
    display({ name: "DP-4", width: 1920, height: 1080, scale: 1, x: 1440 })
  ], 320, 160, 10)
  const original = fitted.items.find(item => item.name === "DP-4")
  const moved = Model.moveDisplayInCanvas(
    fitted.items, "DP-4", original.x + 30, original.y + 20,
    fitted.scale, 10, 320, 160, 12
  )
  const dropped = moved.find(item => item.name === "DP-4")
  const laptop = moved.find(item => item.name === "eDP-1")

  // Dropped away from the laptop: it slides down but stays against its edge.
  assert.equal(dropped.logicalX, laptop.logicalX + laptop.logicalWidth)
  assert.ok(dropped.logicalY > original.logicalY)

  const leftOriginal = fitted.items.find(item => item.name === "eDP-1")
  const movedLeft = Model.moveDisplayInCanvas(
    fitted.items, "eDP-1", leftOriginal.x - 30, leftOriginal.y - 20,
    fitted.scale, 10, 320, 160, 12
  )
  const droppedLeft = movedLeft.find(item => item.name === "eDP-1")
  const external = movedLeft.find(item => item.name === "DP-4")

  assert.equal(droppedLeft.logicalX + droppedLeft.logicalWidth, external.logicalX)
  assert.ok(droppedLeft.logicalY < leftOriginal.logicalY)
}

// ---- Edge snapping: never a gap, never an overlap ----
function rectOf(item) {
  return { name: item.name, x: item.logicalX, y: item.logicalY, w: item.logicalWidth, h: item.logicalHeight }
}
function assertConnected(items, label) {
  const rects = items.map(rectOf)
  for (let a = 0; a < rects.length; a++)
    for (let b = a + 1; b < rects.length; b++)
      assert.ok(!Model.rectsOverlap(rects[a], rects[b]), label + ": " + rects[a].name + " overlaps " + rects[b].name)
  const reached = new Set([rects[0].name])
  let grew = true
  while (grew) {
    grew = false
    for (const r of rects) {
      if (reached.has(r.name)) continue
      if (rects.some(o => reached.has(o.name) && Model.rectsTouch(r, o))) { reached.add(r.name); grew = true }
    }
  }
  assert.equal(reached.size, rects.length, label + ": displays not all edge-connected")
}
function payloadItems(payload) {
  return payload.filter(r => r.enabled !== false).map(r => ({
    name: r.name, logicalX: r.x, logicalY: r.y,
    logicalWidth: (r.transform % 2 ? r.height : r.width) / r.scale,
    logicalHeight: (r.transform % 2 ? r.width : r.height) / r.scale
  }))
}

{
  // The live XPS + LG ULTRAGEAR+ layout: every drop, however far off, lands
  // edge-to-edge. Before the fix a 20 px drag left a 117 px gap and a 30 px
  // drag the other way overlapped the laptop (cursor drawn on both screens).
  const fitted = Model.fitDisplayLayout([
    display({ name: "eDP-1", width: 2880, height: 1800, scale: 2, x: 0, y: 765 }),
    display({ name: "DP-1", width: 3840, height: 2160, scale: 1.5, x: 1440, y: 0 })
  ], 900, 420, 24, 0.8)
  for (const name of ["DP-1", "eDP-1"]) {
    const start = fitted.items.find(item => item.name === name)
    for (const [dx, dy] of [[0, 0], [5, 0], [20, 0], [40, 0], [-30, 0], [-80, 40], [60, 60], [0, -200], [-400, -300], [300, 250]]) {
      const moved = Model.moveDisplayInCanvas(fitted.items, name, start.x + dx, start.y + dy,
                                              fitted.scale, 24, 900, 420, 12)
      assertConnected(moved, name + " by " + dx + "," + dy)
    }
  }
}

{
  // Dropped on top of the other display: pushed to the nearest free edge,
  // here just below it (1080 px away) rather than beside it (1620 px).
  const items = [
    { name: "a", logicalX: 0, logicalY: 0, logicalWidth: 1920, logicalHeight: 1080 },
    { name: "b", logicalX: 1920, logicalY: 0, logicalWidth: 1920, logicalHeight: 1080 }
  ]
  const moved = Model.moveDisplayInCanvas(items, "b", 10 + 300 / 10, 10, 0.1, 10, 1000, 1000, 12)
  assertConnected(moved, "dropped on top")
  assert.equal(moved[1].logicalX, 300)
  assert.equal(moved[1].logicalY, 1080)
}

{
  // Three in a row; the middle one (the bridge) moves below the left one. The
  // right one is reconnected instead of being left floating.
  const items = [
    { name: "left", logicalX: 0, logicalY: 0, logicalWidth: 1920, logicalHeight: 1080 },
    { name: "middle", logicalX: 1920, logicalY: 0, logicalWidth: 1920, logicalHeight: 1080 },
    { name: "right", logicalX: 3840, logicalY: 0, logicalWidth: 1920, logicalHeight: 1080 }
  ]
  const moved = Model.moveDisplayInCanvas(items, "middle", 10, 10 + 1080 / 10, 0.1, 10, 2000, 2000, 12)
  assertConnected(moved, "bridge moved")
  const middle = moved.find(item => item.name === "middle")
  assert.equal(middle.logicalX, 0)
  assert.equal(middle.logicalY, 1080)
  assert.equal(moved.find(item => item.name === "left").logicalX, 0)
}

{
  // Changing scale keeps neighbours attached: laptop 2x -> 1.6x grows it from
  // 1440 to 1800 logical px wide, so the LG to its right shifts right by 360
  // instead of being overlapped.
  const previous = [
    { name: "eDP-1", x: 0, y: 0, width: 2880, height: 1800, refreshRate: 60, scale: 2, transform: 0 },
    { name: "DP-1", x: 1440, y: 0, width: 3840, height: 2160, refreshRate: 144, scale: 1, transform: 0 }
  ]
  const proposed = [Object.assign({}, previous[0], { scale: 1.6 }), previous[1]]
  const snapped = Model.snapTopologyPayload(proposed, previous)
  assert.equal(snapped[0].x, 0)
  assert.equal(snapped[1].x, 1800)
  assertConnected(payloadItems(snapped), "laptop scale up")

  // A display on the LEFT shrinking (LG 1x -> 1.5x) pulls the laptop in.
  const leftPrevious = [
    { name: "DP-1", x: 0, y: 0, width: 3840, height: 2160, refreshRate: 144, scale: 1, transform: 0 },
    { name: "eDP-1", x: 3840, y: 0, width: 2880, height: 1800, refreshRate: 60, scale: 2, transform: 0 }
  ]
  const leftProposed = [Object.assign({}, leftPrevious[0], { scale: 1.5 }), leftPrevious[1]]
  const leftSnapped = Model.snapTopologyPayload(leftProposed, leftPrevious)
  assert.equal(leftSnapped[1].x, 2560)
  assertConnected(payloadItems(leftSnapped), "left display scale down")

  // Rotating a side monitor to portrait keeps it attached.
  const rotated = Model.snapTopologyPayload(
    [previous[0], Object.assign({}, previous[1], { transform: 1 })], previous)
  assertConnected(payloadItems(rotated), "rotate")

  // Disabled and mirrored records pass through untouched.
  const withDisabled = Model.snapTopologyPayload(
    previous.concat([{ name: "HDMI-A-1", enabled: false }, { name: "DP-2", x: 0, y: 0, width: 1920, height: 1080, scale: 1, mirrorOf: "eDP-1" }]),
    previous)
  assert.deepEqual(withDisabled[2], { name: "HDMI-A-1", enabled: false })
  assert.equal(withDisabled[3].mirrorOf, "eDP-1")

  // An already valid layout is returned unchanged.
  assert.deepEqual(Model.snapTopologyPayload(previous, previous), previous)

  // A gap in the incoming payload (e.g. from an old saved layout) is closed.
  const gapped = Model.snapTopologyPayload(
    [previous[0], Object.assign({}, previous[1], { x: 1600 })], previous)
  assertConnected(payloadItems(gapped), "gap closed")
}

{
  const displays = [
    display({ name: "DP-1", x: -1920, scale: 1.25, refreshRate: 59.95 }),
    display({ name: "eDP-1", width: 2880, height: 1800, x: 0, scale: 2 })
  ]
  const preview = [
    { name: "DP-1", logicalX: -1919.6, logicalY: 0 },
    { name: "eDP-1", logicalX: 0, logicalY: 80.4 }
  ]

  assert.deepEqual(Model.buildDisplayLayoutPayload(displays, preview), [
    { name: "DP-1", x: 0, y: 0, width: 1920, height: 1080, refreshRate: 59.95, scale: 1.25, transform: 0 },
    { name: "eDP-1", x: 1920, y: 80, width: 2880, height: 1800, refreshRate: 60, scale: 2, transform: 0 }
  ])
}

{
  assert.equal(Model.cleanTransform(undefined), 0)
  assert.equal(Model.cleanTransform(3), 3)
  assert.equal(Model.cleanTransform(8), 0)

  const displays = [
    display({ name: "DP-1", transform: 0 }),
    display({ name: "eDP-1", x: 1920 })
  ]
  const preview = Model.prepareDisplaySettingPreview(
    displays, {}, "DP-1", { transform: 1 })

  assert.equal(preview.changed, true)
  assert.deepEqual(preview.stagedSettings, { "DP-1": { transform: 1 } })
  assert.equal(preview.previous[0].transform, 0)
  assert.equal(preview.proposed[0].transform, 1)
}

{
  const fitted = Model.fitDisplayLayout([
    display({ name: "DP-1", width: 1920, height: 1080, transform: 1 })
  ], 320, 320, 10)

  assert.equal(fitted.items[0].logicalWidth, 1080)
  assert.equal(fitted.items[0].logicalHeight, 1920)
  assert.ok(fitted.items[0].height > fitted.items[0].width)
}

{
  assert.deepEqual(Model.advanceDisplayConfirmation(15), { remaining: 14, expired: false })
  assert.deepEqual(Model.advanceDisplayConfirmation(1), { remaining: 0, expired: true })
  assert.deepEqual(Model.advanceDisplayConfirmation(0), { remaining: 0, expired: true })
}

{
  assert.deepEqual(Model.parsePendingDisplayTransaction(
    '{"id":"display-123","scope":"settings","remainingSeconds":12,"originScreen":"DP-1","originWorkspace":5}'
  ), {
    id: "display-123",
    scope: "settings",
    remainingSeconds: 12,
    originScreen: "DP-1",
    originWorkspace: 5
  })
  assert.equal(Model.parsePendingDisplayTransaction('{}'), null)
  assert.equal(Model.parsePendingDisplayTransaction(
    '{"id":"bad/id","scope":"layout","remainingSeconds":12}'
  ), null)
  assert.equal(Model.parsePendingDisplayTransaction(
    '{"id":"display-123","scope":"layout","remainingSeconds":0}'
  ), null)
}

{
  const screens = ["eDP-1", "DP-5", "DP-4"]
  assert.equal(Model.confirmationTargetScreen("DP-5", "eDP-1", "DP-4", screens), "DP-5")
  assert.equal(Model.confirmationTargetScreen("DP-9", "eDP-1", "DP-5", screens), "eDP-1")
  assert.equal(Model.confirmationTargetScreen("DP-9", "DP-9", "DP-5", screens), "DP-5")
  assert.equal(Model.confirmationTargetScreen("DP-9", "DP-9", "DP-9", screens), "DP-4")
  assert.equal(Model.confirmationTargetScreen("DP-5", "", "", []), "")

  assert.equal(Model.ownsDisplayConfirmation("eDP-1", "DP-9", "eDP-1", "DP-5", screens), true)
  assert.equal(Model.ownsDisplayConfirmation("DP-4", "DP-9", "eDP-1", "DP-5", screens), false)
}

{
  assert.equal(Model.shouldAutoResetDisplayLayout({
    dirty: false,
    dragging: false,
    confirmationPending: false,
    applying: false
  }), true)
  assert.equal(Model.shouldAutoResetDisplayLayout({
    dirty: true,
    dragging: false,
    confirmationPending: false,
    applying: false
  }), false)
  assert.equal(Model.shouldAutoResetDisplayLayout({
    dirty: false,
    dragging: true,
    confirmationPending: false,
    applying: false
  }), false)
  assert.equal(Model.shouldAutoResetDisplayLayout({
    dirty: false,
    dragging: false,
    confirmationPending: true,
    applying: false
  }), false)
  assert.equal(Model.shouldAutoResetDisplayLayout({
    dirty: false,
    dragging: false,
    confirmationPending: false,
    applying: true
  }), false)
}

console.log("layout model tests passed")
