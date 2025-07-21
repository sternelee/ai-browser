import SwiftUI
import WebKit
import Combine

// GPU-accelerated smooth scrolling WebView for iOS Safari-like experience
class SmoothScrollingWebView: WKWebView {
    private var scrollVelocity: CGPoint = .zero
    private var lastScrollTime: CFTimeInterval = 0
    private var scrollDecelerationTimer: Timer?
    private var momentumScrolling: Bool = false
    private var scrollGestureRecognizer: NSPanGestureRecognizer?
    
    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frame, configuration: configuration)
        setupSmoothScrolling()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupSmoothScrolling()
    }
    
    private func setupSmoothScrolling() {
        // Enable GPU acceleration and optimization
        wantsLayer = true
        layer?.drawsAsynchronously = true
        layer?.shouldRasterize = false // Better for scrolling performance
        
        // Configure CALayer for optimal scrolling
        if let layer = layer {
            layer.contentsGravity = .topLeft
            layer.isOpaque = true
            layer.allowsEdgeAntialiasing = true
        }
        
        // Inject enhanced JavaScript for ultra-smooth scrolling
        let smoothScrollScript = generateSmoothScrollScript()
        let script = WKUserScript(source: smoothScrollScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        configuration.userContentController.addUserScript(script)
        
        // Setup native momentum scrolling for trackpad
        setupMomentumScrolling()
    }
    
    private func generateSmoothScrollScript() -> String {
        return """
        (function() {
            if (window.smoothScrollInitialized) return;
            window.smoothScrollInitialized = true;
            
            let isScrolling = false;
            let scrollTimeout;
            let lastScrollTime = Date.now();
            let scrollVelocity = 0;
            let scrollElement = document.documentElement || document.body;
            
            // Enhanced easing functions for natural motion
            const easing = {
                easeOutCubic: function(t) {
                    return 1 - Math.pow(1 - t, 3);
                },
                easeInOutQuart: function(t) {
                    return t < 0.5 ? 8 * t * t * t * t : 1 - 8 * (--t) * t * t * t;
                },
                springEasing: function(t) {
                    // Physics-based spring with proper damping
                    return 1 - Math.exp(-6 * t) * Math.cos(12 * Math.PI * t);
                },
                momentumEasing: function(t) {
                    // iOS-like momentum decay
                    return t * (2 - t);
                }
            };
            
            function smoothScroll(element, deltaY, duration = 600) {
                if (!element) return;
                
                const start = element.scrollTop;
                const change = deltaY;
                const startTime = performance.now();
                
                function animateScroll() {
                    const elapsed = performance.now() - startTime;
                    const progress = Math.min(elapsed / duration, 1);
                    
                    // Use spring easing for natural feel
                    const easedProgress = easing.springEasing(progress);
                    const currentScroll = start + (change * easedProgress);
                    
                    element.scrollTop = currentScroll;
                    
                    if (progress < 1) {
                        requestAnimationFrame(animateScroll);
                    } else {
                        isScrolling = false;
                    }
                }
                
                if (!isScrolling) {
                    isScrolling = true;
                    requestAnimationFrame(animateScroll);
                }
            }
            
            // Enhanced wheel event handling with velocity tracking
            function handleWheel(e) {
                // Don't prevent default if this looks like a horizontal scroll
                if (Math.abs(e.deltaX) > Math.abs(e.deltaY)) {
                    return; // Let native horizontal scrolling work
                }
                
                e.preventDefault();
                
                const now = performance.now();
                const deltaTime = Math.max(now - lastScrollTime, 16); // Minimum 16ms
                const element = scrollElement;
                
                // Calculate velocity for momentum
                const currentVelocity = e.deltaY / deltaTime;
                scrollVelocity = scrollVelocity * 0.8 + currentVelocity * 0.2; // Smooth velocity
                lastScrollTime = now;
                
                // Determine scroll distance with dynamic scaling
                let scrollDistance = e.deltaY;
                
                // Scale based on scroll speed for natural feel
                const velocityScale = Math.min(2.5, Math.max(0.8, Math.abs(scrollVelocity) * 0.1));
                scrollDistance *= velocityScale;
                
                // Dynamic duration based on distance and velocity
                const baseDuration = 400;
                const velocityFactor = Math.min(1.5, Math.abs(scrollVelocity) * 0.05);
                const dynamicDuration = baseDuration * (1 / Math.max(0.5, velocityFactor));
                
                smoothScroll(element, scrollDistance, Math.min(800, Math.max(200, dynamicDuration)));
                
                // Clear existing momentum timeout
                clearTimeout(scrollTimeout);
                
                // Set momentum scrolling timeout
                scrollTimeout = setTimeout(() => {
                    if (Math.abs(scrollVelocity) > 0.1) {
                        const momentumDistance = scrollVelocity * 300;
                        const momentumDuration = Math.min(1200, Math.max(400, Math.abs(momentumDistance) * 2));
                        smoothScroll(element, momentumDistance, momentumDuration);
                    }
                    scrollVelocity = 0;
                }, 150);
            }
            
            // Attach enhanced wheel listener
            document.addEventListener('wheel', handleWheel, { passive: false });
            
            // Touch/trackpad gesture support
            let touchStartY = 0;
            let touchVelocity = 0;
            let lastTouchTime = 0;
            
            document.addEventListener('touchstart', function(e) {
                if (e.touches.length === 1) {
                    touchStartY = e.touches[0].clientY;
                    lastTouchTime = performance.now();
                    touchVelocity = 0;
                }
            }, { passive: true });
            
            document.addEventListener('touchmove', function(e) {
                if (e.touches.length === 1) {
                    const touchY = e.touches[0].clientY;
                    const currentTime = performance.now();
                    const deltaY = touchStartY - touchY;
                    const deltaTime = Math.max(currentTime - lastTouchTime, 16);
                    
                    touchVelocity = deltaY / deltaTime;
                    
                    const element = scrollElement;
                    smoothScroll(element, deltaY * 0.8, 300);
                    
                    touchStartY = touchY;
                    lastTouchTime = currentTime;
                }
            }, { passive: true });
            
            document.addEventListener('touchend', function(e) {
                if (Math.abs(touchVelocity) > 2) {
                    const element = scrollElement;
                    const momentumDistance = touchVelocity * 500;
                    const momentumDuration = Math.min(1500, Math.max(600, Math.abs(momentumDistance) * 1.5));
                    smoothScroll(element, momentumDistance, momentumDuration);
                }
                touchVelocity = 0;
            }, { passive: true });
            
            // Keyboard scrolling enhancement
            document.addEventListener('keydown', function(e) {
                let scrollDistance = 0;
                let duration = 400;
                
                switch(e.key) {
                    case 'ArrowUp':
                        scrollDistance = -100;
                        duration = 300;
                        break;
                    case 'ArrowDown':
                        scrollDistance = 100;
                        duration = 300;
                        break;
                    case 'PageUp':
                        scrollDistance = -window.innerHeight * 0.8;
                        duration = 500;
                        break;
                    case 'PageDown':
                        scrollDistance = window.innerHeight * 0.8;
                        duration = 500;
                        break;
                    case 'Home':
                        if (e.metaKey || e.ctrlKey) {
                            scrollDistance = -scrollElement.scrollTop;
                            duration = 800;
                        }
                        break;
                    case 'End':
                        if (e.metaKey || e.ctrlKey) {
                            scrollDistance = scrollElement.scrollHeight - scrollElement.scrollTop - window.innerHeight;
                            duration = 800;
                        }
                        break;
                }
                
                if (scrollDistance !== 0) {
                    e.preventDefault();
                    smoothScroll(scrollElement, scrollDistance, duration);
                }
            });
            
            // Handle spacebar scrolling
            document.addEventListener('keydown', function(e) {
                if (e.key === ' ' && !e.target.matches('input, textarea, [contenteditable]')) {
                    e.preventDefault();
                    const scrollDistance = e.shiftKey ? -window.innerHeight * 0.8 : window.innerHeight * 0.8;
                    smoothScroll(scrollElement, scrollDistance, 500);
                }
            });
            
            // Page visibility optimization
            document.addEventListener('visibilitychange', function() {
                if (document.hidden) {
                    clearTimeout(scrollTimeout);
                    isScrolling = false;
                }
            });
            
        })();
        """
    }
    
    private func setupMomentumScrolling() {
        // Configure for 120fps scrolling performance
        if let scrollView = enclosingScrollView {
            scrollView.wantsLayer = true
            scrollView.layer?.drawsAsynchronously = true
            scrollView.hasVerticalScroller = true
            scrollView.hasHorizontalScroller = true
            scrollView.autohidesScrollers = true
            scrollView.scrollerStyle = .overlay
            
            // Enable elastic scrolling for natural feel
            scrollView.verticalScrollElasticity = .automatic
            scrollView.horizontalScrollElasticity = .automatic
        }
        
        // Add custom gesture recognizer for enhanced trackpad support
        let panGesture = NSPanGestureRecognizer(target: self, action: #selector(handlePanGesture(_:)))
        panGesture.delegate = self
        self.addGestureRecognizer(panGesture)
        scrollGestureRecognizer = panGesture
    }
    
    @objc private func handlePanGesture(_ gesture: NSPanGestureRecognizer) {
        let velocity = gesture.velocity(in: self)
        let translation = gesture.translation(in: self)
        
        switch gesture.state {
        case .began:
            scrollDecelerationTimer?.invalidate()
            momentumScrolling = false
            
        case .changed:
            // Track velocity for momentum calculation
            scrollVelocity = CGPoint(x: velocity.x, y: velocity.y)
            
        case .ended, .cancelled:
            // Apply momentum scrolling if velocity is significant
            if abs(velocity.y) > 200 {
                startMomentumScrolling(initialVelocity: velocity.y)
            }
            
        default:
            break
        }
    }
    
    private func startMomentumScrolling(initialVelocity: CGFloat) {
        momentumScrolling = true
        var currentVelocity = initialVelocity
        let decelerationRate: CGFloat = 0.96 // Slightly higher for more natural feel
        let minVelocity: CGFloat = 30
        
        scrollDecelerationTimer = Timer.scheduledTimer(withTimeInterval: 1/120.0, repeats: true) { [weak self] timer in
            guard let self = self, self.momentumScrolling else {
                timer.invalidate()
                return
            }
            
            // Apply deceleration with iOS-like curve
            currentVelocity *= decelerationRate
            
            // Stop if velocity is too low
            if abs(currentVelocity) < minVelocity {
                timer.invalidate()
                self.momentumScrolling = false
                return
            }
            
            // Apply scroll offset with smooth animation
            let scrollDelta = currentVelocity / 120.0 // Convert to per-frame at 120fps
            
            // Use JavaScript to apply smooth scrolling
            let script = """
                window.scrollBy({
                    top: \(scrollDelta),
                    behavior: 'instant'
                });
            """
            
            self.evaluateJavaScript(script) { _, error in
                if let error = error {
                    print("Momentum scroll error: \(error)")
                    timer.invalidate()
                    self.momentumScrolling = false
                }
            }
        }
    }
    
    // Override scrollWheel for additional native enhancements
    override func scrollWheel(with event: NSEvent) {
        // Let our JavaScript handle the smooth scrolling
        // but still call super for any native behaviors we want to preserve
        super.scrollWheel(with: event)
    }
    
    deinit {
        scrollDecelerationTimer?.invalidate()
        if let gesture = scrollGestureRecognizer {
            removeGestureRecognizer(gesture)
        }
    }
}

extension SmoothScrollingWebView: NSGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: NSGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: NSGestureRecognizer) -> Bool {
        return true
    }
}