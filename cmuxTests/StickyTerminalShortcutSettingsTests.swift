import XCTest
import AppKit

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@MainActor
final class StickyTerminalShortcutSettingsTests: XCTestCase {
    private var originalSettingsFileStore: KeyboardShortcutSettingsFileStore!

    override func setUp() {
        super.setUp()
        originalSettingsFileStore = KeyboardShortcutSettings.settingsFileStore
        KeyboardShortcutSettings.settingsFileStore = KeyboardShortcutSettingsFileStore(
            primaryPath: FileManager.default.temporaryDirectory
                .appendingPathComponent("cmux-sticky-terminal-shortcuts-\(UUID().uuidString).json")
                .path,
            fallbackPath: nil,
            additionalFallbackPaths: [],
            startWatching: false
        )
        KeyboardShortcutSettings.resetAll()
    }

    override func tearDown() {
        KeyboardShortcutSettings.settingsFileStore = originalSettingsFileStore
        KeyboardShortcutSettings.resetAll()
        super.tearDown()
    }

    func testStickyTerminalDefaultShortcutIsCommandShiftT() {
        let defaultShortcut = KeyboardShortcutSettings.shortcut(for: .toggleStickyTerminal)

        XCTAssertEqual(
            defaultShortcut,
            StoredShortcut(key: "t", command: true, shift: true, option: false, control: false)
        )
        XCTAssertEqual(
            KeyboardShortcutSettings.Action.toggleStickyTerminal.normalizedRecordedShortcutResult(defaultShortcut),
            .accepted(defaultShortcut)
        )
    }

    func testReopenClosedBrowserPanelDefaultIsCommandZ() {
        // Cmd+Z reopens the most recently closed surface/terminal in the focused
        // workspace (no-op if the workspace itself is gone).
        XCTAssertEqual(
            KeyboardShortcutSettings.shortcut(for: .reopenClosedBrowserPanel),
            StoredShortcut(key: "z", command: true, shift: false, option: false, control: false)
        )
    }

    func testCloseTabDefaultIsCommandW() {
        // Cmd+W closes the focused surface; on the sticky window's last surface it
        // closes the whole hotkey window (see StickyTerminal close-behavior tests).
        XCTAssertEqual(
            KeyboardShortcutSettings.shortcut(for: .closeTab),
            StoredShortcut(key: "w", command: true, shift: false, option: false, control: false)
        )
    }

    func testStickyTerminalIsHiddenFromGenericShortcutsList() {
        // The recorder lives in the dedicated Sticky Terminal settings section,
        // like showHideAllWindows — so it is excluded from the generic list.
        XCTAssertFalse(KeyboardShortcutSettings.settingsVisibleActions.contains(.toggleStickyTerminal))
    }

    func testStickyTerminalRejectsBareSystemWideShortcut() {
        let bareShortcut = StoredShortcut(key: "t", command: false, shift: false, option: false, control: false)

        XCTAssertEqual(
            KeyboardShortcutSettings.Action.toggleStickyTerminal.normalizedRecordedShortcutResult(bareShortcut),
            .rejected(.systemWideHotkeyRequiresModifier)
        )
    }

    func testStickyTerminalRejectsConfiguredShowHideHotkeyConflict() {
        let reservedShortcut = StoredShortcut(key: "g", command: true, shift: false, option: true, control: true)

        KeyboardShortcutSettings.setShortcut(.unbound, for: .toggleStickyTerminal)
        SystemWideHotkeySettings.setShortcut(reservedShortcut)

        // Recording the same keystroke the system-wide Show/Hide hotkey already
        // occupies must be refused. The exact rejection reason
        // (`.conflictsWithAction` vs `.reservedBySystem`) depends on the active
        // keyboard layout, so only assert that it is rejected.
        let result = KeyboardShortcutSettings.Action.toggleStickyTerminal
            .normalizedRecordedShortcutResult(reservedShortcut)
        guard case .rejected = result else {
            return XCTFail("Expected the conflicting system-wide shortcut to be rejected, got \(result)")
        }
    }

    func testSettingsFileStoreParsesStickyTerminalShortcut() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmux-sticky-terminal-settings-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let settingsFileURL = directoryURL.appendingPathComponent("cmux.json", isDirectory: false)
        try """
        {
          "shortcuts": {
            "bindings": {
              "toggleStickyTerminal": {
                "first": { "key": "j", "command": true, "shift": false, "option": false, "control": true }
              }
            }
          }
        }
        """.write(to: settingsFileURL, atomically: true, encoding: .utf8)

