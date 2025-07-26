import SwiftUI
import OSLog

struct AboutView: View {
    @ObservedObject private var updateService = UpdateService.shared
    @State private var isVisible = false
    @State private var showingUpdateDetails = false
    
    private let logger = Logger(subsystem: "com.nuance.web", category: "AboutView")
    
    var body: some View {
        VStack(spacing: 0) {
            // Close button (top-right)
            HStack {
                Spacer()
                Button(action: {
                    withAnimation(.easeOut(duration: 0.2)) {
                        KeyboardShortcutHandler.shared.showAboutPanel = false
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                        .background(Circle().fill(.ultraThinMaterial))
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.top, 16)
                .padding(.trailing, 20)
            }
            
            // Header with app icon and title
            VStack(spacing: 16) {
                // App Icon
                HStack {
                    Spacer()
                    if let iconImage = NSApp.applicationIconImage {
                        Image(nsImage: iconImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 80, height: 80)
                            .cornerRadius(12)
                            .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.accentColor.gradient)
                            .frame(width: 80, height: 80)
                            .overlay {
                                Text("W")
                                    .font(.system(size: 36, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                            }
                            .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                    }
                    Spacer()
                }
                
                // App name and version
                VStack(spacing: 8) {
                    Text("Web")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    
                    Text("Version \(updateService.getCurrentVersion())")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                }
                
                // Tagline
                Text("Next-generation macOS browser")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 8)
            .padding(.horizontal, 32)
            
            Divider()
                .padding(.vertical, 24)
            
            // Update section
            VStack(spacing: 16) {
                if updateService.isCheckingForUpdates {
                    HStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Checking for updates...")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                } else if let availableUpdate = updateService.availableUpdate {
                    // Update available
                    VStack(spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.up.circle.fill")
                                .foregroundColor(.green)
                                .font(.title2)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Update Available")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.primary)
                                
                                Text("Version \(availableUpdate.displayVersion)")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                        }
                        
                        HStack(spacing: 12) {
                            Button("View Details") {
                                showingUpdateDetails.toggle()
                                logger.info("User viewed update details for version \(availableUpdate.displayVersion)")
                            }
                            .buttonStyle(.bordered)
                            
                            Button("Download Update") {
                                openUpdateURL(availableUpdate.htmlURL)
                                logger.info("User initiated download for version \(availableUpdate.displayVersion)")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                } else if let error = updateService.checkError {
                    // Error state
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.title2)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Update Check Failed")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.primary)
                            
                            Text(error)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                        
                        Spacer()
                    }
                } else {
                    // Up to date
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.title2)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Up to Date")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.primary)
                            
                            if let lastCheck = updateService.lastCheckDate {
                                Text("Last checked: \(lastCheck, formatter: lastCheckedFormatter)")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                    }
                }
                
                // Check for updates button
                Button("Check for Updates") {
                    updateService.checkForUpdates(manual: true)
                    logger.info("Manual update check initiated")
                }
                .buttonStyle(.bordered)
                .disabled(updateService.isCheckingForUpdates)
            }
            .padding(.horizontal, 32)
            
            Spacer(minLength: 24)
            
            // Footer
            VStack(spacing: 8) {
                Text("© 2025 Nuance Development")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 24)
        }
        .frame(width: 400, height: 480)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(isVisible ? 1 : 0.9)
        .onAppear {
            withAnimation(.easeOut(duration: 0.3)) {
                isVisible = true
            }
            
            // Check for updates if we haven't checked recently
            if updateService.lastCheckDate == nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    updateService.checkForUpdates(manual: false)
                }
            }
        }
        .sheet(isPresented: $showingUpdateDetails) {
            if let update = updateService.availableUpdate {
                UpdateDetailsView(release: update)
            }
        }
    }
    
    private func openUpdateURL(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
    
    private var lastCheckedFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }
}

// MARK: - Update Details View

struct UpdateDetailsView: View {
    let release: GitHubRelease
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with title and action buttons
            HStack {
                Button("Download") {
                    NSWorkspace.shared.open(URL(string: release.htmlURL)!)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                
                Spacer()
                
                Text("Update Details")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(.regularMaterial)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text(release.name.isEmpty ? "Web \(release.displayVersion)" : release.name)
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("Released on \(release.formattedDate)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        if release.prerelease {
                            Label("Pre-release", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                    
                    Divider()
                    
                    // Release notes
                    if !release.body.isEmpty {
                        Text("What's New")
                            .font(.headline)
                            .padding(.bottom, 4)
                        
                        Text(release.body)
                            .font(.body)
                            .textSelection(.enabled)
                    } else {
                        Text("No release notes available.")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                .padding()
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .frame(width: 500, height: 400)
    }
}

// MARK: - Preview

#Preview {
    AboutView()
        .frame(width: 400, height: 480)
}