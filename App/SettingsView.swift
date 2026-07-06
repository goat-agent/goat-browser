import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            PrivacySettings()
                .tabItem { Label("Privacy", systemImage: "hand.raised") }
        }
        .frame(width: 500, height: 320)
    }
}

private struct GeneralSettings: View {
    @State private var settings = AppSettings.shared

    var body: some View {
        Form {
            Picker("Search engine", selection: Binding(
                get: { settings.searchEngine },
                set: { settings.searchEngine = $0 })) {
                ForEach(SearchEngine.allCases) { engine in
                    Text(engine.title).tag(engine)
                }
            }

            Picker("Appearance", selection: Binding(
                get: { settings.theme },
                set: { settings.theme = $0 })) {
                ForEach(AppTheme.allCases) { theme in
                    Text(theme.title).tag(theme)
                }
            }
            .pickerStyle(.segmented)

            Toggle("Restore tabs on launch", isOn: Binding(
                get: { settings.restoreSession },
                set: { settings.restoreSession = $0 }))

            Toggle("Always show full URL", isOn: Binding(
                get: { settings.alwaysShowFullURL },
                set: { settings.alwaysShowFullURL = $0 }))
        }
        .formStyle(.grouped)
        .padding()
    }
}

private struct PrivacySettings: View {
    @State private var cleared = false

    var body: some View {
        Form {
            Section("Browsing Data") {
                Button("Clear History") {
                    HistoryStore.clearAll()
                    cleared = true
                }
                if cleared {
                    Text("History cleared.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
