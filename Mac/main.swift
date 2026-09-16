import Foundation

let arguments = CommandLine.arguments
func port(_ flag: String, default value: UInt16) -> UInt16 {
    guard let i = arguments.firstIndex(of: flag), arguments.indices.contains(i + 1),
          let result = UInt16(arguments[i + 1]), result > 0 else { return value }
    return result
}
func option(_ flag: String) -> String? {
    guard let i = arguments.firstIndex(of: flag), arguments.indices.contains(i + 1) else { return nil }
    return arguments[i + 1]
}
let server = try Server(port: port("--port", default: 17893))
// CLI defaults to development mode (no pairing) unless --code NNNNNN is given.
if let code = option("--code") { server.pairingCode = code; server.developmentMode = false }
let source = try EventSource(server: server, port: port("--event-port", default: 17894))
withExtendedLifetime(source) { dispatchMain() }
