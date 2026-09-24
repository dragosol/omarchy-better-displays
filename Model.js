function clampBrightness(value) {
  var n = Number(value)
  if (!isFinite(n)) return 1
  return Math.max(1, Math.min(100, Math.round(n)))
}

function normalizeScale(scale) {
  var n = parseFloat(String(scale || ""))
  if (!isFinite(n)) return ""
  return String(Math.round(n * 100) / 100)
}

function gcd(a, b) {
  while (b) {
    var remainder = a % b
    a = b
    b = remainder
  }
  return a
}

function cleanScale(scale, width, height) {
  var requested = Number(scale)
  var modeWidth = Number(width)
  var modeHeight = Number(height)
  if (!isFinite(requested) || !isFinite(modeWidth) || !isFinite(modeHeight)
      || requested <= 0 || modeWidth <= 0 || modeHeight <= 0) return ""

  var divisor = gcd(Math.round(modeWidth * 120), Math.round(modeHeight * 120))
  var scaleUnits = Math.round(requested * 120)
  if (scaleUnits > divisor) scaleUnits = divisor
  while (divisor % scaleUnits !== 0) scaleUnits++
  return normalizeScale(scaleUnits / 120)
}

function matchingScaleIndex(scales, currentScale, width, height) {
  var current = Number(currentScale)
  if (!Array.isArray(scales) || !isFinite(current)) return -1

  var bestIndex = -1
  var bestDistance = Infinity
  var normalizedCurrent = normalizeScale(current)
  for (var i = 0; i < scales.length; i++) {
    if (cleanScale(scales[i], width, height) !== normalizedCurrent) continue

    var distance = Math.abs(Number(scales[i]) - current)
    if (distance < bestDistance) {
      bestIndex = i
      bestDistance = distance
    }
  }
  return bestIndex
}

function availableScales(scales, width, height) {
  if (!Array.isArray(scales) || Number(width) <= 0 || Number(height) <= 0) return scales || []

  var byEffectiveScale = {}
  for (var i = 0; i < scales.length; i++) {
    var requested = Number(scales[i])
    var effective = Number(cleanScale(requested, width, height))

    if (!isFinite(requested) || !isFinite(effective)) continue

    var key = normalizeScale(effective)
    var existing = byEffectiveScale[key]
    if (!existing || Math.abs(requested - effective) < existing.distance) {
      byEffectiveScale[key] = {
        value: String(scales[i]),
        index: i,
        distance: Math.abs(requested - effective)
      }
    }
  }

  return Object.keys(byEffectiveScale)
    .map(function(key) { return byEffectiveScale[key] })
    .sort(function(a, b) { return a.index - b.index })
    .map(function(candidate) { return candidate.value })
}

function parseDisplayMode(mode) {
  var match = String(mode || "").trim().match(/^(\d+)x(\d+)@([0-9]+(?:\.[0-9]+)?)(?:Hz)?$/i)
  if (!match) return null

  var width = Number(match[1])
  var height = Number(match[2])
  var refreshRate = Number(match[3])
  if (width <= 0 || height <= 0 || !isFinite(refreshRate) || refreshRate <= 0) return null

  return {
    width: width,
    height: height,
    refreshRate: refreshRate,
    value: width + "x" + height + "@" + String(refreshRate)
  }
}

function availableResolutions(modes, preferredResolution) {
  var seen = {}
  var resolutions = []
  for (var i = 0; Array.isArray(modes) && i < modes.length; i++) {
    var parsed = parseDisplayMode(modes[i])
    if (!parsed) continue
    var key = parsed.width + "x" + parsed.height
    if (seen[key]) continue
    seen[key] = true
    resolutions.push({
      value: parsed.value,
      width: parsed.width,
      height: parsed.height,
      refreshRate: parsed.refreshRate
    })
  }

  var preferred = String(preferredResolution || "").match(/^(\d+)x(\d+)/)
  var preferredKey = preferred ? Number(preferred[1]) + "x" + Number(preferred[2]) : ""
  if (!seen[preferredKey] && resolutions.length > 0)
    preferredKey = resolutions[0].width + "x" + resolutions[0].height

  resolutions.forEach(function(resolution) {
    resolution.recommended = resolution.width + "x" + resolution.height === preferredKey
    resolution.label = resolution.width + " × " + resolution.height
      + (resolution.recommended ? " (Recommended)" : "")
  })
  resolutions.sort(function(a, b) {
    return a.recommended === b.recommended ? 0 : (a.recommended ? -1 : 1)
  })
  return resolutions
}

function matchingResolutionValue(options, width, height) {
  var targetWidth = Math.round(finiteNumber(width, 0))
  var targetHeight = Math.round(finiteNumber(height, 0))
  for (var i = 0; Array.isArray(options) && i < options.length; i++) {
    if (Number(options[i].width) === targetWidth && Number(options[i].height) === targetHeight)
      return String(options[i].value || "")
  }
  return ""
}

function availableRefreshRates(modes, width, height) {
  var targetWidth = Math.round(finiteNumber(width, 0))
  var targetHeight = Math.round(finiteNumber(height, 0))
  var seen = {}
  var rates = []
  for (var i = 0; Array.isArray(modes) && i < modes.length; i++) {
    var parsed = parseDisplayMode(modes[i])
    if (!parsed || parsed.width !== targetWidth || parsed.height !== targetHeight) continue
    var key = String(parsed.refreshRate)
    if (seen[key]) continue
    seen[key] = true
    rates.push({ value: key, refreshRate: parsed.refreshRate, label: key + " Hz" })
  }
  rates.sort(function(a, b) { return b.refreshRate - a.refreshRate })
  return rates
}

function matchingRefreshRateValue(options, refreshRate) {
  var target = Number(refreshRate)
  if (!isFinite(target)) return ""
  for (var i = 0; Array.isArray(options) && i < options.length; i++) {
    if (Math.abs(Number(options[i].refreshRate) - target) <= 0.01)
      return String(options[i].value || "")
  }
  return ""
}

function preferredRefreshRate(options, currentRefreshRate) {
  var current = matchingRefreshRateValue(options, currentRefreshRate)
  return current || (Array.isArray(options) && options.length > 0
    ? String(options[0].value || "") : "")
}

function cleanTransform(transform) {
  var value = Number(transform)
  if (!isFinite(value) || Math.floor(value) !== value || value < 0 || value > 7) return 0
  return value
}

