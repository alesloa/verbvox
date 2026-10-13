import SwiftUI

/// Progress, readiness and recovery for the built-in speech engine; shared by Home
/// and Recording.
struct BuiltinStatusView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        let status = app.builtin.status
        VStack(alignment: .leading, spacing: 6) {
            Text(title(status)).font(.headline)
            if let detail = detail(status), !detail.isEmpty {
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            switch status.phase {
            case .downloading where status.total > 0:
                ProgressView(value: Double(status.received), total: Double(status.total))
            case .downloading, .starting, .warmingUp:
                ProgressView().progressViewStyle(.linear)
            default:
                EmptyView()
            }
            if status.phase == .failed, let error = status.error {
                Text(error).font(.caption).foregroundStyle(.orange)
            }
            if let background = status.background {
                Text(background).font(.caption).foregroundStyle(.secondary)
            }
            if status.phase == .failed {
                Button("Try now") { app.retryBuiltin() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func title(_ status: BuiltinWhisper.Status) -> String {
        switch status.phase {
        case .downloading: return "Downloading \(status.modelLabel)"
        case .starting: return "Starting the speech engine"
        case .warmingUp: return "Checking speed on this Mac"
        case .ready: return "Ready: \(status.modelLabel)"
        case .failed: return "The speech engine is not running"
        case .idle: return "The speech engine starts with VerbVox"
        }
    }

    private func detail(_ status: BuiltinWhisper.Status) -> String? {
        switch status.phase {
        case .downloading:
            return "\(status.detail ?? "") \(status.received / 1_000_000) of \(status.total / 1_000_000) MB."
        case .ready:
            guard let seconds = status.warmupSeconds, status.clipSeconds > 0 else { return nil }
            return String(format: "Speed check: %.1f s of speech transcribed in %.2f s.", status.clipSeconds, seconds)
        default:
            return status.detail
        }
    }
}
