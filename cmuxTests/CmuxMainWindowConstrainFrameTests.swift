import AppKit
import XCTest

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

#if DEBUG
@MainActor
final class CmuxMainWindowConstrainFrameTests: XCTestCase {
    // On a display/system sleep→wake, AppKit re-runs its constrain pass over
    // every window and repositions even windows that are already fully
    // on-screen; cmux never re-asserts its saved frame afterward, so the window
    // creeps each sleep cycle. CmuxMainWindow.constrainFrameRect must leave a
    // fully-on-screen (below-the-menu-bar) frame untouched so AppKit can no
    // longer move it — see the screen-agnostic helper cases below. A frame whose
    // titlebar is UNDER the menu bar is the one exception: it is pinned back down
    // so the traffic-light buttons stay reachable (the pin is idempotent, so it
    // still does not creep).
    func testConstrainPinsMenuBarOverlappingFrameBelowMenuBar() throws {
        guard let screen = NSScreen.main else {
            throw XCTSkip("No screen available for constrainFrameRect regression")
        }
        let window = CmuxMainWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        defer {
            window.orderOut(nil)
            window.close()
        }

        let size = NSSize(width: 800, height: 600)
        // Flush against the very top of the physical screen so the titlebar
        // overlaps the menu bar — the placement that hides the traffic lights.
        let proposed = NSRect(
            x: screen.visibleFrame.midX - size.width / 2,
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )

        let constrained = window.constrainFrameRect(proposed, to: screen)

        // x + size preserved; top pinned at/below the visibleFrame top (menu bar).
        XCTAssertEqual(constrained.origin.x, proposed.origin.x, accuracy: 0.5)
        XCTAssertEqual(constrained.size.width, proposed.size.width, accuracy: 0.5)
        XCTAssertEqual(constrained.size.height, proposed.size.height, accuracy: 0.5)
        XCTAssertLessThanOrEqual(constrained.maxY, screen.visibleFrame.maxY + 0.5)
    }

    // Screen-agnostic helper cases for the menu-bar pin.

    func testPinnedBelowMenuBarShiftsFrameWithTopUnderMenuBar() {
        let visible = NSRect(x: 0, y: 0, width: 1512, height: 948)
        // Titlebar 34pt under the menu bar (maxY 982 > 948).
        let frame = NSRect(x: 100, y: 382, width: 800, height: 600)
        let pinned = CmuxMainWindow.pinnedBelowMenuBar(frame, visibleFrame: visible)
        XCTAssertEqual(pinned.maxY, visible.maxY, accuracy: 0.001)
        XCTAssertEqual(pinned.origin.x, 100, accuracy: 0.001)
        XCTAssertEqual(pinned.size.width, 800, accuracy: 0.001)
        XCTAssertEqual(pinned.size.height, 600, accuracy: 0.001)
    }

    func testPinnedBelowMenuBarShrinksFrameTallerThanVisibleArea() {
        let visible = NSRect(x: 0, y: 0, width: 1512, height: 948)
        // Maximized to the full display frame (982 tall) — must shrink to 948 and
        // sit at the visible origin so the titlebar clears the menu bar.
        let frame = NSRect(x: 0, y: 0, width: 1512, height: 982)
        let pinned = CmuxMainWindow.pinnedBelowMenuBar(frame, visibleFrame: visible)
        XCTAssertEqual(pinned.origin.y, 0, accuracy: 0.001)
        XCTAssertEqual(pinned.size.height, 948, accuracy: 0.001)
        XCTAssertEqual(pinned.maxY, visible.maxY, accuracy: 0.001)
    }

    func testPinnedBelowMenuBarLeavesBelowMenuBarFrameUnchanged() {
        let visible = NSRect(x: 0, y: 0, width: 1512, height: 948)
        // Already fully below the menu bar — creep protection: returned as-is.
        let frame = NSRect(x: 100, y: 100, width: 800, height: 600) // maxY 700 < 948
        let pinned = CmuxMainWindow.pinnedBelowMenuBar(frame, visibleFrame: visible)
        XCTAssertEqual(pinned, frame)
    }

    // The decision helper is screen-agnostic, so these cases run deterministically
    // on CI regardless of the test host's display configuration.

    func testPreservesFrameFullyInsideVisibleArea() {
        let visible = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = NSRect(x: 100, y: 100, width: 800, height: 600)
        XCTAssertTrue(
            CmuxMainWindow.shouldPreserveFrameDuringConstrain(frame, visibleFrames: [visible])
        )
    }

    func testPreservesFrameWhoseTitlebarOverlapsMenuBarBand() {
        // The visible area excludes a 37pt menu-bar band at the top; the window's
        // titlebar pokes into it — the placement AppKit would otherwise push down.
        let visible = NSRect(x: 0, y: 0, width: 1440, height: 863)
        let frame = NSRect(x: 320, y: 263, width: 800, height: 637) // maxY 900 > 863
        XCTAssertTrue(
            CmuxMainWindow.shouldPreserveFrameDuringConstrain(frame, visibleFrames: [visible])
        )
    }

    func testDoesNotPreserveFrameStrandedOffScreen() {
        let visible = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = NSRect(x: 3000, y: 2000, width: 800, height: 600)
        XCTAssertFalse(
            CmuxMainWindow.shouldPreserveFrameDuringConstrain(frame, visibleFrames: [visible])
        )
    }

    func testDoesNotPreserveBarelyPeekingFrame() {
        let visible = NSRect(x: 0, y: 0, width: 1440, height: 900)
        // Only ~20pt of the window overlaps the bottom-left corner — not grabbable.
        let frame = NSRect(x: -780, y: -580, width: 800, height: 600)
        XCTAssertFalse(
            CmuxMainWindow.shouldPreserveFrameDuringConstrain(frame, visibleFrames: [visible])
        )
    }

    func testDoesNotPreserveWhenNoScreensAvailable() {
        let frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        XCTAssertFalse(
            CmuxMainWindow.shouldPreserveFrameDuringConstrain(frame, visibleFrames: [])
        )
    }
}
#endif
