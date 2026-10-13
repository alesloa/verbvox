import Foundation

/// A set of keyboard modifiers used as a hold-to-talk hotkey.
///
/// Mirrors the engine's `_parse_combo` in `transcribe_cli.py`: the engine stores
/// each hotkey as a `+`-joined modifier string (e.g. `"ctrl+alt"`) and matches the
/// pressed modifier set exactly. Order is irrelevant to the engine (it's a set),
/// but `engineString` emits a stable canonical order.
public struct HotkeyCombo: Equatable, Hashable {
    public enum Modifier: String, CaseIterable, Hashable {
        case ctrl, alt, cmd, shift

        /// macOS display symbol.
        var symbol: String {
            switch self {
            case .ctrl: return "⌃"
            case .alt: return "⌥"
            case .shift: return "⇧"
            case .cmd: return "⌘"
            }
        }
    }

    /// Canonical ordering for serialized output (engine string).
    private static let engineOrder: [Modifier] = [.ctrl, .alt, .cmd, .shift]
    /// Conventional macOS ordering for display symbols (⌃⌥⇧⌘).
    private static let displayOrder: [Modifier] = [.ctrl, .alt, .shift, .cmd]

    public var modifiers: Set<Modifier>

    public init(_ modifiers: Set<Modifier>) {
        self.modifiers = modifiers
    }

    /// Parse a `+`-joined modifier string. Unknown tokens are dropped; case and
    /// surrounding whitespace are ignored. Matches the engine's `_parse_combo`.
    public static func parse(_ string: String) -> HotkeyCombo {
        let tokens = string
            .split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .compactMap { Modifier(rawValue: $0) }
        return HotkeyCombo(Set(tokens))
    }

    /// Canonical `+`-joined string the engine expects, e.g. `"ctrl+alt"`.
    public var engineString: String {
        Self.engineOrder
            .filter { modifiers.contains($0) }
            .map { $0.rawValue }
            .joined(separator: "+")
    }

    /// macOS symbol string for display, e.g. `"⌃⌘"`.
    public var displaySymbols: String {
        Self.displayOrder
            .filter { modifiers.contains($0) }
            .map { $0.symbol }
            .joined()
    }

    public var isEmpty: Bool { modifiers.isEmpty }
}
