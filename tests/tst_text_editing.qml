import QtQuick
import QtTest
import "../TextEditing.js" as TextEditing

// The profile-name field is read-only to Qt and typed into by TextEditing.key,
// so it never reads the clipboard when it changes (q_canPasteChanged only runs
// for editable fields) and paste is not offered.
Item {
    width: 400; height: 100
    property int enters: 0
    readonly property var std: ({ paste: StandardKey.Paste, selectAll: StandardKey.SelectAll, cut: StandardKey.Cut })

    TextInput {
        id: field
        width: 400; height: 30
        readOnly: true
        maximumLength: 64
        Keys.onPressed: ev => ev.accepted = TextEditing.key(field, ev, {
            paste: function() {}, enter: function() { enters++; return true } }, std)
    }

    TestCase {
        name: "TextEditing"
        when: windowShown

        function init() { field.text = ""; enters = 0 }

        function test_typing_and_editing() {
            field.forceActiveFocus()
            for (const k of [Qt.Key_H, Qt.Key_O, Qt.Key_M, Qt.Key_E, Qt.Key_Space, Qt.Key_D, Qt.Key_E, Qt.Key_S, Qt.Key_K])
                keyClick(k)
            compare(field.text, "home desk")
            keyClick(Qt.Key_Backspace)
            compare(field.text, "home des")
            keyClick(Qt.Key_Backspace, Qt.ControlModifier)
            compare(field.text, "home ")
            keyClick(Qt.Key_Home)
            keyClick(Qt.Key_Delete)
            compare(field.text, "ome ")
            keyClick(Qt.Key_A, Qt.ControlModifier)
            keyClick(Qt.Key_X)
            compare(field.text, "x")
        }

        function test_enter_renames_and_paste_does_nothing() {
            field.forceActiveFocus()
            keyClick(Qt.Key_A)
            keyClick(Qt.Key_V, Qt.ControlModifier)
            compare(field.text, "a")
            keyClick(Qt.Key_Return)
            compare(enters, 1)
        }

        function test_length_limit_holds() {
            field.forceActiveFocus()
            field.text = "x".repeat(64)
            field.cursorPosition = 64
            keyClick(Qt.Key_Y)
            compare(field.text.length, 64)
        }

        function test_never_reads_the_clipboard() {
            verify(field.readOnly && !field.canPaste)
        }
    }
}