function stageDisplaySettings(displays, stagedSettings, targetName, overrides) {
  var next = {}
  var source = stagedSettings || {}
  Object.keys(source).forEach(function(name) {
    next[name] = Object.assign({}, source[name])
  })

  var target = null
  for (var i = 0; Array.isArray(displays) && i < displays.length; i++) {
    if (displays[i] && displays[i].name === targetName) {
      target = displays[i]
      break
    }
  }
  if (!target) return next

  var merged = Object.assign({}, next[targetName] || {}, overrides || {})
  var staged = {}
  var fields = ["width", "height", "refreshRate", "scale", "transform"]
  for (var j = 0; j < fields.length; j++) {
    var field = fields[j]
    if (merged[field] === undefined) continue
    var value = Number(merged[field])
    var actual = field === "transform"
      ? cleanTransform(target[field]) : Number(target[field])
    if (!isFinite(value)) continue
    if (field === "transform") {
      if (Math.floor(value) !== value || value < 0 || value > 7) continue
    } else if (value <= 0) continue
    if (field === "width" || field === "height") value = Math.round(value)
    var tolerance = field === "refreshRate" ? 0.01 : 0.0001
    if (!isFinite(actual) || Math.abs(value - actual) > tolerance) staged[field] = value
  }

  if (Object.keys(staged).length > 0) next[targetName] = staged
  else delete next[targetName]
  return next
}

function displaysWithSettings(displays, stagedSettings) {
  var settings = stagedSettings || {}
  return (Array.isArray(displays) ? displays : []).map(function(display) {
    if (!display) return display
    return Object.assign({}, display, settings[display.name] || {})
  })
}

function retainDisplaySettings(displays, stagedSettings) {
  var enabled = {}
  for (var i = 0; Array.isArray(displays) && i < displays.length; i++) {
    if (displays[i] && displays[i].enabled) enabled[displays[i].name] = true
  }

  var retained = {}
  var settings = stagedSettings || {}
  Object.keys(settings).forEach(function(name) {
    if (enabled[name]) retained[name] = Object.assign({}, settings[name])
  })
  return retained
}

function brightnessName(percent) {
  var p = Math.round(percent)
  if (p >= 95) return "Sun blast"
  if (p >= 80) return "Solar flare"
  if (p >= 65) return "Golden hour"
  if (p >= 45) return "Even day"
  if (p >= 30) return "Soft glow"
  if (p >= 20) return "Lamp light"
  if (p >= 10) return "Candlelit"
  return "Night owl"
}

function finiteNumber(value, fallback) {
  var number = Number(value)
  return isFinite(number) ? number : fallback
}

function responsiveDisplayUtilization(displayCount) {
  var count = Math.max(1, Math.floor(finiteNumber(displayCount, 1)))
  // Scale by sqrt(count) so workspace area grows with every display. The
  // conservative coefficient also leaves enough centered travel to pull two
  // identical, fully overlapped monitors completely beside one another.
  return Math.max(0.1, Math.min(0.34, 0.46 / Math.sqrt(count)))
}

function cycleDisplayIndex(currentIndex, displayCount, direction) {
  var count = Math.max(0, Math.floor(finiteNumber(displayCount, 0)))
  if (count === 0) return -1

  var current = Math.floor(finiteNumber(currentIndex, -1))
  var step = finiteNumber(direction, 1) < 0 ? -1 : 1
  if (current < 0 || current >= count) return step < 0 ? count - 1 : 0
  return (current + step + count) % count
}

function displayLabel(display) {
  var name = String(display && display.name || "").trim()
  if (/^(eDP|LVDS|DSI)-/i.test(name)) return "Built-in Display"

  var make = String(display && display.make || "").trim()
  var model = String(display && display.model || "").trim()
  var description = String(display && display.description || "").trim()

  make = make
    .replace(/\s+(Electric Company|Electronics|Incorporated|Inc\.?|Corporation|Corp\.?|Co\.,?\s*Ltd\.?|Ltd\.?)$/i, "")
    .trim()

  if (make && model && model.toLowerCase().indexOf(make.toLowerCase()) === 0) return model
  if (make && model) return make + " " + model
  if (model) return model
  if (make) return make
  return description || name
}

function fitDisplayLayout(displays, canvasWidth, canvasHeight, padding, utilization) {
  var usable = []
  var inset = Math.max(0, finiteNumber(padding, 0))
  var width = Math.max(1, finiteNumber(canvasWidth, 1) - inset * 2)
  var height = Math.max(1, finiteNumber(canvasHeight, 1) - inset * 2)
  var fill = Math.max(0.1, Math.min(1, finiteNumber(utilization, 0.8)))

  for (var i = 0; Array.isArray(displays) && i < displays.length; i++) {
    var display = displays[i]
    var scale = Math.max(0.01, finiteNumber(display && display.scale, 1))
    var pixelWidth = finiteNumber(display && display.width, 0)
    var pixelHeight = finiteNumber(display && display.height, 0)
    if (!display || display.enabled === false || pixelWidth <= 0 || pixelHeight <= 0) continue
    var transform = cleanTransform(display.transform)
    var rotated = transform % 2 === 1

    usable.push({
      name: String(display.name || ""),
      label: displayLabel(display),
      focused: display.focused === true,
      mirrorOf: display.mirrorOf && display.mirrorOf !== "none" ? String(display.mirrorOf) : null,
      logicalX: finiteNumber(display.x, 0),
      logicalY: finiteNumber(display.y, 0),
      logicalWidth: (rotated ? pixelHeight : pixelWidth) / scale,
      logicalHeight: (rotated ? pixelWidth : pixelHeight) / scale,
      modeLabel: pixelWidth + " × " + pixelHeight + (Math.abs(scale - 1) > 0.001
        ? " · " + Math.round(scale * 100) / 100 + "x" : "")
    })
  }

  if (usable.length === 0) return { items: [], scale: 1, padding: inset }

  var minX = usable[0].logicalX
  var minY = usable[0].logicalY
  var maxX = usable[0].logicalX + usable[0].logicalWidth
  var maxY = usable[0].logicalY + usable[0].logicalHeight
  for (var j = 1; j < usable.length; j++) {
    minX = Math.min(minX, usable[j].logicalX)
    minY = Math.min(minY, usable[j].logicalY)
    maxX = Math.max(maxX, usable[j].logicalX + usable[j].logicalWidth)
    maxY = Math.max(maxY, usable[j].logicalY + usable[j].logicalHeight)
  }

  // Leave working room around the detected arrangement. If the initial
  // monitors fill the canvas exactly, an edge monitor cannot be dropped any
  // farther outward because moveDisplayInCanvas has no valid space there.
  var factor = Math.min(width / Math.max(1, maxX - minX), height / Math.max(1, maxY - minY)) * fill
  var offsetX = (width / factor - (maxX - minX)) / 2
  var offsetY = (height / factor - (maxY - minY)) / 2
  var items = usable.map(function(display) {
    var logicalX = display.logicalX - minX + offsetX
    var logicalY = display.logicalY - minY + offsetY
    return {
      name: display.name,
      label: display.label,
      focused: display.focused,
      mirrorOf: display.mirrorOf,
      logicalX: logicalX,
      logicalY: logicalY,
      logicalWidth: display.logicalWidth,
      logicalHeight: display.logicalHeight,
      x: inset + logicalX * factor,
      y: inset + logicalY * factor,
      width: display.logicalWidth * factor,
      height: display.logicalHeight * factor,
      modeLabel: display.modeLabel
    }
  })

  return { items: items, scale: factor, padding: inset }
}

