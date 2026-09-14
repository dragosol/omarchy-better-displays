const assert = require("node:assert/strict")
const Planner = require("../MemoryPlanner.js")

const laptopEdid = "edid-laptop"
const samsungEdid = "edid-samsung"
const dellEdid = "edid-dell"

function connector(name) {
  return { name, sysfsPath: "/sys/class/drm/card0-" + name, instance: Number(name.split("-").pop()) || 1,
           transport: name.startsWith("eDP") ? "internal" : "displayport" }
}
function monitor(name, edidHash, serial, extra) {
  return Object.assign({ name, edidHash, serial: serial || null, serialTrusted: !!serial,
    make: "Make", model: "Model", physicalWidth: 500, physicalHeight: 300, preferredMode: null }, extra || {})
}
function live(name, mode, modes, x, scale, extra) {
  return Object.assign({ name, enabled: true, mode, modes, x, y: 0, scale, transform: 0, mirrorOf: null, focused: false }, extra || {})
}
function snapshot(entries) {
  return {
    connectors: entries.map(e => connector(e.live.name)),
    monitors: entries.map(e => e.monitor),
    topology: entries.map(e => e.live)
  }
}
function identities(snap) {
  return require("../ProfileMatcher.js").identitiesFromSnapshot(snap)
}
function profile(id, updatedAt, snap, monitors, workspaces) {
  return { id, name: id, connectedSet: snap.topology.map(t => t.name).sort(), updatedAt, createdAt: updatedAt,
    topology: { monitors, workspaces: workspaces || {}, anchor: "eDP-1" },
    matchPolicy: { identities: identities(snap) } }
}

const samsungModes = ["2560x1440@59.95Hz", "3440x1440@99.98Hz", "3440x1440@59.97Hz"]
const laptop = { monitor: monitor("eDP-1", laptopEdid), live: live("eDP-1", "2880x1800@59.99", ["2880x1800@59.99Hz"], 0, 2) }

// Kept at home: laptop left, Samsung to its right at 3440x1440@100, scale 1.25.
const homeSnap = snapshot([laptop, { monitor: monitor("DP-1", samsungEdid, "HNK1"),
  live: live("DP-1", "2560x1440@59.95", samsungModes, 1440, 2) }])
const home = profile("home", "2026-09-14T10:00:00Z", homeSnap, [
  { name: "eDP-1", enabled: true, x: 0, y: 0, width: 2880, height: 1800, refreshRate: 59.99, scale: 2, transform: 0 },
  { name: "DP-1", enabled: true, x: 1440, y: 0, width: 3440, height: 1440, refreshRate: 99.98, scale: 1.25, transform: 0 }
], { "4": "DP-1", "5": "DP-1" })
const store = { schemaVersion: 2, activeProfileId: "home", profiles: [home] }

{
  // Plugged back in exactly as before: restore that profile.
  const result = Planner.plan(store, homeSnap)
  assert.equal(result.source, "exact")
  assert.equal(result.profileId, "home")
  assert.deepEqual(result.workspaces, { "4": "DP-1", "5": "DP-1" })
}

{
  // Same Samsung, other USB-C port: the profile follows it to DP-2.
  const moved = snapshot([laptop, { monitor: monitor("DP-2", samsungEdid, "HNK1"),
    live: live("DP-2", "2560x1440@59.95", samsungModes, 1440, 2) }])
  const result = Planner.plan(store, moved)
  assert.equal(result.source, "moved")
  assert.deepEqual(result.monitors.map(m => m.name).sort(), ["DP-2", "eDP-1"])
  assert.equal(result.monitors.find(m => m.name === "DP-2").refreshRate, 99.98)
  assert.deepEqual(result.workspaces, { "4": "DP-2", "5": "DP-2" })
}

{
  // A new combination: laptop, the Samsung on DP-2 and an unknown Dell on
  // HDMI. The Samsung keeps its remembered mode, scale and offset from the
  // laptop; the Dell keeps its live settings and goes to the right.
  const mixed = snapshot([
    laptop,
    { monitor: monitor("DP-2", samsungEdid, "HNK1"), live: live("DP-2", "2560x1440@59.95", samsungModes, 2000, 2) },
    { monitor: monitor("HDMI-A-1", dellEdid, "DELL1"), live: live("HDMI-A-1", "1920x1080@60", ["1920x1080@60.00Hz"], 0, 1) }
  ])
  const result = Planner.plan(store, mixed)
  assert.equal(result.source, "per-monitor")
  assert.deepEqual(result.remembered, ["DP-2", "eDP-1"])
  const byName = Object.fromEntries(result.monitors.map(m => [m.name, m]))
  assert.deepEqual([byName["eDP-1"].x, byName["eDP-1"].y], [0, 0])
  assert.deepEqual([byName["DP-2"].width, byName["DP-2"].refreshRate, byName["DP-2"].scale, byName["DP-2"].x],
                   [3440, 99.98, 1.25, 1440])
  // 1440 + 3440 / 1.25 = 4192
  assert.deepEqual([byName["HDMI-A-1"].width, byName["HDMI-A-1"].scale, byName["HDMI-A-1"].x], [1920, 1, 4192])
  assert.deepEqual(result.workspaces, {})
}

