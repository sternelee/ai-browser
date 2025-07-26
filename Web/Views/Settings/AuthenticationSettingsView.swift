import SwiftUI

/// AuthenticationSettingsView: Comprehensive authentication and token management interface
///
/// This view provides a user-friendly interface for managing JWT/OAuth authentication,
/// token storage, and authentication settings. It integrates seamlessly with the existing
/// browser settings interface and follows the same glass morphism design patterns.
///
/// Features:
/// - OAuth provider configuration and management
/// - Token status monitoring and management
/// - Authentication flow initiation
/// - Security settings and biometric authentication controls
/// - Session management and monitoring
/// - Integration with existing browser security infrastructure
struct AuthenticationSettingsView: View {
    @StateObject private var authStateManager = AuthStateManager.shared
    @StateObject private var tokenManager = TokenManager.shared
    @StateObject private var oauthManager = OAuthManager.shared
    
    @State private var selectedTab: AuthTab = .overview
    @State private var showingAddProvider = false
    @State private var showingTokenDetails = false
    @State private var selectedToken: TokenManager.StoredToken?
    @State private var isAuthenticating = false
    @State private var authenticationError: String?
    
    enum AuthTab: String, CaseIterable {
        case overview = "Overview"
        case providers = "Providers"
        case tokens = "Tokens"
        case sessions = "Sessions"
        case security = "Security"
        
        var icon: String {
            switch self {
            case .overview: return "person.circle"
            case .providers: return "server.rack"
            case .tokens: return "key"
            case .sessions: return "clock.arrow.circlepath"
            case .security: return "shield.lefthalf.filled"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            authenticationHeader
            
            HStack(spacing: 0) {
                authSidebar
                
                Divider()
                    .background(Color.white.opacity(0.1))
                
                authContentArea
            }
        }
        .background(
            ZStack {
                // Glass morphism background
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                
                // Subtle gradient overlay
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.blue.opacity(0.02),
                        Color.purple.opacity(0.02)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .sheet(isPresented: $showingAddProvider) {
            AddOAuthProviderView()
        }
        .sheet(isPresented: $showingTokenDetails) {
            if let token = selectedToken {
                TokenDetailsView(token: token)
            }
        }
        .alert("Authentication Error", isPresented: .constant(authenticationError != nil)) {
            Button("OK") {
                authenticationError = nil
            }
        } message: {
            Text(authenticationError ?? "")
        }
    }
    
    // MARK: - Header
    
    private var authenticationHeader: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "person.badge.key")
                    .font(.title2)
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Authentication")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(authStateManager.authenticationState.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                authStatusIndicator
            }
            