function normalizeDisplayLayout(items) {
  if (!Array.isArray(items) || items.length === 0) return []

  var rounded = items.map(function(item) {
    return {
      name: String(item && item.name || ""),
      x: Math.round(finiteNumber(item && item.logicalX, 0)),
      y: Math.round(finiteNumber(item && item.logicalY, 0))
    }
  })
  var minX = rounded.reduce(function(value, item) { return Math.min(value, item.x) }, rounded[0].x)
  var minY = rounded.reduce(function(value, item) { return Math.min(value, item.y) }, rounded[0].y)

  return rounded.map(function(item) {
    return { name: item.name, x: item.x - minX, y: item.y - minY }
  })
}

function refitDisplayLayout(displays, previewItems, canvasWidth, canvasHeight, padding, utilization) {
  var positions = normalizeDisplayLayout(previewItems)
  if (positions.length === 0)
    return fitDisplayLayout(displays, canvasWidth, canvasHeight, padding, utilization)

  var byName = {}
  for (var i = 0; i < positions.length; i++) byName[positions[i].name] = positions[i]

  var staged = (Array.isArray(displays) ? displays : []).map(function(display) {
    var position = display && byName[display.name]
    if (!position) return display
    return Object.assign({}, display, { x: position.x, y: position.y })
  })

  return fitDisplayLayout(staged, canvasWidth, canvasHeight, padding, utilization)
}

function nearestSnap(value, candidates, threshold) {
  var best = value
  var distance = Math.max(0, finiteNumber(threshold, 0)) + 0.0001
  for (var i = 0; i < candidates.length; i++) {
    var candidateDistance = Math.abs(value - candidates[i])
    if (candidateDistance < distance) {
      best = candidates[i]
      distance = candidateDistance
    }
  }
  return best
}

function snapDisplayPosition(moving, others, threshold) {
  var xCandidates = []
  var yCandidates = []
  var movingWidth = finiteNumber(moving && moving.logicalWidth, 0)
  var movingHeight = finiteNumber(moving && moving.logicalHeight, 0)

  for (var i = 0; Array.isArray(others) && i < others.length; i++) {
    var other = others[i]
    if (!other || other.name === moving.name) continue
    var ox = finiteNumber(other.logicalX, 0)
    var oy = finiteNumber(other.logicalY, 0)
    var ow = finiteNumber(other.logicalWidth, 0)
    var oh = finiteNumber(other.logicalHeight, 0)
    xCandidates.push(ox - movingWidth, ox, ox + ow - movingWidth, ox + ow)
    yCandidates.push(oy - movingHeight, oy, oy + oh - movingHeight, oy + oh)
  }

  return {
    x: nearestSnap(finiteNumber(moving && moving.logicalX, 0), xCandidates, threshold),
    y: nearestSnap(finiteNumber(moving && moving.logicalY, 0), yCandidates, threshold)
  }
}

// ---- Edge snapping --------------------------------------------------------
// Hyprland moves the cursor between outputs only across a shared edge. A gap
// strands the cursor at the edge; an overlap draws the cursor (and anything
// dragged) on both outputs. So the arrangement is kept as one connected group
// of rectangles that touch along real edges and never overlap, like macOS.
// Rects here are { name, x, y, w, h } in logical pixels.

var EDGE_EPSILON = 0.5

function sharedSpan(start, length, otherStart, otherLength) {
  return Math.min(start + length, otherStart + otherLength) - Math.max(start, otherStart)
}

function rectsOverlap(a, b) {
  return sharedSpan(a.x, a.w, b.x, b.w) > EDGE_EPSILON
    && sharedSpan(a.y, a.h, b.y, b.h) > EDGE_EPSILON
}

function rectsTouch(a, b) {
  var vertical = Math.abs(a.x + a.w - b.x) <= EDGE_EPSILON || Math.abs(b.x + b.w - a.x) <= EDGE_EPSILON
  var horizontal = Math.abs(a.y + a.h - b.y) <= EDGE_EPSILON || Math.abs(b.y + b.h - a.y) <= EDGE_EPSILON
  return (vertical && sharedSpan(a.y, a.h, b.y, b.h) > EDGE_EPSILON)
    || (horizontal && sharedSpan(a.x, a.w, b.x, b.w) > EDGE_EPSILON)
}

function rectFits(rect, placed) {
  var touches = false
  for (var i = 0; i < placed.length; i++) {
    if (rectsOverlap(rect, placed[i])) return false
    if (!touches && rectsTouch(rect, placed[i])) touches = true
  }
  return touches
}

// Where along target's edge the moving rect may sit: the shared edge must be
// long enough for the cursor to find it, and the spot nearest the desired one
// wins, pulled onto a start or end alignment when within alignThreshold.
function slideAlongEdge(desired, length, targetStart, targetLength, alignThreshold) {
  var minShared = Math.min(100, Math.min(length, targetLength) / 4)
  var low = targetStart - length + minShared
  var high = targetStart + targetLength - minShared
  var value = Math.max(low, Math.min(high, desired))
  var aligned = [targetStart, targetStart + targetLength - length]
  var best = value
  var distance = Math.max(0, finiteNumber(alignThreshold, 0)) + 0.0001
  for (var i = 0; i < aligned.length; i++) {
    var d = Math.abs(desired - aligned[i])
    if (d < distance && aligned[i] >= low - EDGE_EPSILON && aligned[i] <= high + EDGE_EPSILON) {
      best = aligned[i]
      distance = d
    }
  }
  return best
}

