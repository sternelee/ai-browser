import SwiftUI
import AppKit

class GlassWindow: NSWindow {
    private var hoverTrackingArea: NSTrackingArea?
    
    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        
        setupGlassEffect()
        setupCustomTitleBar()
        setupHoverTracking()
    }
    
    private func setupGlassEffect() {
        // Enable glass effect
        appearance = NSAppearance(named: .aqua)
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        
        // Custom material and blur
        if let contentView = contentView {
            let visualEffect = NSVisualEffectView()
            visualEffect.material = .hudWindow
            visualEffect.blendingMode = .behindWindow
            visualEffect.state = .active
            
            contentView.addSubview(visualEffect, positioned: .below, relativeTo: nil)
            visualEffect.frame = contentView.bounds
            visualEffect.autoresizingMask = [.width, .height]
        }
        
        // Subtle border radius and padding
        contentView?.wantsLayer = true
        contentView?.layer?.cornerRadius = 12
        contentView?.layer?.masksToBounds = true
        
        // Super slight padding
        if let contentView = contentView {
            let inset: CGFloat = 8
            let paddedFrame = contentView.frame.insetBy(dx: inset, dy: inset)
            contentView.frame = paddedFrame
        }
    }
    
    private func setupCustomTitleBar() {
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        
        // Position window controls in custom positions with hover behavior
        if let closeButton = standardWindowButton(.closeButton),
           let miniButton = standardWindowButton(.miniaturizeButton),
           let zoomButton = standardWindowButton(.zoomButton) {
            
            // Initially hide controls (they appear on hover)
            closeButton.alphaValue = 0.0
            miniButton.alphaValue = 0.0
            zoomButton.alphaValue = 0.0
            
            // Position controls with subtle spacing
            let controlY = frame.height - 32
            closeButton.frame = NSRect(x: 16, y: controlY, width: 16, height: 16)
            miniButton.frame = NSRect(x: 36, y: controlY, width: 16, height: 16)
            zoomButton.frame = NSRect(x: 56, y: controlY, width: 16, height: 16)
        }
    }
    
    private func setupHoverTracking() {
        // Setup mouse tracking for hover effects in title bar area
        let trackingRect = NSRect(x: 0, y: frame.height - 50, width: frame.width, height: 50)
        hoverTrackingArea = NSTrackingArea(
            rect: trackingRect,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        
        if let trackingArea = hoverTrackingArea {
            contentView?.addTrackingArea(trackingArea)
        }
    }
    
    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        showWindowControls()
    }
    
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        hideWindowControls()
    }
    
    private func showWindowControls() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.allowsImplicitAnimation = true
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            
            standardWindowButton(.closeButton)?.alphaValue = 1.0
            standardWindowButton(.miniaturizeButton)?.alphaValue = 1.0
            standardWindowButton(.zoomButton)?.alphaValue = 1.0
        }
    }
    
    private func hideWindowControls() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.allowsImplicitAnimation = true
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            
            standardWindowButton(.closeButton)?.alphaValue = 0.0
            standardWindowButton(.miniaturizeButton)?.alphaValue = 0.0
            standardWindowButton(.zoomButton)?.alphaValue = 0.0
        }
    }
    
    override func setFrame(_ frameRect: NSRect, display displayFlag: Bool) {
        super.setFrame(frameRect, display: displayFlag)
        
        // Update tracking area when window frame changes
        if let oldTrackingArea = hoverTrackingArea {
            contentView?.removeTrackingArea(oldTrackingArea)
        }
        setupHoverTracking()
    }
}

// SwiftUI wrapper for custom glass window
struct GlassWindowView<Content: View>: NSViewControllerRepresentable {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    func makeNSViewController(context: Context) -> NSViewController {
        let viewController = NSViewController()
        let hostingView = NSHostingView(rootView: content)
        viewController.view = hostingView
        return viewController
    }
    
    func updateNSViewController(_ nsViewController: NSViewController, context: Context) {
        if let hostingView = nsViewController.view as? NSHostingView<Content> {
            hostingView.rootView = content
        }
    }
}