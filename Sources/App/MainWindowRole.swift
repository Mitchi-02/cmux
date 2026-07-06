import Foundation

/// The role a cmux main window plays in the app's window topology.
enum MainWindowRole {
    /// A regular user-managed main window.
    case standard
    /// The dedicated Sticky Terminal overlay window: fullscreen, floats above
    /// other apps, shown/hidden by the global hotkey, never truly closed.
    case stickyTerminal
}
