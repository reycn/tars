import Foundation
import ServiceManagement
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()
    private let defaults = UserDefaults.standard
    @Published var pairingCode: String { didSet { defaults.set(pairingCode, forKey: "pairingCode"); server?.pairingCode = pairingCode } }
    @Published var developmentMode: Bool { didSet { defaults.set(developmentMode, forKey: "developmentMode"); server?.developmentMode = developmentMode } }
    @Published var hideWindowAtStartup: Bool { didSet { defaults.set(hideWindowAtStartup, forKey: "hideWindowAtStartup") } }
    @Published var showMenuBarItem: Bool { didSet { defaults.set(showMenuBarItem, forKey: "showMenuBarItem") } }
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var state = "waiting"
    @Published var sourceAvailable = false
    @Published var detail: String?
    @Published var lastPairing: String?
    @Published var error: String?
    @Published var hooked: [String: Bool] = [:]

    /// Agents the hook installer knows about, in the order Settings lists them.
    struct Provider: Identifiable { let id: String; let label: String }
    static let providers = [Provider(id: "claude", label: "Claude Code"), Provider(id: "codex", label: "Codex"),
                            Provider(id: "opencode", label: "opencode"), Provider(id: "pi", label: "pi")]

    private var server: Server?
    private var source: EventSource?

    init() {
        pairingCode = defaults.string(forKey: "pairingCode") ?? Server.randomCode()
        developmentMode = defaults.bool(forKey: "developmentMode")
        hideWindowAtStartup = defaults.bool(forKey: "hideWindowAtStartup")
        showMenuBarItem = defaults.object(forKey: "showMenuBarItem") as? Bool ?? true
        if defaults.string(forKey: "pairingCode") == nil { defaults.set(pairingCode, forKey: "pairingCode") }
    }

    func start() {
        guard server == nil else { return }
        refreshHooks()
        do {
            let server = try Server(port: 17893)
            server.pairingCode = pairingCode
            server.developmentMode = developmentMode
            server.onStateChange = { [weak self] state, available, detail in
                self?.state = state; self?.sourceAvailable = available; self?.detail = detail
            }
            server.onPairingAttempt = { [weak self] ok, remote in
                let time = Date().formatted(date: .omitted, time: .shortened)
                self?.lastPairing = "\(ok ? "Paired" : "Rejected") \(remote) · \(time)"
            }
            self.server = server
            source = try EventSource(server: server, port: 17894)
        } catch {
            self.error = "Cannot start server: \(error.localizedDescription). Is another Tars running?"
        }
    }

    func regenerateCode() { pairingCode = Server.randomCode() }

    // MARK: Agent hooks (codestatus-style lifecycle hooks; installer script is bundled)

    private var installer: String? { Bundle.main.path(forResource: "install-hooks", ofType: "py") }

    func refreshHooks() {
        guard let out = runInstaller(["status"]),
              let data = out.data(using: .utf8),
              let status = try? JSONSerialization.jsonObject(with: data) as? [String: Bool] else { return }
        hooked = status
    }

    func setHook(_ provider: String, installed: Bool) {
        _ = runInstaller([installed ? "install" : "remove", provider])
        refreshHooks()
    }

    @discardableResult
    private func runInstaller(_ args: [String]) -> String? {
        guard let installer else { error = "install-hooks.py missing from bundle"; return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [installer] + args
        let pipe = Pipe(); process.standardOutput = pipe; process.standardError = pipe
        do { try process.run() } catch { self.error = "Hook installer: \(error.localizedDescription)"; return nil }
        process.waitUntilExit()
        let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        if process.terminationStatus != 0 { error = "Hook installer failed: \(out)" }
        return out
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
        } catch { self.error = "Login item: \(error.localizedDescription)" }
    }
}
