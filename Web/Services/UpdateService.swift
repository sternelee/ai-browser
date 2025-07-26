import Foundation
import SwiftUI
import OSLog

class UpdateService: ObservableObject {
    static let shared = UpdateService()
    
    @Published var isCheckingForUpdates = false
    @Published var availableUpdate: GitHubRelease?
    @Published var lastCheckDate: Date?
    @Published var checkError: String?
    
    private let githubAPI = "https://api.github.com/repos/nuance-dev/Web/releases/latest"
    private let logger = Logger(subsystem: "com.nuance.web", category: "UpdateService")
    
    private init() {}
    
    // MARK: - Public Methods
    
    func checkForUpdates(manual: Bool = false) {
        guard !isCheckingForUpdates else { return }
        
        // Skip automatic checks if checked recently (within 24 hours)
        if !manual, let lastCheck = lastCheckDate,
           Date().timeIntervalSince(lastCheck) < 24 * 60 * 60 {
            return
        }
        
        Task {
            await performUpdateCheck()
        }
    }
    
    func getCurrentVersion() -> String {
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.1"
    }
    
    // MARK: - Private Methods
    
    @MainActor
    private func performUpdateCheck() async {
        isCheckingForUpdates = true
        checkError = nil
        
        do {
            let release = try await fetchLatestRelease()
            let currentVersion = getCurrentVersion()
            
            if isNewerVersion(release.tagName, than: currentVersion) {
                availableUpdate = release
                logger.info("Update available: \(release.tagName) (current: \(currentVersion))")
            } else {
                availableUpdate = nil
                logger.info("App is up to date: \(currentVersion)")
            }
            
            lastCheckDate = Date()
            
        } catch {
            checkError = error.localizedDescription
            logger.error("Update check failed: \(error.localizedDescription)")
        }
        
        isCheckingForUpdates = false
    }
    
    private func fetchLatestRelease() async throws -> GitHubRelease {
        guard let url = URL(string: githubAPI) else {
            throw UpdateError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.timeoutInterval = 30
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UpdateError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw UpdateError.httpError(httpResponse.statusCode)
        }
        
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        return release
    }
    
    private func isNewerVersion(_ remoteVersion: String, than currentVersion: String) -> Bool {
        let remote = parseVersion(remoteVersion)
        let current = parseVersion(currentVersion)
        
        // Compare major.minor.patch
        if remote.major != current.major {
            return remote.major > current.major
        }
        if remote.minor != current.minor {
            return remote.minor > current.minor
        }
        return remote.patch > current.patch
    }
    
    private func parseVersion(_ version: String) -> (major: Int, minor: Int, patch: Int) {
        // Remove 'v' prefix if present
        let cleanVersion = version.hasPrefix("v") ? String(version.dropFirst()) : version
        let components = cleanVersion.split(separator: ".").compactMap { Int($0) }
        
        return (
            major: components.count > 0 ? components[0] : 0,
            minor: components.count > 1 ? components[1] : 0,
            patch: components.count > 2 ? components[2] : 0
        )
    }
}

// MARK: - Models

struct GitHubRelease: Codable {
    let tagName: String
    let name: String
    let body: String
    let htmlURL: String
    let publishedAt: String
    let draft: Bool
    let prerelease: Bool
    
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlURL = "html_url"
        case publishedAt = "published_at"
        case draft
        case prerelease
    }
    
    var displayVersion: String {
        return tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
    }
    
    var formattedDate: String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: publishedAt) else {
            return publishedAt
        }
        
        let displayFormatter = DateFormatter()
        displayFormatter.dateStyle = .medium
        displayFormatter.timeStyle = .none
        return displayFormatter.string(from: date)
    }
}

// MARK: - Errors

enum UpdateError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case networkError
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid GitHub API URL"
        case .invalidResponse:
            return "Invalid response from GitHub API"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .networkError:
            return "Network connection error"
        }
    }
}