import XCTest
@testable import VerbVoxCore

/// State-machine tests for hold-to-talk detection. The regression that motivated
/// the debounce: a Cmd→Ctrl remapper surfaces a transient `{cmd,ctrl}` state that
/// exactly matches the With-AI combo, which used to fire a phantom
/// record-then-instant-stop (beep, no audio).
final class HoldToTalkMachineTests: XCTestCase {

    private let noAI: Set<HotkeyCombo.Modifier> = [.ctrl, .alt]
    private let withAI: Set<HotkeyCombo.Modifier> = [.ctrl, .cmd]

    private func makeMachine() -> HoldToTalkMachine {
        HoldToTalkMachine(noAICombo: noAI, withAICombo: withAI)
    }

    // MARK: - The bug: remapper transient must NOT start a session

    func testRemapperTransientDoesNotStart() {
        var m = makeMachine()

        // Cmd→Ctrl remap in progress: {cmd} → {cmd,ctrl} → {ctrl}, all within ms.
        XCTAssertEqual(m.flagsChanged([.cmd]), [])                       // no match yet
        XCTAssertEqual(m.flagsChanged([.cmd, .ctrl]), [.armStartTimer(withAI)])
        XCTAssertEqual(m.flagsChanged([.ctrl]), [.cancelStartTimer])     // resolved away

        // Even if the (already-cancelled) timer somehow fires, it must not commit.
        XCTAssertEqual(m.startTimerFired(withAI), [])
        XCTAssertFalse(m.isRecording)
    }

    func testTransientThatSkipsIntermediateNeverArms() {
        var m = makeMachine()
        // Fast press where the burst coalesces straight to {ctrl}: no arm at all.
        XCTAssertEqual(m.flagsChanged([.cmd]), [])
        XCTAssertEqual(m.flagsChanged([.ctrl]), [])
        XCTAssertFalse(m.isRecording)
    }

    // MARK: - A genuine hold still starts

    func testHeldComboStartsAfterDebounce() {
        var m = makeMachine()
        XCTAssertEqual(m.flagsChanged([.ctrl]), [])                       // partial
        XCTAssertEqual(m.flagsChanged([.ctrl, .alt]), [.armStartTimer(noAI)])
        // Still held when the debounce elapses → commit.
        XCTAssertEqual(m.startTimerFired(noAI), [.commitStart(.noAI)])
        XCTAssertTrue(m.isRecording)
    }

    func testWithAIComboStartsWhenGenuinelyHeld() {
        var m = makeMachine()
        XCTAssertEqual(m.flagsChanged([.ctrl, .cmd]), [.armStartTimer(withAI)])
        XCTAssertEqual(m.startTimerFired(withAI), [.commitStart(.withAI)])
        XCTAssertTrue(m.isRecording)
    }

    // MARK: - Stop semantics

    func testReleaseStopsRecording() {
        var m = makeMachine()
        _ = m.flagsChanged([.ctrl, .alt])
        _ = m.startTimerFired(noAI)
        XCTAssertTrue(m.isRecording)
        XCTAssertEqual(m.flagsChanged([.ctrl]), [.stop])                 // released alt
        XCTAssertFalse(m.isRecording)
    }

    func testExtraModifierWhileRecordingStops() {
        var m = makeMachine()
        _ = m.flagsChanged([.ctrl, .alt])
        _ = m.startTimerFired(noAI)
        XCTAssertEqual(m.flagsChanged([.ctrl, .alt, .shift]), [.stop])   // superset also breaks
        XCTAssertFalse(m.isRecording)
    }

    // MARK: - Release before the debounce elapses

    func testReleaseBeforeDebounceCancelsAndNeverStarts() {
        var m = makeMachine()
        XCTAssertEqual(m.flagsChanged([.ctrl, .alt]), [.armStartTimer(noAI)])
        XCTAssertEqual(m.flagsChanged([.ctrl]), [.cancelStartTimer])     // let go early
        XCTAssertEqual(m.startTimerFired(noAI), [])                      // stale timer no-ops
        XCTAssertFalse(m.isRecording)
    }

    func testTimerForSupersededComboDoesNotStart() {
        var m = makeMachine()
        // Arm no-AI, then slide to with-AI without fully releasing.
        XCTAssertEqual(m.flagsChanged([.ctrl, .alt]), [.armStartTimer(noAI)])
        XCTAssertEqual(m.flagsChanged([.ctrl, .cmd]), [.armStartTimer(withAI)])
        // The old no-AI timer firing must not start anything.
        XCTAssertEqual(m.startTimerFired(noAI), [])
        XCTAssertFalse(m.isRecording)
        // The current with-AI timer still commits.
        XCTAssertEqual(m.startTimerFired(withAI), [.commitStart(.withAI)])
        XCTAssertTrue(m.isRecording)
    }

    // MARK: - Duplicate events don't re-arm

    func testDuplicateMatchDoesNotRearm() {
        var m = makeMachine()
        XCTAssertEqual(m.flagsChanged([.ctrl, .alt]), [.armStartTimer(noAI)])
        XCTAssertEqual(m.flagsChanged([.ctrl, .alt]), [])                // same combo, keep waiting
    }
}
