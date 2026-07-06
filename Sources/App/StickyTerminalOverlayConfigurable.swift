import AppKit

/// A cmux window that can act as the Sticky Terminal fullscreen overlay.
///
/// Both `CmuxMainWindow` and `StickyTerminalPanel` conform so callers can
/// treat either interchangeably when deciding overlay chrome (traffic-light
/// hiding, visibility-controller exclusion, etc.).
@MainActor
protocol StickyTerminalOverlayConfigurable: NSWindow {
    /// Whether this window is currently acting as the Sticky Terminal overlay.
    ///
    /// `nonisolated` so `WindowDecorationsController` can read it from its
    /// nonisolated window-notification handlers.
    nonisolated var isStickyTerminalOverlay: Bool { get }

    /// Applies (or re-asserts) the overlay chrome: floating level, all-Spaces
    /// collection behavior, translucency, and hidden window buttons.
    func configureAsStickyTerminalOverlay()
}
