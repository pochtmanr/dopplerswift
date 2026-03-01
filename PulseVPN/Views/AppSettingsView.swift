import SwiftUI

struct AppSettingsView: View {
    let vpnManager: VPNManager
    @Bindable var languageManager: LanguageManager

    @AppStorage("connectOnLaunch") private var connectOnLaunch = false
    @AppStorage("killSwitch") private var killSwitch = false

    var body: some View {
        List {
            Section("General") {
                NavigationLink {
                    LanguagePickerView(selectedLanguage: $languageManager.selectedLanguage)
                } label: {
                    HStack {
                        Text("Language")
                        Spacer()
                        Text(languageManager.selectedLanguage.displayName)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Connection") {
                Toggle("Connect on Launch", isOn: $connectOnLaunch)
                Toggle("Always-on VPN", isOn: $killSwitch)
            }

        }
        .navigationTitle("App Settings")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onChange(of: killSwitch) {
            Task {
                await vpnManager.setKillSwitch(enabled: killSwitch)
            }
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

#Preview {
    NavigationStack {
        AppSettingsView(vpnManager: VPNManager(), languageManager: LanguageManager.shared)
    }
}
