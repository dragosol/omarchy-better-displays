const assert = require("node:assert/strict")
const Model = require("../Model.js")

// Samsung ultrawide behind a USB-C dock: Hyprland's list lacks the native
// resolution; the EDID provides it at 100, 60 and 50 Hz.
const dock = {
  name: "DP-1", width: 2560, height: 1440, refreshRate: 59.951,
  advertisedModes: ["2560x1440@59.95Hz", "1920x1080@100.00Hz", "1920x1080@60.00Hz"],
  availableModes: ["2560x1440@59.95Hz", "1920x1080@100.00Hz", "1920x1080@60.00Hz",
                   "3440x1440@99.98Hz", "3440x1440@59.97Hz", "3440x1440@49.99Hz"],
  nativeMode: { width: 3440, height: 1440, refreshRate: 99.98 }
}

{
  const choices = Model.resolutionChoices(dock.availableModes, dock.advertisedModes, dock.nativeMode, "")
  assert.equal(choices[0].width, 3440)
  assert.equal(choices[0].native, true)
  assert.equal(choices[0].edidOnly, true)
  assert.equal(choices[1].width, 2560)
  assert.equal(choices[1].edidOnly, false)
  assert.match(choices[0].label, /native/)
}

{
  const rates = Model.refreshChoices(dock.availableModes, dock.advertisedModes, 3440, 1440)
  assert.deepEqual(rates.map(r => r.label), ["100 Hz", "60 Hz", "50 Hz"])
  assert.equal(rates.every(r => r.edidOnly), true)
}

{
  const insight = Model.modeInsight(dock)
  assert.equal(insight.level, "suggest")
  assert.equal(insight.title, "Not at native resolution")
  // The gentlest native timing is proposed when the link never offered it.
  assert.deepEqual(insight.recommendation, { width: 3440, height: 1440, refreshRate: 59.97, edidOnly: true })
}

{
  // Running the EDID 60 Hz timing (reported drifted): never suggest going
  // down; offer to try the faster EDID timing.
  const insight = Model.modeInsight(Object.assign({}, dock, { width: 3440, height: 1440, refreshRate: 59.83 }))
  assert.equal(insight.level, "limited")
  assert.equal(insight.recommendation.refreshRate, 99.98)
  assert.equal(insight.recommendation.tryOnly, true)
}

{
  // Running the EDID 100 Hz timing: that is the best there is.
  const insight = Model.modeInsight(Object.assign({}, dock, { width: 3440, height: 1440, refreshRate: 99.98 }))
  assert.equal(insight.level, "ok")
  assert.equal(insight.recommendation, null)
  assert.match(insight.detail, /EDID timing/)
}

{
  // Direct DisplayPort: native at full refresh is advertised and active.
  const direct = {
    width: 3440, height: 1440, refreshRate: 164.9,
    advertisedModes: ["3440x1440@164.90Hz", "3440x1440@100.00Hz", "3440x1440@59.97Hz"],
    availableModes: ["3440x1440@164.90Hz", "3440x1440@100.00Hz", "3440x1440@59.97Hz"],
    nativeMode: { width: 3440, height: 1440, refreshRate: 164.9 }
  }
  assert.equal(Model.modeInsight(direct).level, "ok")
  const slow = Model.modeInsight(Object.assign({}, direct, { refreshRate: 59.97 }))
  assert.equal(slow.level, "suggest")
  assert.equal(slow.title, "A better refresh rate is available")
  assert.equal(slow.recommendation.refreshRate, 164.9)
  // Running faster than anything suggested stays ok.
  assert.equal(Model.modeInsight(Object.assign({}, direct, { refreshRate: 164.9 })).recommendation, null)
}

{
  // A link that offers native only below the monitor's EDID maximum.
  const capped = {
    width: 3440, height: 1440, refreshRate: 59.97,
    advertisedModes: ["3440x1440@59.97Hz"],
    availableModes: ["3440x1440@59.97Hz", "3440x1440@99.98Hz"],
    nativeMode: { width: 3440, height: 1440, refreshRate: 99.98 }
  }
  const insight = Model.modeInsight(capped)
  assert.equal(insight.level, "limited")
  assert.match(insight.detail, /100 Hz/)
}

{
  assert.equal(Model.refreshLabel(59.94, [59.94, 60]), "59.94 Hz")
  assert.equal(Model.refreshLabel(143.97, [143.97, 120]), "144 Hz")
  assert.equal(Model.modeInsight(null).level, "unknown")
}

{
  const presets = ["1", "1.25", "1.6", "2", "3", "4"]
  // 34-inch 3440x1440 ultrawide (~109 PPI) and a 13-inch 2880x1800 laptop (~252 PPI).
  assert.equal(Model.recommendedScale({ name: "DP-1", width: 3440, height: 1440, physicalWidth: 800 }, presets), "1")
  assert.equal(Model.recommendedScale({ name: "eDP-1", width: 2880, height: 1800, physicalWidth: 290 }, presets), "2")
  // 27-inch 4K (~163 PPI) lands between the stops.
  assert.equal(Model.recommendedScale({ name: "DP-2", width: 3840, height: 2160, physicalWidth: 597 }, presets), "1.6")
  assert.equal(Model.recommendedScale({ name: "HDMI-A-1", width: 1920, height: 1080, physicalWidth: 0 }, presets), "")
}

console.log("mode insight tests passed")