// Put rect against the nearest free edge of any placed rect, as close to
// (desiredX, desiredY) as possible. A drop that already touches and overlaps
// nothing keeps its spot, apart from alignment.
function attachRect(rect, desiredX, desiredY, placed, alignThreshold) {
  if (!placed.length) return Object.assign({}, rect, { x: desiredX, y: desiredY })
  var best = null
  var bestDistance = Infinity
  function consider(x, y) {
    var candidate = Object.assign({}, rect, { x: x, y: y })
    if (!rectFits(candidate, placed)) return
    var distance = Math.hypot(x - desiredX, y - desiredY)
    if (distance < bestDistance - 0.0001) {
      best = candidate
      bestDistance = distance
    }
  }
  for (var i = 0; i < placed.length; i++) {
    var t = placed[i]
    var alongY = slideAlongEdge(desiredY, rect.h, t.y, t.h, alignThreshold)
    var alongX = slideAlongEdge(desiredX, rect.w, t.x, t.w, alignThreshold)
    consider(t.x + t.w, alongY)
    consider(t.x - rect.w, alongY)
    consider(alongX, t.y + t.h)
    consider(alongX, t.y - rect.h)
  }
  if (best) return best
  // Every edge near the drop is blocked: go beside the whole group instead.
  var right = -Infinity
  var top = 0
  for (var j = 0; j < placed.length; j++) {
    if (placed[j].x + placed[j].w > right) {
      right = placed[j].x + placed[j].w
      top = placed[j].y
    }
  }
  return Object.assign({}, rect, { x: right, y: top })
}

// Make rects one connected, non-overlapping group. rects[0] never moves; the
// rest keep their spot when they already fit against what is placed, and
// otherwise attach at the nearest free edge. Order is priority.
function connectRects(rects, alignThreshold) {
  if (!Array.isArray(rects) || rects.length < 2) return (rects || []).slice()
  var placed = [Object.assign({}, rects[0])]
  var remaining = rects.slice(1)
  while (remaining.length) {
    var index = -1
    for (var i = 0; i < remaining.length; i++) {
      if (rectFits(remaining[i], placed)) { index = i; break }
    }
    if (index >= 0) {
      placed.push(Object.assign({}, remaining[index]))
    } else {
      // Nothing fits as-is: move the one closest to the group the least.
      var nearest = 0
      var nearestGap = Infinity
      for (var k = 0; k < remaining.length; k++) {
        for (var p = 0; p < placed.length; p++) {
          var r = remaining[k]
          var o = placed[p]
          var gap = Math.hypot(Math.max(0, o.x - (r.x + r.w), r.x - (o.x + o.w)),
                               Math.max(0, o.y - (r.y + r.h), r.y - (o.y + o.h)))
          if (gap < nearestGap) { nearestGap = gap; nearest = k }
        }
      }
      index = nearest
      placed.push(attachRect(remaining[index], remaining[index].x, remaining[index].y, placed, alignThreshold))
    }
    remaining.splice(index, 1)
  }
  var byName = {}
  for (var n = 0; n < placed.length; n++) byName[placed[n].name] = placed[n]
  return rects.map(function(rect) { return byName[rect.name] })
}

function moveDisplayInCanvas(items, name, canvasX, canvasY, scale, padding, canvasWidth, canvasHeight, snapPixels) {
  if (!Array.isArray(items)) return []
  var factor = Math.max(0.0001, finiteNumber(scale, 1))
  var inset = Math.max(0, finiteNumber(padding, 0))
  var moving = items.find(function(item) { return item && item.name === name })
  if (!moving) return items.slice()

  var toRect = function(item) {
    return { name: item.name, x: finiteNumber(item.logicalX, 0), y: finiteNumber(item.logicalY, 0),
             w: finiteNumber(item.logicalWidth, 0), h: finiteNumber(item.logicalHeight, 0) }
  }
  var others = items.filter(function(item) { return item && item.name !== name && !item.mirrorOf })
  var desiredX = (finiteNumber(canvasX, inset) - inset) / factor
  var desiredY = (finiteNumber(canvasY, inset) - inset) / factor
  var threshold = finiteNumber(snapPixels, 0) / factor
  var attached = attachRect(toRect(moving), desiredX, desiredY, others.map(toRect), threshold)
  // The moved display may have been the bridge between others; reconnect them
  // around its new spot without moving it.
  var settled = connectRects([attached].concat(others.map(toRect)), threshold)
  var byName = {}
  for (var i = 0; i < settled.length; i++) byName[settled[i].name] = settled[i]

  // Positions can go negative (dropped left of or above everything); the
  // caller refits the canvas, which normalizes them back into view.
  return items.map(function(item) {
    var rect = item && byName[item.name]
    if (!rect) return Object.assign({}, item)
    return Object.assign({}, item, {
      logicalX: rect.x, logicalY: rect.y,
      x: inset + rect.x * factor, y: inset + rect.y * factor
    })
  })
}

function payloadRect(record) {
  var rotated = cleanTransform(record.transform) % 2 === 1
  var scale = Math.max(0.01, finiteNumber(record.scale, 1))
  var width = finiteNumber(record.width, 0)
  var height = finiteNumber(record.height, 0)
  return { name: String(record.name), x: finiteNumber(record.x, 0), y: finiteNumber(record.y, 0),
           w: (rotated ? height : width) / scale, h: (rotated ? width : height) / scale }
}

function arrangedRecord(record) {
  return record && record.enabled !== false && !record.mirrorOf
    && finiteNumber(record.width, 0) > 0 && finiteNumber(record.height, 0) > 0
}

