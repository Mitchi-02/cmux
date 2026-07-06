import AppKit

/// The dedicated Sticky Terminal overlay window, implemented as a
/// **non-activating** `NSPanel` so it can appear and take keyboard focus over
/// another app — including an app in native fullscreen (its own Space) —
/// without activating cmux. Activating the app would switch macOS out of the
/// fullscreen Space back to the desktop, which is exactly the behavior we must
/// avoid. This mirrors iTerm2's "floating panel" hotkey-window mode.
@MainActor
final class StickyTerminalPanel: NSPanel, StickyTerminalOverlayConfigurable {
    nonisolated let isStickyTerminalOverlay = true

    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: style.union(.nonactivatingPanel),
            backing: backingStoreType,
            defer: flag
        )
    }

    // A terminal needs real key/main status so keystrokes reach the surface,
    // even though the panel never activates the app.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// The overlay covers the whole screen frame including the menu-bar band;
    /// AppKit's default constrain for titled windows would clip it.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    func configureAsStickyTerminalOverlay() {
        level = .statusBar
        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle,
            .fullScreenDisallowsTiling,
        ]
        // Panels hide themselves when the app deactivates by default; the
        // sticky terminal manages its own show/hide, and (over a fullscreen app)
        // cmux is never the active app, so this must stay visible.
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        isFloatingPanel = true
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
        isRestorable = false
        isOpaque = false
        alphaValue = CmuxMainWindow.stickyTerminalOverlayAlpha
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
    }
}
