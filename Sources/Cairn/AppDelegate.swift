import AppKit
import ServiceManagement
import SwiftAppKit
import SwiftUI

/// Cairn's parts on top of SwiftAppKit's standard menu bar app (menu, Settings, updates,
/// launch at login). The cairn CLI owns the server; this only shows it and calls the CLI.
@MainActor
final class AppDelegate: MenuBarAppDelegate {
    private let monitor = Monitor()
    private var updating = false

    override func start() {
        monitor.onChange = { [weak self] in self?.updateIcon() }
        monitor.start()
    }

    override func addMenuItems(to menu: NSMenu) {
        addStatus("Local", monitor.local, to: menu)
        addStatus(monitor.teamTitle, monitor.team, to: menu)
        menu.addItem(.separator())

        if let client = monitor.localClient, monitor.local.reachable {
            menu.addItem("Open Local UI") { [weak self] in self?.openUI(client) }
        }
        if let client = monitor.teamClient, monitor.team.reachable {
            menu.addItem("Open Team UI") { [weak self] in self?.openUI(client) }
        }
        guard CLI.path != nil else {
            menu.addItem("Copy Install Command") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(Config.installCommand, forType: .string)
            }
            return
        }
        guard monitor.local.configured else { return }
        if monitor.serviceInstalled {
            if monitor.local.reachable {
                menu.addItem("Restart Local Server") { [weak self] in self?.cairn("service", "restart") }
                menu.addItem("Stop Local Server") { [weak self] in self?.cairn("service", "stop") }
            } else if !monitor.blocked {
                menu.addItem("Start Local Server") { [weak self] in self?.cairn("service", "start") }
            }
        }
        if monitor.gitEnabled, monitor.local.reachable {
            menu.addItem("Push Git Mirror Now") { [weak self] in self?.cairn("git", "push") }
        }
        if FileManager.default.fileExists(atPath: Config.serverLog.path) {
            menu.addItem("Open Server Log") { NSWorkspace.shared.open(Config.serverLog) }
        }
        if monitor.blocked {
            menu.addItem("Allow in Login Items…") { SMAppService.openSystemSettingsLoginItems() }
        }
        menu.addItem(updating ? "Updating Server and CLI…" : "Update Server and CLI") { [weak self] in
            self?.updateServer()
        }.isEnabled = !updating
    }

    override func makeSettingsView() -> AnyView {
        AnyView(SettingsView(monitor: monitor))
    }

    private func addStatus(_ name: String, _ status: StoreStatus, to menu: NSMenu) {
        menu.addDisabledItem("\(name): \(status.line)")
        if let detail = status.detail {
            menu.addDisabledItem(detail).indentationLevel = 1
        }
    }

    /// Dimmed while a store that's set up can't be reached, or when nothing is set up.
    private func updateIcon() {
        let stores = [monitor.local, monitor.team].filter(\.configured)
        statusItem.button?.appearsDisabled = stores.isEmpty || stores.contains { !$0.reachable }
    }

    private func cairn(_ args: String...) {
        Task {
            let result = await CLI.run(args)
            if !result.ok { show(result.output) }
            monitor.poke()
        }
    }

    /// `cairn upgrade`: the CLI and the local server are one package, so this updates both.
    private func updateServer() {
        updating = true
        Task {
            let result = await CLI.run(["upgrade"])
            updating = false
            monitor.poke()
            show(!result.ok ? "The update failed:\n\(result.output)"
                 : result.output.contains("Nothing to upgrade") ? "The server and CLI are already up to date."
                 : "Updated the server and CLI to the latest on GitHub. New agent sessions pick up the change.")
        }
    }

    /// Logs the browser in with a one-time ticket, as `cairn ui` does.
    private func openUI(_ client: Client) {
        Task {
            struct Ticket: Decodable, Sendable { let ticket: String }
            do {
                if client.base.host() == "127.0.0.1", !(await client.proven()) {
                    return show("The local server didn't prove it's yours, so Cairn didn't send it your token.")
                }
                let ticket = try await client.post("/api/v1/ui/ticket", as: Ticket.self).ticket
                var login = URLComponents(url: client.base.appending(path: "ui/login"), resolvingAgainstBaseURL: false)!
                login.queryItems = [URLQueryItem(name: "ticket", value: ticket)]
                NSWorkspace.shared.open(login.url!)
            } catch {
                show("Couldn't open the web UI: \(error.localizedDescription)")
            }
        }
    }

    private func show(_ message: String) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Cairn"
        alert.informativeText = message
        alert.runModal()
    }
}
