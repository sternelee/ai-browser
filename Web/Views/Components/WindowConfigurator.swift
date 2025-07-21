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
        
        // Make title bar transparent and hide title
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        
        // Make window movable by dragging anywhere
        window.isMovableByWindowBackground = true
        
        // Content view configuration for transparency
        if let contentView = window.contentView {
            contentView.wantsLayer = true
            contentView.layer?.backgroundColor = NSColor.clear.cgColor
        }
        
        // Initially hide window controls but keep them functional
        if let closeButton = window.standardWindowButton(.closeButton) {
            closeButton.alphaValue = 0.0
        }
        if let miniButton = window.standardWindowButton(.miniaturizeButton) {
            miniButton.alphaValue = 0.0
        }
        if let zoomButton = window.standardWindowButton(.zoomButton) {
            zoomButton.alphaValue = 0.0
        }
        
        // Note: Window controls hover will be handled by SwiftUI in ContentView
    }
    
}