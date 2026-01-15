import SwiftUI
import ServiceManagement

struct PreferencesView: View {
    @StateObject private var permissionManager = PermissionManager.shared

    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("showNotification") private var showNotification = true
    @AppStorage("playSoundOnCapture") private var playSoundOnCapture = true

    var body: some View {
        TabView {
            GeneralTab(
                launchAtLogin: $launchAtLogin,
                showNotification: $showNotification,
                playSoundOnCapture: $playSoundOnCapture
            )
            .tabItem {
                Label("General", systemImage: "gear")
            }

            PermissionsTab()
                .environmentObject(permissionManager)
                .tabItem {
                    Label("Permissions", systemImage: "lock.shield")
                }

            AboutTab()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 450, height: 280)
    }
}

// MARK: - General Tab

struct GeneralTab: View {
    @Binding var launchAtLogin: Bool
    @Binding var showNotification: Bool
    @Binding var playSoundOnCapture: Bool

    var body: some View {
        Form {
            Section {
                Toggle("Launch Shotter at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        updateLaunchAtLogin(newValue)
                    }
            }

            Section("After Capture") {
                Toggle("Show notification", isOn: $showNotification)
                Toggle("Play sound", isOn: $playSoundOnCapture)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to update launch at login: \(error)")
        }
    }
}

// MARK: - Permissions Tab

struct PermissionsTab: View {
    @EnvironmentObject var permissionManager: PermissionManager

    var body: some View {
        Form {
            Section("Screen Recording") {
                HStack {
                    Image(systemName: permissionManager.isAuthorized ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(permissionManager.isAuthorized ? .green : .red)
                        .font(.title2)

                    VStack(alignment: .leading) {
                        Text("Screen Recording Permission")
                            .font(.headline)
                        Text(permissionManager.isAuthorized ? "Granted" : "Required for screen capture")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if !permissionManager.isAuthorized {
                        Button("Grant Access") {
                            permissionManager.openSystemSettings()
                        }
                    }
                }
            }

            if !permissionManager.isAuthorized {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("How to grant permission:")
                            .font(.headline)
                        Text("1. Click 'Grant Access' above")
                        Text("2. In System Settings, find Shotter in the list")
                        Text("3. Toggle the switch to enable")
                        Text("4. Restart Shotter if needed")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - About Tab

struct AboutTab: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)

            Text("Shotter")
                .font(.title)
                .fontWeight(.bold)

            Text("Version 1.0.0")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text("A lightweight screenshot utility that captures directly to your clipboard.")
                .multilineTextAlignment(.center)
                .font(.body)
                .foregroundColor(.secondary)
                .padding(.horizontal)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

#Preview {
    PreferencesView()
}
