// Typing for the panel's text fields, which are read-only to Qt. An editable
// TextInput reads the whole clipboard every time it changes, to keep canPaste
// up to date (QQuickTextInput::q_canPasteChanged, only when not read-only),
// with no size limit and no deadline, inside the shared shell. Read-only
// fields never look; this does their editing instead: characters, Backspace
// and Delete (by word with Ctrl), cut, select all, Enter. Paste is not offered.
// Cursor movement, selection and copy stay Qt's.
.pragma library

function stepBack(text, at) {
    const c = text.charCodeAt(at - 1);
    return at - (at > 1 && c >= 0xDC00 && c <= 0xDFFF ? 2 : 1);
}

function stepForward(text, at) {
    const c = text.charCodeAt(at);
    return at + (at < text.length - 1 && c >= 0xD800 && c <= 0xDBFF ? 2 : 1);
}

function wordBack(text, at) {
    let i = at;
    while (i > 0 && /\s/.test(text.charAt(i - 1))) i--;
    while (i > 0 && !/\s/.test(text.charAt(i - 1))) i--;
    return i;
}

function wordForward(text, at) {
    let i = at;
    while (i < text.length && /\s/.test(text.charAt(i))) i++;
    while (i < text.length && !/\s/.test(text.charAt(i))) i++;
    return i;
}

function cutSelection(field) {
    if (field.selectedText.length === 0) return false;
    field.remove(field.selectionStart, field.selectionEnd);
    return true;
}

// Puts `text` where the cursor is, over the selection if there is one.
function insert(field, text) {
    cutSelection(field);
    field.insert(field.cursorPosition, text);
}

// actions: { paste(), enter(event) -> bool (true = handled), multiline }
// The field's maximumLength still applies: insert() respects it.
// std: { paste, selectAll, cut } - StandardKey values, which a .pragma library can't
// see, passed in from QML. Returns true when the key was handled.
function key(field, event, actions, std) {
    const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
    const at = field.cursorPosition;
    const text = field.text;
    if (event.matches(std.paste)) {
        if (actions.paste) actions.paste();
    } else if (event.matches(std.selectAll)) {
        field.selectAll();
    } else if (event.matches(std.cut)) {
        field.copy();
        cutSelection(field);
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
        if (actions.enter && actions.enter(event)) return true;
        if (!actions.multiline) return false;
        insert(field, "\n");
    } else if (event.key === Qt.Key_Backspace) {
        if (!cutSelection(field) && at > 0)
            field.remove(ctrl ? wordBack(text, at) : stepBack(text, at), at);
    } else if (event.key === Qt.Key_Delete) {
        if (!cutSelection(field) && at < text.length)
            field.remove(at, ctrl ? wordForward(text, at) : stepForward(text, at));
    } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
        return false;                       // focus moves on, as before
    } else if (event.text.length > 0 && event.text.charCodeAt(0) >= 0x20
               && event.text.charCodeAt(0) !== 0x7F
               && (event.modifiers & (Qt.ControlModifier | Qt.MetaModifier)) === 0) {
        insert(field, event.text);
    } else {
        return false;                       // movement, selection, copy: Qt's own
    }
    return true;
}