// Keep a proposed full-topology payload edge-to-edge. When a display's logical
// size changes (scale, resolution, rotation) the displays that sat to its
// right or below it shift by the same amount, so neighbours stay attached the
// way they were; anything still overlapping or detached is then reattached.
// Displays whose size and position did not change anchor the result.
function snapTopologyPayload(proposed, previous) {
  if (!Array.isArray(proposed)) return proposed
  var before = {}
  for (var i = 0; Array.isArray(previous) && i < previous.length; i++) {
    if (arrangedRecord(previous[i])) before[previous[i].name] = payloadRect(previous[i])
  }
  var records = proposed.filter(arrangedRecord)
  if (records.length < 2) return proposed

  var rects = records.map(payloadRect)
  var shifted = rects.map(function(rect) { return Object.assign({}, rect) })
  for (var d = 0; d < rects.length; d++) {
    var old = before[rects[d].name]
    if (!old || Math.abs(old.x - rects[d].x) > EDGE_EPSILON || Math.abs(old.y - rects[d].y) > EDGE_EPSILON) continue
    var dw = rects[d].w - old.w
    var dh = rects[d].h - old.h
    if (Math.abs(dw) <= EDGE_EPSILON && Math.abs(dh) <= EDGE_EPSILON) continue
    for (var o = 0; o < rects.length; o++) {
      var other = before[rects[o].name]
      if (o === d || !other) continue
      if (Math.abs(other.x - rects[o].x) > EDGE_EPSILON || Math.abs(other.y - rects[o].y) > EDGE_EPSILON) continue
      if (other.x >= old.x + old.w - EDGE_EPSILON) shifted[o].x += dw
      if (other.y >= old.y + old.h - EDGE_EPSILON) shifted[o].y += dh
    }
  }

  function unchanged(rect) {
    var old = before[rect.name]
    return old && Math.abs(old.x - rect.x) <= EDGE_EPSILON && Math.abs(old.y - rect.y) <= EDGE_EPSILON
      && Math.abs(old.w - rect.w) <= EDGE_EPSILON && Math.abs(old.h - rect.h) <= EDGE_EPSILON
  }
  var order = shifted.map(function(rect, index) { return { rect: rect, stable: unchanged(rects[index]) } })
  order.sort(function(a, b) { return (b.stable ? 1 : 0) - (a.stable ? 1 : 0) })
  var settled = connectRects(order.map(function(entry) {
    return Object.assign({}, entry.rect, { x: Math.round(entry.rect.x), y: Math.round(entry.rect.y) })
  }), 0)
  var byName = {}
  for (var s = 0; s < settled.length; s++) byName[settled[s].name] = settled[s]
  return proposed.map(function(record) {
    var rect = record && arrangedRecord(record) && byName[record.name]
    if (!rect) return record
    return Object.assign({}, record, { x: Math.round(rect.x), y: Math.round(rect.y) })
  })
}

function buildDisplayLayoutPayload(displays, previewItems, stagedSettings) {
  var normalized = normalizeDisplayLayout(previewItems)
  var byName = {}
  var settings = stagedSettings || {}
  for (var i = 0; Array.isArray(displays) && i < displays.length; i++) {
    if (displays[i] && displays[i].enabled !== false) byName[displays[i].name] = displays[i]
  }

  return normalized.map(function(position) {
    var display = byName[position.name] || {}
    var staged = settings[position.name] || {}
    return {
      name: position.name,
      x: position.x,
      y: position.y,
      width: Math.round(finiteNumber(staged.width, finiteNumber(display.width, 0))),
      height: Math.round(finiteNumber(staged.height, finiteNumber(display.height, 0))),
      refreshRate: finiteNumber(staged.refreshRate, finiteNumber(display.refreshRate, 60)),
      scale: finiteNumber(staged.scale, finiteNumber(display.scale, 1)),
      transform: cleanTransform(staged.transform !== undefined
                                ? staged.transform : display.transform)
    }
  }).filter(function(display) {
    return display.name !== "" && display.width > 0 && display.height > 0 && display.scale > 0
  })
}

function buildMonitorSettingPayload(displays, targetName, overrides) {
  var enabled = (Array.isArray(displays) ? displays : []).filter(function(display) {
    return display && display.enabled !== false
  })
  if (enabled.length === 0) return []

  var minX = enabled.reduce(function(value, display) {
    return Math.min(value, Math.round(finiteNumber(display.x, 0)))
  }, Math.round(finiteNumber(enabled[0].x, 0)))
  var minY = enabled.reduce(function(value, display) {
    return Math.min(value, Math.round(finiteNumber(display.y, 0)))
  }, Math.round(finiteNumber(enabled[0].y, 0)))
  var changes = overrides || {}

  return enabled.map(function(display) {
    var targeted = String(display.name || "") === String(targetName || "")
    return {
      name: String(display.name || ""),
      x: Math.round(finiteNumber(display.x, 0)) - minX,
      y: Math.round(finiteNumber(display.y, 0)) - minY,
      width: Math.round(finiteNumber(targeted ? changes.width : undefined,
                                     finiteNumber(display.width, 0))),
      height: Math.round(finiteNumber(targeted ? changes.height : undefined,
                                      finiteNumber(display.height, 0))),
      refreshRate: finiteNumber(targeted ? changes.refreshRate : undefined,
                                finiteNumber(display.refreshRate, 60)),
      scale: finiteNumber(targeted ? changes.scale : undefined,
                          finiteNumber(display.scale, 1)),
      transform: cleanTransform(targeted && changes.transform !== undefined
                                ? changes.transform : display.transform)
    }
  }).filter(function(display) {
    return display.name !== "" && display.width > 0 && display.height > 0 && display.scale > 0
  })
}

function prepareDisplaySettingPreview(displays, stagedSettings, targetName, overrides, buildPayload) {
  var nextSettings = stageDisplaySettings(displays, stagedSettings, targetName, overrides)
  var targetSettings = nextSettings[targetName]
  if (!targetSettings || Object.keys(targetSettings).length === 0) {
    return {
      changed: false,
      stagedSettings: nextSettings,
      previous: [],
      proposed: []
    }
  }

  if (typeof buildPayload === "function") {
    return {
      changed: true,
      stagedSettings: nextSettings,
      previous: buildPayload(displays, stagedSettings || {}),
      proposed: buildPayload(displays, nextSettings)
    }
  }

  return {
    changed: true,
    stagedSettings: nextSettings,
    previous: buildMonitorSettingPayload(displays, "", {}),
    proposed: buildMonitorSettingPayload(displays, targetName, targetSettings)
  }
}

function advanceDisplayConfirmation(seconds) {
  var remaining = Math.max(0, Math.floor(finiteNumber(seconds, 0)) - 1)
  return { remaining: remaining, expired: remaining === 0 }
}

