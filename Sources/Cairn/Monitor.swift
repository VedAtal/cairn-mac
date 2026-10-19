import Combine
import Foundation
import ServiceManagement

/// One store's status, as the menu and Settings show it.
struct StoreStatus {
    var configured = false
    var reachable = false
    var line = "Not configured"
    var detail: String?
}

/// Polls the local server and the team server, and works out what to show.
@MainActor
final class Monitor: ObservableObject {
    @Published private(set) var local = StoreStatus()
    @Published private(set) var team = StoreStatus()
    private(set) var config = Config.load()
    private(set) var serviceInstalled = false
    private(set) var blocked = false
    private(set) var gitEnabled = false
    var onChange: (() -> Void)?

    private var timer: Timer?
    private var teamCheckedAt = Date.distantPast

    var teamTitle: String { config.remoteAlias.map { "Team \($0)" } ?? "Team" }

    var localClient: Client? {
        config.localPort.map { Client(base: URL(string: "http://127.0.0.1:\($0)")!, token: config.localToken) }
    }

    var teamClient: Client? {
        guard let url = config.remoteURL, let key = config.remoteKey else { return nil }
        return Client(base: url, token: key)
    }

    func start() {
        refresh(team: true)
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh(team: false) }
        }
    }

    /// After an action, check every second for a while, so the menu catches up quickly.
    func poke() {
        Task {
            for _ in 0..<15 {
                await update(team: false)
                try? await Task.sleep(for: .seconds(1))
            }
        }
        refresh(team: true)
    }

    private func refresh(team: Bool) {
        Task { await update(team: team || Date().timeIntervalSince(teamCheckedAt) > 60) }
    }

    private func update(team includeTeam: Bool) async {
        config = Config.load()
        local = await checkLocal()
        if includeTeam {
            teamCheckedAt = Date()
            team = await checkTeam()
        }
        onChange?()
    }

    private func checkLocal() async -> StoreStatus {
        serviceInstalled = FileManager.default.fileExists(atPath: Config.servicePlist.path)
        guard let client = localClient else {
            gitEnabled = false
            return StoreStatus()
        }
        struct Health: Decodable, Sendable { let status: String }
        guard (try? await client.get("/healthz", as: Health.self)) != nil else {
            blocked = serviceInstalled && SMAppService.statusForLegacyPlist(at: Config.servicePlist) == .requiresApproval
            return StoreStatus(configured: true, line: blocked ? "Blocked in Login Items" : "Not running")
        }
        blocked = false
        guard await client.proven() else {
            return StoreStatus(configured: true, line: "Port \(config.localPort ?? 0) is held by something else")
        }
        guard let status = try? await client.get("/api/v1/status", as: ServerStatus.self) else {
            return StoreStatus(configured: true, line: "Running, but its status didn't load")
        }
        gitEnabled = status.git.enabled
        return StoreStatus(configured: true, reachable: true, line: "Running · v\(status.version)",
                           detail: [Self.counts(status), Self.git(status.git)].compactMap { $0 }.joined(separator: " · "))
    }

    private func checkTeam() async -> StoreStatus {
        guard let client = teamClient else { return StoreStatus() }
        do {
            let status = try await client.get("/api/v1/status", as: ServerStatus.self)
            return StoreStatus(configured: true, reachable: true, line: "Connected · v\(status.version)",
                               detail: [Self.counts(status), client.base.host()].compactMap { $0 }.joined(separator: " · "))
        } catch let error as HTTPError where error.status == 401 {
            return StoreStatus(configured: true, line: "API key rejected")
        } catch {
            return StoreStatus(configured: true, line: "Unreachable")
        }
    }

    private static func counts(_ status: ServerStatus) -> String? {
        status.counts.map { plural($0.entries, "entry", "entries") + " · " + plural($0.projects, "project", "projects") }
    }

    private static func git(_ git: ServerStatus.Git) -> String? {
        guard git.enabled else { return nil }
        if git.state == "error" || git.state == "diverged" { return "git push failing" }
        if git.remote == nil { return "git backup on this Mac" }
        if git.pendingPush == true { return "git push pending" }
        guard let pushed = git.lastPush.flatMap({ ISO8601DateFormatter().date(from: $0) }) else { return "git on" }
        let ago = RelativeDateTimeFormatter()
        ago.unitsStyle = .short
        return "git pushed \(ago.localizedString(for: pushed, relativeTo: Date()))"
    }

    private static func plural(_ n: Int, _ one: String, _ many: String) -> String {
        "\(n.formatted()) \(n == 1 ? one : many)"
    }
}
