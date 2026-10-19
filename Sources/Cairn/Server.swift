import CryptoKit
import Foundation

/// What the cairn CLI has set up, read from ~/.cairn. The app never writes there.
struct Config {
    static let home = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".cairn")
    static let servicePlist = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/LaunchAgents/local.cairn.server.plist")
    static let serverLog = home.appending(path: "logs/server.log")
    static let installCommand = "curl -fsSL https://raw.githubusercontent.com/VedAtal/cairn/main/install.sh | sh"

    var localPort: Int?
    var localToken: String?
    var remoteURL: URL?
    var remoteAlias: String?
    var remoteKey: String?

    static func load() -> Config {
        let config = toml("config.toml"), credentials = toml("credentials.toml")
        let local = config["local"] ?? [:], remote = config["remote"] ?? [:]
        let token = try? String(contentsOf: home.appending(path: "run/token"), encoding: .utf8)
        return Config(
            localPort: local["enabled"] as? Bool == true ? local["port"] as? Int : nil,
            localToken: token?.trimmingCharacters(in: .whitespacesAndNewlines),
            remoteURL: (remote["url"] as? String).flatMap(URL.init(string:)),
            remoteAlias: remote["alias"] as? String,
            remoteKey: credentials["remote"]?["api_key"] as? String)
    }

    // The CLI writes a small subset of TOML: [table] lines, then `key = <JSON value>` lines.
    private static func toml(_ name: String) -> [String: [String: Any]] {
        guard let text = try? String(contentsOf: home.appending(path: name), encoding: .utf8) else { return [:] }
        var tables: [String: [String: Any]] = [:], table = ""
        for line in text.split(separator: "\n").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            if line.hasPrefix("[") && line.hasSuffix("]") {
                table = String(line.dropFirst().dropLast())
            } else if let eq = line.range(of: " = "),
                      let value = try? JSONSerialization.jsonObject(with: Data(line[eq.upperBound...].utf8),
                                                                    options: .fragmentsAllowed) {
                tables[table, default: [:]][String(line[..<eq.lowerBound])] = value
            }
        }
        return tables
    }
}

/// The `cairn` command, which owns the local server and its login service.
enum CLI {
    /// The binary the login service runs, else where the installer puts it.
    static var path: String? {
        let plist = NSDictionary(contentsOf: Config.servicePlist)
        let candidates: [String?] = [(plist?["ProgramArguments"] as? [String])?.first,
                          FileManager.default.homeDirectoryForCurrentUser.appending(path: ".local/bin/cairn").path]
        return candidates.compactMap { $0 }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Runs `cairn <args>` off the main thread. Returns nil on success, else what went wrong.
    static func run(_ args: [String]) async -> String? {
        guard let path else { return "The cairn command isn't installed." }
        return await withCheckedContinuation { done in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = args
                let home = NSHomeDirectory()
                // Apps start with a bare PATH; git and the harness CLIs live in these.
                process.environment = ["HOME": home,
                                       "PATH": "\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"]
                let errors = Pipe()
                process.standardError = errors
                process.standardOutput = FileHandle.nullDevice
                do {
                    try process.run()
                } catch {
                    return done.resume(returning: error.localizedDescription)
                }
                let output = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                process.waitUntilExit()
                done.resume(returning: process.terminationStatus == 0 ? nil
                            : output.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "cairn: ", with: ""))
            }
        }
    }
}

struct ServerStatus: Decodable, Sendable {
    let store: String
    let version: String
    let counts: Counts?
    let git: Git

    struct Counts: Decodable, Sendable {
        let entries: Int
        let projects: Int
    }

    struct Git: Decodable, Sendable {
        let enabled: Bool
        let state: String?
        let error: String?
        let remote: String?
        let lastPush: String?
        let pendingPush: Bool?
    }
}

struct HTTPError: Error {
    let status: Int
}

/// A Cairn server's REST API, as one user (the local token or a team API key).
struct Client: Sendable {
    let base: URL
    var token: String?

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [:]  // a corporate proxy would swallow loopback calls
        config.timeoutIntervalForRequest = 5
        return URLSession(configuration: config)
    }()

    func get<T: Decodable & Sendable>(_ path: String, as type: T.Type) async throws -> T {
        try await send("GET", path, as: type)
    }

    func post<T: Decodable & Sendable>(_ path: String, as type: T.Type) async throws -> T {
        try await send("POST", path, as: type)
    }

    /// The local server proves it holds the token before the token is sent to it.
    func proven() async -> Bool {
        guard let token else { return false }
        let nonce = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        struct Hello: Decodable, Sendable { let proof: String? }
        let hello = try? await Client(base: base).get("/api/v1/hello?nonce=\(nonce)", as: Hello.self)
        let expected = HMAC<SHA256>.authenticationCode(for: Data(nonce.utf8), using: SymmetricKey(data: Data(token.utf8)))
        return hello?.proof == expected.map { String(format: "%02x", $0) }.joined()
    }

    private func send<T: Decodable & Sendable>(_ method: String, _ path: String, as type: T.Type) async throws -> T {
        var request = URLRequest(url: URL(string: base.absoluteString.trimmingCharacters(in: ["/"]) + path)!)
        request.httpMethod = method
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if method == "POST" {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data("{}".utf8)
        }
        let (data, response) = try await Self.session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw HTTPError(status: status) }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(type, from: data)
    }
}
