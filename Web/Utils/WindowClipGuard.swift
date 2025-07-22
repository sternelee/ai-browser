import SwiftUI
import AppKit

/// A zero-size helper view that simply forces its backing `NSView` to have
/// `clipsToBounds == true`.  Apple changed the default for this property in
/// macOS 14 and a false value appears to be one of the triggers for the
/// `TUINSRemoteViewController does not override -viewServiceDidTerminateWithError:`
/// crash that leaves all input fields unresponsive.  Embedding this view once
/// at the root of the window guarantees the flag is set without otherwise
/// affecting layout or rendering.
struct WindowClipGuard: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.clipsToBounds = true   // <-- the important line
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Enforce the flag in case something else toggled it at runtime.
        if nsView.clipsToBounds == false {
            nsView.clipsToBounds = true
        }
    }
} 