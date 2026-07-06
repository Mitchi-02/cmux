import AppKit
import XCTest

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@MainActor
final class StickyTerminalControllerTests: XCTestCase {
    func testIndexOfScreenPicksScreenContainingMouse() {
        let frames = [
            NSRect(x: 0, y: 0, width: 1000, height: 800),
            NSRect(x: 1000, y: 0, width: 1440, height: 900),
        ]

        XCTAssertEqual(
            StickyTerminalController.indexOfScreen(containing: NSPoint(x: 1200, y: 400), screenFrames: frames),
            1
        )
        XCTAssertEqual(
            StickyTerminalController.indexOfScreen(containing: NSPoint(x: 500, y: 400), screenFrames: frames),
            0
        )
    }

    func testIndexOfScreenFallsBackToFirstWhenMouseOutside() {
        let frames = [NSRect(x: 0, y: 0, width: 1000, height: 800)]
        XCTAssertEqual(
            StickyTerminalController.indexOfScreen(containing: NSPoint(x: 5000, y: 5000), screenFrames: frames),
            0
        )
    }

    func testIndexOfScreenReturnsNilWithoutScreens() {
        XCTAssertNil(
            StickyTerminalController.indexOfScreen(containing: NSPoint(x: 0, y: 0), screenFrames: [])
        )
    }

    func testToggleDoesNothingWhenDisabled() {
        var ensureCalls = 0
        let controller = StickyTerminalController(
            dependencies: .init(
                ensureWindow: { ensureCalls += 1; return nil },
                isEnabled: { false },
                isAutoHideEnabled: { false },
                mouseLocation: { .zero },
                screens: { [] },
                hideApplicationIfNoOtherVisibleWindow: {},
                isShortcutRecorderActive: { false }
            )
        )

        controller.toggle()
        XCTAssertEqual(ensureCalls, 0)
        XCTAssertFalse(controller.isWindowVisible)
    }

    func testToggleShowsWindowWhenEnabled() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let controller = StickyTerminalController(
            dependencies: .init(
                ensureWindow: { window },
                isEnabled: { true },
                isAutoHideEnabled: { false },
                mouseLocation: { .zero },
                screens: { [] },
                hideApplicationIfNoOtherVisibleWindow: {},
                isShortcutRecorderActive: { false }
            )
        )

        controller.toggle()
        XCTAssertTrue(window.isVisible)

        window.orderOut(nil)
    }

    func testForgetWindowForcesFreshWindowOnNextShow() {
        // Regression: after a real close (Cmd+W on the last surface), the
        // controller must drop its window so the next show() builds a FRESH,
        // registered overlay. Reusing the closed window left it out of the
        // main-window contexts, so every shortcut bypassed on the reopened
        // overlay (Cmd+W/Cmd+T did nothing).
        var ensureCalls = 0
        var windows: [NSWindow] = []
        let controller = StickyTerminalController(
            dependencies: .init(
                ensureWindow: {
                    ensureCalls += 1
                    let window = NSWindow(
                        contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                        styleMask: [.titled],
                        backing: .buffered,
                        defer: false
                    )
                    windows.append(window)
                    return window
                },
                isEnabled: { true },
                isAutoHideEnabled: { false },
                mouseLocation: { .zero },
                screens: { [] },
                hideApplicationIfNoOtherVisibleWindow: {},
                isShortcutRecorderActive: { false }
            )
        )

        controller.show()
        XCTAssertEqual(ensureCalls, 1)

        // A plain hide keeps the window (reused on next show — no rebuild).
        controller.hide()
        controller.show()
        XCTAssertEqual(ensureCalls, 1, "hide() must reuse the existing overlay window")

        // A real close forgets the window → next show() rebuilds a fresh one.
        controller.forgetWindow()
        controller.show()
        XCTAssertEqual(ensureCalls, 2, "forgetWindow() must force a fresh overlay window")

        windows.forEach { $0.orderOut(nil) }
    }
}
