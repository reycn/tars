import Foundation
import Network

struct Event: Decodable { let session: String; let state: String; let detail: String? }

final class EventSource {
    let server: Server
    let listener: NWListener
    var sessions: [String: (state: String, time: Date, detail: String?)] = [:]
    var clients: [UUID: NWConnection] = [:]
    var completion: DispatchWorkItem?
    var staleTimer: DispatchSourceTimer?
    var lastBridgeSeen = Date.distantPast

    init(server: Server, port: UInt16) throws {
        self.server = server
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
        listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in
            guard let self, self.clients.count < 32 else { connection.cancel(); return }
            let id = UUID(); self.clients[id] = connection
            connection.start(queue: .main)
            self.receive(connection, id: id, buffer: Data())
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self, weak connection] in
                connection?.cancel(); self?.clients.removeValue(forKey: id)
            }
        }
        listener.stateUpdateHandler = { state in
            if case .failed(let error) = state {
                fputs("Event source failed: \(error)\n", stderr); exit(1)
            }
        }
        listener.start(queue: .main)
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 60, repeating: 60, leeway: .seconds(5))
        timer.setEventHandler { [weak self] in self?.expire() }
        staleTimer = timer; timer.resume()
    }

    func receive(_ connection: NWConnection, id: UUID, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 2048) { [weak self] data, _, done, error in
            guard let self, self.clients[id] != nil else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if buffer.count > 2048 { connection.cancel(); self.clients.removeValue(forKey: id); return }
            if let newline = buffer.firstIndex(of: 10) {
                if let event = try? JSONDecoder().decode(Event.self, from: buffer.prefix(upTo: newline)),
                   event.session.count <= 128, !event.session.isEmpty, (event.detail ?? "").count <= 200,
                   ["waiting", "working", "approval", "completed", "ended"].contains(event.state) {
                    self.apply(event)
                }
                connection.cancel(); self.clients.removeValue(forKey: id)
            } else if !done && error == nil { self.receive(connection, id: id, buffer: buffer) }
            else { connection.cancel(); self.clients.removeValue(forKey: id) }
        }
    }

    func apply(_ event: Event) {
        lastBridgeSeen = Date()
        if event.state == "ended" { sessions.removeValue(forKey: event.session) }
        else {
            if sessions.count >= 256, sessions[event.session] == nil,
               let oldest = sessions.min(by: { $0.value.time < $1.value.time }) { sessions.removeValue(forKey: oldest.key) }
            // Keep the last known detail when an event carries none (e.g. PostToolUse without text).
            let detail = event.detail ?? (sessions[event.session]?.state == event.state ? sessions[event.session]?.detail : nil)
            sessions[event.session] = (event.state, Date(), detail)
        }
        publish()
    }

    func publish() {
        let states = sessions.values.map(\.state)
        let state = states.contains("approval") ? "approval" : states.contains("working") ? "working" : states.contains("completed") ? "completed" : "waiting"
        let detail = sessions.values.filter { $0.state == state }.max(by: { $0.time < $1.time })?.detail
        server.update(state: state, available: lastBridgeSeen != .distantPast, detail: detail)
        if state == "completed", completion == nil {
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.completion = nil
                for (key, value) in self.sessions where value.state == "completed" {
                    self.sessions[key] = ("waiting", value.time, nil)
                }
                self.publish()
            }
            completion = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
        } else if state != "completed" {
            completion?.cancel(); completion = nil
            // Do not replay a hidden completion after an approval/working state clears.
            for (key, value) in sessions where value.state == "completed" { sessions[key] = ("waiting", value.time, nil) }
        }
    }

    func expire() {
        // ponytail: hooks cannot prove a silent session is alive; expire after 30 minutes.
        // Upgrade to native agent liveness when the direct-agent source is implemented.
        let cutoff = Date().addingTimeInterval(-1800)
        sessions = sessions.filter { $0.value.time > cutoff }
        if lastBridgeSeen < cutoff { lastBridgeSeen = .distantPast }
        publish()
    }
}