            if let user = authStateManager.currentUser {
                currentUserCard(user)
            }
        }
        .padding()
        .background(
            Color.white.opacity(0.05)
                .background(.regularMaterial)
        )
    }
    
    private var authStatusIndicator: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(authStateManager.isAuthenticated ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
            
            Text(authStateManager.isAuthenticated ? "Authenticated" : "Not Authenticated")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private func currentUserCard(_ user: AuthStateManager.AuthenticatedUser) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(user.name ?? user.email ?? user.id)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text(user.provider.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if user.isTokenExpiring {
                    Label("Expiring Soon", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                
                Button("Sign Out") {
                    Task {
                        await authStateManager.signOut()
                    }
                }
                .buttonStyle(.borderless)
                .foregroundColor(.red)
            }
            
            // Token expiration info
            if let expiresAt = user.tokenExpiresAt {
                HStack {
                    Text("Token expires:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(expiresAt, style: .relative)
                        .font(.caption)
                        .foregroundColor(user.isTokenExpiring ? .orange : .secondary)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.1))
        )
    }
    
    // MARK: - Sidebar
    
    private var authSidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(AuthTab.allCases, id: \.self) { tab in
                Button(action: {
                    selectedTab = tab
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: tab.icon)
                            .frame(width: 16, height: 16)
                            .foregroundColor(selectedTab == tab ? .blue : .secondary)
                        
                        Text(tab.rawValue)
                            .font(.subheadline)
                            .foregroundColor(selectedTab == tab ? .primary : .secondary)
                        
                        Spacer()
                        
                        // Badge for some tabs
                        if tab == .tokens && !tokenManager.activeTokens.isEmpty {
                            Text("\(tokenManager.activeTokens.count)")
                                .font(.caption2)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Circle().fill(Color.blue))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(selectedTab == tab ? Color.blue.opacity(0.15) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
            
            Spacer()
        }
        .padding()
        .frame(width: 180)
    }
    
    // MARK: - Content Area
    
    private var authContentArea: some View {
        Group {
            switch selectedTab {
            case .overview:
                authOverviewView
            case .providers:
                oauthProvidersView
            case .tokens:
                tokensView
            case .sessions:
                sessionsView
            case .security:
                securitySettingsView
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    
    // MARK: - Overview Tab
    
    private var authOverviewView: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Authentication Overview")
                .font(.title2)
                .fontWeight(.semibold)
            
            // Quick stats
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 16) {
                statCard(
                    title: "Active Tokens",
                    value: "\(tokenManager.activeTokens.count)",
                    icon: "key",
                    color: .blue
                )
                
                statCard(
                    title: "Active Sessions",
                    value: "\(authStateManager.activeSessions.count)",
                    icon: "clock",
                    color: .green
                )
                
                statCard(
                    title: "Providers",
                    value: "\(oauthManager.activeProviders.count)",
                    icon: "server.rack",
                    color: .purple
                )
            }
            
            if !authStateManager.isAuthenticated {
                authenticationPrompt
            } else {
                activeSessionOverview
            }
            
            Spacer()
        }
    }
    
    private func statCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.05))
        )
    }
    
    private var authenticationPrompt: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Get Started")
                .font(.headline)
            
            Text("Connect your accounts to enable browser sync, secure token storage, and enhanced authentication features.")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Button("Add OAuth Provider") {
                showingAddProvider = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.blue.opacity(0.1))
        )
    }
    
    private var activeSessionOverview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Current Session")
                .font(.headline)
            
            if let session = authStateManager.activeSessions.first {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Session Duration")
                        Spacer()
                        Text(formatDuration(session.sessionDuration))
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Device")
                        Spacer()
                        Text("Current Device")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Last Activity")
                        Spacer()
                        Text(session.lastAccessedAt, style: .relative)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.05))
                )
            }
        }
    }
    
    // MARK: - Providers Tab
    
    private var oauthProvidersView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("OAuth Providers")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("Add Provider") {
                    showingAddProvider = true
                }
                .buttonStyle(.borderedProminent)
            }
            
            if oauthManager.activeProviders.isEmpty {
                emptyProvidersView
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(oauthManager.activeProviders) { provider in
                            providerCard(provider)
                        }
                    }
                }
            }
            
            Spacer()
        }
    }
    
    private var emptyProvidersView: some View {
        VStack(spacing: 16) {
            Image(systemName: "server.rack")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("No Providers Configured")
                .font(.headline)
            
            Text("Add OAuth providers to enable authentication with external services.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxHeight: .infinity)
    }
    
    private func providerCard(_ provider: OAuthManager.OAuthProvider) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(provider.name)
                        .font(.headline)
                    
                    Text(provider.authorizationEndpoint.host ?? "Unknown Host")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button("Authenticate") {
                    Task {
                        isAuthenticating = true
                        let result = await authStateManager.authenticate(provider: provider)
                        isAuthenticating = false
                        
                        switch result {
                        case .success:
                            break // Success handled by state updates
                        case .failure(let error):
                            authenticationError = error.localizedDescription
                        }
                    }
                }
                .disabled(isAuthenticating)
                .buttonStyle(.borderedProminent)
            }
            
            HStack {
                Label("PKCE: \(provider.supportsPKCE ? "Supported" : "Not Supported")", 
                      systemImage: provider.supportsPKCE ? "checkmark.shield" : "xmark.shield")
                    .font(.caption)
                    .foregroundColor(provider.supportsPKCE ? .green : .orange)
                
                Spacer()
                
                Text("Scope: \(provider.scope)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.05))
        )
    }
    
    // MARK: - Tokens Tab
    
    private var tokensView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Stored Tokens")
                .font(.title2)
                .fontWeight(.semibold)
            
            if tokenManager.activeTokens.isEmpty {
                emptyTokensView
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(tokenManager.activeTokens) { token in
                            tokenCard(token)
                        }
                    }
                }
            }
            
            Spacer()
        }
    }
    
    private var emptyTokensView: some View {
        VStack(spacing: 16) {
            Image(systemName: "key")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("No Tokens Stored")
                .font(.headline)
            
            Text("Authenticate with a provider to securely store tokens.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxHeight: .infinity)
    }
    
    private func tokenCard(_ token: TokenManager.StoredToken) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(token.provider.displayName)
                            .font(.headline)
                        
                        if token.isExpired {
                            Label("Expired", systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundColor(.red)
                        } else if token.needsRefresh {
                            Label("Expires Soon", systemImage: "clock")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                    
                    Text(token.identifier)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button("Details") {
                    selectedToken = token
                    showingTokenDetails = true
                }
                .buttonStyle(.borderless)
            }
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Type")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(token.tokenType.displayName)
                        .font(.caption)
                }
                
                Spacer()
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Created")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(token.dateCreated, style: .date)
                        .font(.caption)
                }
                
                Spacer()
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Last Used")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(token.lastUsed, style: .relative)
                        .font(.caption)
                }
            }
            
            if let expiresAt = token.expiresAt {
                HStack {
                    Text("Expires:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(expiresAt, style: .relative)
                        .font(.caption)
                        .foregroundColor(token.needsRefresh ? .orange : .secondary)
                    
                    Spacer()
                    
                    if token.canRefresh {
                        Button("Refresh") {
                            Task {
                                _ = await tokenManager.refreshToken(
                                    provider: token.provider,
                                    identifier: token.identifier
                                )
                            }
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.05))
        )
    }
    
    // MARK: - Sessions Tab
    
    private var sessionsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Active Sessions")
                .font(.title2)
                .fontWeight(.semibold)
            
            if authStateManager.activeSessions.isEmpty {
                emptySessionsView
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(authStateManager.activeSessions) { session in
                            sessionCard(session)
                        }
                    }
                }
            }
            
            Spacer()
        }
    }
    
    private var emptySessionsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("No Active Sessions")
                .font(.headline)
            
            Text("Sessions will appear here after authentication.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxHeight: .infinity)
    }
    
    private func sessionCard(_ session: AuthStateManager.AuthSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Session \(session.id.uuidString.prefix(8))")
                        .font(.headline)
                    
                    Text(session.provider.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if session.isActive {
                    Label("Active", systemImage: "circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                } else {
                    Label("Inactive", systemImage: "circle")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                GridRow {
                    Text("Duration:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(formatDuration(session.sessionDuration))
                        .font(.caption)
                }
                
                GridRow {
                    Text("Last Activity:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(session.lastAccessedAt, style: .relative)
                        .font(.caption)
                }
                
                if let expiresAt = session.expiresAt {
                    GridRow {
                        Text("Expires:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(expiresAt, style: .relative)
                            .font(.caption)
                            .foregroundColor(session.isExpired ? .red : .secondary)
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.05))
        )
    }
    
    // MARK: - Security Tab
    
    private var securitySettingsView: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Security Settings")
                .font(.title2)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 16) {
                Text("Authentication Security")
                    .font(.headline)
                
                Toggle("Require Biometric Authentication", isOn: $tokenManager.requireBiometricAuth)
                    .onChange(of: tokenManager.requireBiometricAuth) {
                        // Save settings handled by TokenManager
                    }
                
                Toggle("Enable Token Authentication", isOn: $tokenManager.isTokenAuthEnabled)
                    .onChange(of: tokenManager.isTokenAuthEnabled) {
                        // Save settings handled by TokenManager
                    }
                
                Divider()
                
                Text("Token Management")
                    .font(.headline)
                
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Automatic Token Refresh")
                            .font(.subheadline)
                        Text("Automatically refresh tokens before expiration")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button("Configure") {
                        // TODO: Open token refresh configuration
                    }
                    .buttonStyle(.borderless)
                }
                
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Token Cleanup")
                            .font(.subheadline)
                        Text("Remove expired tokens automatically")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button("Cleanup Now") {
                        Task {
                            await tokenManager.cleanupExpiredTokens()
                        }
                    }
                    .buttonStyle(.borderless)
                }
                
                Divider()
                
                Text("Session Security")
                    .font(.headline)
                
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Clear All Sessions")
                            .font(.subheadline)
                        Text("Sign out from all devices and clear session data")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button("Clear Sessions") {
                        Task {
                            await authStateManager.signOut()
                        }
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.red)
                }
            }
            
            Spacer()
        }
    }
    
    // MARK: - Helper Methods
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) % 3600 / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

