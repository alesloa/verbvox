import AppKit

/// Port of `play_sound` (transcribe_cli.py). Plays a bundled macOS system sound
/// (`/System/Library/Sounds/<name>.aiff`) when hotkey sounds are enabled. Python
/// read `features.enable_hotkey_sounds` (default on) from the DB; here the caller
/// resolves that flag and passes it in, keeping this DB-free like the pipeline.
public enum Sounds {
    /// - Parameters:
    ///   - name: system sound base name, e.g. `"Tink"` (start) / `"Pop"` (stop).
    ///   - enabled: the resolved `features.enable_hotkey_sounds` flag.
    public static func play(_ name: String, enabled: Bool) {
        guard enabled else { return }
        let path = "/System/Library/Sounds/\(name).aiff"
        NSSound(contentsOfFile: path, byReference: true)?.play()
    }
}