{
  // On a direct cable the same timing is advertised as 100.00 Hz: use it.
  const direct = snapshot([laptop, { monitor: monitor("DP-3", samsungEdid, "HNK1"),
    live: live("DP-3", "3440x1440@100", ["3440x1440@100.00Hz", "3440x1440@164.90Hz"], 1440, 1) },
    { monitor: monitor("HDMI-A-1", dellEdid, "DELL1"), live: live("HDMI-A-1", "1920x1080@60", ["1920x1080@60.00Hz"], 4192, 1) }])
  const result = Planner.plan(store, direct)
  const samsung = result.monitors.find(m => m.name === "DP-3")
  assert.equal(samsung.refreshRate, 100)
}

{
  // The remembered resolution is not available on this link: keep the live
  // mode but still apply the remembered scale.
  const limited = snapshot([
    laptop,
    { monitor: monitor("DP-2", samsungEdid, "HNK1"), live: live("DP-2", "2560x1440@59.95", ["2560x1440@59.95Hz"], 1440, 2) },
    { monitor: monitor("HDMI-A-1", dellEdid, "DELL1"), live: live("HDMI-A-1", "1920x1080@60", ["1920x1080@60.00Hz"], 0, 1) }
  ])
  const samsung = Planner.plan(store, limited).monitors.find(m => m.name === "DP-2")
  assert.deepEqual([samsung.width, samsung.refreshRate, samsung.scale], [2560, 59.95, 1.25])
}

{
  // The newest profile that contains a monitor wins.
  const newer = profile("newer", "2026-09-14T12:00:00Z", homeSnap, [
    { name: "eDP-1", enabled: true, x: 0, y: 0, width: 2880, height: 1800, refreshRate: 59.99, scale: 2, transform: 0 },
    { name: "DP-1", enabled: true, x: 1440, y: 0, width: 3440, height: 1440, refreshRate: 59.97, scale: 1, transform: 0 }
  ])
  const both = { schemaVersion: 2, activeProfileId: "home", profiles: [home, newer] }
  const alone = snapshot([
    { monitor: monitor("DP-2", samsungEdid, "HNK1"), live: live("DP-2", "2560x1440@59.95", samsungModes, 0, 2) },
    { monitor: monitor("HDMI-A-1", dellEdid, "DELL1"), live: live("HDMI-A-1", "1920x1080@60", ["1920x1080@60.00Hz"], 1280, 1) }
  ])
  const samsung = Planner.plan(both, alone).monitors.find(m => m.name === "DP-2")
  assert.deepEqual([samsung.refreshRate, samsung.scale, samsung.x], [59.97, 1, 0])
}

{
  // Identical monitors without serials are never guessed at.
  const twins = snapshot([
    { monitor: monitor("DP-1", "same-edid"), live: live("DP-1", "1920x1080@60", ["1920x1080@60.00Hz"], 0, 1) },
    { monitor: monitor("DP-2", "same-edid"), live: live("DP-2", "1920x1080@60", ["1920x1080@60.00Hz"], 1920, 1) }
  ])
  const twinProfile = profile("twins", "2026-09-14T09:00:00Z", twins, [
    { name: "DP-1", enabled: true, x: 1920, y: 0, width: 1920, height: 1080, refreshRate: 60, scale: 1, transform: 0 },
    { name: "DP-2", enabled: true, x: 0, y: 0, width: 1920, height: 1080, refreshRate: 60, scale: 1, transform: 0 }
  ])
  const withLaptop = snapshot([laptop].concat(twins.topology.map((t, i) => ({ monitor: twins.monitors[i], live: t }))))
  const result = Planner.plan({ schemaVersion: 2, activeProfileId: "", profiles: [twinProfile] }, withLaptop)
  assert.equal(result.source, "none")
}

{
  assert.equal(Planner.plan({ profiles: [] }, homeSnap).source, "none")
}

console.log("memory planner tests passed")
