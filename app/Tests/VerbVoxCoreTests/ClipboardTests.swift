import XCTest
import AppKit
@testable import VerbVoxCore

/// Round-trips text through `Clipboard.snapshot()` / `restore(_:)`, mirroring the
/// Python `backup_clipboard` / `restore_clipboard` behavior (which the paste flow
/// relies on to preserve the user's clipboard across a paste). Image/file/RTF
/// preservation is verified manually; text is the unit-testable slice.
final class ClipboardTests: XCTestCase {

    func testSnapshotRestoreRoundTripsText() {
        let pb = NSPasteboard.general
        let original = "clipboard payload \(UUID().uuidString)"

        pb.clearContents()
        pb.setString(original, forType: .string)

        let snapshot = Clipboard.snapshot()

        // Clobber the pasteboard, as a paste would.
        pb.clearContents()
        pb.setString("temporary paste text", forType: .string)
        XCTAssertNotEqual(pb.string(forType: .string), original)

        Clipboard.restore(snapshot)

        XCTAssertEqual(pb.string(forType: .string), original)
    }

    func testSnapshotPreservesMultipleTypesOnOneItem() {
        let pb = NSPasteboard.general
        let text = "typed \(UUID().uuidString)"
        let custom = NSPasteboard.PasteboardType("com.verbvox.test.custom")
        let blob = Data([0x01, 0x02, 0x03, 0x04])

        pb.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setData(blob, forType: custom)
        pb.writeObjects([item])

        let snapshot = Clipboard.snapshot()
        pb.clearContents()
        Clipboard.restore(snapshot)

        XCTAssertEqual(pb.string(forType: .string), text)
        XCTAssertEqual(pb.data(forType: custom), blob)
    }
}
