import SwiftUI
import AppKit

/// Dashboard metric card (TypeWhisper Home style).
struct StatCard: View {
    let title: String
    let value: String
    let systemImage: String
    var accent: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: systemImage).foregroundStyle(accent)
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            Text(value).font(.title2.weight(.semibold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// A pill showing a hotkey combo, with a record/clear control. Captures modifier
/// combos (ctrl/alt/cmd/shift) via the hold-to-talk model the engine uses.
struct HotkeyRecorderView: View {
    let title: String
    @Binding var combo: HotkeyCombo
    var onCommit: (HotkeyCombo) -> Void

    @State private var recording = false
    @State private var current: Set<HotkeyCombo.Modifier> = []
    @State private var maxSeen: Set<HotkeyCombo.Modifier> = []
    @State private var monitor: Any?

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            badge
            Button(recording ? "Stop" : "Change") {
                recording ? stopRecording() : startRecording()
            }
            .buttonStyle(.bordered)
        }
        .onDisappear { teardown() }
    }

    private var badge: some View {
        Text(displayText)
            .font(.system(.body, design: .rounded).weight(.medium))
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(recording ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.15),
                        in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7)
                .strokeBorder(recording ? Color.accentColor : .clear))
    }

    private var displayText: String {
        if recording {
            let live = HotkeyCombo(current.isEmpty ? maxSeen : current)
            return live.modifiers.isEmpty ? "Hold modifiers…" : live.displaySymbols
        }
        return combo.modifiers.isEmpty ? "—" : combo.displaySymbols
    }

    private func startRecording() {
        recording = true
        current = []
        maxSeen = []
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { event in
            let mods = Self.modifiers(from: event.modifierFlags)
            current = mods
            if mods.count > maxSeen.count { maxSeen = mods }
            // Finalize when everything is released after at least one modifier.
            if mods.isEmpty && !maxSeen.isEmpty { stopRecording() }
            return nil
        }
    }

    private func stopRecording() {
        teardown()
        recording = false
        if !maxSeen.isEmpty {
            let newCombo = HotkeyCombo(maxSeen)
            combo = newCombo
            onCommit(newCombo)
        }
    }

    private func teardown() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }

    static func modifiers(from flags: NSEvent.ModifierFlags) -> Set<HotkeyCombo.Modifier> {
        var s: Set<HotkeyCombo.Modifier> = []
        if flags.contains(.control) { s.insert(.ctrl) }
        if flags.contains(.option) { s.insert(.alt) }
        if flags.contains(.command) { s.insert(.cmd) }
        if flags.contains(.shift) { s.insert(.shift) }
        return s
    }
}

/// Small status dot + label used in menus and headers.
struct StatusDot: View {
    let color: Color
    let text: String
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text)
        }
    }
}
