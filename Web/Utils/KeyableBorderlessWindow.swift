import AppKit

/// Border-less window that can always regain key/main status.
/// We mutate the class of the SwiftUI-provided window to this subclass in `WindowConfigurator`.
final class KeyableBorderlessWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
} 