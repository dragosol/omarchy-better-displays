import QtQuick
import Quickshell.Io

// A finite helper run through bounded.sh: an overall deadline, capped stdout
// and stderr, and the helper's whole process group ended with it. `finished`
// fires exactly once per launch(), with the exit code, 124 when the deadline
// passed, or 127 when the program never started or its exit never arrived
// (Quickshell reports no exit for a command that fails to start), so busy
// state the caller set for it is always cleared.
Process {
  id: proc

  required property string runner
  // The interpreter for bounded.sh. A test points it at a missing program to
  // exercise a start failure.
  property string shell: "bash"
  property int deadlineSeconds: 30
  property int stdoutBytes: 4194304
  property int stderrBytes: 65536
  readonly property bool busy: awaiting

  property bool awaiting: false

  signal finished(int exitCode)

  // Process has no default property, so the timers are typed properties.
  property Timer deadline: Timer {
    interval: (proc.deadlineSeconds + 5) * 1000
    repeat: false
    onTriggered: proc.giveUp(124)
  }
  property Timer exitWait: Timer {
    interval: 2000
    repeat: false
    onTriggered: proc.giveUp(127)
  }

  function launch(command) {
    if (awaiting || running) return false
    proc.command = [shell, runner, String(deadlineSeconds), String(stdoutBytes),
                    String(stderrBytes)].concat(command)
    awaiting = true
    deadline.restart()
    running = true
    // Nothing started at all: no exit will ever be reported for it.
    if (!running) exitWait.restart()
    return true
  }

  function complete(exitCode) {
    if (!awaiting) return
    awaiting = false
    deadline.stop()
    exitWait.stop()
    finished(exitCode)
  }

  function giveUp(exitCode) {
    if (!awaiting) return
    // Stopping the runner makes bounded.sh end the helper's process group.
    if (running) running = false
    complete(exitCode)
  }

  onExited: function(exitCode) { complete(exitCode) }
  onRunningChanged: if (!running && awaiting) exitWait.restart()
}
