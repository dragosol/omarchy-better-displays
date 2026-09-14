// Plans the layout to restore automatically when displays connect.
//
// Every kept layout is remembered, so plugging displays in should put them back
// the way they were last set, without asking:
//
//   exact  - the same monitors on the same connectors: that profile, as saved.
//   moved  - the same strongly identified monitors on other connectors: the
//            profile with connector names (and workspace owners) remapped.
//   new    - any other combination: each strongly identified monitor gets the
//            mode, scale and rotation it was last kept with, positioned where it
//            last sat relative to a display that is also connected now, or to
//            the right of the others. Unknown monitors keep their live settings.
//
// Weak or ambiguous identities (identical monitors without serials) are never
// guessed at; they keep their live settings.

var Matcher = typeof require !== "undefined" ? require("./ProfileMatcher.js") : null

function text(value) {
  return value === null || value === undefined ? "" : String(value)
}

function parseMode(value) {
  var match = text(value).match(/^(\d+)x(\d+)@([0-9]+(?:\.[0-9]+)?)(?:Hz)?$/)
  return match ? { width: Number(match[1]), height: Number(match[2]), refreshRate: Number(match[3]) } : null
}

function closestMode(modes, width, height, refreshRate) {
  var best = null
  ;(Array.isArray(modes) ? modes : []).forEach(function(value) {
    var mode = parseMode(value)
    if (!mode || mode.width !== Number(width) || mode.height !== Number(height)) return
    var delta = Math.abs(mode.refreshRate - Number(refreshRate))
    if (delta <= 0.5 && (!best || delta < Math.abs(best.refreshRate - Number(refreshRate)))) best = mode
  })
  return best
}

function liveRecord(topology) {
  if (topology.enabled === false) return { name: topology.name, enabled: false }
  var mode = parseMode(topology.mode) || { width: 0, height: 0, refreshRate: 0 }
  var record = {
    name: topology.name, enabled: true, x: Number(topology.x) || 0, y: Number(topology.y) || 0,
    width: mode.width, height: mode.height, refreshRate: mode.refreshRate,
    scale: Number(topology.scale) || 1, transform: Number(topology.transform) || 0
  }
  if (topology.mirrorOf) record.mirrorOf = topology.mirrorOf
  return record
}

function logicalSize(record) {
  var rotated = (Number(record.transform) || 0) % 2 === 1
  var scale = Number(record.scale) || 1
  return {
    width: Math.round((rotated ? record.height : record.width) / scale),
    height: Math.round((rotated ? record.width : record.height) / scale)
  }
}

function byUpdatedDesc(left, right) {
  return text(right.updatedAt).localeCompare(text(left.updatedAt))
}

// Strong identity key for one identity record: trusted serial, else EDID hash.
function strongKey(identity, counts) {
  var serial = text(identity.serial)
  if (serial && identity.serialTrusted === true && counts.serial[serial] === 1) return "serial:" + serial
  var edid = text(identity.edidHash)
  if (edid && counts.edid[edid] === 1) return "edid:" + edid
  return ""
}

function identityCounts(identities) {
  var counts = { serial: {}, edid: {} }
  identities.forEach(function(identity) {
    if (text(identity.serial) && identity.serialTrusted === true)
      counts.serial[identity.serial] = (counts.serial[identity.serial] || 0) + 1
    if (text(identity.edidHash)) counts.edid[identity.edidHash] = (counts.edid[identity.edidHash] || 0) + 1
  })
  return counts
}

function remapProfile(profile, matches) {
  var rename = {}
  matches.forEach(function(match) { rename[match.savedName] = match.currentName })
  var monitors = (profile.topology.monitors || []).map(function(monitor) {
    var copy = Object.assign({}, monitor, { name: rename[monitor.name] || monitor.name })
    if (copy.mirrorOf) copy.mirrorOf = rename[copy.mirrorOf] || copy.mirrorOf
    return copy
  })
  var workspaces = {}
  Object.keys(profile.topology.workspaces || {}).forEach(function(workspace) {
    var owner = profile.topology.workspaces[workspace]
    workspaces[workspace] = rename[owner] || owner
  })
  var anchor = text(profile.topology.anchor)
  return { monitors: monitors, workspaces: workspaces, anchor: rename[anchor] || anchor }
}

