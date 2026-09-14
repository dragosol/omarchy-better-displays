.pragma library
// One QML engine owns the per-screen panels. Synchronous, shared edit guards
// prevent the IPC owner's hotplug restore from interrupting a different bar's
// editor. Runtime generation fencing in Bash also survives engine recreation.
var blocked = ({})
var sequence = 0
function register() { sequence += 1; return "panel-" + sequence }
function setBlocked(id, value) { if (id) blocked[id] = value === true }
function remove(id) { delete blocked[id] }
function anyBlocked() {
  return Object.keys(blocked).some(function(id) { return blocked[id] })
}
