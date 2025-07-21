// SettingsView.swift - Browser settings with security configuration
import SwiftUI

struct SettingsView: View {
    @StateObject private var adBlockService = AdBlockService.shared
    @StateObject private var passwordManager = PasswordManager.shared
    @StateObject private var incognitoSession = IncognitoSession.shared
    
    var body: some View {
        NavigationView {
            List {
                // General Settings
                Section("General") {
                    HStack {
                        Image(systemName: "globe")
                            .foregroundColor(.blue)
                            .frame(width: 20)
                        Text("Default Search Engine")
                        Spacer()
                        Text("Google")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Image(systemName: "house")
                            .foregroundColor(.green)
                            .frame(width: 20)
                        Text("Homepage")
                        Spacer()
                        Text("New Tab")
                            .foregroundColor(.secondary)
                    }
                }
                
                // Security & Privacy
                Section("Security & Privacy") {
                    // Ad Blocker Settings
                    HStack {
                        Image(systemName: "shield.fill")
                            .foregroundColor(.orange)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Ad Blocker")
                                .font(.body)
                            Text("Blocked today: \(adBlockService.blockedRequestsToday)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: $adBlockService.isEnabled)
                    }
                    
                    // Password Manager Settings
                    HStack {
                        Image(systemName: "key.fill")
                            .foregroundColor(.blue)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Password Manager")
                                .font(.body)
                            Text("Saved: \(passwordManager.savedPasswords.count) passwords")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: $passwordManager.isAutofillEnabled)
                    }
                    
                    HStack {
                        Image(systemName: "touchid")
                            .foregroundColor(.red)
                            .frame(width: 20)
                        Text("Require Touch ID/Face ID")
                        Spacer()
                        Toggle("", isOn: $passwordManager.requireBiometricAuth)
                    }
                    
                    // Privacy Settings
                    HStack {
                        Image(systemName: "hand.raised.fill")
                            .foregroundColor(.purple)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Tracking Prevention")
                                .font(.body)
                            Text("Enhanced privacy protection")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                    
                    if incognitoSession.isActive {
                        HStack {
                            Image(systemName: "eye.slash.fill")
                                .foregroundColor(.gray)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Private Browsing")
                                    .font(.body)
                                Text("Active: \(incognitoSession.incognitoTabs.count) tabs")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button("End Session") {
                                incognitoSession.endIncognitoSession()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.mini)
                        }
                    }
                }
                
                // Advanced Settings
                Section("Advanced") {
                    NavigationLink(destination: AdBlockSettingsView()) {
                        HStack {
                            Image(systemName: "shield.lefthalf.fill")
                                .foregroundColor(.orange)
                                .frame(width: 20)
                            Text("Content Blocking")
                        }
                    }
                    
                    NavigationLink(destination: PasswordSettingsView()) {
                        HStack {
                            Image(systemName: "lock.fill")
                                .foregroundColor(.blue)
                                .frame(width: 20)
                            Text("Password Settings")
                        }
                    }
                    
                    NavigationLink(destination: PrivacySettingsView()) {
                        HStack {
                            Image(systemName: "hand.raised.fill")
                                .foregroundColor(.purple)
                                .frame(width: 20)
                            Text("Privacy & Security")
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .frame(minWidth: 250)
            
            // Detail view placeholder
            VStack {
                Image(systemName: "gearshape.2")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
                Text("Select a setting to configure")
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Ad Block Settings Detail View
struct AdBlockSettingsView: View {
    @StateObject private var adBlockService = AdBlockService.shared
    
    var body: some View {
        List {
            Section("Statistics") {
                HStack {
                    Text("Requests blocked today")
                    Spacer()
                    Text("\(adBlockService.blockedRequestsToday)")
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Total requests blocked")
                    Spacer()
                    Text("\(adBlockService.blockedRequestsCount)")
                        .foregroundColor(.secondary)
                }
            }
            
            Section("Filter Lists") {
                ForEach(Array(adBlockService.filterListsStatus.keys.sorted()), id: \.self) { listName in
                    if let status = adBlockService.filterListsStatus[listName] {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(listName)
                                    .font(.body)
                                Text("Rules: \(status.ruleCount)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if status.isActive {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            } else {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundColor(.red)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Content Blocking")
    }
}

// MARK: - Password Settings Detail View
struct PasswordSettingsView: View {
    @StateObject private var passwordManager = PasswordManager.shared
    
    var body: some View {
        List {
            Section("Autofill") {
                Toggle("Enable password autofill", isOn: $passwordManager.isAutofillEnabled)
                Toggle("Require biometric authentication", isOn: $passwordManager.requireBiometricAuth)
            }
            
            Section("Password Generator") {
                HStack {
                    Text("Length")
                    Spacer()
                    Text("\(passwordManager.passwordGeneratorSettings.length)")
                        .foregroundColor(.secondary)
                }
                
                Toggle("Include uppercase letters", isOn: $passwordManager.passwordGeneratorSettings.includeUppercase)
                Toggle("Include lowercase letters", isOn: $passwordManager.passwordGeneratorSettings.includeLowercase)
                Toggle("Include numbers", isOn: $passwordManager.passwordGeneratorSettings.includeNumbers)
                Toggle("Include symbols", isOn: $passwordManager.passwordGeneratorSettings.includeSymbols)
                Toggle("Exclude similar characters", isOn: $passwordManager.passwordGeneratorSettings.excludeSimilar)
                Toggle("Exclude ambiguous characters", isOn: $passwordManager.passwordGeneratorSettings.excludeAmbiguous)
            }
            
            Section("Saved Passwords") {
                Text("\(passwordManager.savedPasswords.count) passwords saved")
                    .foregroundColor(.secondary)
                
                Button("Generate Test Password") {
                    let password = passwordManager.generateSecurePassword()
                    print("Generated password: \(password)")
                }
            }
        }
        .navigationTitle("Password Settings")
    }
}

// MARK: - Privacy Settings Detail View
struct PrivacySettingsView: View {
    @StateObject private var incognitoSession = IncognitoSession.shared
    
    var body: some View {
        List {
            Section("Private Browsing") {
                if incognitoSession.isActive {
                    HStack {
                        Text("Active incognito tabs")
                        Spacer()
                        Text("\(incognitoSession.incognitoTabs.count)")
                            .foregroundColor(.secondary)
                    }
                    
                    Button("End All Incognito Sessions") {
                        incognitoSession.endIncognitoSession()
                    }
                    .foregroundColor(.red)
                } else {
                    Text("No active incognito sessions")
                        .foregroundColor(.secondary)
                }
            }
            
            Section("Data Protection") {
                HStack {
                    Text("Encrypted password storage")
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
                
                HStack {
                    Text("Keychain integration")
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
                
                HStack {
                    Text("Content blocking")
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
            }
            
            Section("Privacy Features") {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Enhanced tracking prevention")
                        Text("Blocks analytics, social trackers, and fingerprinting")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: "shield.fill")
                        .foregroundColor(.green)
                }
                
                HStack {
                    VStack(alignment: .leading) {
                        Text("Secure incognito mode")
                        Text("Complete data isolation with privacy JavaScript")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: "eye.slash.fill")
                        .foregroundColor(.gray)
                }
            }
        }
        .navigationTitle("Privacy & Security")
    }
}

#Preview {
    SettingsView()
        .frame(width: 800, height: 600)
}