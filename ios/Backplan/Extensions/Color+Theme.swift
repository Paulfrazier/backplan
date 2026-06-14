import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    // Backplan palette (ported from index.html CSS custom properties)
    static let bpPurple = Color(hex: 0x4A154B)
    static let bpPurpleElectric = Color(hex: 0x6D28D9)
    static let bpLime = Color(hex: 0x84CC16)
    static let bpLimeInk = Color(hex: 0x3F6212)
    static let bpCoral = Color(hex: 0xFB5D3C)
    static let bpGold = Color(hex: 0xECB22E)
    static let bpInk = Color(hex: 0x1D1C1D)
    static let bpPaper = Color(hex: 0xFBFAFF)
    static let bpCard = Color.white
    static let bpMuted = Color(hex: 0x696969)
    static let bpBorder = Color(hex: 0xE6E6E6)
    static let bpLimeTint = Color(hex: 0xF1FAE3)
    static let bpCoralTint = Color(hex: 0xFDECE8)

    /// 4-color cycle for timeline segments (light tints).
    static let timelineTints: [Color] = [
        Color(hex: 0xEDE4FF),
        Color(hex: 0xE6F4D0),
        Color(hex: 0xFFEFC4),
        Color(hex: 0xFFD8CF),
    ]
}

extension ShapeStyle where Self == Color {
    static var bpInk: Color { .bpInk }
    static var bpPaper: Color { .bpPaper }
    static var bpCard: Color { .bpCard }
    static var bpPurple: Color { .bpPurple }
    static var bpPurpleElectric: Color { .bpPurpleElectric }
    static var bpLime: Color { .bpLime }
    static var bpLimeInk: Color { .bpLimeInk }
    static var bpCoral: Color { .bpCoral }
    static var bpGold: Color { .bpGold }
    static var bpMuted: Color { .bpMuted }
    static var bpBorder: Color { .bpBorder }
    static var bpLimeTint: Color { .bpLimeTint }
    static var bpCoralTint: Color { .bpCoralTint }
}

extension Font {
    /// Space Grotesk display font (bundled variable font). Weight is applied via the
    /// variable weight axis; falls back to system if the font is unavailable.
    static func display(_ size: CGFloat, bold: Bool = true) -> Font {
        .custom("SpaceGrotesk-Light", size: size).weight(bold ? .bold : .medium)
    }
}