function parsePendingDisplayTransaction(raw) {
  var value
  try {
    value = raw ? JSON.parse(String(raw)) : null
  } catch (e) {
    return null
  }

  if (!value || typeof value !== "object") return null
  var id = String(value.id || "")
  var scope = String(value.scope || "")
  var originScreen = String(value.originScreen || "")
  var originWorkspace = Math.floor(Number(value.originWorkspace || 0))
  var remaining = Math.floor(Number(value.remainingSeconds))
  if (!/^[A-Za-z0-9._-]+$/.test(id)
      || (scope !== "layout" && scope !== "settings" && scope !== "topology")
      || (originScreen !== "" && !/^[A-Za-z0-9._:-]+$/.test(originScreen))
      || !isFinite(originWorkspace) || originWorkspace < 0
      || !isFinite(remaining) || remaining < 1) return null

  return {
    id: id,
    scope: scope,
    remainingSeconds: remaining,
    originScreen: originScreen,
    originWorkspace: originWorkspace
  }
}

function confirmationTargetScreen(preferredScreen, workspaceScreen, focusedScreen,
                                  availableScreens) {
  var preferred = String(preferredScreen || "")
  var workspace = String(workspaceScreen || "")
  var focused = String(focusedScreen || "")
  var seen = {}
  var screens = []
  for (var i = 0; Array.isArray(availableScreens) && i < availableScreens.length; i++) {
    var name = String(availableScreens[i] || "")
    if (!name || seen[name]) continue
    seen[name] = true
    screens.push(name)
  }
  screens.sort()
  if (preferred && seen[preferred]) return preferred
  if (workspace && seen[workspace]) return workspace
  if (focused && seen[focused]) return focused
  return screens.length > 0 ? screens[0] : ""
}

function ownsDisplayConfirmation(hostScreen, preferredScreen, workspaceScreen,
                                 focusedScreen, availableScreens) {
  var target = confirmationTargetScreen(
    preferredScreen, workspaceScreen, focusedScreen, availableScreens)
  return target !== "" && String(hostScreen || "") === target
}

function ownsDisplayIpc(hostScreen, availableScreens) {
  var wanted = String(hostScreen || "")
  if (!wanted) return false

  var seen = {}
  var names = []
  for (var i = 0; Array.isArray(availableScreens) && i < availableScreens.length; i++) {
    var name = String(availableScreens[i] || "")
    if (!name || seen[name]) continue
    seen[name] = true
    names.push(name)
  }
  names.sort()
  return names.length > 0 && wanted === names[0]
}

function workspaceNumber(value, maximum) {
  var text = String(value === undefined || value === null ? "" : value).trim()
  if (!/^\d+$/.test(text)) return 0
  var number = Number(text)
  return number >= 1 && number <= maximum ? Math.floor(number) : 0
}

function workspaceAssignments(displays, workspaces, rules, maximum) {
  var limit = Math.max(1, Math.floor(finiteNumber(maximum, 10)))
  var enabledMonitors = {}
  for (var i = 0; Array.isArray(displays) && i < displays.length; i++) {
    var display = displays[i]
    if (display && display.enabled !== false && display.name)
      enabledMonitors[String(display.name)] = true
  }

  var assignments = {}
  for (var j = 0; Array.isArray(workspaces) && j < workspaces.length; j++) {
    var workspace = workspaces[j] || {}
    var number = workspaceNumber(workspace.name !== undefined ? workspace.name : workspace.id, limit)
    var monitor = String(workspace.monitor || "")
    if (number > 0 && enabledMonitors[monitor]) assignments[String(number)] = monitor
  }

  for (var k = 0; Array.isArray(rules) && k < rules.length; k++) {
    var rule = rules[k] || {}
    var ruleNumber = workspaceNumber(
      rule.workspaceString !== undefined ? rule.workspaceString : rule.workspace, limit)
    var ruleMonitor = String(rule.monitor || "")
    if (ruleNumber > 0 && enabledMonitors[ruleMonitor])
      assignments[String(ruleNumber)] = ruleMonitor
  }
  return assignments
}

function workspacesForMonitor(assignments, monitorName) {
  var target = String(monitorName || "")
  return Object.keys(assignments || {}).filter(function(number) {
    return String(assignments[number]) === target
  }).map(Number).filter(function(number) {
    return isFinite(number) && number > 0
  }).sort(function(a, b) { return a - b })
}

function toggleWorkspaceAssignment(assignments, workspace, monitorName) {
  var number = workspaceNumber(workspace, 10)
  var monitor = String(monitorName || "")
  var next = {}
  Object.keys(assignments || {}).forEach(function(key) {
    next[key] = String(assignments[key])
  })
  if (number === 0 || monitor === "") return next

  var key = String(number)
  if (next[key] === monitor) delete next[key]
  else next[key] = monitor
  return next
}

function workspaceAssignmentsEqual(left, right) {
  var leftKeys = Object.keys(left || {}).sort()
  var rightKeys = Object.keys(right || {}).sort()
  if (leftKeys.length !== rightKeys.length) return false
  for (var i = 0; i < leftKeys.length; i++) {
    var key = leftKeys[i]
    if (key !== rightKeys[i] || String(left[key]) !== String(right[key])) return false
  }
  return true
}

function parseDisplays(raw) {
  var displays = []
  try {
    displays = raw ? JSON.parse(String(raw)) : []
  } catch (e) {
    displays = []
  }
  if (!Array.isArray(displays)) displays = []

  var count = 0
  for (var i = 0; i < displays.length; i++) {
    if (displays[i] && displays[i].enabled) count++
  }

  return {
    displays: displays,
    enabledDisplayCount: count
  }
}

function shouldAutoResetDisplayLayout(state) {
  state = state || {}
  return !state.dirty && !state.dragging && !state.confirmationPending && !state.applying
}

function displayConfirmationPolicy(match) {
  match = match || {}
  var status = String(match.status || "new")
  var profileId = String(match.profileId || "")

  if (status === "moved") {
    return {
      kind: "choose-profile",
      profileId: profileId,
      message: "These displays moved connectors. Update the existing profile or save this layout as a new profile."
    }
  }
  if (status === "weak" || status === "ambiguous") {
    return {
      kind: "identify-first",
      profileId: profileId,
      message: "Displays cannot safely match these displays. Revert, then use Identify before applying again."
    }
  }
  return { kind: "keep", profileId: profileId, message: "" }
}

