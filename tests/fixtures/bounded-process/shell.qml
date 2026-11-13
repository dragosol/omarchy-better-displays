import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
  id: root
  property var results: ({})
  property string runner: String(Qt.resolvedUrl("bounded.sh")).replace(/^file:\/\//, "")
  function record(name, value) {
    var r = root.results; r[name] = value; root.results = r
    if (Object.keys(r).length === 4) {
      out.launch(["bash", "-c", "printf '%s\\n' \"$1\" > " + Quickshell.env("RESULT_FILE"), "x", JSON.stringify(r)])
    }
  }
  BoundedProcess { id: normal; runner: root.runner; deadlineSeconds: 5
    stdout: StdioCollector { id: normalOut; waitForEnd: true }
    onFinished: function(code) { root.record("normal", code + ":" + String(normalOut.text).trim()) } }
  BoundedProcess { id: late; runner: root.runner; deadlineSeconds: 1
    onFinished: function(code) { root.record("deadline", code) } }
  BoundedProcess { id: nostart; runner: root.runner; shell: "/nonexistent/bash"; deadlineSeconds: 5
    onFinished: function(code) { root.record("nostart", code) } }
  BoundedProcess { id: capped; runner: root.runner; deadlineSeconds: 5; stdoutBytes: 7
    stdout: StdioCollector { id: cappedOut; waitForEnd: true }
    onFinished: function(code) { root.record("capped", String(cappedOut.text).length) } }
  BoundedProcess { id: out; runner: root.runner; deadlineSeconds: 5
    onFinished: Qt.quit() }
  Component.onCompleted: {
    normal.launch(["bash", "-c", "echo hi; exit 3"])
    late.launch(["sleep", "30"])
    nostart.launch(["true"])
    capped.launch(["bash", "-c", "yes | head -c 100000"])
  }
}
