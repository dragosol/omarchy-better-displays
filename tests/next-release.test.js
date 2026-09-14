const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const events = require('../DisplayEventModel.js');
assert.equal(typeof events.autoRestorePermission, 'function');
assert.equal(events.autoRestorePermission({}), 'allow');
for (const key of ['dirty','dragging','editing','applying','pending','profileBusy','transitioning'])
  assert.equal(events.autoRestorePermission({[key]:true}), 'block', key);
const qml = fs.readFileSync(require.resolve('../Panel.qml'),'utf8');
assert.match(qml, /"auto-restore"/);
assert.doesNotMatch(qml, /pluginScript\("apply-layout.sh"\), "restore"/);
assert.match(qml, /function applyRecommendedSetup/);
assert.match(qml, /Studio\.recommendedSetup/);
assert.match(qml, /Recommended Extend/);
assert.match(qml, /Arrange manually/);
assert.match(qml, /DISPLAY HEALTH/);
assert.match(qml, /Studio\.sanitizedReport/);
assert.match(qml, /Preview safe repair/);
assert.match(qml, /"wl-copy", "--type", "text\/plain", "--"/);
const guard = {};
const guardFile = require('node:path').join(__dirname, '../SessionGuard.js');
if (fs.existsSync(guardFile)) vm.runInNewContext(fs.readFileSync(guardFile,'utf8').replace(/^\.pragma library\s*/,''), guard);
assert.equal(typeof guard.setBlocked,'function');
guard.setBlocked('screen-a',true);
assert.equal(guard.anyBlocked(),true);
guard.setBlocked('screen-b',false);
assert.equal(guard.anyBlocked(),true);
guard.remove('screen-a');
assert.equal(guard.anyBlocked(),false);
console.log('next release integration tests passed');

// Execute the real QML snapshot handler against clock/process seams: no live
// Qt engine or display changes. This catches control-flow errors beyond wiring.
const handler = qml.match(/^  function handleMonitorSnapshot\(raw\) \{[\s\S]*?^  \}/m)[0];
function harness(overrides={}) {
  const proc = {running:false, command:[]};
  const root = Object.assign({healthSnapshot:{},displayEventState:events.initialState('a'),
    displayTransitioning:false,stateProcHotplugScan:true,scanEventAt:1000,
    scanRestorePermission:'allow',ownsDisplayIpc:true,observedRestoreGeneration:'a',
    layoutDirty:false,layoutDragging:false,arrangementEditing:false,expandedLayoutOpen:false,
    layoutApplying:false,layoutConfirmationPending:false,profileActionBusy:false,
    burstRestoreBlocked:false,pluginScript:n=>n,canceled:0,
    cancelStaleDisplayPreview(){this.canceled++},
    noteDisplayHardwareEvent(){this.displayEventState=events.noteHardwareEvent(this.displayEventState,3000);this.displayTransitioning=true}
  },overrides);
  const c={root, DisplayEvents:events, SessionGuard:{anyBlocked:()=>false},
    restoreLayoutProc:proc,hotplugQuietTimer:{restart(){}},Date:{now:()=>3000}};
  vm.runInNewContext(handler,c);
  return {root,proc,run:g=>c.handleMonitorSnapshot(JSON.stringify({hardwareGeneration:g}))};
}
let h=harness();h.run('b');assert.equal(h.proc.running,false);assert.equal(h.root.displayTransitioning,true);
h=harness({displayEventState:events.noteHardwareEvent(events.initialState('a'),1000)});
h.run('b');assert.equal(h.proc.command[2],'auto-restore');assert.equal(h.proc.command[4],'allow');
h.proc.running=false;h.run('b');assert.equal(h.proc.running,false);
h=harness({displayEventState:events.noteHardwareEvent(events.initialState('a'),1000),layoutDirty:true});
h.run('b');assert.equal(h.proc.command[4],'block');assert.equal(h.root.layoutApplying,false);
h=harness({displayEventState:events.noteHardwareEvent(events.initialState('a'),2500)});
h.run('b');assert.equal(h.proc.running,false);
h=harness({displayEventState:events.noteHardwareEvent(events.initialState('a'),1000),layoutConfirmationPending:true});
h.run('b');assert.equal(h.root.canceled,1);assert.equal(h.proc.command[4],'block');
h=harness({scanRestorePermission:'block'});h.run('b');
assert.equal(h.root.burstRestoreBlocked,true, 'read-only initial refresh must not trigger later auto restore');
h=harness({burstRestoreBlocked:true});h.run('a');
assert.equal(h.root.burstRestoreBlocked,false, 'unchanged settled generation clears the burst latch');
console.log('QML snapshot control-flow tests passed');
