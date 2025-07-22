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
        // EXPERIMENTAL FIX: Less aggressive window configuration to preserve responder chain
        // The previous borderless configuration may have been disrupting input handling
        
        // Enhance window appearance while keeping it visible
        window.backgroundColor = NSColor.clear
        window.isOpaque = false
        window.hasShadow = true
        
        // RESPONDER CHAIN FIX: Use .titled instead of .borderless to preserve normal input handling
        // Keep .resizable and .miniaturizable for proper window behavior
        window.styleMask = [.titled, .resizable, .miniaturizable, .closable]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.toolbar = nil // Remove any toolbar
        
        // RESPONDER CHAIN FIX: Disable window background movability - this intercepts all mouse events
        // and may be preventing proper input focus handling
        window.isMovableByWindowBackground = false
        
        // Content view configuration for transparency and full size
        if let contentView = window.contentView {
            contentView.wantsLayer = true
            contentView.layer?.backgroundColor = NSColor.clear.cgColor
            
            // Ensure content view takes up the entire window frame
            contentView.autoresizingMask = [.width, .height]
        }
        
        // Completely hide and disable window controls - we'll add custom ones with hover
        if let closeButton = window.standardWindowButton(.closeButton) {
            closeButton.isHidden = true
            closeButton.alphaValue = 0.0
        }
        if let miniButton = window.standardWindowButton(.miniaturizeButton) {
            miniButton.isHidden = true
            miniButton.alphaValue = 0.0
        }
        if let zoomButton = window.standardWindowButton(.zoomButton) {
            zoomButton.isHidden = true
            zoomButton.alphaValue = 0.0
        }
    }
    
}