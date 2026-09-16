import SwiftUI

/// A theme is a sprite sheet: one 12×12 bitmap per glyph role, plus a default palette.
/// All artwork is original pixel art; the names are only an homage.
enum Theme: String, CaseIterable, Identifiable {
    case bit, eva, pika

    var id: String { rawValue }
    static let key = "themeName"

    var title: String {
        switch self {
        case .bit: return "Bit"
        case .eva: return "Eva"
        case .pika: return "Pika"
        }
    }

    /// The palette selected automatically when the theme is picked.
    var paletteName: String {
        switch self {
        case .bit: return "Techno White"
        case .eva: return "Eva"
        case .pika: return "Pika"
        }
    }

    /// Whether the right eye is the mirror image of the left (asymmetric designs need it).
    var mirrored: Bool { self != .bit }

    func rows(for glyph: PixelGlyph) -> [String] {
        switch self {
        case .bit: return glyph.bitRows
        case .eva:
            switch glyph {
            case .bar: return [   // narrow angled slit
                "............", "............", "............", "............",
                "##..........", ".###........", "..#####.....", "....######..",
                "......######", "............", "............", "............"]
            case .blink: return [
                "............", "............", "............", "............",
                "............", "............", "..###.......", ".....#####..",
                "..........##", "............", "............", "............"]
            case .smile: return [ // lit, angled lens
                "............", "............", "............", ".##.........",
                ".####.......", "..######....", "...#######..", "....#######.",
                ".....######.", "......####..", "............", "............"]
            case .ring: return [  // wide eye, hollow pupil
                "....####....", "..##....##..", ".#........#.", ".#...##...#.",
                "#...####...#", "#...####...#", "#...####...#", "#...####...#",
                ".#...##...#.", ".#........#.", "..##....##..", "....####...."]
            case .check: return [ // relaxed chevron
                "............", "............", "............", "............",
                "##........##", ".##......##.", "..##....##..", "...##..##...",
                "....####....", ".....##.....", "............", "............"]
            }
        case .pika:
            switch glyph {
            case .bar: return [   // round eye with highlight
                "............", "...######...", "..########..", ".#####..###.",
                ".#####..###.", "############", "############", ".##########.",
                ".##########.", "..########..", "...######...", "............"]
            case .blink: return [
                "............", "............", "............", "............",
                "............", "............", "..########..", ".##......##.",
                "##........##", "............", "............", "............"]
            case .smile: return [ // happy arc
                "............", "............", "............", "............",
                "....####....", "..###..###..", ".##......##.", "##........##",
                "............", "............", "............", "............"]
            case .ring: return [  // lightning bolt
                "......###...", ".....###....", "....###.....", "...###......",
                "..#######...", ".....###....", "....###.....", "...###......",
                "..###.......", ".###........", "............", "............"]
            case .check: return [ // sparkle
                ".....##.....", ".....##.....", "..#..##..#..", "...#.##.#...",
                "############", "...#.##.#...", "..#..##..#..", ".....##.....",
                ".....##.....", "............", "............", "............"]
            }
        }
    }

    static func current(_ defaults: UserDefaults = .standard) -> Theme {
        Theme(rawValue: defaults.string(forKey: key) ?? "") ?? .bit
    }
}
