import SwiftUI

/// TypeWhisper-style floating HUD shown while recording/processing.
/// No live waveform: the batch engine doesn't stream audio levels or partials.
struct OverlayIndicator: View {
    let status: EngineStatus

    var body: some View {
        HStack(spacing: 10) {
            switch status.phase {
            case .recording:
                PulsingDot()
                Text(status.mode == "with_ai" ? "Recording · AI" : "Recording")
                    .font(.callout.weight(.semibold))
                TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                    Text(elapsedString)
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.7))
                }
            case .processing:
                ProgressView().controlSize(.small).tint(.white)
                Text("Transcribing…").font(.callout.weight(.semibold))
            default:
                EmptyView()
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.black.opacity(0.85), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.15)))
        .foregroundStyle(.white)
        .fixedSize()
    }

    private var elapsedString: String {
        let started = status.timestamp
        guard started > 0 else { return "0:00" }
        let elapsed = max(0, Date().timeIntervalSince1970 - started)
        let m = Int(elapsed) / 60
        let s = Int(elapsed) % 60
        return String(format: "%d:%02d", m, s)
    }
}

private struct PulsingDot: View {
    @State private var on = false
    var body: some View {
        Circle()
            .fill(.red)
            .frame(width: 11, height: 11)
            .scaleEffect(on ? 1.0 : 0.6)
            .opacity(on ? 1.0 : 0.5)
            .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}
