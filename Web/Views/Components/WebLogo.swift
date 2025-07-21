import SwiftUI

// App Icon Logo - Uses actual app icon from Assets.xcassets
struct WebLogo: View {
    var body: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}


// Subtle animated logo for refined UX
struct AnimatedWebLogo: View {
    @State private var isAnimating: Bool = false
    
    var body: some View {
        WebLogo()
            .scaleEffect(isAnimating ? 1.02 : 1.0)
            .opacity(isAnimating ? 0.95 : 1.0)
            .animation(
                .easeInOut(duration: 3.0)
                .repeatForever(autoreverses: true),
                value: isAnimating
            )
            .onAppear {
                // Delayed start for more refined entrance
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isAnimating = true
                }
            }
    }
}

// App icon generator (for use in Xcode project)  
struct AppIconGenerator: View {
    let size: CGFloat
    
    var body: some View {
        WebLogo()
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