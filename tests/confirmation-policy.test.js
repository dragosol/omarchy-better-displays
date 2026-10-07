const assert = require("node:assert/strict")
const Model = require("../Model.js")

// Baseline policies are unchanged.
assert.equal(Model.displayConfirmationPolicy({ status: "exact", profileId: "p1" }).kind, "keep")
assert.equal(Model.displayConfirmationPolicy({ status: "new" }).kind, "keep")
assert.equal(Model.displayConfirmationPolicy({ status: "moved", profileId: "p1" }).kind, "choose-profile")

// A complete weak match (every connected display mapped 1:1 onto a saved
// display on the same connector) is safe to keep manually: the user confirms
// the exact preview and no display can silently swap. This covers monitors
// whose EDID serial or blob changes between sessions (KVM-style identity
// churn). The matcher itself still reports "weak", so automatic restore
// stays conservative.
const completeWeak = {
  status: "weak", profileId: "p1", legacyConnectorOnly: false,
  matches: [{
    currentName: "DP-1", savedName: "DP-1", status: "weak",
    reason: "make, model, size, and connector instance match",
    candidateSavedNames: ["DP-1"], requiresModeRevalidation: false
  }],
  unmatchedSavedNames: []
}
const weakPolicy = Model.displayConfirmationPolicy(completeWeak)
assert.equal(weakPolicy.kind, "keep-uncertain")
assert.equal(weakPolicy.profileId, "p1")
assert.ok(weakPolicy.message.length > 0)

// Ambiguous ties still require Identify.
assert.equal(Model.displayConfirmationPolicy({
  status: "ambiguous", profileId: "p1", legacyConnectorOnly: false,
  matches: [
    { currentName: "DP-1", savedName: null, status: "ambiguous" },
    { currentName: "DP-2", savedName: null, status: "ambiguous" }
  ],
  unmatchedSavedNames: []
}).kind, "identify-first")

// A weak match with an unmatched saved display is incomplete and still
// requires Identify.
assert.equal(Model.displayConfirmationPolicy({
  status: "weak", profileId: "p1", legacyConnectorOnly: false,
  matches: [{ currentName: "DP-1", savedName: "DP-1", status: "weak" }],
  unmatchedSavedNames: ["DP-2"]
}).kind, "identify-first")

// A weak status whose matches carry no saved assignment is incomplete.
assert.equal(Model.displayConfirmationPolicy({
  status: "weak", profileId: "p1", legacyConnectorOnly: false,
  matches: [{ currentName: "DP-1", savedName: null, status: "weak" }],
  unmatchedSavedNames: []
}).kind, "identify-first")

console.log("confirmation policy tests passed")
