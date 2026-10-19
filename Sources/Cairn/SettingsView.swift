import SwiftAppKit
import SwiftUI

/// Cairn's section of the Settings window. SettingsForm adds the standard General section.
struct SettingsView: View {
    @ObservedObject var monitor: Monitor

    var body: some View {
        SettingsForm(height: 300) {
            Section {
                LabeledContent("Local", value: monitor.local.line)
                LabeledContent(monitor.teamTitle, value: monitor.team.line)
            } header: {
                Text("Stores")
            } footer: {
                Text("The local server runs as a login service and keeps running when Cairn quits. Set up and "
                     + "change stores with the cairn command, for example cairn remote add or cairn git enable.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
