# Web Browser - Technical Specification

## Project Overview

Web is a next-generation macOS browser built with SwiftUI that delivers an unparalleled minimal, progressive UX experience rivaling Arc Browser. This native application emphasizes subtle design, smooth animations, and innovative interface paradigms that make browsing feel effortless and delightful.

OG prompt for reference of the ethos of this app: ("This new macOS app. Ensure you put in the intro that it is a next-gen UX macOS swiftUI native app, that grea design is minimal, small, subtle and progressive, that rivals Arc Browser. Should use native webkit integration, swiftui, should be forversion 14+ of macos so it uses the almost latest stuff. For features it needs to have: 1. All the basics of a browser like the inspect, history, cmd + t for new tab, download manager and all the shit necessary, and al the basics, dont forget any please. Please list them all in the spec t implement. 2. Custom title bar that dissapears like the arc browser, i should have a custom glass main window with a super slightly padding,then with cmd + s you toggle between sidebar or top bar for the tabs, in sidebar mode we should only show the favicons not the tabs names so it would be a super mega minimal sidebar, this would disrupt the industry people would love it, also since that sidebar would be so small the window controls like close, minimize, expand should like appear only o hover or something next-gen. 3. We need a cmd to toggle the tabs (sidebar or top bar) on/off into a windowless/borderless edge-to-edge mode, so only the website is visible. 4. Let's have a nic performant UI, minimal but nice looking, glass, it should have but smoot animations, the name of the app is "Web", lets add to create an svgsquared logo and use that one everywhere, for now could just be a "W". 5 Lets create a minimal "new tab" experience, a custom input bar thatsearches google but looks super nice. 6. Lets have a settings with all the basics. 7. I don't know if its easy to implement but would be nice t have an integrated native ad blocker like safari does, to have autofil like safari does and save passwords and stuff, automatic updates, also that stuff where you connect your google profile and it auto logins on all google places idk if thats possible locally and natively in the app, and restore all previously closed tabs/windows. 8. We also need incognit mode ofc, its a basic, clear all cookies and cache after closing., cmd + shift + t to reopen last closed tab too. 9. Customize toolbar. 10. hovering links a status bar should appear from the bot to show where the link shows, think of other next-gen ways we ca use this dynamic status bar for, super contextual ideas that would mak users go whoa. 11. Find in page, inspect, developer tools. 12. Background tab previews. 13. Adaptive Glass UI – Window background subtly adapts its glass tint based on website color scheme or favicon color. Favicon-based tab coloring – Sidebar favicon background gets a minimal color splash for faster recognition. 14. Floating micro-controls – Contextual floating buttons (e.g., back/forward) that appear on slight mouse movement.. 15. Background tab previews – Hovering over a favicon in sidebar shows a live preview thumbnail. 16. Subtle animated underline for loading states instead of spinners, next gen and super minimal gradienty and glowy. 17. GPU-accelerated smooth scrolling – Feel like iOS Safari, ultra-smooth with physics-based gestures. 18. Live content preview – Hovering over a link briefly shows a card preview of the page (cached snapshot). 19. Smart integration with Apple Universal Clipboard for seamless cross-device pasting. 20. Lets add some quick notes, in the new tab we have a quick notes section where users can write text or md like notion and we store it as a file in the hidden files where we store shit locally. 21. If easy have translation like safari does.... You can research Zen Browser, which is opensource, its c++ and javascript but maybe there is stuff to learn from it.
)

**Key Principles:**
- Great design is minimal, small, subtle, and progressive
- Native macOS integration using SwiftUI and WebKit
- macOS 14+ for latest API capabilities
- GPU-accelerated performance
- Glass morphism and adaptive UI
- Progressive disclosure of features

## Technical Architecture

### Core Technologies
- **Language:** Swift 6
- **UI Framework:** SwiftUI
- **Web Engine:** WebKit (WKWebView)
- **Minimum OS:** macOS 14.0+
- **Build System:** Xcode 16+
- **Architecture Pattern:** MVVM with Combine
- **Data Persistence:** Core Data for history/bookmarks, UserDefaults for settings
- **Networking:** URLSession for downloads, WebKit for browsing

