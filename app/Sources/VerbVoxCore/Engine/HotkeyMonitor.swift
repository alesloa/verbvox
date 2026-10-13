import AppKit
import Foundation

/// Global hold-to-talk hotkey listener — the Swift port of the pynput
/// `keyboard.Listener` block in `transcribe_cli.py`.
///
/// Python tracked the currently-held modifier set and, on each key press, fired
/// only when EXACTLY two modifier *types* were down (`modifier_count == 2`):
/// `ctrl+alt` → No-AI, `ctrl+cmd` → With-AI. Any modifier release while recording
/// stopped it; ESC stopped speech. This reproduces that with `NSEvent`
/// `.flagsChanged` (press/release of modifiers) + `.keyDown` (ESC).
///
/// **Exact-match guard:** a combo fires only when the held modifier set is
/// *identical* to it. Unlike the Python — which never tracked shift, so
/// `ctrl+alt+shift` still triggered `ctrl+alt` — this treats shift as a tracked
/// modifier, so `ctrl+alt+shift` does NOT match `ctrl+alt`.
///
/// **Debounced start:** the exact-match decision lives in `HoldToTalkMachine`,
/// which requires a matched combo to still be held after `startDebounce` before it
/// actually starts. This defeats the transient intermediate modifier states that
/// remappers (e.g. Karabiner ⌘→⌃) and fast key rolls emit — see that type's docs.
///
/// **Threading:** `NSEvent` monitor blocks are delivered on the main run loop and
/// the debounce fires on `DispatchQueue.main`, so all callbacks and all mutations
/// of `machine` happen on the main thread — Phase 6's `DictationEngine` can touch
/// `@MainActor` state directly without hopping queues.
public final class HotkeyMonitor {

    // Callbacks are wired by `DictationEngine` (Phase 6); this type only detects.
    public var onStart: (RecordingMode) -> Void = { _ in }
    public var onStop: () -> Void = {}
    public var onEscape: () -> Void = {}

    /// ESC virtual key code (`kVK_Escape`).
    private static let escKeyCode: UInt16 = 53

    /// How long a matched combo must stay held before a session actually starts.
    /// Comfortably longer than any software-remap / key-rollover transient (~1 ms),
    /// far shorter than an intentional hold (150 ms+): phantom matches never start,
    /// real holds are unaffected (they just begin ~50 ms later).
    private static let startDebounce: TimeInterval = 0.05

    private var machine: HoldToTalkMachine

    private var globalMonitor: Any?
    private var localMonitor: Any?
    /// The in-flight debounce, so a later flags change / stop can cancel it.
    private var startTimer: DispatchWorkItem?

    /// Parse the two `+`-joined config strings (e.g. `"ctrl+alt"` / `"ctrl+cmd"`)
    /// via `HotkeyCombo.parse`, reusing the same parser the settings UI uses.
    public init(noAIHotkey: String, withAIHotkey: String) {
        machine = HoldToTalkMachine(
            noAICombo: HotkeyCombo.parse(noAIHotkey).modifiers,
            withAICombo: HotkeyCombo.parse(withAIHotkey).modifiers)
    }

    /// Install a global monitor (fires when other apps are focused) plus a local
    /// monitor (fires when this app is focused — global monitors don't). Both
    /// watch `.flagsChanged` and `.keyDown`.
    public func start() {
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown]

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
            return event // don't swallow the event for the focused app
        }
    }

    /// Remove both monitors, cancel any pending start, and clear session state.
    public func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        startTimer?.cancel()
        startTimer = nil
        machine.reset()
    }

    // MARK: - Event handling

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .flagsChanged:
            run(machine.flagsChanged(currentModifiers(event.modifierFlags)))
        case .keyDown where event.keyCode == Self.escKeyCode:
            onEscape()
        default:
            break
        }
    }

    /// Execute the commands the state machine returns.
    private func run(_ commands: [HoldToTalkMachine.Command]) {
        for command in commands {
            switch command {
            case .armStartTimer(let combo):
                startTimer?.cancel()
                let item = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    self.startTimer = nil
                    self.run(self.machine.startTimerFired(combo))
                }
                startTimer = item
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.startDebounce, execute: item)

            case .cancelStartTimer:
                startTimer?.cancel()
                startTimer = nil

            case .commitStart(let mode):
                onStart(mode)

            case .stop:
                startTimer?.cancel()
                startTimer = nil
                onStop()
            }
        }
    }

    /// Map the event's modifier flags to the tracked modifier set.
    private func currentModifiers(_ flags: NSEvent.ModifierFlags) -> Set<HotkeyCombo.Modifier> {
        var set: Set<HotkeyCombo.Modifier> = []
        if flags.contains(.control) { set.insert(.ctrl) }
        if flags.contains(.option) { set.insert(.alt) }
        if flags.contains(.command) { set.insert(.cmd) }
        if flags.contains(.shift) { set.insert(.shift) }
        return set
    }
}
