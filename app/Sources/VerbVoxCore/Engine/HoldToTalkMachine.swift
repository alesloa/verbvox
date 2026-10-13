import Foundation

/// Pure, timer-free decision core for hold-to-talk hotkey detection.
///
/// Split out of `HotkeyMonitor` so the start/stop policy is unit-testable without
/// `NSEvent` or real timers: the monitor feeds it modifier-set changes and timer
/// firings, and it returns `Command`s the monitor executes (arm/cancel a debounce
/// timer, commit a start, stop).
///
/// **Why the debounce exists.** A single `.flagsChanged` that momentarily equals a
/// combo must NOT start a session. Modifier remappers (e.g. Karabiner mapping ⌘→⌃)
/// and fast key rolls emit transient intermediate states: pressing a remapped ⌘
/// surfaces `{cmd}` → `{cmd,ctrl}` → `{ctrl}` within a few milliseconds. That middle
/// state exactly matches the default With-AI combo (`ctrl+cmd`), so the old
/// "start immediately on an exact match" logic fired a phantom record-then-instant-stop
/// on every such press — a beep with no audio. Requiring the combo to still be held
/// after a short debounce lets transients resolve away before we ever start, while an
/// intentional hold (150 ms+) sails through.
struct HoldToTalkMachine {
    enum Command: Equatable {
        /// Begin the debounce for `combo`; if it survives, a `startTimerFired` will
        /// commit it. Re-arming supersedes any prior pending combo.
        case armStartTimer(Set<HotkeyCombo.Modifier>)
        /// Drop the pending start — the held set resolved away from the combo.
        case cancelStartTimer
        case commitStart(RecordingMode)
        case stop
    }

    private let noAICombo: Set<HotkeyCombo.Modifier>
    private let withAICombo: Set<HotkeyCombo.Modifier>

    private(set) var isRecording = false
    private var activeCombo: Set<HotkeyCombo.Modifier>?
    /// A combo whose start is waiting out the debounce (`nil` = nothing pending).
    private var armedCombo: Set<HotkeyCombo.Modifier>?
    /// The most recent modifier set seen, so a timer firing can confirm the combo
    /// is *still* held rather than a transient that has since resolved.
    private var lastHeld: Set<HotkeyCombo.Modifier> = []

    init(noAICombo: Set<HotkeyCombo.Modifier>, withAICombo: Set<HotkeyCombo.Modifier>) {
        self.noAICombo = noAICombo
        self.withAICombo = withAICombo
    }

    /// The mode a held set exactly matches, if any (No-AI wins an exact-equal tie,
    /// preserving the old `if/else if` order).
    private func matchedMode(_ held: Set<HotkeyCombo.Modifier>) -> RecordingMode? {
        if !noAICombo.isEmpty, held == noAICombo { return .noAI }
        if !withAICombo.isEmpty, held == withAICombo { return .withAI }
        return nil
    }

    /// Feed a new held-modifier set. Returns the commands to execute.
    mutating func flagsChanged(_ held: Set<HotkeyCombo.Modifier>) -> [Command] {
        lastHeld = held

        if isRecording {
            // Any deviation from the exact active combo ends the hold — a real
            // modifier of the combo released, or an extra one added.
            if held != activeCombo {
                isRecording = false
                activeCombo = nil
                armedCombo = nil
                return [.stop]
            }
            return []
        }

        if let mode = matchedMode(held) {
            let combo = mode == .noAI ? noAICombo : withAICombo
            if armedCombo == combo { return [] }   // already waiting on this combo
            armedCombo = combo
            return [.armStartTimer(combo)]
        }

        // The held set no longer matches any combo. This is what kills the remapper
        // transient: the intermediate `{cmd,ctrl}` match is cancelled the instant the
        // flags resolve to `{ctrl}`, before the debounce could commit it.
        if armedCombo != nil {
            armedCombo = nil
            return [.cancelStartTimer]
        }
        return []
    }

    /// The debounce timer for `combo` elapsed. Commit the start only if that combo
    /// is still both armed and physically held.
    mutating func startTimerFired(_ combo: Set<HotkeyCombo.Modifier>) -> [Command] {
        guard !isRecording, armedCombo == combo, lastHeld == combo,
              let mode = matchedMode(combo) else {
            // Only clear the pending state when THIS combo is the one armed; a stale
            // timer for a superseded combo must not disturb the current arm.
            if armedCombo == combo { armedCombo = nil }
            return []
        }
        isRecording = true
        activeCombo = combo
        armedCombo = nil
        return [.commitStart(mode)]
    }

    /// Clear all session state (monitor stopped / torn down).
    mutating func reset() {
        isRecording = false
        activeCombo = nil
        armedCombo = nil
        lastHeld = []
    }
}
