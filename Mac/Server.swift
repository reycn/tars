import Foundation
import Network

// Development transport: aggregate status plus one short detail line (current task / approval question / result).
struct Packet: Encodable {
    let version = 1
    let session: String
    let seq: UInt64
    let state: String
    let sourceAvailable: Bool
    let heartbeat: Double
    let detail: String?
}

final class Server {
    let session = UUID().uuidString
    var sequence: UInt64 = 0
    var state = "waiting"
    var available = false
    var detail: String?
    var clients: [UUID: NWConnection] = [:]
    var pending: Set<UUID> = []
    var listener: NWListener!
    let port: UInt16
    var heartbeat: DispatchSourceTimer?

    /// Pairing: a phone sends `{"code":"123456"}\n` as its first line. Development mode streams to anyone.
    var pairingCode = Server.randomCode()
    var developmentMode = true
    /// UI hook: (paired, remote description). Called on the main queue.
    var onPairingAttempt: ((Bool, String) -> Void)?
    var onStateChange: ((String, Bool, String?) -> Void)?

    static func randomCode() -> String { String(format: "%06d", Int.random(in: 0...999_999)) }

    init(port: UInt16) throws {
        self.port = port
        try startListening()
        scheduleHeartbeat()
    }

    /// Bonjour listeners fail on network changes (Wi‑Fi switch, sleep/wake, VPN). Never exit: rebuild after a pause.
    func startListening() throws {
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        if let tcp = parameters.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options { tcp.noDelay = true }
        listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
        listener.service = NWListener.Service(name: "Tars · \(Host.current().localizedName ?? "Mac")", type: "_tars._tcp")
        listener.newConnectionHandler = { [weak self] connection in
            guard let self, self.clients.count < 8 else { connection.cancel(); return }
            let id = UUID()
            self.clients[id] = connection
            connection.stateUpdateHandler = { [weak self] status in
                guard let self else { return }
                switch status {
                case .ready:
                    if self.developmentMode { self.send(id) }
                    else {
                        // Unpaired clients get 5 s to present a code.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                            guard let self, self.clients[id] === connection, !self.paired.contains(id) else { return }
                            self.reject(id)
                        }
                    }
                    self.readCode(id, connection: connection, buffer: Data())
                case .failed, .cancelled: self.drop(id)
                default: break
                }
            }
            connection.start(queue: .main)
        }
        listener.stateUpdateHandler = { [weak self] status in
            switch status {
            case .ready: print("Tars ready · Bonjour _tars._tcp · port \(self?.port ?? 0)"); fflush(stdout)
            case .failed(let error): self?.restartListening(after: error)
            default: break
            }
        }
        listener.start(queue: .main)
    }

    private func restartListening(after error: Error) {
        fputs("Listener failed: \(error) · restarting in 2 s\n", stderr)
        listener.cancel()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self else { return }
            do { try self.startListening() } catch { self.restartListening(after: error) }
        }
    }

    var paired: Set<UUID> = []

    private func readCode(_ id: UUID, connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 256) { [weak self] data, _, done, error in
            guard let self, self.clients[id] === connection else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            // After pairing (or in development mode) any further input means the client is done.
            if self.paired.contains(id) || buffer.count > 256 { self.drop(id); return }
            if let newline = buffer.firstIndex(of: 10) {
                let line = buffer.prefix(upTo: newline)
                let code = (try? JSONDecoder().decode([String: String].self, from: line))?["code"] ?? ""
                let remote = String(describing: connection.endpoint)
                if self.developmentMode || code == self.pairingCode {
                    self.paired.insert(id)
                    self.onPairingAttempt?(true, remote)
                    if !self.developmentMode { self.send(id) }
                    self.readCode(id, connection: connection, buffer: Data())
                } else {
                    self.onPairingAttempt?(false, remote)
                    self.reject(id)
                }
            } else if done || error != nil { self.drop(id) }
            else { self.readCode(id, connection: connection, buffer: buffer) }
        }
    }

    private func reject(_ id: UUID) {
        guard let client = clients[id] else { return }
        client.send(content: Data("{\"version\":1,\"error\":\"unpaired\"}\n".utf8), completion: .contentProcessed { [weak self] _ in self?.drop(id) })
    }

    private func drop(_ id: UUID) {
        clients[id]?.cancel(); clients.removeValue(forKey: id); pending.remove(id); paired.remove(id)
    }

    func update(state: String, available: Bool, detail: String? = nil) {
        guard ["waiting", "working", "approval", "completed"].contains(state) else { return }
        guard state != self.state || available != self.available || detail != self.detail else { return }
        self.state = state; self.available = available; self.detail = detail; sequence += 1
        for id in Array(clients.keys) { send(id) }
        scheduleHeartbeat()
        print("State: \(state) · source \(available ? "connected" : "unavailable")\(detail.map { " · " + $0 } ?? "")"); fflush(stdout)
        onStateChange?(state, available, detail)
    }

    var interval: Double { state == "working" || state == "approval" ? 20 : 120 }
    func scheduleHeartbeat() {
        heartbeat?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + interval, repeating: interval, leeway: .seconds(2))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            for id in Array(self.clients.keys) { self.send(id) }
        }
        heartbeat = timer; timer.resume()
    }

    func send(_ id: UUID) {
        guard let client = clients[id] else { return }
        guard developmentMode || paired.contains(id) else { return }
        // Bound queued data: a stalled consumer reconnects for a fresh snapshot.
        guard !pending.contains(id) else { drop(id); return }
        let packet = Packet(session: session, seq: sequence, state: state, sourceAvailable: available, heartbeat: interval, detail: detail)
        guard var data = try? JSONEncoder().encode(packet) else { return }
        data.append(10); pending.insert(id)
        client.send(content: data, completion: .contentProcessed { [weak self] error in
            self?.pending.remove(id)
            if error != nil { self?.drop(id) }
        })
    }
}