### Project Structure
```
Web/
├── WebApp.swift (App entry point)
├── Models/
│   ├── Tab.swift
│   ├── Bookmark.swift
│   ├── HistoryItem.swift
│   └── Settings.swift
├── Views/
│   ├── MainWindow/
│   │   ├── WebContentView.swift
│   │   ├── CustomTitleBar.swift
│   │   ├── SidebarView.swift
│   │   └── TabBarView.swift
│   ├── NewTab/
│   │   ├── NewTabView.swift
│   │   └── QuickNotesView.swift
│   ├── Settings/
│   │   └── SettingsView.swift
│   └── Components/
│       ├── GlassBackground.swift
│       ├── FloatingControls.swift
│       └── StatusBar.swift
├── ViewModels/
│   ├── BrowserViewModel.swift
│   ├── TabViewModel.swift
│   └── SettingsViewModel.swift
├── Services/
│   ├── WebKitService.swift
│   ├── AdBlockService.swift
│   ├── PasswordManager.swift
│   └── UpdateService.swift
├── Utils/
│   ├── Extensions/
│   └── Helpers/
└── Resources/
    └── Assets.xcassets
```

### Architecture Overview

| Layer | Tech / Frameworks |
|-------|-------------------|
| UI | SwiftUI 3, Combine, SF Symbols 5, MaterialFX |
| Web Engine | WKWebView (WebKit stable & experimental build) |
| Data | Core Data (history, bookmarks), UserDefaults |
| Services | Keychain, URLSession, Network.framework |
| Updates | Sparkle v3 (delta & background) |
| Pattern | MVVM + coordinators |

## Feature Breakdown

### Phase 1: Core Browser Foundation
1. **Basic WebKit Integration**
   - WKWebView wrapper with SwiftUI
   - Navigation controls (back, forward, refresh)
   - URL bar with loading states
   - Basic tab management

2. **Essential Browser Features**
   - History tracking
   - Bookmarks system
   - Download manager with progress
   - Find in page (Cmd+F)
   - Developer tools/inspect element
   - Print functionality
   - Zoom controls

3. **Keyboard Shortcuts**
   - Cmd+T: New tab
   - Cmd+W: Close tab
   - Cmd+Shift+T: Reopen closed tab
   - Cmd+L: Focus URL bar
   - Cmd+R: Refresh
   - Cmd+D: Bookmark
   - Cmd+H: History
   - Cmd+Shift+N: Incognito mode

### Phase 2: Next-Gen UI/UX
1. **Custom Glass Window**
   - NSWindow customization with glass effect
   - Subtle padding and border radius
   - Adaptive tint based on content

2. **Revolutionary Tab Management**
   - Collapsible title bar (Arc-style)
   - Cmd+S: Toggle sidebar/top bar
   - Favicon-only minimal sidebar mode
   - Hover-reveal window controls
   - Smooth spring animations

3. **Edge-to-Edge Mode** *(Inspired by macOS 18 Finder)*
   - Cmd+Shift+B: Toggle borderless mode
   - Complete chrome hiding - website content is never obscured
   - Gesture-based navigation with physics-based momentum
   - **Seamless hover-reveal controls**: When hovering near window edges, UI elements slide in from the edges without overlaying web content, ensuring the viewed website is never obfuscated. Ideally everything has rounded corner and its like a "fluid or liquid" thats comes out on hover.
   - If top bar active → hover top edge reveals tab bar with smooth slide-in animation
   - If sidebar active → hover left edge reveals favicon-only sidebar
   - Smart new tab input: Hovering bottom edge reveals a minimal search bar for quick Google searches
   - All hover interactions use the macOS 18 principle of revealing controls from edges rather than overlaying content

4. **Logo Design**
   - Minimal "W" SVG logo
   - Adaptive to light/dark mode
   - Used in app icon and new tab

### Phase 3: Advanced Features
1. **New Tab Experience**
   - Beautiful search input with glass morphism
   - Google search integration
   - Quick notes section (Markdown support)
   - Recently closed tabs
   - Frequently visited sites

