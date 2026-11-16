import SwiftAppKit
import SwiftUI

/// What the panel's controls ask for. AppDelegate carries them out.
enum PanelAction {
    case openUI(Client)
    case copyInstallCommand
    /// `cairn service <command>`: start, stop or restart.
    case service(String)
    case pushGit
    case openLog
    case allowInLoginItems
    case update
}

/// What the menu bar icon opens: both stores' status, and the local server's controls.
/// SwiftAppKit adds the footer.
struct PanelView: View {
    @ObservedObject var monitor: Monitor
    let updating: Bool
    let run: @MainActor (PanelAction) -> Void

    var body: some View {
        PanelSection("Stores") {
            store("Local", monitor.local, client: monitor.localClient)
            store(monitor.teamTitle, monitor.team, client: monitor.teamClient)
        }
        if CLI.path == nil {
            PanelSection("Setup") {
                Text("The cairn command isn't installed. Run its install command in Terminal.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                tile("Copy Install Command", "doc.on.doc", .copyInstallCommand)
            }
        } else if monitor.local.configured {
            PanelSection("Local Server") {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                    ForEach(serverActions, id: \.title) { tile($0.title, $0.symbol, $0.action) }
                    tile(updating ? "Updating…" : "Update", "arrow.down.circle", .update).disabled(updating)
                }
                Text("Update gets the latest server and cairn command from GitHub.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// What can be done to the local server right now.
    private var serverActions: [(title: String, symbol: String, action: PanelAction)] {
        var actions: [(String, String, PanelAction)] = []
        if monitor.serviceInstalled {
            if monitor.local.reachable {
                actions += [("Restart", "arrow.clockwise", .service("restart")), ("Stop", "stop.fill", .service("stop"))]
            } else if !monitor.blocked {
                actions.append(("Start", "play.fill", .service("start")))
            }
        }
        if monitor.blocked { actions.append(("Allow at Login…", "lock.open", .allowInLoginItems)) }
        if monitor.gitEnabled, monitor.local.reachable { actions.append(("Push Git Mirror", "arrow.up.circle", .pushGit)) }
        if FileManager.default.fileExists(atPath: Config.serverLog.path) { actions.append(("Server Log", "doc.text", .openLog)) }
        return actions
    }

    private func store(_ name: String, _ status: StoreStatus, client: Client?) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(status.reachable ? Color.green : status.configured ? Color.orange : Color.secondary.opacity(0.5))
                .frame(width: 8, height: 8)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).fontWeight(.medium)
                Text(status.line).font(.caption).foregroundStyle(.secondary)
                if let detail = status.detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            if let client, status.reachable {
                Button { run(.openUI(client)) } label: {
                    Label("Open", systemImage: "safari").font(.caption.weight(.medium)).padding(.horizontal, 8).padding(.vertical, 4)
                }
                .buttonStyle(.panelTile)
                .help("Open this store's web UI")
            }
        }
        .padding(10)
        .panelTile()
    }

    private func tile(_ title: String, _ symbol: String, _ action: PanelAction) -> some View {
        Button { run(action) } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol).frame(width: 16)
                Text(title).lineLimit(1).minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }
            .font(.callout.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .buttonStyle(.panelTile)
    }
}
