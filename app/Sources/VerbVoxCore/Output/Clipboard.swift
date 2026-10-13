import AppKit
import Carbon.HIToolbox
import CoreGraphics

/// Port of `backup_clipboard` / `restore_clipboard` plus the copy/paste keystrokes
/// (transcribe_cli.py). Snapshots the FULL pasteboard (every item, every UTI/type)
/// so images, files, and RTF survive a paste — not just plain text — exactly like
/// the Python engine's stash/restore. Also drives ⌘C / ⌘V / ⌃V via `CGEvent`.
public enum Clipboard {

    /// Modifier used for the paste keystroke: ⌘V for Mac apps, ⌃V for the
    /// Windows App / Remote Desktop / VMware family.
    public enum PasteModifier {
        case command
        case control

        fileprivate var flags: CGEventFlags {
            switch self {
            case .command: return .maskCommand
            case .control: return .maskControl
            }
        }
    }

    // MARK: Snapshot / restore

    /// Snapshot every pasteboard item as `[uti: bytes]`, mirroring `backup_clipboard`.
    /// Items with no readable data are dropped (same as the Python `if types:` guard).
    public static func snapshot() -> [[String: Data]] {
        let pasteboard = NSPasteboard.general
        var snapshot: [[String: Data]] = []
        for item in pasteboard.pasteboardItems ?? [] {
            var types: [String: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    types[type.rawValue] = data
                }
            }
            if !types.isEmpty { snapshot.append(types) }
        }
        return snapshot
    }

    /// Rebuild `NSPasteboardItem`s from a snapshot and write them back, mirroring
    /// `restore_clipboard`. A no-op-safe empty snapshot clears nothing extra.
    public static func restore(_ snapshot: [[String: Data]]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        var items: [NSPasteboardItem] = []
        for types in snapshot {
            let item = NSPasteboardItem()
            for (type, data) in types {
                item.setData(data, forType: NSPasteboard.PasteboardType(type))
            }
            items.append(item)
        }
        if !items.isEmpty { pasteboard.writeObjects(items) }
    }

    // MARK: Text access

    /// Current plain-text clipboard contents (`pbpaste`).
    public static func readString() -> String? {
        NSPasteboard.general.string(forType: .string)
    }

    /// Replace the clipboard with plain text (`pbcopy`).
    public static func setString(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    // MARK: Keystrokes

    /// Copy the current selection (⌘C). Python always used command-down for copy,
    /// even in the Windows/Remote paste contexts.
    public static func copySelection() {
        sendKey(CGKeyCode(kVK_ANSI_C), modifier: .maskCommand)
    }

    /// Paste (⌘V or ⌃V) depending on the target app family.
    public static func paste(modifier: PasteModifier) {
        sendKey(CGKeyCode(kVK_ANSI_V), modifier: modifier.flags)
    }

    private static func sendKey(_ keyCode: CGKeyCode, modifier: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        keyDown?.flags = modifier
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        keyUp?.flags = modifier
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
