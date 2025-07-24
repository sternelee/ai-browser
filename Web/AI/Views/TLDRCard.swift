import SwiftUI
import Combine

/// Next-generation TL;DR component with progressive disclosure
/// Auto-generates summaries of current page content with subtle, minimal UI
struct TLDRCard: View {
    @ObservedObject var tabManager: TabManager
    @ObservedObject var aiAssistant: AIAssistant
    @ObservedObject private var contextManager = ContextManager.shared
    
    @State private var isExpanded: Bool = false
    @State private var tldrSummary: String = ""
    @State private var isGenerating: Bool = false
    @State private var lastProcessedURL: String = ""
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    
    // Animation states
    @State private var pulseOpacity: Double = 0.3
    @State private var shimmerOffset: CGFloat = -200
    
    var body: some View {
        VStack(spacing: 0) {
            if isExpanded {
                expandedView()
            } else {
                collapsedView()
            }
        }
        .background(cardBackground())
        .clipShape(RoundedRectangle(cornerRadius: isExpanded ? 12 : 20))
        .overlay(
            RoundedRectangle(cornerRadius: isExpanded ? 12 : 20)
                .stroke(.quaternary.opacity(0.3), lineWidth: 0.5)
        )
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isExpanded)
        .onReceive(NotificationCenter.default.publisher(for: .pageNavigationCompleted)) { _ in
            autoGenerateTLDR()
        }
        .onReceive(contextManager.$lastExtractedContext) { _ in
            autoGenerateTLDR()
        }
        .onChange(of: tabManager.activeTab?.url?.absoluteString) { _, newURL in
            if newURL != lastProcessedURL {
                autoGenerateTLDR()
            }
        }
        .onAppear {
            startPulseAnimation()
            autoGenerateTLDR()
        }
    }
    
    // MARK: - Collapsed View
    
    @ViewBuilder
    private func collapsedView() -> some View {
        Button(action: {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                isExpanded = true
            }
        }) {
            HStack(spacing: 6) {
                // TL;DR icon with status indicator
                ZStack {
                    Circle()
                        .fill(statusGradient)
                        .frame(width: 16, height: 16)
                    
                    if isGenerating {
                        // Subtle loading animation
                        Circle()
                            .trim(from: 0, to: 0.6)
                            .stroke(
                                AngularGradient(
                                    colors: [.blue.opacity(0.3), .blue],
                                    center: .center
                                ),
                                style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                            )
                            .frame(width: 14, height: 14)
                            .rotationEffect(.degrees(shimmerOffset))
                            .animation(
                                .linear(duration: 1.2).repeatForever(autoreverses: false),
                                value: shimmerOffset
                            )
                    } else {
                        Image(systemName: statusIcon)
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                
                // TL;DR label
                Text("TL;DR")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.primary.opacity(0.8))
                
                // Status indicator
                if !tldrSummary.isEmpty {
                    Circle()
                        .fill(.green)
                        .frame(width: 4, height: 4)
                        .opacity(pulseOpacity)
                        .animation(
                            .easeInOut(duration: 2.0).repeatForever(autoreverses: true),
                            value: pulseOpacity
                        )
                }
                
                Spacer()
                
                // Expand hint
                Image(systemName: "chevron.up")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isGenerating && tldrSummary.isEmpty)
    }
    
    // MARK: - Expanded View
    
    @ViewBuilder
    private func expandedView() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with collapse button
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.blue)
                    
                    Text("TL;DR")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                Button(action: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        isExpanded = false
                    }
                }) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            // Content area
            if isGenerating && tldrSummary.isEmpty {
                generatingView()
            } else if showError {
                errorView()
            } else if tldrSummary.isEmpty {
                emptyStateView()
            } else {
                summaryView()
            }
        }
        .padding(12)
    }
    
    // MARK: - Content Views
    
    @ViewBuilder
    private func generatingView() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Subtle shimmer placeholder
            VStack(alignment: .leading, spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    .secondary.opacity(0.1),
                                    .secondary.opacity(0.3),
                                    .secondary.opacity(0.1)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 12)
                        .frame(width: index == 2 ? 80 : nil)
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                        .offset(x: shimmerOffset)
                        .clipped()
                }
            }
            
            Text("Analyzing page content...")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary.opacity(0.7))
        }
    }
    
    @ViewBuilder
    private func errorView() -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundColor(.orange)
            
            Text("Unable to generate summary")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            
            Spacer()
            
            Button("Retry") {
                autoGenerateTLDR()
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(.blue)
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    @ViewBuilder
    private func emptyStateView() -> some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.text")
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.6))
            
            Text("No content to summarize")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary.opacity(0.8))
        }
    }
    
    @ViewBuilder
    private func summaryView() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tldrSummary)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(.primary.opacity(0.9))
                .lineLimit(6)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            
            // Word count indicator
            if !tldrSummary.isEmpty {
                Text("\(tldrSummary.split(separator: " ").count) words")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
    
    // MARK: - Background Styling
    
    @ViewBuilder
    private func cardBackground() -> some View {
        ZStack {
            // Base glass material
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(isExpanded ? 0.8 : 0.6)
            
            // Subtle gradient overlay
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.blue.opacity(0.02),
                            Color.blue.opacity(0.01),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }
    
    // MARK: - Computed Properties
    
    private var statusIcon: String {
        if showError {
            return "exclamationmark"
        } else if tldrSummary.isEmpty {
            return "doc.text"
        } else {
            return "checkmark"
        }
    }
    
    private var statusGradient: LinearGradient {
        if showError {
            return LinearGradient(
                colors: [.orange.opacity(0.8), .orange.opacity(0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else if tldrSummary.isEmpty {
            return LinearGradient(
                colors: [.secondary.opacity(0.6), .secondary.opacity(0.4)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            return LinearGradient(
                colors: [.green.opacity(0.8), .green.opacity(0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    // MARK: - Auto-Generation Logic
    
    private func autoGenerateTLDR() {
        guard let activeTab = tabManager.activeTab,
              let currentURL = activeTab.url?.absoluteString,
              currentURL != lastProcessedURL,
              !currentURL.isEmpty,
              aiAssistant.isInitialized else {
            return
        }
        
        // Reset state for new page
        showError = false
        errorMessage = ""
        tldrSummary = ""
        lastProcessedURL = currentURL
        isGenerating = true
        
        NSLog("🔄 TL;DR: Auto-generating for \(currentURL)")
        
        Task {
            do {
                // Small delay to ensure context is extracted after page load
                try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds for page content to be fully extracted
                
                // Generate TL;DR using the dedicated method that doesn't affect chat history
                let summary = try await aiAssistant.generatePageTLDR()
                
                await MainActor.run {
                    isGenerating = false
                    tldrSummary = summary
                    showError = false
                    
                    NSLog("✅ TL;DR: Generated bullet point summary (\(tldrSummary.count) chars)")
                }
                
            } catch {
                await MainActor.run {
                    isGenerating = false
                    showError = true
                    errorMessage = error.localizedDescription
                    
                    NSLog("❌ TL;DR: Generation failed - \(error.localizedDescription)")
                }
            }
        }
    }
    
    // MARK: - Animation Helpers
    
    private func startPulseAnimation() {
        withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
            pulseOpacity = 0.8
        }
        
        withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
            shimmerOffset = 200
        }
    }
}

// MARK: - Preview

#Preview {
    VStack {
        TLDRCard(
            tabManager: TabManager(),
            aiAssistant: AIAssistant()
        )
        .frame(width: 300)
        
        Spacer()
    }
    .padding()
    .background(.regularMaterial)
}