# Web - macOS AI Browser

Built natively with SwiftUI to delivers a minimal, progressive browsing experience with integrated AI capabilities.

<img width="4694" height="2379" alt="image" src="https://github.com/user-attachments/assets/b54a2937-09d5-480a-9ca6-eae7967af30c" />

![Web Browser](https://img.shields.io/badge/platform-macOS-blue.svg)
![Swift](https://img.shields.io/badge/Swift-6-orange.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)

*_Note: This is an experimental early access version, as AI models improve so will Web_*

## Features

### Core Browsing
- **WebKit Integration**: Native WebKit rendering with WKWebView
- **Tab Management**: Tab hibernation for optimal performance
- **Glass Design**: Glass morphism UI with ultraThinMaterial effects
- **Keyboard Shortcuts**: Comprehensive shortcuts (⌘T, ⌘W, ⌘R, etc.)
- **Downloads**: Built-in download manager with progress tracking

### Privacy & Security
- **Incognito Mode**: Private browsing sessions
- **Ad Blocking**: Integrated ad blocking service
- **DNS over HTTPS**: Enhanced DNS privacy
- **Password Management**: Secure password handling
- **Privacy Settings**: Granular privacy controls

### AI Integration
- **Local AI Models**: On-device AI powered by [Apple MLX](https://github.com/ml-explore/mlx) and [MLX Swift Examples](https://github.com/ml-explore/mlx-swift-examples)
- **MLX Framework**: Apple Silicon optimized inference
- **Privacy-First**: AI processing happens locally on your device
- **Smart Assistance**: Integrated AI sidebar for web content analysis

## Requirements

- macOS 14.0 or later
- Apple Silicon Mac (for AI features)
- Xcode 15.0+ (for development)

## Installation

### From Source

1. Clone the repository:
```bash
git clone https://github.com/nuance-dev/Web.git
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
- **MLXRunner**: Local AI model execution
- **DownloadManager**: File download handling
- **BookmarkService**: Bookmark management

## AI Features

Web integrates local AI capabilities using Apple's MLX framework and Swift examples:

- **Framework**: [Apple MLX](https://github.com/ml-explore/mlx) with [MLX Swift Examples](https://github.com/ml-explore/mlx-swift-examples)
- **Models**: Gemma and other compatible models
- **Inference**: MLX-optimized for Apple Silicon
- **Privacy**: All AI processing happens locally

### Code Standards

- Swift 6 with strict concurrency
- Zero warnings/errors policy
- Comprehensive keyboard shortcuts
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

- [Apple MLX](https://github.com/ml-explore/mlx) - Machine learning framework for Apple Silicon
- [MLX Swift Examples](https://github.com/ml-explore/mlx-swift-examples) - Swift examples and utilities for MLX
- WebKit - Apple's web rendering engine
- Core Data - Local data persistence
- Combine - Reactive programming framework

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [Apple MLX](https://github.com/ml-explore/mlx) by Apple for optimized machine learning on Apple Silicon
- [MLX Swift Examples](https://github.com/ml-explore/mlx-swift-examples) by Apple for Swift integration examples
- Apple's WebKit team for the excellent web rendering engine
- The Swift community for SwiftUI and modern iOS/macOS development patterns

---

## 🔗 Links

- Website: [Nuanc.me](https://nuanc.me)
- Report issues: [GitHub Issues](https://github.com/nuance-dev/Web/issues)
- Follow updates: [@Nuanced](https://x.com/Nuancedev)
