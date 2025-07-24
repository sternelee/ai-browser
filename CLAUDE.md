# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Web is a next-generation macOS browser built with SwiftUI that delivers minimal, progressive UX. This native application uses WebKit for web rendering and emphasizes glass morphism, smooth animations, and innovative interface paradigms rivaling Arc Browser.

**Key Architecture:**
- **Language:** Swift 6 with SwiftUI
- **Web Engine:** WebKit (WKWebView)
- **Target Platform:** macOS 14.0+
- **Pattern:** MVVM with Combine
- **Data:** Core Data for history/bookmarks, UserDefaults for settings

## Common Commands

### Building and Running
- Build the project: `xcodebuild -project Web.xcodeproj -scheme Web build`
- Open in Xcode: `open Web.xcodeproj`
- Run tests: `xcodebuild test -project Web.xcodeproj -scheme Web -destination 'platform=macOS'`
- Clean build folder: `xcodebuild clean -project Web.xcodeproj -scheme Web`

### AI Development Commands
- Convert Gemma models: `./scripts/convert_gemma.sh`
- Check MLX dependencies: Review `Package.resolved` for MLX Swift versions

### Development Requirements
- **CRITICAL:** Every change must result in zero warnings and zero errors
- Always run full build before committing changes
- Test the app launches without crashes after modifications

## Code Architecture

### Core Structure
```
Web/
├── WebApp.swift              # App entry point with keyboard shortcuts
├── ContentView.swift         # Main view wrapper
├── Models/
│   ├── Tab.swift            # Tab data model with hibernation
│   └── ...
├── Views/
│   ├── MainWindow/
│   │   └── BrowserView.swift # Main browser interface
│   ├── Components/
│   │   ├── WebView.swift    # WebKit wrapper
│   │   ├── URLBar.swift     # Address bar with search
│   │   └── NavigationControls.swift
│   └── NewTab/, Settings/
├── ViewModels/
│   └── TabManager.swift     # Tab lifecycle management
├── Services/
│   └── DownloadManager.swift # File download handling
└── Utils/, specs/
```

### Key Components
- **TabManager**: Handles tab lifecycle, memory management, and hibernation
- **WebView**: SwiftUI wrapper around WKWebView with progress tracking
- **BrowserView**: Main UI orchestrating toolbar, tabs, and web content
- **DownloadManager**: Handles file downloads with progress and security
- **Keyboard Shortcuts**: Comprehensive shortcuts (Cmd+T, Cmd+W, etc.) defined in WebApp.swift
- **MLX Integration**: Local AI models using Apple MLX framework for on-device inference
- **ContextManager**: AI context processing and page content analysis
- **IncognitoSession**: Private browsing session management

### Architecture Patterns
- **MVVM**: ViewModels manage state, Views handle presentation
- **NotificationCenter**: Used for keyboard shortcut communication
- **Combine**: Reactive programming for data flow
- **Glass Design**: NSVisualEffectView with .ultraThinMaterial throughout

## Keyboard Shortcuts

| Action | Keys | Implementation |
|--------|------|---------------|
| New Tab | ⌘T | NotificationCenter.newTabRequested |
| Close Tab | ⌘W | NotificationCenter.closeTabRequested |
| Reopen Closed Tab | ⇧⌘T | NotificationCenter.reopenTabRequested |
| Reload | ⌘R | NotificationCenter.reloadRequested |
| Focus Address Bar | ⌘L | NotificationCenter.focusAddressBarRequested |
| Find in Page | ⌘F | NotificationCenter.findInPageRequested |
| Downloads | ⇧⌘J | NotificationCenter.showDownloadsRequested |
| Developer Tools | ⌥⌘I | NotificationCenter.showDeveloperToolsRequested |
| Cycle Top Bar Mode | ⇧⌘H | NotificationCenter.toggleTopBar |
| New Incognito Tab | ⇧⌘N | NotificationCenter.newIncognitoTabRequested |
| Toggle AI Sidebar | ⇧⌘A | NotificationCenter.toggleAISidebar |
| Focus AI Input | ⌥⌘A | NotificationCenter.focusAIInput |
| Next Tab | ⌘→ or ⇧⌘] | NotificationCenter.nextTabRequested |
| Previous Tab | ⌘← or ⇧⌘[ | NotificationCenter.previousTabRequested |
| Tab 1-9 | ⌘1-9 | NotificationCenter.selectTabByNumber |

## Critical Implementation Notes

### Build Quality Enforcement
- **Zero tolerance for warnings/errors**: All builds must be completely clean
- **Safety checks required**: All arithmetic operations must handle overflow/underflow
- **Progress value validation**: Always clamp progress values to 0.0-1.0 range
- **Memory management**: Implement proper tab hibernation for performance

### WebKit Integration
- Use `WKWebView` with proper configuration for security and performance
- Implement progress observers with safety guards for non-finite values
- Handle navigation delegate methods for custom URL handling
- Support developer tools through WKWebView inspector

### Performance Requirements
- Tab hibernation when not active to manage memory
- GPU-accelerated scrolling and animations
- Safe arithmetic operations to prevent runtime crashes
- Progress tracking with bounds checking

## Development Workflow

1. **Read specs first**: Always check `specs/web-browser-spec.md` for current requirements
2. **Follow phase structure**: Implementation is organized in phases (Foundation → UI → Advanced)
3. **Update specs**: Mark completed tasks and add new discoveries
4. **Zero-error builds**: Never proceed with warnings or errors
5. **Test thoroughly**: Verify no crashes and proper functionality

## Dependencies and External Packages

The project uses Swift Package Manager with these key dependencies:
- **MLX Swift**: Apple's machine learning framework for local AI inference
- **MLX Swift Examples**: Reference implementations and utilities
- **Swift Transformers**: Hugging Face transformers for Swift
- **Swift Collections**: Apple's enhanced collection types
- **Swift Numerics**: Numerical computing utilities
- **GzipSwift**: Compression utilities
- **Jinja**: Template engine for AI model configuration

## AI Integration Architecture

### MLX Framework Integration
- **MLX Runner**: Core engine for running local AI models (Gemma, etc.)
- **Model Management**: Download, convert, and cache AI models locally
- **Privacy-First**: All AI processing happens on-device, no data sent to external servers
- **Context Processing**: Intelligent page content analysis and summarization
- **Hardware Requirements**: Apple Silicon Mac required for optimal AI performance

### AI Services Structure
```
AI/
├── Models/           # Data models for AI functionality
├── Runners/          # MLX execution engines
├── Services/         # AI business logic and privacy management
├── Utils/           # Hardware detection and system monitoring
└── Views/           # AI sidebar and chat interface
```