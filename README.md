# Web

A next-generation macOS browser built with SwiftUI that delivers minimal, progressive UX with integrated AI capabilities.

![Web Browser](https://img.shields.io/badge/platform-macOS-blue.svg)
![Swift](https://img.shields.io/badge/Swift-6-orange.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)

## Features

### Core Browsing
- **WebKit Integration**: Native WebKit rendering with WKWebView
- **Tab Management**: Smart tab hibernation for optimal performance
- **Glass Design**: Beautiful glass morphism UI with ultraThinMaterial effects
- **Keyboard Shortcuts**: Comprehensive shortcuts (⌘T, ⌘W, ⌘R, etc.)
- **Downloads**: Built-in download manager with progress tracking

### Privacy & Security
- **Incognito Mode**: Private browsing sessions
- **Ad Blocking**: Integrated ad blocking service
- **DNS over HTTPS**: Enhanced DNS privacy
- **Password Management**: Secure password handling
- **Privacy Settings**: Granular privacy controls

### AI Integration
- **Local AI Models**: On-device AI powered by [LLM.swift](https://github.com/eastriverlee/LLM.swift)
- **MLX Framework**: Apple Silicon optimized inference
- **Privacy-First**: AI processing happens locally on your device
- **Smart Assistance**: Integrated AI sidebar for web content analysis

### Advanced Features
- **Bookmarks & History**: Full bookmark management and browsing history
- **Autofill**: Smart form filling capabilities  
- **Memory Management**: Intelligent tab hibernation
- **Hardware Detection**: Optimized for Apple Silicon

## Requirements

- macOS 14.0 or later
- Apple Silicon Mac (for AI features)
- Xcode 15.0+ (for development)

## Installation

### From Source

1. Clone the repository:
```bash
git clone https://github.com/your-username/Web.git
cd Web
```

2. Open the project in Xcode:
```bash
open Web.xcodeproj
```

3. Build and run (⌘R)

## Architecture

Web follows MVVM architecture with SwiftUI and Combine:

```
Web/
├── Models/           # Data models (Tab, Bookmark, etc.)
├── Views/           # SwiftUI views and components
├── ViewModels/      # Business logic and state management
├── Services/        # Core services (Download, History, etc.)
├── AI/             # Local AI integration
└── Utils/          # Utilities and extensions
```

### Key Components

- **TabManager**: Handles tab lifecycle and hibernation
- **WebView**: SwiftUI wrapper around WKWebView
- **LLMRunner**: Local AI model execution
- **DownloadManager**: File download handling
- **BookmarkService**: Bookmark management

## AI Features

Web integrates local AI capabilities using the LLM.swift framework:

- **Framework**: [LLM.swift v1.8.0](https://github.com/eastriverlee/LLM.swift)
- **Models**: Gemma and other compatible models
- **Inference**: MLX-optimized for Apple Silicon
- **Privacy**: All AI processing happens locally

## Development

### Building

```bash
# Build the project
xcodebuild -project Web.xcodeproj -scheme Web build

# Run tests
xcodebuild test -project Web.xcodeproj -scheme Web -destination 'platform=macOS'
```

### Code Standards

- Swift 6 with strict concurrency
- Zero warnings/errors policy
- Comprehensive keyboard shortcuts
- Glass design system
- Memory-efficient tab management

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## Keyboard Shortcuts

| Action | Shortcut | Description |
|--------|----------|-------------|
| New Tab | ⌘T | Open new tab |
| Close Tab | ⌘W | Close current tab |
| Reopen Tab | ⇧⌘T | Reopen last closed tab |
| Reload | ⌘R | Reload current page |
| Address Bar | ⌘L | Focus address bar |
| Find in Page | ⌘F | Search in page |
| Downloads | ⇧⌘J | Show downloads |
| Developer Tools | ⌥⌘I | Open developer tools |
| Toggle Top Bar | ⇧⌘H | Cycle top bar modes |

## Dependencies

- [LLM.swift](https://github.com/eastriverlee/LLM.swift) - Local language model inference for Apple platforms
- WebKit - Apple's web rendering engine
- Core Data - Local data persistence
- Combine - Reactive programming framework

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [LLM.swift](https://github.com/eastriverlee/LLM.swift) by eastriverlee for local AI capabilities
- Apple's WebKit team for the excellent web rendering engine
- The Swift community for SwiftUI and modern iOS/macOS development patterns

---

Built with ❤️ for macOS