// MARK: - Supporting Views

struct AddOAuthProviderView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var providerName = ""
    @State private var clientId = ""
    @State private var authEndpoint = ""
    @State private var tokenEndpoint = ""
    @State private var scope = "openid profile email"
    
    var body: some View {
        NavigationView {
            Form {
                Section("Provider Information") {
                    TextField("Provider Name", text: $providerName)
                    TextField("Client ID", text: $clientId)
                }
                
                Section("Endpoints") {
                    TextField("Authorization Endpoint", text: $authEndpoint)
                    TextField("Token Endpoint", text: $tokenEndpoint)
                }
                
                Section("Configuration") {
                    TextField("Scope", text: $scope)
                }
            }
            .navigationTitle("Add OAuth Provider")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        // TODO: Create and add provider
                        dismiss()
                    }
                    .disabled(providerName.isEmpty || clientId.isEmpty)
                }
            }
        }
    }
}

struct TokenDetailsView: View {
    let token: TokenManager.StoredToken
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Token Information")
                        .font(.headline)
                    
                    Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                        GridRow {
                            Text("Provider:")
                                .foregroundColor(.secondary)
                            Text(token.provider.displayName)
                        }
                        
                        GridRow {
                            Text("Type:")
                                .foregroundColor(.secondary)
                            Text(token.tokenType.displayName)
                        }
                        
                        GridRow {
                            Text("Identifier:")
                                .foregroundColor(.secondary)
                            Text(token.identifier)
                        }
                        
                        GridRow {
                            Text("Created:")
                                .foregroundColor(.secondary)
                            Text(token.dateCreated, style: .date)
                        }
                        
                        GridRow {
                            Text("Last Used:")
                                .foregroundColor(.secondary)
                            Text(token.lastUsed, style: .relative)
                        }
                        
                        if let expiresAt = token.expiresAt {
                            GridRow {
                                Text("Expires:")
                                    .foregroundColor(.secondary)
                                Text(expiresAt, style: .relative)
                                    .foregroundColor(token.needsRefresh ? .orange : .primary)
                            }
                        }
                        
                        if let scope = token.scope {
                            GridRow {
                                Text("Scope:")
                                    .foregroundColor(.secondary)
                                Text(scope)
                            }
                        }
                    }
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Token Details")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Visual Effect View

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
        visualEffectView.state = .active
        return visualEffectView
    }
    
    func updateNSView(_ visualEffectView: NSVisualEffectView, context: Context) {
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
    }
}

#Preview {
    AuthenticationSettingsView()
        .frame(width: 800, height: 600)
}