function perMonitorPlan(store, snapshot, current) {
  var counts = identityCounts(current)
  var profiles = (store.profiles || []).slice().sort(byUpdatedDesc)
  var topology = snapshot.topology || []
  var live = {}
  topology.forEach(function(entry) { live[entry.name] = liveRecord(entry) })

  // For each connected monitor, the most recently kept record of it.
  var memory = {}
  current.forEach(function(identity) {
    var key = strongKey(identity, counts)
    if (!key) return
    for (var p = 0; p < profiles.length; p++) {
      var saved = ((profiles[p].matchPolicy || {}).identities || [])
      var savedCounts = identityCounts(saved)
      for (var s = 0; s < saved.length; s++) {
        if (strongKey(saved[s], savedCounts) !== key) continue
        var record = (profiles[p].topology.monitors || []).filter(function(m) { return m.name === saved[s].name })[0]
        if (!record) continue
        memory[identity.name] = { profile: profiles[p], savedName: saved[s].name, record: record, identities: saved, savedCounts: savedCounts }
        return
      }
    }
  })

  var names = Object.keys(memory)
  if (names.length === 0) return null

  var proposed = {}
  topology.forEach(function(entry) {
    var base = live[entry.name]
    var remembered = memory[entry.name]
    if (!remembered) { proposed[entry.name] = base; return }
    var record = remembered.record
    if (record.enabled === false) {
      // A remembered "off" only applies when something else stays on.
      proposed[entry.name] = { name: entry.name, enabled: false }
      return
    }
    var next = Object.assign({}, base, { enabled: true })
    // The same timing may be listed with a slightly different rate on another
    // connection (99.98 Hz from EDID, 100.00 Hz advertised), so take the
    // nearest rate within half a hertz at the remembered resolution.
    var nearest = closestMode(entry.modes, record.width, record.height, record.refreshRate)
    if (nearest) {
      next.width = nearest.width
      next.height = nearest.height
      next.refreshRate = nearest.refreshRate
    }
    next.scale = Number(record.scale) || next.scale
    next.transform = Number(record.transform) || 0
    delete next.mirrorOf
    proposed[entry.name] = next
  })

  if (!topology.some(function(entry) { return proposed[entry.name].enabled !== false })) return null

  // Place displays: the built-in panel (or else the first remembered display)
  // stays at its live position; each remembered display keeps its saved
  // offset from a display it was saved alongside that is already placed;
  // anything else goes to the right of what has been placed.
  var liveCounts = identityCounts(current)
  var keyByName = {}
  current.forEach(function(identity) { keyByName[identity.name] = strongKey(identity, liveCounts) })
  var internal = function(name) { return /^(eDP|LVDS|DSI)-/.test(name) }
  var order = topology.map(function(entry) { return entry.name })
    .filter(function(name) { return proposed[name].enabled !== false })
  order.sort(function(a, b) {
    return (internal(b) ? 1 : 0) - (internal(a) ? 1 : 0)
      || (memory[b] ? 1 : 0) - (memory[a] ? 1 : 0)
      || (Number(live[a].x) || 0) - (Number(live[b].x) || 0)
      || a.localeCompare(b)
  })
  var placed = {}
  var placedOrder = []
  var rightEdge = null
  order.forEach(function(name) {
    var record = proposed[name]
    var remembered = memory[name]
    var positioned = false
    if (remembered) {
      var savedMonitors = remembered.profile.topology.monitors || []
      for (var i = 0; i < placedOrder.length && !positioned; i++) {
        var other = placedOrder[i]
        if (!keyByName[other]) continue
        var savedOther = null
        remembered.identities.forEach(function(identity) {
          if (strongKey(identity, remembered.savedCounts) !== keyByName[other]) return
          savedOther = savedMonitors.filter(function(m) {
            return m.name === identity.name && m.enabled !== false
          })[0] || null
        })
        if (!savedOther) continue
        record.x = placed[other].x + (Number(remembered.record.x) - Number(savedOther.x))
        record.y = placed[other].y + (Number(remembered.record.y) - Number(savedOther.y))
        positioned = true
      }
    }
    if (!positioned) {
      record.x = rightEdge === null ? (Number(live[name].x) || 0) : rightEdge
      record.y = rightEdge === null ? (Number(live[name].y) || 0) : 0
    }
    placed[name] = { x: record.x, y: record.y }
    placedOrder.push(name)
    var size = logicalSize(record)
    rightEdge = Math.max(rightEdge === null ? -Infinity : rightEdge, record.x + size.width)
  })

  return {
    source: "per-monitor",
    remembered: names.sort(),
    monitors: topology.map(function(entry) { return proposed[entry.name] }),
    workspaces: {},
    anchor: order[0] || ""
  }
}

function plan(store, snapshot) {
  store = store || { profiles: [] }
  var status = Matcher.profileStatus(store, snapshot)
  var profile = (store.profiles || []).filter(function(p) { return p.id === status.profileId })[0]

  if (profile && status.status === "exact" && !status.legacyConnectorOnly) {
    return { source: "exact", profileId: profile.id, profileName: profile.name, status: status,
      monitors: profile.topology.monitors, workspaces: profile.topology.workspaces || {},
      anchor: text(profile.topology.anchor) }
  }
  if (profile && status.status === "moved") {
    var remapped = remapProfile(profile, status.matches)
    return Object.assign({ source: "moved", profileId: profile.id, profileName: profile.name, status: status }, remapped)
  }
  var current = Matcher.identitiesFromSnapshot(snapshot)
  var perMonitor = perMonitorPlan(store, snapshot, current)
  if (perMonitor) return Object.assign({ status: status }, perMonitor)
  return { source: "none", status: status }
}

if (typeof module !== "undefined") {
  module.exports = { plan: plan, perMonitorPlan: perMonitorPlan, remapProfile: remapProfile }
  if (typeof require !== "undefined" && require.main === module) {
    var fs = require("fs")
    var storeArg = process.argv[2]
    var snapshotArg = process.argv[3]
    process.stdout.write(JSON.stringify(plan(JSON.parse(storeArg), JSON.parse(snapshotArg))) + "\n")
  }
}
