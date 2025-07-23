import SwiftUI

/// Unified loading dots animation component for AI responses
/// Provides consistent timing and visual style across all AI interfaces
struct LoadingDotsView: View {
    let dotColor: Color
    let dotSize: CGFloat
    let spacing: CGFloat
    
    @State private var animationPhase: Double = 0
    @State private var isAnimating: Bool = false
    
    // Standard configuration for consistency
    private let animationDuration: Double = 1.5
    private let phaseOffset: Double = 0.5
    private let scaleRange: (min: CGFloat, max: CGFloat) = (0.5, 1.5)
    
    init(dotColor: Color = .secondary.opacity(0.6), dotSize: CGFloat = 6, spacing: CGFloat = 4) {
        self.dotColor = dotColor
        self.dotSize = dotSize
        self.spacing = spacing
    }
    
    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(dotColor)
                    .frame(width: dotSize, height: dotSize)
                    .scaleEffect(dotScale(for: index))
            }
        }
        .onAppear {
            startAnimation()
        }
        .onDisappear {
            stopAnimation()
        }
    }
    
    private func dotScale(for index: Int) -> CGFloat {
        guard isAnimating else { return 1.0 }
        
        let phase = animationPhase + Double(index) * phaseOffset
        let normalizedSin = (sin(phase) + 1) / 2 // Normalize to 0-1
        return scaleRange.min + (scaleRange.max - scaleRange.min) * normalizedSin
    }
    
    private func startAnimation() {
        guard !isAnimating else { return }
        
        isAnimating = true
        withAnimation(
            .linear(duration: animationDuration)
                .repeatForever(autoreverses: false)
        ) {
            animationPhase = .pi * 2
        }
    }
    
    private func stopAnimation() {
        isAnimating = false
        withAnimation(.easeOut(duration: 0.3)) {
            animationPhase = 0
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 32) {
        // Standard typing indicator style
        HStack(spacing: 8) {
            Text("Typing")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
            LoadingDotsView()
        }
        
        // Green AI style
        HStack(spacing: 8) {
            Text("AI Thinking")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
            LoadingDotsView(dotColor: .green.opacity(0.6))
        }
        
        // Larger dots for different contexts
        HStack(spacing: 8) {
            Text("Processing")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
            LoadingDotsView(dotColor: .blue.opacity(0.6), dotSize: 8, spacing: 6)
        }
    }
    .padding(32)
    .background(Color(.controlBackgroundColor))
}