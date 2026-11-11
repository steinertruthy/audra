import SwiftUI

/// Audra's visual identity: near-black surfaces with a faint violet cast, and a deep lilac accent
/// used sparingly for interaction, selection and state.
enum Theme {
    // MARK: Surfaces (darkest → lightest)
    static let canvas = Color(hex: 0x070609)
    static let base = Color(hex: 0x0B0A0E)
    static let panel = Color(hex: 0x0F0E13)
    static let elevated = Color(hex: 0x15131B)
    static let control = Color(hex: 0x1B1823)
    static let controlHover = Color(hex: 0x231F2D)

    // MARK: Lines
    static let hairline = Color.white.opacity(0.05)
    static let stroke = Color.white.opacity(0.075)
    static let strokeStrong = Color.white.opacity(0.13)

    // MARK: Deep violet / lilac accent
    static let accent = Color(hex: 0x6A45D9)
    static let accentBright = Color(hex: 0xB4A0FF)
    static let accentDeep = Color(hex: 0x3F2496)
    static let accentSoft = Color(hex: 0x7B5BF0).opacity(0.14)
    static let accentGradient = LinearGradient(colors: [Color(hex: 0x7653E6), Color(hex: 0x5733C4)],
                                               startPoint: .top, endPoint: .bottom)

    // MARK: Text
    static let textPrimary = Color(hex: 0xEEEBF5)
    static let textSecondary = Color(hex: 0xEEEBF5).opacity(0.58)
    static let textTertiary = Color(hex: 0xEEEBF5).opacity(0.36)
    static let textQuaternary = Color(hex: 0xEEEBF5).opacity(0.2)

    // MARK: Semantic
    static let success = Color(hex: 0x4ADE9B)
    static let warning = Color(hex: 0xF5B94A)
    static let danger = Color(hex: 0xF27272)
    static let highlight = Color(hex: 0xF2CC4A)

    // MARK: Timeline clip colors (desaturated so the accent stays meaningful)
    static let videoClip = Color(hex: 0x2B2350)
    static let videoClipEdge = Color(hex: 0x6E5BC4)
    static let audioClip = Color(hex: 0x16302F)
    static let audioClipEdge = Color(hex: 0x3D8C84)
    static let audioWave = Color(hex: 0x76CFC4)
    static let textClip = Color(hex: 0x3A2A16)
    static let textClipEdge = Color(hex: 0xC4934C)

    // MARK: Metrics
    enum Radius {
        static let small: CGFloat = 6
        static let medium: CGFloat = 8
        static let large: CGFloat = 12
        static let xlarge: CGFloat = 16
    }

    /// Height of the custom top bar (aligned with the window controls).
    static let topBarHeight: CGFloat = 52
    /// Space reserved for the window's traffic-light buttons.
    static let trafficLightInset: CGFloat = 96
}

/// Shared motion vocabulary so every interaction feels related.
enum Motion {
    static let snappy = Animation.spring(response: 0.26, dampingFraction: 0.88)
    static let smooth = Animation.spring(response: 0.4, dampingFraction: 0.9)
    static let bouncy = Animation.spring(response: 0.36, dampingFraction: 0.72)
    static let hover = Animation.easeOut(duration: 0.12)
    static let fade = Animation.easeInOut(duration: 0.2)
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

extension Font {
    static let audraDisplay = Font.system(size: 30, weight: .semibold)
    static let audraTitle = Font.system(size: 22, weight: .semibold)
    static let audraHeadline = Font.system(size: 14, weight: .semibold)
    static let audraBody = Font.system(size: 13)
    static let audraCaption = Font.system(size: 11, weight: .medium)
    static let audraTimecode = Font.system(size: 12, weight: .medium, design: .monospaced)
}
