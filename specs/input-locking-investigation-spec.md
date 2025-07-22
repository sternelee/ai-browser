# Input Locking Investigation Spec

## Problem Statement
**ALL INPUT FIELDS** in the browser become permanently unresponsive after some usage:
- Browser URL bars (both regular and hoverable) ✋ LOCKED
- Web content inputs (Google search, Reddit search bar) ✋ LOCKED  
- AI chat input box ✋ LOCKED
- New tab search input ✋ LOCKED

This persists even after **completely removing** the complex FocusCoordinator system, suggesting a deeper architectural issue.

## Investigation History

### Phase 1: SwiftUI Focus Loop Theory ❌ DISPROVEN
**Hypothesis:** SwiftUI `@FocusState` feedback loops in URL bars
**Action:** Fixed `isURLBarFocused = false` inside `.onChange(of: isURLBarFocused)` observers
**Result:** Issue persisted - web content inputs still locked

### Phase 2: Focus Coordination Theory ❌ DISPROVEN  
**Hypothesis:** Overly aggressive FocusCoordinator interfering with web content
**Action:** Extended timeouts from 3s to 30s, reduced interference
**Result:** Issue persisted - Google's own focus management still broken

### Phase 3: JavaScript Timer Interference Theory ⚠️ PARTIAL
**Hypothesis:** Timer cleanup breaking Google's focus restoration
**Action:** Removed `pagehide` event cleanup, kept only `beforeunload`
**Result:** Reduced some interference but issue persisted

### Phase 4: Complete Focus System Removal ❌ DISPROVEN
**Hypothesis:** Any focus coordination is the problem
**Action:** Completely deleted FocusCoordinator.swift, removed all coordination
**Result:** **STILL LOCKING!** - This proves the issue is NOT focus coordination

## Current Status: DEEPER ARCHITECTURAL ISSUE

Since removing the entire focus system didn't fix it, the root cause must be:

## New Investigation Theories

### Theory A: Main Thread Blocking 🔍 INVESTIGATE
**Hypothesis:** Some operation is blocking the main thread, preventing input handling
**Evidence:** All UI inputs (SwiftUI + WebKit) affected simultaneously
**Investigation Plan:**
- Search for `DispatchQueue.main.sync` calls
- Look for heavy operations on main thread
- Check AI model loading/streaming blocking main thread
- Profile main thread usage

### Theory B: WebKit Configuration Issue 🔍 INVESTIGATE  
**Hypothesis:** WebView configuration is interfering with input handling globally
**Evidence:** Both browser inputs AND web content inputs affected
**Investigation Plan:**
- Check WKWebViewConfiguration settings
- Look for input intercepting JavaScript
- Check if WebView is stealing first responder status
- Investigate WebView delegate methods

### Theory C: SwiftUI/AppKit Integration Bug 🔍 INVESTIGATE
**Hypothesis:** Mixing SwiftUI with AppKit is causing responder chain issues
**Evidence:** All input types affected (TextField, WebView, etc.)
**Investigation Plan:**
- Search for NSResponder/first responder handling
- Check if WindowConfigurator is interfering
- Look for focus/responder method overrides

### Theory D: Timer/Async Operation Interference 🔍 INVESTIGATE
**Hypothesis:** Background timers are interfering with input event loop
**Evidence:** Issue happens "after some usage" - timing dependent
**Investigation Plan:**
- Find all Timer instances in codebase
- Check DispatchQueue.main.asyncAfter usage
- Look for repeating operations that could block input

### Theory E: Memory/Resource Issue 🔍 INVESTIGATE
**Hypothesis:** Memory pressure or resource exhaustion affecting input handling
**Evidence:** Happens after usage (not immediately)
**Investigation Plan:**
- Check for memory leaks
- Monitor resource usage during locking
- Look for retain cycles in UI components

## Investigation Plan

### Immediate Actions (Phase 5)
1. **Build Fix** - Resolve compilation errors to enable testing
2. **Main Thread Profiling** - Add logging to detect main thread blocking
3. **Timer Audit** - Find and log all timer operations
4. **WebView Investigation** - Check configuration and JavaScript injection
5. **Minimal Reproduction** - Create minimal test case

### Diagnostic Logging Strategy
Add comprehensive logging to identify:
- When exactly the locking occurs
- What operations precede the locking
- Main thread activity during locking
- Timer/async operations when locking happens
- WebView state during locking

### Progressive Testing
1. **Disable AI System** - Test if AI processing is causing blocking
2. **Disable JavaScript Injection** - Test if WebView scripts are interfering
3. **Disable Timers** - Test if background operations are the cause
4. **Minimal UI** - Test with basic TextField only

## Success Criteria
- All input fields remain responsive during normal usage
- No permanent locking after AI interactions
- Both SwiftUI inputs and web content inputs work properly
- Solution is architecturally sound and maintainable

## Files to Investigate
- `WebView.swift` - WebKit configuration and JavaScript injection
- `AIAssistant.swift` / `LLMRunner.swift` - AI operations that might block main thread
- `WindowConfigurator.swift` - AppKit/SwiftUI integration
- `TabManager.swift` - Tab lifecycle and memory management
- All files with `Timer`, `DispatchQueue`, or `@MainActor`

## Next Steps
1. Fix build errors to enable testing
2. Add comprehensive diagnostic logging
3. Test each theory systematically
4. Create minimal reproduction case
5. Profile main thread and memory usage during locking

This is a critical issue affecting core browser functionality. The solution requires deep architectural investigation since surface-level fixes have failed.