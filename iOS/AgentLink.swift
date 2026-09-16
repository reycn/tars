import Foundation
import Network
import Combine

 enum AgentState: String, Codable { case waiting, working, approval, completed }

struct ServerError: Decodable { let error: String }

struct StatusPacket: Decodable {
    let version: Int
    let session: String
    let seq: UInt64
    let state: AgentState
    let sourceAvailable: Bool
    let heartbeat: Double
    let detail: String?
}

@MainActor
final class AgentLink: ObservableObject {
    @Published private(set) var state: AgentState = .waiting
    @Published private(set) var connected = false
    @Published private(set) var detail: String?
    /// Server rejected our pairing code (or we have none). Cleared on the next accepted packet.
    @Published private(set) var pairingRequired = false
    /// A status packet has been accepted on the current connection.
    @Published private(set) var paired = false
    @Published private(set) var serverName: String?
    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var buffer = Data()
    private var session: String?
    private var sequence: UInt64?
    private var active = false
    private var retry: Task<Void, Never>?
    private var expiry: Task<Void, Never>?
    private var completion: Task<Void, Never>?
    private var retryDelay: UInt64 = 1

    func start() {
        guard !active else { return }
        active = true
        #if DEBUG
        if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "--preview-state"),
           ProcessInfo.processInfo.arguments.indices.contains(index + 1),
           let preview = AgentState(rawValue: ProcessInfo.processInfo.arguments[index + 1]) {
            connected = true; paired = true
            show(preview)
            return
        }
        #endif
        discover()
        // No accepted packet 2 s after launch → surface the PIN prompt instead of a blank face.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, self.active, !self.paired else { return }
            self.pairingRequired = true
        }
    }

    /// Called after the user changes the pairing code: drop the current attempt and retry now.
    func repair() {
        guard active else { return }
        retryDelay = 1
        reconnect()
    }

    func stop() {
        active = false
        retry?.cancel(); expiry?.cancel(); completion?.cancel()
        browser?.cancel(); browser = nil
        let old = connection; connection = nil; old?.cancel()
        buffer.removeAll(); session = nil; sequence = nil
        connected = false; state = .waiting; detail = nil; paired = false
    }

    private func discover() {
        guard active else { return }
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: "_tars._tcp", domain: nil), using: parameters)
        self.browser = browser
        browser.browseResultsChangedHandler = { [weak self, weak browser] results, _ in
            Task { @MainActor in
                guard let self, let browser, self.browser === browser,
                      self.connection == nil, let server = results.sorted(by: {
                          String(describing: $0.endpoint) < String(describing: $1.endpoint)
                      }).first else { return }
                if case .service(let name, _, _, _) = server.endpoint { self.serverName = name }
                self.connect(server.endpoint)
            }
        }
        browser.stateUpdateHandler = { [weak self, weak browser] status in
            Task { @MainActor in
                guard let self, let browser, self.browser === browser else { return }
                if case .failed = status { self.reconnect() }
            }
        }
        browser.start(queue: .main)
    }

    private func connect(_ endpoint: NWEndpoint) {
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        if let tcp = parameters.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
            tcp.noDelay = true
            tcp.enableKeepalive = true
            tcp.keepaliveIdle = 30
            tcp.keepaliveInterval = 10
            tcp.keepaliveCount = 3
        }
        let connection = NWConnection(to: endpoint, using: parameters)
        self.connection = connection
        buffer.removeAll(); session = nil; sequence = nil
        connection.stateUpdateHandler = { [weak self, weak connection] status in
            Task { @MainActor in
                guard let self, let connection, self.connection === connection else { return }
                switch status {
                case .ready:
                    self.armExpiry(seconds: 8)
                    // Pairing handshake: first line carries the stored code; the server ignores it in development mode.
                    let code = UserDefaults.standard.string(forKey: "pairingCode") ?? ""
                    connection.send(content: Data("{\"code\":\"\(code)\"}\n".utf8), completion: .contentProcessed { _ in })
                    self.receive(connection)
                case .failed, .waiting: self.reconnect()
                default: break
                }
            }
        }
        connection.start(queue: .main)
        armExpiry(seconds: 10)
    }

    private func receive(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self, weak connection] data, _, done, error in
            Task { @MainActor in
                guard let self, let connection, self.connection === connection else { return }
                if let data { self.buffer.append(data) }
                guard self.buffer.count <= 65_536 else { self.reconnect(); return }
                while let newline = self.buffer.firstIndex(of: 10) {
                    let line = self.buffer.prefix(upTo: newline)
                    self.buffer.removeSubrange(...newline)
                    if (try? JSONDecoder().decode(ServerError.self, from: line))?.error == "unpaired" {
                        self.pairingRequired = true
                        self.retryDelay = 5
                        self.reconnect(); return
                    }
                    guard let packet = try? JSONDecoder().decode(StatusPacket.self, from: line),
                          packet.version == 1, packet.heartbeat.isFinite,
                          (5...300).contains(packet.heartbeat), packet.session.count <= 128 else {
                        self.reconnect(); return
                    }
                    self.armExpiry(seconds: packet.heartbeat * 2 + 5)
                    self.pairingRequired = false
                    self.paired = true
                    self.connected = packet.sourceAvailable
                    self.retryDelay = 1
                    if self.session != packet.session || self.sequence == nil || packet.seq > self.sequence! {
                        self.session = packet.session; self.sequence = packet.seq
                        self.detail = packet.sourceAvailable ? packet.detail : nil
                        self.show(packet.sourceAvailable ? packet.state : .waiting)
                    }
                }
                if done || error != nil { self.reconnect() }
                else { self.receive(connection) }
            }
        }
    }

    private func show(_ state: AgentState) {
        completion?.cancel()
        self.state = state
        if state == .completed {
            completion = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
                self?.state = .waiting; self?.detail = nil
            }
        }
    }

    private func armExpiry(seconds: Double) {
        expiry?.cancel()
        expiry = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            self?.reconnect()
        }
    }

    private func reconnect() {
        guard active else { return }
        expiry?.cancel(); completion?.cancel()
        let old = connection; connection = nil; old?.cancel()
        browser?.cancel(); browser = nil
        connected = false; state = .waiting; detail = nil; paired = false
        retry?.cancel()
        let delay = retryDelay
        retryDelay = min(retryDelay * 2, 30)
        retry = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            self?.discover()
        }
    }
}
