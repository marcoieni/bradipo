import SwiftUI

struct BreakAccent: RawRepresentable, Equatable {
    static let defaultsKey = "accentColor"
    static let green = Self(rawValue: 0x85C7AD)
    let rawValue: Int

    init(rawValue: Int) {
        self.rawValue = (0...0xFFFFFF).contains(rawValue) ? rawValue : Self.green.rawValue
    }

    init?(color: NSColor) {
        guard let rgb = color.usingColorSpace(.sRGB) else { return nil }
        func byte(_ channel: CGFloat) -> Int {
            Int((min(1, max(0, channel)) * 255).rounded())
        }
        rawValue = byte(rgb.redComponent) << 16 | byte(rgb.greenComponent) << 8 | byte(rgb.blueComponent)
    }

    var color: NSColor {
        NSColor(srgbRed: CGFloat(rawValue >> 16) / 255,
                green: CGFloat((rawValue >> 8) & 0xFF) / 255,
                blue: CGFloat(rawValue & 0xFF) / 255, alpha: 1)
    }

    var glow: Color { Color(nsColor: color) }

    var background: Color {
        self == .green ? Color(red: 0.12, green: 0.19, blue: 0.16) : glow.mix(with: .black, by: 0.80)
    }

    var divider: Color {
        self == .green ? Color(red: 0.63, green: 0.78, blue: 0.61) : glow.mix(with: .white, by: 0.40)
    }

    var countdown: Color {
        self == .green ? Color(red: 0.80, green: 0.87, blue: 0.71) : glow.mix(with: .white, by: 0.75)
    }
}
