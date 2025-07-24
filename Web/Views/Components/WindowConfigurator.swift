import SwiftUI
import AppKit
import ObjectiveC.runtime

// Simple window configurator that enhances the existing window without breaking visibility
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        
        DispatchQueue.main.async {
            if let window = view.window {
                configureWindow(window)
            }
        }
        
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                configureWindow(window)
            }
        }
    }
    
    // Unique key for associated object to mark observer setup
    private static var keyRestorerKey: UInt8 = 0
    
    private func configureWindow(_ window: NSWindow) {
        // Window is already an NSWindow; we keep its original class to avoid KVO conflicts.
        // Instead of making it borderless we create a hidden-titlebar window which can still become key.

        // Install one-time observer to automatically restore key status if lost
        if objc_getAssociatedObject(window, &WindowConfigurator.keyRestorerKey) == nil {
            NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak window] _ in
                guard let w = window, w.isVisible else { return }
                // Give the system a tiny moment to hand back focus. If it doesn’t, steal it.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    if !w.isKeyWindow {
                        w.makeKey()
                        w.makeFirstResponder(w.contentView)
                    }
                }
            }
            // Mark observer as installed
            objc_setAssociatedObject(window, &WindowConfigurator.keyRestorerKey, true, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }

        // --- APPEARANCE CONFIGURATION ---
        // Create the "hidden title bar" look: visually border-less while still using a titled window
        // (required so it can always become key without subclassing).

        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true

        // Hide the traffic-light buttons to get a completely chrome-less appearance.
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        // Style mask keeps .titled so the window remains key-eligible, but adds .fullSizeContentView
        // so the content occupies the full frame.
        window.styleMask = [
            .titled,
            .resizable,
            .fullSizeContentView
        ]

        // Transparency + shadow for the floating glass feel
        window.backgroundColor = NSColor.clear
        window.isOpaque = false
        window.hasShadow = true

        // INPUT SAFETY: Keep movable background DISABLED to prevent global mouse event interception
        // This was the real cause of input locking - not the borderless style itself
        window.isMovableByWindowBackground = false
        
        // Full-size content configuration for true edge-to-edge design
        if let contentView = window.contentView {
            contentView.wantsLayer = true
            contentView.layer?.backgroundColor = NSColor.clear.cgColor
            
            // Ensure content view takes up the entire window frame with no title bar space
            contentView.autoresizingMask = [.width, .height]
        }
        
        // No system window controls in borderless mode - we use custom implementations
        // This maintains the pure floating glass panel aesthetic
    }
    
}