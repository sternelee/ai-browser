import SwiftUI
import AppKit

/// Enhanced drag area for borderless windows with improved hit testing and event handling
/// Provides window dragging capabilities without interfering with interactive UI elements
struct WindowDragArea: NSViewRepresentable {
    let allowsHitTesting: Bool
    
    init(allowsHitTesting: Bool = true) {
        self.allowsHitTesting = allowsHitTesting
    }
    
    func makeNSView(context: Context) -> WindowDragAreaView {
        let view = WindowDragAreaView()
        view.allowsHitTesting = allowsHitTesting
        return view
    }
    
    func updateNSView(_ nsView: WindowDragAreaView, context: Context) {
        nsView.allowsHitTesting = allowsHitTesting
    }
}

class WindowDragAreaView: NSView {
    var allowsHitTesting: Bool = true
    private var isDragging: Bool = false
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        // Configure for transparent background operation
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        
        // Enable proper mouse event tracking
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        
        // Remove existing tracking areas and add new one with updated bounds
        trackingAreas.forEach { removeTrackingArea($0) }
        
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        // Allow hit testing control - some areas may want to be transparent to mouse events
        if !allowsHitTesting {
            return nil
        }
        
        // Check if point is within bounds
        guard bounds.contains(point) else {
            return nil
        }
        
        // Return self for drag handling
        return self
    }
    
    override func mouseDown(with event: NSEvent) {
        // Only handle left mouse button for window dragging
        guard event.type == .leftMouseDown else {
            super.mouseDown(with: event)
            return
        }

        // Handle double-click to zoom/restore window size just like the standard title-bar
        if event.clickCount == 2 {
            window?.zoom(nil)
            return
        }
        
        // Ensure we have a valid window for dragging
        guard let window = window else {
            super.mouseDown(with: event)
            return
        }
        
        // Mark as starting to drag
        isDragging = true
        
        // Begin window drag operation
        window.performDrag(with: event)
    }
    
    override func mouseDragged(with event: NSEvent) {
        // Only proceed if we initiated the drag and have a valid window
        guard isDragging,
              let window = window else {
            super.mouseDragged(with: event)
            return
        }
        
        // Continue the window drag operation
        window.performDrag(with: event)
    }
    
    override func mouseUp(with event: NSEvent) {
        // End dragging state
        isDragging = false
        super.mouseUp(with: event)
    }
    
    // Preserve other mouse events for proper interaction
    override func rightMouseDown(with event: NSEvent) {
        super.rightMouseDown(with: event)
    }
    
    override func otherMouseDown(with event: NSEvent) {
        super.otherMouseDown(with: event)
    }
    
    override func scrollWheel(with event: NSEvent) {
        // Pass scroll events through to underlying views
        super.scrollWheel(with: event)
    }
    
    // Handle mouse enter/exit for potential visual feedback
    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        // Optionally add visual feedback when hovering over drag areas
    }
    
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        // Reset any visual feedback
    }
}