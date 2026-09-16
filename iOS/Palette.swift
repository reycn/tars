import SwiftUI

/// Pixel colours per state. Presets are monochrome-ish themes; approval always stays warm so it still signals.
struct Palette: Equatable {
    var waiting: Color
    var working: Color
    var approval: Color
    var completed: Color

    func color(for state: AgentState) -> Color {
        switch state {
        case .waiting: return waiting
        case .working: return working
        case .approval: return approval
        case .completed: return completed
        }
    }

    static let presets: [(name: String, palette: Palette)] = [
        ("Terminal Green", Palette(waiting: Color(hex: "2FBF5A"), working: Color(hex: "39FF6E"), approval: Color(hex: "FFB000"), completed: Color(hex: "9CFFB0"))),
        ("Windows Blue", Palette(waiting: Color(hex: "8FB8FF"), working: Color(hex: "1E90FF"), approval: Color(hex: "FFD34D"), completed: Color(hex: "7FE0FF"))),
        ("Techno White", Palette(waiting: Color(hex: "FFFFFF"), working: Color(hex: "8CF2FF"), approval: Color(hex: "FF9E40"), completed: Color(hex: "73FF8C"))),
        ("Eva", Palette(waiting: Color(hex: "B48CFF"), working: Color(hex: "7CFF5A"), approval: Color(hex: "FF7A1A"), completed: Color(hex: "C8FF9E"))),
        ("Pika", Palette(waiting: Color(hex: "FFD600"), working: Color(hex: "FFE97A"), approval: Color(hex: "FFB000"), completed: Color(hex: "FF7A8A"))),
    ]
    static let customName = "Custom"

    // MARK: persistence (UserDefaults keys shared with the settings sheet)
    static let nameKey = "paletteName"
    static func customKey(_ state: AgentState) -> String { "paletteCustom.\(state.rawValue)" }

    static func load(name: String, defaults: UserDefaults = .standard) -> Palette {
        if let preset = presets.first(where: { $0.name == name }) { return preset.palette }
        let base = presets[2].palette
        func pick(_ state: AgentState, _ fallback: Color) -> Color {
            defaults.string(forKey: customKey(state)).map { Color(hex: $0) } ?? fallback
        }
        return Palette(waiting: pick(.waiting, base.waiting), working: pick(.working, base.working),
                       approval: pick(.approval, base.approval), completed: pick(.completed, base.completed))
    }
}

extension Color {
    init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))).scanHexInt64(&value)
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }

    var hexString: String {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}
