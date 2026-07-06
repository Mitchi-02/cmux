import AppKit

/// Shows/hides the dedicated Sticky Terminal overlay window (iTerm2-style
/// hotkey window). The window itself is a full cmux main window configured as
/// a fullscreen overlay; this controller owns only its visibility behavior.
@MainActor
final class StickyTerminalController {
    struct Dependencies {
        var ensureWindow: () -> NSWindow?
        var isEnabled: () -> Bool
        var isAutoHideEnabled: () -> Bool
        var mouseLocation: () -> NSPoint
        var screens: () -> [NSScreen]
        var hideApplicationIfNoOtherVisibleWindow: () -> Void
        var isShortcutRecorderActive: () -> Bool
    }

    private let dependencies: Dependencies
    private weak var window: NSWindow?
    private var didResignKeyObserver: NSObjectProtocol?
    private var defaultsObserver: NSObjectProtocol?
    private var spaceChangeObserver: NSObjectProtocol?
    private var suppressAutoHide = false

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleEnabledSettingChanged() }
        }
        // The overlay is summoned onto ONE Space (the active one). When the user
        // switches Spaces (trackpad swipe / Mission Control), hide it instead of
        // letting the always-spaces panel float over the new Space's app — iTerm2
        // hotkey-window behavior. Re-summon with the hotkey on the new Space.
        spaceChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.hideOnActiveSpaceChangeIfNeeded() }
        }
    }

    var isWindowVisible: Bool {
        guard let window else { return false }
        return window.isVisible && !window.isMiniaturized
    }

    func toggle() {
        guard dependencies.isEnabled() else { return }
        if isWindowVisible, window?.isKeyWindow == true {
            hide()
        } else {
            show()
        }
    }

    func show() {
        guard let window = window ?? dependencies.ensureWindow() else { return }
        attachIfNeeded(window)
        // Re-assert the overlay chrome every time: the window's level and
        // collection behavior can be reset by the shared main-window setup and
        // decoration passes after creation, which would otherwise make it a
        // normal desktop-Space window instead of a floating overlay.
        (window as? StickyTerminalOverlayConfigurable)?.configureAsStickyTerminalOverlay()
        let screens = dependencies.screens()
        if let index = Self.indexOfScreen(
            containing: dependencies.mouseLocation(),
            screenFrames: screens.map(\.frame)
        ) {
            window.setFrame(screens[index].frame, display: false)
        }
        // Order the (non-activating) panel in front WITHOUT activating cmux.
        // Activating the app would switch macOS off the current Space — back to
        // the desktop where cmux's other windows live — which is exactly the
        // bug we are avoiding. A non-activating panel appears over the current
        // Space (including a native-fullscreen app's Space) and can take key
        // focus while cmux stays in the background.
        window.orderFrontRegardless()
        // Re-home the (now visible) window to the active Space. Toggling
        // CanJoinAllSpaces forces AppKit to re-evaluate the window's Space
        // membership; doing it while the window is visible is what actually
        // moves it (iTerm2 does this only once the hotkey window is on screen).
        let behavior = window.collectionBehavior
        window.collectionBehavior = behavior.subtracting(.canJoinAllSpaces)
        window.collectionBehavior = behavior
        window.makeKeyAndOrderFront(nil)
#if DEBUG
        cmuxDebugLog(
            "stickyTerminal.show level=\(window.level.rawValue) " +
                "behavior=\(window.collectionBehavior.rawValue) " +
                "onActiveSpace=\(window.isOnActiveSpace) visible=\(window.isVisible) key=\(window.isKeyWindow)"
        )
#endif
    }

    /// Drops the reference to the overlay window after it is closed for real
    /// (Cmd+W on the last surface). Without this, `show()`'s `window ?? …` reuses
    /// the just-closed, now-unregistered NSWindow — a zombie with no main-window
    /// context — so the reopened overlay can't resolve shortcut routing and every
    /// shortcut (Cmd+W, Cmd+T, …) silently bypasses. Forgetting it forces the
    /// next show() to build a fresh, registered window.
    func forgetWindow() {
        if let didResignKeyObserver {
            NotificationCenter.default.removeObserver(didResignKeyObserver)
            self.didResignKeyObserver = nil
        }
        window = nil
    }

    func hide() {
        guard let window, window.isVisible else { return }
        suppressAutoHide = true
        window.orderOut(nil)
        suppressAutoHide = false
        dependencies.hideApplicationIfNoOtherVisibleWindow()
    }

    /// Cmd+W / red-button close requests on the sticky window hide it instead
    /// of destroying its content.
    func hideForCloseRequest() {
        hide()
    }

    /// Hides the window when the feature is disabled in Settings; the window
    /// (and its content) stays alive for the next enable.
    func handleEnabledSettingChanged() {
        if !dependencies.isEnabled(), isWindowVisible {
            hide()
        }
    }

    /// Index into `screenFrames` of the screen the overlay should cover: the
    /// one containing the mouse, falling back to the first screen. Pure so it
    /// can be unit-tested without constructing `NSScreen`s.
    nonisolated static func indexOfScreen(
        containing point: NSPoint,
        screenFrames: [NSRect]
    ) -> Int? {
        if let match = screenFrames.firstIndex(where: { NSMouseInRect(point, $0, false) }) {
            return match
        }
        return screenFrames.isEmpty ? nil : 0
    }

    private func attachIfNeeded(_ window: NSWindow) {
        guard self.window !== window else { return }
        if let didResignKeyObserver {
            NotificationCenter.default.removeObserver(didResignKeyObserver)
        }
        self.window = window
        didResignKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.autoHideIfNeeded() }
        }
    }

    private func hideOnActiveSpaceChangeIfNeeded() {
        // `suppressAutoHide` guards against our own show()-time collection-behavior
        // toggle re-homing the panel; only hide on a genuine user Space switch.
        guard !suppressAutoHide, isWindowVisible else { return }
        suppressAutoHide = true
        window?.orderOut(nil)
        suppressAutoHide = false
        dependencies.hideApplicationIfNoOtherVisibleWindow()
    }

    private func autoHideIfNeeded() {
        guard !suppressAutoHide,
              dependencies.isAutoHideEnabled(),
              !dependencies.isShortcutRecorderActive(),
              isWindowVisible else { return }
        // Focus already moved elsewhere, so just order out — no NSApp.hide.
        suppressAutoHide = true
        window?.orderOut(nil)
        suppressAutoHide = false
    }
}
