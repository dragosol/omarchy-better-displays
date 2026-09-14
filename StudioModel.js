// Read-only planning from advertised modes. No physical-size, device-class,
// projector or PPI inference. Callers must use the normal preview transaction.
function advertisedModes(display) {
  return (Array.isArray(display.availableModes) ? display.availableModes : []).map(function(raw) {
    var m = String(raw).match(/^(\d+)x(\d+)@(\d+(?:\.\d+)?)Hz?$/)
    return m ? {width:Number(m[1]), height:Number(m[2]), refreshRate:Number(m[3])} : null
  }).filter(function(m) { return m && m.width > 0 && m.height > 0 && m.refreshRate > 0 })
}

function conservativeMode(modes) {
  if (!modes.length) return null
  // The first advertised resolution is the compositor's preferred candidate.
  // Within it, prefer the offered refresh nearest 60 Hz (lower wins a tie).
  var first = modes[0]
  return modes.filter(function(m) { return m.width === first.width && m.height === first.height })
    .sort(function(a,b) { return Math.abs(a.refreshRate-60)-Math.abs(b.refreshRate-60) || a.refreshRate-b.refreshRate })[0]
}

function displayHealth(displays, match, workspaces, transitioning, topology) {
  var group = Array.isArray(displays) ? displays : []
  var issues = []
  function add(code, message) { issues.push({code:code, message:message}) }
  if (transitioning) add("transitioning", "Displays are settling. Refresh after the connection finishes.")
  if (!group.length) add("no-displays", "No display snapshot is available. Refresh before making changes.")
  var status = String((match || {}).status || "new")
  if (status === "weak" || status === "moved" || status === "ambiguous" || (match || {}).legacyConnectorOnly)
    add("identity-uncertain", "Profile identity is uncertain. Use Identify and Profiles; automatic restore is not allowed.")
  var enabled = {}
  group.forEach(function(d) { if (d.enabled !== false) enabled[d.name] = d })
  group.forEach(function(d, index) {
    var label = "Display " + (index+1)
    var modes = advertisedModes(d)
    if (d.enabled === false) add("disabled", label + " is disabled (this may be intentional).")
    if (!modes.length) add("modes-unknown", label + " has no advertised modes. Check the cable/dock and refresh; repair is unavailable.")
    else if (d.enabled !== false && !modes.some(function(m) {
      return m.width === Number(d.width) && m.height === Number(d.height)
        && Math.abs(m.refreshRate-Number(d.refreshRate)) <= 0.05
    })) add("mode-unavailable", label + " is using a mode absent from its advertised list.")
    if (d.enabled !== false && (!(Number(d.scale) > 0) || !isFinite(Number(d.scale))
        || Math.abs(Number(d.width)/Number(d.scale)-Math.round(Number(d.width)/Number(d.scale))) > 0.01
        || Math.abs(Number(d.height)/Number(d.scale)-Math.round(Number(d.height)/Number(d.scale))) > 0.01))
      add("invalid-scale", label + " has an invalid or fractional logical pixel size.")
    if (d.mirrorOf && d.mirrorOf !== "none"
        && (!enabled[d.mirrorOf] || d.mirrorOf === d.name
            || (enabled[d.mirrorOf].mirrorOf && enabled[d.mirrorOf].mirrorOf !== "none")))
      add("invalid-mirror", label + " has an unavailable or chained mirror source.")
  })
  var validation = topology.validateTopologyPayload(topology.buildTopologyPayload(group, {}))
  if (!validation.valid && /overlap/.test(validation.reason))
    add("overlap", "Independent display areas overlap. A side-by-side repair can separate them.")
  if (Object.keys(workspaces || {}).some(function(key) { return !enabled[workspaces[key]] }))
    add("workspace-unavailable", "A workspace targets an unavailable display. Repair remaps it to the anchor.")
  var fixable = issues.some(function(i) {
    return ['disabled','mode-unavailable','invalid-scale','invalid-mirror','overlap','workspace-unavailable'].indexOf(i.code) >= 0
  })
  return {issues:issues, repairable:!transitioning && fixable && recommendedSetup(group,'extend',topology).valid,
    summary:issues.length ? issues.map(function(i) { return i.message }).join("\n")
      : "No issues detected in the current snapshot. This is not a cable, bandwidth or GPU stress test."}
}

// Strict allowlist, not redaction of a raw dump. Never include names, EDID,
// serials, paths, profile IDs/names, workspace IDs, or compositor error text.
function sanitizedReport(displays, match, workspaces, transitioning, topology) {
  var group = Array.isArray(displays) ? displays : []
  function number(value) { var n=Number(value); return isFinite(n) ? n : null }
  var status = String((match || {}).status || "new")
  if (['exact','new','weak','moved','ambiguous'].indexOf(status) < 0) status = 'unknown'
  var health = displayHealth(group, match, workspaces, transitioning, topology)
  return JSON.stringify({report:"Displays Display Health", version:1,
    state:transitioning ? "transitioning" : "snapshot", profileMatch:status,
    issues:health.issues.map(function(i) { return i.code }),
    displays:group.map(function(d,index) {
      var mirrorIndex = group.map(function(other) { return other.name }).indexOf(d.mirrorOf)
      return {display:index+1,enabled:d.enabled !== false,width:number(d.width),height:number(d.height),
        refreshRate:number(d.refreshRate),scale:number(d.scale),transform:number(d.transform),
        x:number(d.x),y:number(d.y),mirrorDisplay:mirrorIndex < 0 ? null : mirrorIndex+1,
        advertisedModes:advertisedModes(d)}
    })}, null, 2)
}

function recommendedSetup(displays, kind, topology) {
  var group = Array.isArray(displays) ? displays : []
  var fail = {valid:false, reason:"Every connected display must advertise a usable mode."}
  if (!group.length || (kind !== "extend" && kind !== "mirror")) return fail
  var common = kind === "mirror" ? conservativeMode(topology.commonAdvertisedModes(group)) : null
  if (kind === "mirror" && !common)
    return {valid:false, reason:"Mirror recommendation needs a mode advertised by every display. Arrange manually instead."}
  var cursor = 0
  var proposed = []
  for (var i=0; i<group.length; i++) {
    var display = group[i]
    var mode = common || conservativeMode(advertisedModes(display))
    if (!mode || !display.name) return fail
    var scale = Number(display.scale)
    if (kind === "mirror" || !(scale > 0) || !isFinite(scale)
        || Math.abs(mode.width/scale-Math.round(mode.width/scale)) > 0.01
        || Math.abs(mode.height/scale-Math.round(mode.height/scale)) > 0.01) scale = 1
    var transform = kind === "mirror" ? 0 : topology.cleanTransform(display.transform)
    var record = {name:display.name, x:Math.round(cursor), y:0,
      width:mode.width, height:mode.height, refreshRate:mode.refreshRate, scale:scale, transform:transform}
    if (kind === "mirror" && i > 0) record.mirrorOf = group[0].name
    if (kind === "extend") cursor += topology.logicalSize(mode.width,mode.height,scale,transform).width
    proposed.push(record)
  }
  var validation = topology.validateTopologyPayload(proposed)
  return {valid:validation.valid, reason:validation.reason, proposed:proposed,
    previous:topology.buildTopologyPayload(group, {}), anchor:group[0].name,
    summary:kind === "extend" ? "Enable all displays side by side using advertised resolutions and refresh nearest 60 Hz. Retain valid scale and rotation."
      : "Mirror all displays using a common advertised mode, scale 1 and landscape. Images may stretch on different aspect ratios."}
}