function nextExpandedSection(current, requested) {
  return String(current || "") === String(requested || "")
    ? "" : String(requested || "")
}

// ---- Mode choices and native-mode insight (EDID aware) ----
//
// Displays carry `availableModes` (Hyprland's list plus EDID timings it lacks),
// `advertisedModes` (Hyprland's own list) and `nativeMode` (the EDID preferred
// timing). A mode is "EDID only" when Hyprland never offered it: it can still be
// applied as an exact modeline, but the connection may not carry it.

function modeAdvertised(advertisedModes, width, height, refreshRate) {
  for (var i = 0; Array.isArray(advertisedModes) && i < advertisedModes.length; i++) {
    var parsed = parseDisplayMode(advertisedModes[i])
    if (parsed && parsed.width === width && parsed.height === height
        && (refreshRate === undefined || Math.abs(parsed.refreshRate - refreshRate) <= 0.05))
      return true
  }
  return false
}

function refreshLabel(rate, allRates) {
  var rounded = Math.round(rate)
  var clash = false
  for (var i = 0; Array.isArray(allRates) && i < allRates.length; i++) {
    if (allRates[i] !== rate && Math.round(allRates[i]) === rounded) clash = true
  }
  return (clash ? String(Math.round(rate * 100) / 100) : String(rounded)) + " Hz"
}

function resolutionChoices(modes, advertisedModes, nativeMode, preferredResolution) {
  var nativeKey = nativeMode ? nativeMode.width + "x" + nativeMode.height : ""
  var preferred = String(preferredResolution || "").match(/^(\d+)x(\d+)/)
  if (!nativeKey && preferred) nativeKey = Number(preferred[1]) + "x" + Number(preferred[2])
  var byKey = {}
  var list = []
  for (var i = 0; Array.isArray(modes) && i < modes.length; i++) {
    var parsed = parseDisplayMode(modes[i])
    if (!parsed) continue
    var key = parsed.width + "x" + parsed.height
    var advertised = modeAdvertised(advertisedModes, parsed.width, parsed.height, parsed.refreshRate)
    var entry = byKey[key]
    if (!entry) {
      entry = byKey[key] = { width: parsed.width, height: parsed.height,
                             maxRefresh: 0, bestAdvertised: 0, advertised: false }
      list.push(entry)
    }
    entry.maxRefresh = Math.max(entry.maxRefresh, parsed.refreshRate)
    if (advertised) {
      entry.advertised = true
      entry.bestAdvertised = Math.max(entry.bestAdvertised, parsed.refreshRate)
    }
  }
  list.forEach(function(entry) {
    entry.native = entry.width + "x" + entry.height === nativeKey
    entry.edidOnly = !entry.advertised
    var rate = entry.advertised ? entry.bestAdvertised : entry.maxRefresh
    entry.value = entry.width + "x" + entry.height + "@" + String(rate)
    entry.refreshRate = rate
    entry.label = entry.width + " × " + entry.height
      + (entry.native ? "  · native" : "")
      + (entry.edidOnly ? "  · from EDID" : "")
  })
  list.sort(function(a, b) {
    if (a.native !== b.native) return a.native ? -1 : 1
    return b.width * b.height - a.width * a.height || b.width - a.width
  })
  return list
}

function refreshChoices(modes, advertisedModes, width, height) {
  var targetWidth = Math.round(finiteNumber(width, 0))
  var targetHeight = Math.round(finiteNumber(height, 0))
  var rates = []
  for (var i = 0; Array.isArray(modes) && i < modes.length; i++) {
    var parsed = parseDisplayMode(modes[i])
    if (!parsed || parsed.width !== targetWidth || parsed.height !== targetHeight) continue
    var duplicate = false
    for (var j = 0; j < rates.length; j++)
      if (Math.abs(rates[j].refreshRate - parsed.refreshRate) <= 0.05) duplicate = true
    if (duplicate) continue
    rates.push({ value: String(parsed.refreshRate), refreshRate: parsed.refreshRate,
                 edidOnly: !modeAdvertised(advertisedModes, parsed.width, parsed.height, parsed.refreshRate) })
  }
  rates.sort(function(a, b) { return b.refreshRate - a.refreshRate })
  var all = rates.map(function(r) { return r.refreshRate })
  rates.forEach(function(r) { r.label = refreshLabel(r.refreshRate, all) })
  return rates
}

function formatMode(width, height, refreshRate) {
  return width + " × " + height + " @ " + refreshLabel(Number(refreshRate), [])
}