        let store = KeyboardShortcutSettingsFileStore(
            primaryPath: settingsFileURL.path,
            fallbackPath: nil,
            startWatching: false
        )

        XCTAssertEqual(
            store.override(for: .toggleStickyTerminal),
            StoredShortcut(key: "j", command: true, shift: false, option: false, control: true)
        )
    }

    func testStickyTerminalSettingsDefaults() {
        let defaults = UserDefaults(suiteName: "cmux-sticky-terminal-\(UUID().uuidString)")!
        XCTAssertTrue(StickyTerminalSettings.isEnabled(defaults: defaults))
        XCTAssertFalse(StickyTerminalSettings.isAutoHideEnabled(defaults: defaults))

        StickyTerminalSettings.setEnabled(true, defaults: defaults)
        StickyTerminalSettings.setAutoHideEnabled(true, defaults: defaults)
        XCTAssertTrue(StickyTerminalSettings.isEnabled(defaults: defaults))
        XCTAssertTrue(StickyTerminalSettings.isAutoHideEnabled(defaults: defaults))

        StickyTerminalSettings.setEnabled(false, defaults: defaults)
        XCTAssertFalse(StickyTerminalSettings.isEnabled(defaults: defaults))

        StickyTerminalSettings.reset(defaults: defaults)
        XCTAssertTrue(StickyTerminalSettings.isEnabled(defaults: defaults))
        XCTAssertFalse(StickyTerminalSettings.isAutoHideEnabled(defaults: defaults))
    }

    // MARK: - Sticky Terminal close behavior

    func testAppDoesNotTerminateAfterLastWindowClosed() {
        // Closing the last window must keep the app (and its Carbon global hotkeys,
        // e.g. Sticky Terminal toggle) alive; quitting is explicit only.
        let appDelegate = AppDelegate()
        XCTAssertFalse(appDelegate.applicationShouldTerminateAfterLastWindowClosed(NSApp))
    }

    // MARK: - Close Tab routing to the Sticky Terminal (the reopen bug)

    func testStickyCloseTargetNilWhenNoStickyWindow() {
        // No sticky window exists → Close Tab must fall through to normal routing.
        let app = AppDelegate()
        XCTAssertNil(app.stickyTerminalCloseTarget(isKeyWindow: { _ in true }))
    }

    func testStickyCloseTargetNilWhenStickyNotKeyWindow() {
        // Sticky exists but is not the key window (focus elsewhere) → the shortcut
        // must NOT be hijacked by the sticky overlay.
        let app = AppDelegate()
        let manager = TabManager()
        let windowId = app.registerMainWindowContextForTesting(tabManager: manager)
        defer {
            app.setStickyTerminalWindowIdForTesting(nil)
            app.unregisterMainWindowContextForTesting(windowId: windowId)
        }
        app.setStickyTerminalWindowIdForTesting(windowId)

        XCTAssertNil(app.stickyTerminalCloseTarget(isKeyWindow: { _ in false }))
    }

    func testStickyCloseTargetRoutesToStickyManagerWhenKeyWindow() {
        // Exact repro: a REOPENED sticky is the key window. Cmd+W must route to the
        // sticky's own manager deterministically — the first-responder heuristic
        // mis-resolved the non-activating panel after a hide/reopen, so Cmd+W did
        // nothing. When a DIFFERENT window is key, the sticky must not hijack it.
        let app = AppDelegate()
        let stickyManager = TabManager()
        let stickyId = app.registerMainWindowContextForTesting(tabManager: stickyManager)
        let otherManager = TabManager()
        let otherId = app.registerMainWindowContextForTesting(tabManager: otherManager)
        defer {
            app.setStickyTerminalWindowIdForTesting(nil)
            app.unregisterMainWindowContextForTesting(windowId: stickyId)
            app.unregisterMainWindowContextForTesting(windowId: otherId)
        }
        app.setStickyTerminalWindowIdForTesting(stickyId)

        XCTAssertTrue(app.stickyTerminalCloseTarget(isKeyWindow: { $0 == stickyId }) === stickyManager)
        XCTAssertNil(app.stickyTerminalCloseTarget(isKeyWindow: { $0 == otherId }))
    }
}
