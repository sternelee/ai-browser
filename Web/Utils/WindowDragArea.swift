import SwiftUI
import AppKit

/// A custom drag area for borderless windows that allows dragging without intercepting all input events
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowDragAreaView {
        return WindowDragAreaView()
    }
    
    func updateNSView(_ nsView: WindowDragAreaView, context: Context) {
        // No updates needed
    }
}

class WindowDragAreaView: NSView {
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        // Make the view transparent
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }
    
    override func mouseDown(with event: NSEvent) {
        // Only handle primary mouse button for dragging
        if event.type == .leftMouseDown {
            window?.performDrag(with: event)
        } else {
            super.mouseDown(with: event)
        }
    }
    
    override func mouseDragged(with event: NSEvent) {
        // Let the window handle the drag
        window?.performDrag(with: event)
    }
    
    // Ensure this view doesn't interfere with other mouse events
    override func rightMouseDown(with event: NSEvent) {
        super.rightMouseDown(with: event)
    }
    
    override func otherMouseDown(with event: NSEvent) {
        super.otherMouseDown(with: event)
    }
}