2. **Smart Status Bar**
   - Context-aware floating bar
   - Link preview on hover
   - Download progress
   - Security indicators
   - Loading progress with gradient animation

3. **Performance Features**
   - GPU-accelerated scrolling
   - Tab hibernation for memory
   - Preloading and caching
   - Smooth 120fps animations

### Phase 4: Security & Privacy
1. **Ad Blocker**
   - Native content blocking rules
   - EasyList integration
   - Custom filter support
   - Performance optimized

2. **Password Manager**
   - Keychain integration
   - Autofill support
   - Secure password generation
   - Cross-device sync via iCloud

3. **Privacy Features**
   - Incognito mode with separate contexts
   - Cookie/cache clearing
   - Tracking prevention
   - DNS over HTTPS

### Phase 5: Advanced Interactions
1. **Adaptive Glass UI**
   - Dynamic tint extraction from favicon
   - Subtle color accents in sidebar
   - Ambient lighting effects
   - Smooth color transitions

2. **Floating Micro-Controls**
   - Context-sensitive buttons
   - Hover-activated controls
   - Minimal visual footprint
   - Spring physics animations

3. **Live Previews**
   - Tab hover previews
   - Link preview cards
   - Smooth thumbnail generation
   - WebKit snapshots

### Phase 6: System Integration
1. **Apple Ecosystem**
   - Universal Clipboard support
   - Handoff integration
   - iCloud sync for bookmarks/history
   - Continuity features

2. **Updates & Maintenance**
   - Sparkle framework integration
   - Background updates
   - Delta updates
   - Rollback capability

3. **Translation**
   - Native translation API
   - Inline translation overlay
   - Language detection
   - Offline capability

## Implementation Sessions

### Session 1: Foundation (Week 1) ✅ COMPLETED
- [x] Set up Xcode project with proper structure
- [x] Create basic WebKit wrapper view
- [x] Implement tab data model with hibernation
- [x] Basic navigation controls with gestures
- [x] URL bar with loading states and suggestions
- [x] Tab creation and switching with memory management
- [x] Essential browser features (print, zoom, developer tools)
- [x] Download manager with progress tracking
- [x] Keyboard shortcuts (Cmd+T, Cmd+W, Cmd+R, etc.)
- [ ] Customizable toolbar system
- [ ] Session restoration for closed tabs/windows

### Session 2: Revolutionary UI (Week 2)  
- [ ] Glass window implementation with adaptive tinting
- [ ] Custom collapsible title bar (Arc-style)
- [ ] Sidebar/top bar toggle (Cmd+S)
- [ ] Favicon-only minimal sidebar mode
- [ ] Window control hover effects
- [ ] Smooth spring animations with 120fps

### Session 3: Edge-to-Edge Mode (Week 3)
- [ ] Borderless browsing mode (Cmd+Shift+B)
- [ ] Gesture-based navigation in edge-to-edge
- [ ] Hover zones for sidebar/topbar reveal
- [ ] Complete chrome hiding system
- [ ] Context-sensitive floating controls

### Session 4: New Tab Experience (Week 4)
- [ ] Minimal new tab with glass morphism
- [ ] Google search integration
- [ ] Quick notes with Markdown support
- [ ] Recently closed tabs section
- [ ] Frequently visited sites
- [ ] Floating particles background effect
- [ ] Logo design and integration

### Session 5: Advanced Interactions (Week 5)
- [ ] Floating micro-controls on mouse movement
- [ ] Live tab previews with thumbnails
- [ ] Link preview cards with Open Graph data
- [ ] Background tab previews on hover
- [ ] Context-sensitive selection tools
- [ ] Google profile integration for auto-login

### Session 6: Performance & Adaptive Effects (Week 6)
- [ ] GPU-accelerated smooth scrolling (iOS Safari-like)
- [ ] Tab hibernation with memory monitoring
- [ ] Adaptive glass effects based on favicon colors
- [ ] Dynamic color extraction with k-means clustering
- [ ] Performance monitoring and alerts
- [ ] Memory optimization strategies

