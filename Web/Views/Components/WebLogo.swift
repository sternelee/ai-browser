import SwiftUI

// Minimal "W" SVG Logo - Adaptive to light/dark mode
struct WebLogo: View {
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ZStack {
            // Background circle with subtle gradient
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            logoBackgroundColor.opacity(0.1),
                            logoBackgroundColor.opacity(0.05)
                        ],
                        center: .center,
                        startRadius: 6,
                        endRadius: 20
                    )
                )
            
            // Main "W" shape
            LogoShape()
                .fill(logoForegroundColor)
                .frame(width: 16, height: 12)
        }
    }
    
    private var logoBackgroundColor: Color {
        colorScheme == .dark ? .white : .black
    }
    
    private var logoForegroundColor: Color {
        colorScheme == .dark ? .white : .black
    }
}

struct LogoShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let width = rect.width
        let height = rect.height
        
        // Create the "W" shape with clean, minimal lines
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: width * 0.2, y: height))
        path.addLine(to: CGPoint(x: width * 0.35, y: height * 0.4))
        path.addLine(to: CGPoint(x: width * 0.5, y: height * 0.8))
        path.addLine(to: CGPoint(x: width * 0.65, y: height * 0.4))
        path.addLine(to: CGPoint(x: width * 0.8, y: height))
        path.addLine(to: CGPoint(x: width, y: 0))
        path.addLine(to: CGPoint(x: width * 0.85, y: 0))
        path.addLine(to: CGPoint(x: width * 0.65, y: height * 0.6))
        path.addLine(to: CGPoint(x: width * 0.5, y: height * 0.2))
        path.addLine(to: CGPoint(x: width * 0.35, y: height * 0.6))
        path.addLine(to: CGPoint(x: width * 0.15, y: 0))
        path.closeSubpath()
        
        return path
    }
}

// Animated logo for loading states
struct AnimatedWebLogo: View {
    @State private var isAnimating: Bool = false
    
    var body: some View {
        WebLogo()
            .scaleEffect(isAnimating ? 1.1 : 1.0)
            .opacity(isAnimating ? 0.8 : 1.0)
            .animation(
                .easeInOut(duration: 1.0)
                .repeatForever(autoreverses: true),
                value: isAnimating
            )
            .onAppear {
                isAnimating = true
            }
    }
}

// App icon generator (for use in Xcode project)
struct AppIconGenerator: View {
    let size: CGFloat
    
    var body: some View {
        ZStack {
            // App icon background with subtle gradient
            RoundedRectangle(cornerRadius: size * 0.2)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.1, green: 0.1, blue: 0.15),
                            Color(red: 0.05, green: 0.05, blue: 0.1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            // Logo with proper scaling
            WebLogo()
                .frame(width: size * 0.6, height: size * 0.6)
        }
        .frame(width: size, height: size)
    }
}

#Preview {
    VStack(spacing: 20) {
        WebLogo()
            .frame(width: 80, height: 80)
        
        AnimatedWebLogo()
            .frame(width: 60, height: 60)
        
        AppIconGenerator(size: 120)
    }
    .padding()
}