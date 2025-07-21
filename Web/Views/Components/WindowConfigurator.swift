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
        // Enhance window appearance while keeping it visible
        window.backgroundColor = NSColor.clear
        window.isOpaque = false
        window.hasShadow = true
        
        // Remove title bar completely - this eliminates the top padding
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        
        // Make window movable by dragging anywhere
        window.isMovableByWindowBackground = true
        
        // Content view configuration for transparency and full size
        if let contentView = window.contentView {
            contentView.wantsLayer = true
            contentView.layer?.backgroundColor = NSColor.clear.cgColor
        }
        
        // Completely hide window controls - we'll add custom ones with hover
        if let closeButton = window.standardWindowButton(.closeButton) {
            closeButton.isHidden = true
        }
        if let miniButton = window.standardWindowButton(.miniaturizeButton) {
            miniButton.isHidden = true
        }
        if let zoomButton = window.standardWindowButton(.zoomButton) {
            zoomButton.isHidden = true
        }
    }
    
}