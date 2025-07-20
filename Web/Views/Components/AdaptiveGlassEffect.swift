import SwiftUI
import AppKit

// Adaptive Glass Effects - Dynamic tinting based on content
struct AdaptiveGlassBackground: View {
    @ObservedObject var tab: Tab
    @State private var dominantColor: Color = .clear
    @State private var colorExtractionTask: Task<Void, Never>?
    
    var body: some View {
        ZStack {
            // Base glass material
            Rectangle()
                .fill(.ultraThinMaterial)
            
            // Adaptive tint overlay
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            dominantColor.opacity(0.03),
                            dominantColor.opacity(0.01)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .animation(.easeInOut(duration: 0.5), value: dominantColor)
        }
        .onReceive(tab.$favicon) { favicon in
            extractDominantColor(from: favicon)
        }
        .onReceive(tab.$url) { _ in
            // Reset color when URL changes
            dominantColor = .clear
        }
    }
    
    private func extractDominantColor(from image: NSImage?) {
        colorExtractionTask?.cancel()
        
        colorExtractionTask = Task {
            guard let image = image,
                  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                await MainActor.run {
                    dominantColor = .clear
                }
                return
            }
            
            let color = await extractDominantColorFromCGImage(cgImage)
            
            await MainActor.run {
                if !Task.isCancelled {
                    dominantColor = color
                }
            }
        }
    }
    
    private func extractDominantColorFromCGImage(_ cgImage: CGImage) async -> Color {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let width = cgImage.width
                let height = cgImage.height
                let bytesPerPixel = 4
                let bytesPerRow = bytesPerPixel * width
                let bitsPerComponent = 8
                
                var pixelData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
                
                let context = CGContext(
                    data: &pixelData,
                    width: width,
                    height: height,
                    bitsPerComponent: bitsPerComponent,
                    bytesPerRow: bytesPerRow,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
                
                context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
                
                var redSum: Int = 0
                var greenSum: Int = 0
                var blueSum: Int = 0
                var pixelCount: Int = 0
                
                for y in 0..<height {
                    for x in 0..<width {
                        let pixelIndex = (y * width + x) * bytesPerPixel
                        let red = Int(pixelData[pixelIndex])
                        let green = Int(pixelData[pixelIndex + 1])
                        let blue = Int(pixelData[pixelIndex + 2])
                        let alpha = Int(pixelData[pixelIndex + 3])
                        
                        if alpha > 128 { // Only consider non-transparent pixels
                            redSum += red
                            greenSum += green
                            blueSum += blue
                            pixelCount += 1
                        }
                    }
                }
                
                if pixelCount > 0 {
                    let avgRed = Double(redSum) / Double(pixelCount) / 255.0
                    let avgGreen = Double(greenSum) / Double(pixelCount) / 255.0
                    let avgBlue = Double(blueSum) / Double(pixelCount) / 255.0
                    
                    continuation.resume(returning: Color(red: avgRed, green: avgGreen, blue: avgBlue))
                } else {
                    continuation.resume(returning: .clear)
                }
            }
        }
    }
}

// Favicon color extraction for sidebar tab items
extension SidebarTabItem {
    func extractedFaviconColor(for tab: Tab) -> Color? {
        // This is a simplified version - full implementation would cache colors
        // and use the same extraction logic as AdaptiveGlassBackground
        guard let favicon = tab.favicon,
              let _ = favicon.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        
        // For now, return a simple color based on the favicon
        // In a real implementation, this would use the same extraction logic
        return .blue.opacity(0.7)
    }
}