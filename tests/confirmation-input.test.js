const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const panel = fs.readFileSync(require.resolve('../Panel.qml'), 'utf8');
const handler = panel.match(/  onLayoutConfirmationPendingChanged: (\{[\s\S]*?\n  \})/)[1];
for (const opened of [false, true]) {
  const root = {
    opened, expandedLayoutOpen: true, layoutConfirmationPending: true,
    close() { this.opened = false; }
  };
  vm.runInNewContext(handler, { root });
  assert.equal(root.opened, false);
  assert.equal(root.expandedLayoutOpen, false);
  assert.equal(root.layoutConfirmationPending, true);
}
// Reopening an editor during the countdown must not steal confirmation input.
const popupOpen = panel.match(/    open: (root\.opened[^\n]*)/)[1];
const arrangement = fs.readFileSync(require.resolve('../FullScreenArrangement.qml'), 'utf8');
const arrangementVisible = arrangement.match(/  visible: (controller\.expandedLayoutOpen[^\n]*)/)[1];
for (const pending of [false, true]) {
  const state = { opened: true, expandedLayoutOpen: true, layoutConfirmationPending: pending };
  assert.equal(vm.runInNewContext(popupOpen, { root: state }), !pending);
  assert.equal(vm.runInNewContext(arrangementVisible, { controller: state }), !pending);
}
console.log('Confirmation releases editor input; editors cannot cover countdown.');
