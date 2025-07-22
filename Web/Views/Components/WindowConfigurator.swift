import SwiftUI
import AppKit

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
    
    private func configureWindow(_ window: NSWindow) {
        // RESTORE BORDERLESS ARCHITECTURE: Bring back the truly borderless floating window
        // while maintaining input safety through targeted fixes instead of architectural changes
        
        // Enhance window appearance - transparent floating glass panel
        window.backgroundColor = NSColor.clear
        window.isOpaque = false
        window.hasShadow = true
        
        // RESTORE BORDERLESS: Use the original borderless style for true floating aesthetic
        // This creates a window with no title bar or system chrome
        window.styleMask = [.borderless, .resizable]
        
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