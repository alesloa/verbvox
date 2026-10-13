import AppKit

/// Port of `get_active_app` (transcribe_cli.py). Python shelled out to
/// `System Events … name of first application process whose frontmost is true`;
/// natively that is just the frontmost application's localized name.
public enum ActiveApp {
    public static func name() -> String? {
        NSWorkspace.shared.frontmostApplication?.localizedName
    }
}
