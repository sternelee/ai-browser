# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a minimal SwiftUI iOS app called "Web" with a basic "Hello, world!" interface. The project follows standard iOS app architecture with:

- `WebApp.swift` - Main app entry point using `@main`
- `ContentView.swift` - Primary SwiftUI view with globe icon and text
- Standard Xcode project structure with unit tests and UI tests

## Common Commands

### Building and Running
- Build the project: `xcodebuild -project Web.xcodeproj -scheme Web build`
- Run tests: `xcodebuild test -project Web.xcodeproj -scheme Web -destination 'platform=iOS Simulator,name=iPhone 15'`
- Run unit tests only: `xcodebuild test -project Web.xcodeproj -scheme Web -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:WebTests`
- Run UI tests only: `xcodebuild test -project Web.xcodeproj -scheme Web -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:WebUITests`

### Development
- Open in Xcode: `open Web.xcodeproj`

## Code Architecture

- **App Structure**: Standard SwiftUI app with single scene `WindowGroup`
- **Testing**: Uses Swift Testing framework for unit tests (`@Test`) and XCTest for UI tests
- **UI Framework**: SwiftUI with standard system icons and styling
- **Target Platform**: iOS with standard app entitlements

## Important Notes

- Always ensure `xcodebuild` succeeds after making changes
- Unit tests use the newer Swift Testing framework with `@Test` annotations
- UI tests use traditional XCTest framework with `XCUIApplication`
- The app uses SwiftUI previews for development (`#Preview`)