import AppKit
import SwiftUI

final class MainWindowHostingView<Content: View>: NSHostingView<Content> {
    private let zeroSafeAreaLayoutGuide = NSLayoutGuide()

    override var safeAreaInsets: NSEdgeInsets { NSEdgeInsetsZero }
    override var safeAreaRect: NSRect { bounds }
    override var safeAreaLayoutGuide: NSLayoutGuide { zeroSafeAreaLayoutGuide }
    override var mouseDownCanMoveWindow: Bool { false }
    override var fittingSize: NSSize { CmuxMainWindow.minimumContentSize }
    override var intrinsicContentSize: NSSize { CmuxMainWindow.minimumContentSize }

    /// Lets a click on an interactive titlebar control (the sidebar toggle, the
    /// right-sidebar mode bar, the session-index header controls, etc.) both
    /// activate the window and trigger the control in a single click when the
    /// window is inactive — matching how macOS services controls in the titlebar.
    ///
    /// Scoped to registered ``MinimalModeTitlebarControlHitRegionRegistry`` regions
    /// (the regions `titlebarInteractiveControl()` registers) so clicking inactive
    /// *content* still only activates the window. This recovers the first-mouse
    /// behavior the previous nested-`NSHostingView` host provided, without
    /// reparenting the control (which dropped active-window clicks in the
    /// full-size-content titlebar band — issue #5099).
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        guard let event, let window else { return false }
        return isMinimalModeTitlebarControlHit(window: window, locationInWindow: event.locationInWindow)
    }

    required init(rootView: Content) {
        super.init(rootView: rootView)
        addLayoutGuide(zeroSafeAreaLayoutGuide)
        NSLayoutConstraint.activate([
            zeroSafeAreaLayoutGuide.leadingAnchor.constraint(equalTo: leadingAnchor),
            zeroSafeAreaLayoutGuide.trailingAnchor.constraint(equalTo: trailingAnchor),
            zeroSafeAreaLayoutGuide.topAnchor.constraint(equalTo: topAnchor),
            zeroSafeAreaLayoutGuide.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    deinit {}

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@MainActor
func configureCmuxMainWindowDragBehavior(_ window: NSWindow) {
    window.isMovableByWindowBackground = false
    window.isMovable = false
}

@MainActor
final class CmuxMainWindow: NSWindow, StickyTerminalOverlayConfigurable {
    static var minimumContentSize: NSSize {
        NSSize(
            width: CGFloat(SessionPersistencePolicy.minimumWindowWidth),
            height: CGFloat(SessionPersistencePolicy.minimumWindowHeight)
        )
    }

    static func standardFrame(forDefaultFrame defaultFrame: NSRect) -> NSRect {
        let minimumSize = minimumContentSize
        var frame = defaultFrame
        frame.size.width = max(frame.size.width, minimumSize.width)
        frame.size.height = max(frame.size.height, minimumSize.height)
        return frame
    }

    /// cmux creates its main window programmatically (never from a nib), so it
    /// cannot inherit fullscreen capability from Interface Builder and instead
    /// relied on AppKit *implicitly* granting `.fullScreenPrimary` to a
    /// resizable, titled window. That implicit grant is not reliable across
    /// macOS versions / display arrangements: on macOS 26 (Tahoe) a
    /// freshly-created window reports an empty collection behavior
    /// (`rawValue == 0`) and AppKit does not treat it as fullscreen-capable, so
    /// Toggle Full Screen / ⌃⌘F / the green traffic-light button all fail to
    /// enter a native fullscreen Space — the green button only zooms (#5933).
    ///
    /// Declaring `.fullScreenPrimary` here makes native fullscreen reachable
    /// regardless of the OS's implicit default. It is idempotent where AppKit
    /// would have granted it anyway, and composes with the temporary
    /// `.fullScreenDisallowsTiling` opt-out the window factory applies when
    /// spawning a window out of an existing fullscreen Space.
    override init(
        contentRect: NSRect,
        styleMask: NSWindow.StyleMask,
        backing: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: styleMask,
            backing: backing,
            defer: flag
        )
        collectionBehavior = Self.canonicalCollectionBehavior(collectionBehavior)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Returns `base` guaranteed to carry `.fullScreenPrimary` (and never
    /// `.fullScreenNone`) so a cmux main window can always enter a native
    /// fullscreen Space. Pure and `nonisolated` so it can be unit-tested
    /// without constructing a window; see ``init(contentRect:styleMask:backing:defer:)``
    /// for why declaring the capability explicitly is required.
    nonisolated static func canonicalCollectionBehavior(
        _ base: NSWindow.CollectionBehavior
    ) -> NSWindow.CollectionBehavior {
        var behavior = base
        // `.fullScreenNone` and `.fullScreenPrimary` are mutually exclusive;
        // drop any stale "none" before declaring primary so fullscreen is not
        // suppressed.
        behavior.remove(.fullScreenNone)
        behavior.insert(.fullScreenPrimary)
        return behavior
    }

    /// Whether this window is the dedicated Sticky Terminal overlay (see
    /// `StickyTerminalController`). Overlay windows cover the entire screen
    /// (including the menu bar) and float above other apps' windows.
    ///
    /// `nonisolated(unsafe)` so `WindowDecorationsController` can read it from
    /// its window-notification handlers: it is written once during main-thread
    /// window setup and only ever read on the main thread thereafter.
    nonisolated(unsafe) private(set) var isStickyTerminalOverlay = false

    /// Fraction of opacity for the Sticky Terminal overlay so the window
    /// underneath stays faintly visible.
    static let stickyTerminalOverlayAlpha: CGFloat = 0.9

    /// Configures this window as the Sticky Terminal fullscreen overlay:
    /// floats above other windows (including over other apps' fullscreen
    /// Spaces), joins all Spaces, is excluded from window cycling, and is
    /// slightly translucent so the content underneath remains faintly visible.
    func configureAsStickyTerminalOverlay() {
        isStickyTerminalOverlay = true
        level = .statusBar
        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle,
            .fullScreenDisallowsTiling,
        ]
        hidesOnDeactivate = false
        isExcludedFromWindowsMenu = true
        isOpaque = false
        alphaValue = Self.stickyTerminalOverlayAlpha
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
    }

    private var isSoftHiddenForVisibilityController = false

    func setSoftHiddenForVisibilityController(_ isSoftHidden: Bool) {
        isSoftHiddenForVisibilityController = isSoftHidden
        if isSoftHidden {
            makeFirstResponder(nil)
            ignoresMouseEvents = true
            alphaValue = 0
        } else {
            alphaValue = 1
            ignoresMouseEvents = false
        }
    }

    override func keyDown(with event: NSEvent) {
        guard !isSoftHiddenForVisibilityController else { return }
        super.keyDown(with: event)
    }

    override func keyUp(with event: NSEvent) {
        guard !isSoftHiddenForVisibilityController else { return }
        super.keyUp(with: event)
    }

    override func flagsChanged(with event: NSEvent) {
        guard !isSoftHiddenForVisibilityController else { return }
        super.flagsChanged(with: event)
    }

    /// cmux owns main-window placement: it persists and restores window frames
    /// itself and disables AppKit window restoration (`isRestorable = false`),
    /// re-applying the saved frame only at startup.
    ///
    /// On a display/system sleep→wake (the kind a locked Mac eventually goes
    /// through — the lock keystroke itself is not the trigger) AppKit re-runs
    /// its constrain pass over every window. The default implementation does not
    /// only clamp off-screen windows back into view; it also repositions windows
    /// that are *already fully on-screen*, which is what we observe as the
    /// window creeping each sleep cycle. The exact reposition is AppKit-internal
    /// and depends on the display arrangement and each screen's menu-bar /
    /// safe-area insets, so it is neither a fixed titlebar-height nudge nor
    /// limited to a window whose titlebar sits under the menu bar — it also hits
    /// e.g. a window in the bottom half of an external display, and likely other
    /// arrangements. Because cmux never re-asserts the saved frame after wake,
    /// whatever the re-constrain produced sticks and accumulates.
    ///
    /// Fix: refuse the re-constrain for any frame that is already reachable on
    /// some screen, and defer to AppKit's default only when the frame would
    /// otherwise be stranded off-screen (e.g. a display was disconnected), so a
    /// genuinely lost window can still be pulled back into view.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        // The Sticky Terminal overlay covers the full screen frame including
        // the menu bar band; AppKit's default constraining for titled windows
        // would clip it below the menu bar.
        if isStickyTerminalOverlay {
            return frameRect
        }
        if Self.shouldPreserveFrameDuringConstrain(
            frameRect,
            visibleFrames: NSScreen.screens.map(\.visibleFrame)
        ) {
            // Preserve off-screen freedom on the sides/bottom, but never let the
            // TOP edge slide under the menu bar — that hides the titlebar and its
            // traffic-light buttons (e.g. a window zoomed/restored to the full
            // display frame, maxY 982 vs a 948 visibleFrame). Pin the top below
            // the menu bar while keeping the rest of the preserved geometry.
            let targetScreen = screen
                ?? self.screen
                ?? NSScreen.screens.first(where: { $0.frame.intersects(frameRect) })
                ?? NSScreen.main
            return Self.pinnedBelowMenuBar(frameRect, visibleFrame: targetScreen?.visibleFrame)
        }
        return super.constrainFrameRect(frameRect, to: screen)
    }

    /// Shifts (and, if taller than the visible area, shrinks) `frame` so its top
    /// edge sits at or below the menu bar, leaving all other axes untouched. A
    /// frame already fully below the menu bar is returned unchanged.
    nonisolated static func pinnedBelowMenuBar(_ frame: NSRect, visibleFrame: NSRect?) -> NSRect {
        guard let visibleFrame, visibleFrame.height > 0 else { return frame }
        guard frame.maxY > visibleFrame.maxY else { return frame }
        var pinned = frame
        if pinned.height > visibleFrame.height {
            pinned.size.height = visibleFrame.height
        }
        pinned.origin.y = visibleFrame.maxY - pinned.size.height
        return pinned
    }

    /// Whether `proposedFrame` is reachable enough across `visibleFrames` that
    /// AppKit's constraining pass should be skipped. The frame qualifies when it
    /// overlaps some screen's visible area by at least `minimumVisibleExtent`
    /// points in both dimensions (or its full extent, when smaller) — i.e. a
    /// usable, grabbable slice of the window is on-screen.
    nonisolated static func shouldPreserveFrameDuringConstrain(
        _ proposedFrame: NSRect,
        visibleFrames: [NSRect],
        minimumVisibleExtent: CGFloat = 60
    ) -> Bool {
        let requiredWidth = min(proposedFrame.width, minimumVisibleExtent)
        let requiredHeight = min(proposedFrame.height, minimumVisibleExtent)
        for visibleFrame in visibleFrames {
            let intersection = proposedFrame.intersection(visibleFrame)
            if intersection.width >= requiredWidth, intersection.height >= requiredHeight {
                return true
            }
        }
        return false
    }
}

extension CmuxMainWindow {
    private static let defaultContentSize = NSSize(width: 1_000, height: 700)

    /// Returns an unpositioned content rect clamped to the visible display; callers own final placement.
    static func defaultContentRect(styleMask: NSWindow.StyleMask) -> NSRect {
        let unpositionedContentRect = NSRect(origin: .zero, size: defaultContentSize)
        guard let visibleFrame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame else {
            return unpositionedContentRect
        }

        let frameRect = NSWindow.frameRect(forContentRect: unpositionedContentRect, styleMask: styleMask)
        let clampedFrameRect = clampedFrame(frameRect, within: visibleFrame)
        return NSWindow.contentRect(forFrameRect: clampedFrameRect, styleMask: styleMask)
    }

    private static func clampedFrame(_ frame: NSRect, within visibleFrame: NSRect) -> NSRect {
        guard visibleFrame.width > 0, visibleFrame.height > 0 else { return frame }

        let width = min(max(frame.width, defaultContentSize.width), visibleFrame.width)
        let height = min(max(frame.height, defaultContentSize.height), visibleFrame.height)
        return NSRect(
            x: min(max(frame.minX, visibleFrame.minX), visibleFrame.maxX - width),
            y: min(max(frame.minY, visibleFrame.minY), visibleFrame.maxY - height),
            width: width,
            height: height
        )
    }
}
