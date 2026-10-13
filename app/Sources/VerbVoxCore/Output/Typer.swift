import CoreGraphics
import Carbon.HIToolbox
import Foundation

/// Port of `simulate_typing` / `simulate_typing_for_windows` (transcribe_cli.py).
///
/// Python typed through `pynput`, which posts **real virtual keycodes** derived
/// from the character (pressing Shift for capitals/shifted symbols). That matters
/// for remote Windows sessions ("Windows App", Microsoft Remote Desktop, VMware):
/// an RDP client forwards the physical keycode + modifier state, NOT the macOS
/// `keyboardSetUnicodeString` overlay. Posting `virtualKey: 0` with a unicode
/// string — which works for native Mac apps — makes RDP see keycode 0 (the "a"
/// key) for every character, so the remote session fills with "aaaa…".
///
/// So we map each character to its US-ANSI keycode (+ Shift) and post real key
/// events, exactly like pynput. Characters with no ANSI keycode (em dash, curly
/// quotes, accents, emoji) fall back to the unicode overlay — best effort, the
/// same limitation pynput has over RDP.
public enum Typer {

    /// General per-character typing (`simulate_typing`).
    public static func type(_ text: String) {
        emit(text, perCharDelay: 0)
    }

    /// Windows App variant (`simulate_typing_for_windows`) — a minimal per-character
    /// delay for reliability inside a remote Windows session (Python slept 0.001s).
    public static func typeForWindows(_ text: String) {
        emit(text, perCharDelay: 1_000) // 0.001s
    }

    private static func emit(_ text: String, perCharDelay: useconds_t) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for character in text {
            if let (keyCode, needsShift) = keyMap[character] {
                postKeyCode(keyCode, shift: needsShift, source: source)
            } else {
                // No US-ANSI keycode for this character — deliver it as a unicode
                // string. Native apps read it; a remote RDP session may drop it,
                // matching pynput's own fallback behaviour.
                postUnicode(character, source: source)
            }
            if perCharDelay > 0 { usleep(perCharDelay) }
        }
    }

    /// Post a real key event (with an explicit Shift key press around it when
    /// needed), so RDP forwards the correct physical key + modifier.
    private static func postKeyCode(_ keyCode: CGKeyCode, shift: Bool, source: CGEventSource?) {
        let shiftKey = CGKeyCode(kVK_Shift)
        if shift {
            CGEvent(keyboardEventSource: source, virtualKey: shiftKey, keyDown: true)?
                .post(tap: .cghidEventTap)
        }

        let flags: CGEventFlags = shift ? .maskShift : []
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        keyDown?.flags = flags
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        keyUp?.flags = flags
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)

        if shift {
            CGEvent(keyboardEventSource: source, virtualKey: shiftKey, keyDown: false)?
                .post(tap: .cghidEventTap)
        }
    }

    /// Deliver one character as a unicode string on a keycode-0 event (works for
    /// native macOS apps; used only for characters absent from `keyMap`).
    private static func postUnicode(_ character: Character, source: CGEventSource?) {
        let utf16 = Array(String(character).utf16)
        guard
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        else { return }
        utf16.withUnsafeBufferPointer { buffer in
            keyDown.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
            keyUp.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
        }
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    /// US-ANSI layout: character → (virtual keycode, needs Shift). Built from the
    /// documented `kVK_ANSI_*` constants, not guessed values.
    private static let keyMap: [Character: (CGKeyCode, Bool)] = {
        var map: [Character: (CGKeyCode, Bool)] = [:]

        // Letters: lowercase unshifted, uppercase on the same key with Shift.
        let letters: [(Character, Int)] = [
            ("a", kVK_ANSI_A), ("b", kVK_ANSI_B), ("c", kVK_ANSI_C), ("d", kVK_ANSI_D),
            ("e", kVK_ANSI_E), ("f", kVK_ANSI_F), ("g", kVK_ANSI_G), ("h", kVK_ANSI_H),
            ("i", kVK_ANSI_I), ("j", kVK_ANSI_J), ("k", kVK_ANSI_K), ("l", kVK_ANSI_L),
            ("m", kVK_ANSI_M), ("n", kVK_ANSI_N), ("o", kVK_ANSI_O), ("p", kVK_ANSI_P),
            ("q", kVK_ANSI_Q), ("r", kVK_ANSI_R), ("s", kVK_ANSI_S), ("t", kVK_ANSI_T),
            ("u", kVK_ANSI_U), ("v", kVK_ANSI_V), ("w", kVK_ANSI_W), ("x", kVK_ANSI_X),
            ("y", kVK_ANSI_Y), ("z", kVK_ANSI_Z),
        ]
        for (ch, code) in letters {
            map[ch] = (CGKeyCode(code), false)
            if let upper = ch.uppercased().first { map[upper] = (CGKeyCode(code), true) }
        }

        // Digit row: unshifted digit + its shifted symbol on the same key.
        let digitRow: [(Character, Int, Character)] = [
            ("1", kVK_ANSI_1, "!"), ("2", kVK_ANSI_2, "@"), ("3", kVK_ANSI_3, "#"),
            ("4", kVK_ANSI_4, "$"), ("5", kVK_ANSI_5, "%"), ("6", kVK_ANSI_6, "^"),
            ("7", kVK_ANSI_7, "&"), ("8", kVK_ANSI_8, "*"), ("9", kVK_ANSI_9, "("),
            ("0", kVK_ANSI_0, ")"),
        ]
        for (ch, code, shifted) in digitRow {
            map[ch] = (CGKeyCode(code), false)
            map[shifted] = (CGKeyCode(code), true)
        }

        // Punctuation keys: unshifted + shifted on the same physical key.
        let punctuation: [(Character, Int, Character)] = [
            ("-", kVK_ANSI_Minus, "_"), ("=", kVK_ANSI_Equal, "+"),
            ("[", kVK_ANSI_LeftBracket, "{"), ("]", kVK_ANSI_RightBracket, "}"),
            ("\\", kVK_ANSI_Backslash, "|"), (";", kVK_ANSI_Semicolon, ":"),
            ("'", kVK_ANSI_Quote, "\""), (",", kVK_ANSI_Comma, "<"),
            (".", kVK_ANSI_Period, ">"), ("/", kVK_ANSI_Slash, "?"),
            ("`", kVK_ANSI_Grave, "~"),
        ]
        for (ch, code, shifted) in punctuation {
            map[ch] = (CGKeyCode(code), false)
            map[shifted] = (CGKeyCode(code), true)
        }

        // Whitespace.
        map[" "] = (CGKeyCode(kVK_Space), false)
        map["\n"] = (CGKeyCode(kVK_Return), false)
        map["\t"] = (CGKeyCode(kVK_Tab), false)

        return map
    }()
}