### Session 7: Security & Privacy (Week 7)
- [ ] Native ad blocker with EasyList integration
- [ ] Content blocking rules compilation
- [ ] Password manager with AES-256 encryption
- [ ] Keychain integration with biometric auth
- [ ] Incognito mode with data isolation
- [ ] Enhanced privacy protections

### Session 8: System Integration (Week 8)
- [ ] Apple ecosystem features (Handoff, Universal Clipboard)
- [ ] iCloud sync for bookmarks/history/settings
- [ ] Native translation with macOS 14+ API
- [ ] Automatic updates with Sparkle framework
- [ ] Delta updates and rollback support

### Session 9: Polish & Testing (Week 9)
- [ ] Comprehensive unit and UI testing
- [ ] Performance profiling and optimization
- [ ] WCAG 2.1 accessibility compliance
- [ ] VoiceOver support and keyboard navigation
- [ ] Memory leak detection and fixes
- [ ] Cross-version compatibility testing
- [ ] Final polish and deployment preparation

## Keyboard Shortcuts Reference

| Action | Keys |
|---------------------------------|-----------------|
| New Tab | ⌘ T |
| Close Tab | ⌘ W |
| Reopen Closed Tab | ⇧⌘ T |
| Focus URL Bar | ⌘ L |
| Refresh | ⌘ R |
| Sidebar / Top-Bar Toggle | ⌘ S |
| Edge-to-Edge Mode | ⇧⌘ B |
| Bookmark Page | ⌘ D |
| History Window | ⌘ Y |
| Downloads | ⌥⌘ L |
| Incognito Window | ⇧⌘ N |
| Find in Page | ⌘ F |
| Developer Tools | ⌥⌘ I |
| Zoom In / Out / Reset | ⌘+ / ⌘– / ⌘0 |

## Design Guidelines

### Visual Design
- **Glass Effects:** Use NSVisualEffectView with .hudWindow material
- **Corner Radius:** 12pt for windows, 8pt for controls
- **Padding:** 16pt standard, 8pt compact
- **Animation Duration:** 0.3s with spring dampening
- **Colors:** System colors with 0.8 opacity for glass
- **Typography:** SF Pro Display for UI, SF Mono for URLs

### Interaction Design
- **Hover States:** 0.1s delay, subtle scale (1.02x)
- **Click Feedback:** Immediate visual response
- **Gestures:** Two-finger swipe for navigation
- **Drag & Drop:** Support for tabs, bookmarks, files
- **Accessibility:** Full VoiceOver support

## Performance Targets
- **Launch Time:** < 0.5 seconds
- **Tab Switch:** < 50ms
- **Page Load:** WebKit default + optimizations
- **Memory per Tab:** < 100MB baseline
- **Animation FPS:** Consistent 120fps

## Testing Strategy
- Unit tests for models and services
- UI tests for critical user flows
- Performance profiling with Instruments
- Memory leak detection
- Accessibility audit
- Cross-version compatibility

## 🚨 CRITICAL BUILD REQUIREMENT

**CRITICAL: lets strive for 0 logs console, bug have logs of errors logs EVERYWHERE, so we can properly debug bc we have error checks at every step but the ideal is 0 logs, we only see logs if there are errors**

**ALSO EVERY SESSION MUST END WITH ZERO WARNINGS AND ZERO ERRORS**

After completing each implementation session, you MUST:
1. Run `xcodebuild -project Web.xcodeproj -scheme Web build` 
2. Verify the build completes with **0 warnings** and **0 errors**
3. Fix any warnings or errors before proceeding to the next session
4. Test the app runs without crashes
5. Mark the session as complete only after achieving zero warnings/errors

**Why this is critical:**
- Warnings accumulate and become unmanageable
- They hide real issues and potential crashes
- Clean builds ensure production-ready code
- Prevents runtime crashes like Double→Int conversion overflow
- Maintains code quality throughout development

**Non-negotiable rule: Never proceed to the next phase with build warnings!**

## Discovered During Work