// Explains how the current mode relates to what the monitor and connection
// can do, and proposes the one-click best mode.
//   level: "ok" | "suggest" | "limited" | "unknown"
function modeInsight(display) {
  var result = { level: "unknown", title: "", detail: "", recommendation: null, nativeLabel: "" }
  if (!display) return result
  var modes = display.availableModes || []
  var advertised = display.advertisedModes || modes
  var native = display.nativeMode
  if (!native) {
    var first = parseDisplayMode(advertised[0])
    if (first) native = { width: first.width, height: first.height, refreshRate: first.refreshRate }
  }
  if (!native) {
    result.title = "Native mode unknown"
    result.detail = "This display did not provide readable EDID data."
    return result
  }

  var nativeRates = refreshChoices(modes, advertised, native.width, native.height)
  var offered = nativeRates.filter(function(r) { return !r.edidOnly })
  var edidOnly = nativeRates.filter(function(r) { return r.edidOnly })
  var monitorMax = nativeRates.length ? nativeRates[0].refreshRate : native.refreshRate
  result.nativeLabel = native.width + " × " + native.height + " · up to " + refreshLabel(monitorMax, [])

  var recommended = null
  if (offered.length) {
    recommended = { width: native.width, height: native.height, refreshRate: offered[0].refreshRate, edidOnly: false }
  } else if (edidOnly.length) {
    // The connection never offered the native resolution, so propose the
    // gentlest EDID timing: the lowest refresh at or above 50 Hz is the one
    // most likely to fit a bandwidth-limited link.
    var gentle = edidOnly.filter(function(r) { return r.refreshRate >= 50 })
    var pick = gentle.length ? gentle[gentle.length - 1] : edidOnly[edidOnly.length - 1]
    recommended = { width: native.width, height: native.height, refreshRate: pick.refreshRate, edidOnly: true }
  }
  result.recommendation = recommended

  var atNativeRes = Number(display.width) === native.width && Number(display.height) === native.height
  var current = Number(display.refreshRate)

  if (atNativeRes) {
    // At native resolution the running rate is proven to work, so only ever
    // suggest going up: first to a faster rate the driver offers, otherwise
    // to a faster EDID timing, flagged as a try.
    var fasterOffered = offered.filter(function(r) { return r.refreshRate > current + 0.5 })
    var fasterEdid = edidOnly.filter(function(r) { return r.refreshRate > current + 0.5 })
    var runningFromEdid = edidOnly.some(function(r) { return Math.abs(r.refreshRate - current) <= 0.5 })
    if (fasterOffered.length) {
      result.level = "suggest"
      result.title = "A better refresh rate is available"
      result.detail = "The driver offers " + refreshLabel(fasterOffered[0].refreshRate, [])
        + " at native resolution; you are running " + refreshLabel(current, []) + "."
      result.recommendation = { width: native.width, height: native.height,
        refreshRate: fasterOffered[0].refreshRate, edidOnly: false }
    } else if (fasterEdid.length) {
      result.level = "limited"
      result.title = "Native resolution"
      result.detail = "The monitor's EDID also lists " + refreshLabel(fasterEdid[0].refreshRate, [])
        + ", which the driver did not offer on this connection. Trying it is safe: it reverts in 15 seconds if the picture does not come back."
      result.recommendation = { width: native.width, height: native.height,
        refreshRate: fasterEdid[0].refreshRate, edidOnly: true, tryOnly: true }
    } else {
      result.level = "ok"
      result.title = "Native resolution"
      result.detail = "Running at the monitor's native resolution and its highest refresh rate"
        + (runningFromEdid ? ", using the monitor's own EDID timing because Hyprland did not list it." : ".")
      result.recommendation = null
    }
    return result
  }

  if (!recommended) {
    result.level = "unknown"
    result.title = "Native mode unavailable"
    result.detail = "The monitor reports " + native.width + " × " + native.height + " but no usable timing for it."
    return result
  }
  result.level = "suggest"
  result.title = "Not at native resolution"
  result.detail = recommended.edidOnly
    ? "Hyprland did not list the native mode, but the monitor's EDID does. Previewing is safe: it reverts in 15 seconds if the picture does not come back."
    : "Text and images are sharpest at the monitor's native resolution."
  return result
}

// Suggests a scale from pixel density. Laptop panels are viewed closer than
// desktop monitors, so they get a denser baseline. Returns "" when the monitor
// does not report a physical size.
function recommendedScale(display, scaleValues) {
  if (!display || !Array.isArray(scaleValues) || scaleValues.length === 0) return ""
  var widthMm = Number(display.physicalWidth)
  var pixels = Number(display.width)
  if (!isFinite(widthMm) || widthMm < 100 || !isFinite(pixels) || pixels <= 0) return ""
  var rotated = cleanTransform(display.transform) % 2 === 1
  if (rotated && Number(display.height) > 0) pixels = Number(display.height)
  var ppi = pixels / (widthMm / 25.4)
  var internal = /^(eDP|LVDS|DSI)-/i.test(String(display.name || ""))
  var ideal = ppi / (internal ? 125 : 105)
  var best = ""
  var bestDistance = Infinity
  for (var i = 0; i < scaleValues.length; i++) {
    var effective = Number(cleanScale(scaleValues[i], display.width, display.height))
    if (!isFinite(effective) || effective <= 0) continue
    var distance = Math.abs(Math.log(effective / Math.max(1, ideal)))
    if (distance < bestDistance) { best = String(scaleValues[i]); bestDistance = distance }
  }
  return best
}

if (typeof module !== "undefined") {
  module.exports = {
    clampBrightness: clampBrightness,
    normalizeScale: normalizeScale,
    cleanScale: cleanScale,
    matchingScaleIndex: matchingScaleIndex,
    availableScales: availableScales,
    parseDisplayMode: parseDisplayMode,
    availableResolutions: availableResolutions,
    matchingResolutionValue: matchingResolutionValue,
    availableRefreshRates: availableRefreshRates,
    matchingRefreshRateValue: matchingRefreshRateValue,
    preferredRefreshRate: preferredRefreshRate,
    cleanTransform: cleanTransform,
    stageDisplaySettings: stageDisplaySettings,
    displaysWithSettings: displaysWithSettings,
    retainDisplaySettings: retainDisplaySettings,
    brightnessName: brightnessName,
    responsiveDisplayUtilization: responsiveDisplayUtilization,
    cycleDisplayIndex: cycleDisplayIndex,
    displayLabel: displayLabel,
    fitDisplayLayout: fitDisplayLayout,
    normalizeDisplayLayout: normalizeDisplayLayout,
    refitDisplayLayout: refitDisplayLayout,
    snapDisplayPosition: snapDisplayPosition,
    moveDisplayInCanvas: moveDisplayInCanvas,
    rectsOverlap: rectsOverlap,
    rectsTouch: rectsTouch,
    connectRects: connectRects,
    snapTopologyPayload: snapTopologyPayload,
    buildDisplayLayoutPayload: buildDisplayLayoutPayload,
    buildMonitorSettingPayload: buildMonitorSettingPayload,
    prepareDisplaySettingPreview: prepareDisplaySettingPreview,
    advanceDisplayConfirmation: advanceDisplayConfirmation,
    parsePendingDisplayTransaction: parsePendingDisplayTransaction,
    confirmationTargetScreen: confirmationTargetScreen,
    ownsDisplayConfirmation: ownsDisplayConfirmation,
    ownsDisplayIpc: ownsDisplayIpc,
    workspaceAssignments: workspaceAssignments,
    workspacesForMonitor: workspacesForMonitor,
    toggleWorkspaceAssignment: toggleWorkspaceAssignment,
    workspaceAssignmentsEqual: workspaceAssignmentsEqual,
    parseDisplays: parseDisplays,
    displayConfirmationPolicy: displayConfirmationPolicy,
    nextExpandedSection: nextExpandedSection,
    shouldAutoResetDisplayLayout: shouldAutoResetDisplayLayout,
    modeAdvertised: modeAdvertised,
    refreshLabel: refreshLabel,
    resolutionChoices: resolutionChoices,
    refreshChoices: refreshChoices,
    formatMode: formatMode,
    modeInsight: modeInsight,
    recommendedScale: recommendedScale
  }
}