### WebKit Logging Suppression (July 20, 2025) ✅ COMPLETED
- **Issue**: Verbose WebKit system logs flooding console with RBSService, ViewBridge, and ProcessAssertion messages
- **Root Cause**: Default WebKit configuration outputs debugging information that's not useful for app development
- **Fixes Applied**:
  1. **Environment Variables**: Set `WEBKIT_DISABLE_VERBOSE_LOGGING`, `WEBKIT_SUPPRESS_PROCESS_LOGS`, and `OS_ACTIVITY_MODE=disable`
  2. **WebKit Preferences**: Disabled `logsPageMessagesToSystemConsoleEnabled` and `diagnosticLoggingEnabled` in WebView.swift:36-37
  3. **App-Level Logging**: Added structured logging with Logger for actual app events in WebApp.swift:29
  4. **Clean Console**: Significantly reduced log noise while keeping error logs for debugging
- **Verification**: Build completes with 0 warnings and 0 errors, console now shows minimal relevant logs

### Google Search Functionality Fix (July 20, 2025) ✅ COMPLETED
- **Issue**: Google search wasn't working properly for non-URL inputs in the address bar
- **Root Cause**: Inconsistent URL validation logic between URLBar.swift and BrowserView.swift components
- **Fixes Applied**:
  1. **Enhanced URL Validation**: Improved `isValidURL()` function to better distinguish between URLs and search queries
  2. **Decimal Number Handling**: Added logic to prevent decimal numbers (like "1.5") from being treated as domains
  3. **Consistent Logic**: Standardized URL processing between URLBar and BrowserView components
  4. **Search Query Encoding**: Proper URL encoding for Google search queries with special characters
- **Verification**: Build completes with 0 warnings and 0 errors, Google search now works for any non-URL input

### Phase 1 Critical Fixes Applied
**Double→Int Conversion Crash (July 20, 2025)** ✅ FULLY RESOLVED
- **Issue**: Runtime crash with "Double value cannot be converted to Int because the result would be greater than Int.max"
- **Root Cause**: Multiple unsafe operations including invalid WebGL preference keys and unsafe arithmetic operations
- **Comprehensive Fixes Applied**:
  1. **WebGL Configuration Fix**: Removed invalid `webgl2Enabled` and `webglEnabled` keys from WKPreferences that were causing NSUnknownKeyException crashes
  2. **Safe Conversion Utility**: Created `SafeNumericConversions.swift` with robust utility functions for all numeric conversions
  3. **Enhanced Progress Tracking**: Replaced manual safety checks with `SafeNumericConversions.safeProgress()` in WebView.swift:81 and BrowserView.swift:208
  4. **Safe Snapshot Creation**: Added comprehensive bounds validation using `SafeNumericConversions.validateSafeRect()` in Tab.swift:104-110
  5. **Download Safety**: Enhanced speed calculations with finite value checks in DownloadManager.swift:165-171
  6. **WebView Frame Safety**: Initialized WebView with safe non-zero frame (100x100) to prevent frame calculation issues
  7. **Comprehensive Validation**: Added utility functions for CGRect, CGSize, and numeric range validation
- **New Safety Infrastructure**:
  - `safeDoubleToInt()`: Clamps Double values to Int.min/Int.max range
  - `safeProgress()`: Validates and clamps progress values to 0.0-1.0
  - `validateSafeRect()`: Ensures CGRect has finite, safe dimensions
  - `validateSafeSize()`: Validates CGSize dimensions
- **Verification**: Build completes with 0 warnings and 0 errors, comprehensive crash prevention implemented

**Build Quality Enforcement**
- Established **zero warnings/errors** requirement for all sessions
- All Swift warnings eliminated from codebase
- Build process now clean and production-ready

## References
- Arc Browser UX patterns
- Safari implementation details
- WebKit documentation
- SwiftUI best practices
- Zen Browser (for inspiration): https://github.com/zen-browser/desktop
- **macOS 18 Finder Seamless Experience**: The principle of never obscuring content, demonstrated by macOS 18's Finder interface where hovering reveals controls without blocking the main content view. This serves as inspiration for the browser's edge-to-edge mode where website content is never obstructed - controls appear on hover from edges without overlaying the web content.

---

**Last Updated:** Initial specification
**Status:** Ready for implementation
**Version:** 1.0.0