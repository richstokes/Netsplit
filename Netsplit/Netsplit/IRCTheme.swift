//
//  IRCTheme.swift
//  Netsplit
//

import SwiftUI

struct IRCThemePalette {
    let background: Color
    let bar: Color
    let panel: Color
    let field: Color
    let border: Color
    let text: Color
    let secondaryText: Color
    let accent: Color
    let emphasizedBackground: Color
    let emphasizedText: Color
    let warningSecondaryText: Color
    let prominentButtonText: Color
    let nicknameColors: [Color]

    static let catppuccinLatteBackgroundHex: UInt32 = 0xEFF1F5
    static let catppuccinLatteBarHex: UInt32 = 0xE6E9EF
    static let catppuccinLatteSecondaryTextHex: UInt32 = 0x5C5F77
    static let catppuccinLatteNicknameHexValues: [UInt32] = [
        0x1C60E6, 0x8839EF, 0xB44708, 0x9D4F88,
        0x307820, 0x5363B9, 0x12757A, 0xD20F39
    ]
    static let cyberpunkBackgroundHex: UInt32 = 0x101521
    static let cyberpunkBarHex: UInt32 = 0x0B0F19
    static let cyberpunkSecondaryTextHex: UInt32 = 0x9AA8CC
    static let cyberpunkNicknameHexValues: [UInt32] = [
        0x4FE6D5, 0xFF6BCE, 0x9D8CFF, 0x5AAEFF,
        0xFFB454, 0xB7E36A, 0xFFD166, 0xF28FAD
    ]
    static let rosePineBackgroundHex: UInt32 = 0x191724
    static let rosePineBarHex: UInt32 = 0x1F1D2E
    static let rosePineSecondaryTextHex: UInt32 = 0x908CAA
    static let rosePineNicknameHexValues: [UInt32] = [
        0x9CCFD8, 0xC4A7E7, 0xF6C177, 0xEBBCBA,
        0xEB6F92, 0x3E8FB0, 0x908CAA, 0xE0DEF4
    ]
    static let rosePineDawnBackgroundHex: UInt32 = 0xFAF4ED
    static let rosePineDawnBarHex: UInt32 = 0xF2E9E1
    static let rosePineDawnSecondaryTextHex: UInt32 = 0x625D75
    static let rosePineDawnNicknameHexValues: [UInt32] = [
        0x286983, 0xA14360, 0x6E5A8A, 0xA8504D,
        0x8A5900, 0x356C75, 0x625D75, 0x3F5F8F
    ]
    static let solarizedSepiaBackgroundHex: UInt32 = 0xF7EEDB
    static let solarizedSepiaBarHex: UInt32 = 0xEDE2CA
    static let solarizedSepiaSecondaryTextHex: UInt32 = 0x665E4E
    static let solarizedSepiaNicknameHexValues: [UInt32] = [
        0x2D6F73, 0x7B5F17, 0x9A4738, 0x8B3F64,
        0x4F5F93, 0x3F6E45, 0x76547E, 0x81532D
    ]
    static let greyscaleBackgroundHex: UInt32 = 0x161616
    static let greyscaleBarHex: UInt32 = 0x101010
    static let greyscaleSecondaryTextHex: UInt32 = 0xA6A6A6
    static let greyscaleNicknameHexValues: [UInt32] = [
        0x8B8B8B, 0x9A9A9A, 0xAAAAAA, 0xBABABA,
        0xCACACA, 0xD9D9D9, 0xE7E7E7, 0xF5F5F5
    ]

    // Latte and Mocha values are adapted from the canonical Catppuccin palette:
    // https://github.com/catppuccin/palette
    static let catppuccinLatte = IRCThemePalette(
        background: Color(hex: catppuccinLatteBackgroundHex),
        bar: Color(hex: catppuccinLatteBarHex),
        panel: Color(hex: 0xE6E9EF),
        field: Color(hex: 0xCCD0DA).opacity(0.62),
        border: Color(hex: 0xBCC0CC),
        text: Color(hex: 0x4C4F69),
        secondaryText: Color(hex: catppuccinLatteSecondaryTextHex),
        accent: Color(hex: 0x8839EF),
        emphasizedBackground: Color(hex: 0xCCD0DA),
        emphasizedText: Color(hex: 0x4C4F69),
        warningSecondaryText: Color(hex: 0x5C5F77),
        prominentButtonText: Color(hex: 0xFFFFFF),
        // These preserve the canonical accent hues while darkening only as
        // needed to remain readable when used as small text on Latte's base.
        nicknameColors: catppuccinLatteNicknameHexValues.map { Color(hex: $0) }
    )

    static let catppuccinMocha = IRCThemePalette(
        background: Color(hex: 0x1E1E2E),
        bar: Color(hex: 0x181825),
        panel: Color(hex: 0x313244),
        field: Color(hex: 0x313244),
        border: Color(hex: 0x45475A),
        text: Color(hex: 0xCDD6F4),
        secondaryText: Color(hex: 0xA6ADC8),
        accent: Color(hex: 0xCBA6F7),
        emphasizedBackground: Color(hex: 0x45475A),
        emphasizedText: Color(hex: 0xCDD6F4),
        warningSecondaryText: Color(hex: 0xA6ADC8),
        prominentButtonText: Color(hex: 0x11111B),
        nicknameColors: [
            Color(hex: 0x89B4FA), Color(hex: 0xCBA6F7),
            Color(hex: 0xFAB387), Color(hex: 0xF5C2E7),
            Color(hex: 0xA6E3A1), Color(hex: 0xB4BEFE),
            Color(hex: 0x94E2D5), Color(hex: 0xF38BA8)
        ]
    )

    // Default light and dark values follow the Primer primitives used by the
    // official GitHub VS Code theme: https://github.com/primer/github-vscode-theme
    static let githubLight = IRCThemePalette(
        background: Color(hex: 0xFFFFFF),
        bar: Color(hex: 0xF6F8FA),
        panel: Color(hex: 0xF6F8FA),
        field: Color(hex: 0xEFF2F5),
        border: Color(hex: 0xD0D7DE),
        text: Color(hex: 0x1F2328),
        secondaryText: Color(hex: 0x656D76),
        accent: Color(hex: 0x0969DA),
        emphasizedBackground: Color(hex: 0xD0D7DE),
        emphasizedText: Color(hex: 0x1F2328),
        warningSecondaryText: Color(hex: 0x656D76),
        prominentButtonText: Color(hex: 0xFFFFFF),
        nicknameColors: [
            Color(hex: 0x0969DA), Color(hex: 0x8250DF),
            Color(hex: 0xBF3989), Color(hex: 0xCF222E),
            Color(hex: 0x953800), Color(hex: 0x4D2D00),
            Color(hex: 0x1A7F37), Color(hex: 0x0A7A83)
        ]
    )

    static let githubDark = IRCThemePalette(
        background: Color(hex: 0x0D1117),
        bar: Color(hex: 0x161B22),
        panel: Color(hex: 0x161B22),
        field: Color(hex: 0x21262D),
        border: Color(hex: 0x30363D),
        text: Color(hex: 0xE6EDF3),
        secondaryText: Color(hex: 0x7D8590),
        accent: Color(hex: 0x2F81F7),
        emphasizedBackground: Color(hex: 0x30363D),
        emphasizedText: Color(hex: 0xE6EDF3),
        warningSecondaryText: Color(hex: 0x7D8590),
        prominentButtonText: Color(hex: 0x0D1117),
        nicknameColors: [
            Color(hex: 0x58A6FF), Color(hex: 0xD2A8FF),
            Color(hex: 0xF778BA), Color(hex: 0xFF7B72),
            Color(hex: 0xFFA657), Color(hex: 0xD29922),
            Color(hex: 0x7EE787), Color(hex: 0x39C5CF)
        ]
    )

    // Adapted from the canonical Rosé Pine Dawn palette. Identity colors retain
    // its muted hues while being darkened enough for small text on the light base.
    static let rosePineDawn = IRCThemePalette(
        background: Color(hex: rosePineDawnBackgroundHex),
        bar: Color(hex: rosePineDawnBarHex),
        panel: Color(hex: 0xFFFAF3),
        field: Color(hex: 0xEAE2DC),
        border: Color(hex: 0xCCC7C2),
        text: Color(hex: 0x575279),
        secondaryText: Color(hex: rosePineDawnSecondaryTextHex),
        accent: Color(hex: 0x286983),
        emphasizedBackground: Color(hex: 0xDFDAD9),
        emphasizedText: Color(hex: 0x575279),
        warningSecondaryText: Color(hex: 0xA14360),
        prominentButtonText: Color(hex: 0xFAF4ED),
        nicknameColors: rosePineDawnNicknameHexValues.map { Color(hex: $0) }
    )

    // Solarized-inspired hues on a warmer parchment base. Large surfaces stay
    // within one sepia family while muted spectrum colors identify participants.
    static let solarizedSepia = IRCThemePalette(
        background: Color(hex: solarizedSepiaBackgroundHex),
        bar: Color(hex: solarizedSepiaBarHex),
        panel: Color(hex: 0xF3E8D3),
        field: Color(hex: 0xE4D8BC),
        border: Color(hex: 0xCBBE9F),
        text: Color(hex: 0x4A4335),
        secondaryText: Color(hex: solarizedSepiaSecondaryTextHex),
        accent: Color(hex: 0x2D6F73),
        emphasizedBackground: Color(hex: 0xDDD0B3),
        emphasizedText: Color(hex: 0x3F392E),
        warningSecondaryText: Color(hex: 0x9A4738),
        prominentButtonText: Color(hex: 0xFFF8E8),
        nicknameColors: solarizedSepiaNicknameHexValues.map { Color(hex: $0) }
    )

    // Adapted from the canonical Rosé Pine palette. The brighter Moon pine is
    // used for small nickname text so every identity color remains readable.
    static let rosePine = IRCThemePalette(
        background: Color(hex: rosePineBackgroundHex),
        bar: Color(hex: rosePineBarHex),
        panel: Color(hex: 0x1F1D2E),
        field: Color(hex: 0x26233A),
        border: Color(hex: 0x524F67),
        text: Color(hex: 0xE0DEF4),
        secondaryText: Color(hex: rosePineSecondaryTextHex),
        accent: Color(hex: 0xEBBCBA),
        emphasizedBackground: Color(hex: 0x403D52),
        emphasizedText: Color(hex: 0xE0DEF4),
        warningSecondaryText: Color(hex: 0xEB6F92),
        prominentButtonText: Color(hex: 0x191724),
        nicknameColors: rosePineNicknameHexValues.map { Color(hex: $0) }
    )

    // A restrained neon palette inspired by Tokyo at night: saturated color is
    // reserved for controls and identities, while large surfaces stay calm.
    static let cyberpunk = IRCThemePalette(
        background: Color(hex: cyberpunkBackgroundHex),
        bar: Color(hex: cyberpunkBarHex),
        panel: Color(hex: 0x171E2E),
        field: Color(hex: 0x202A3D),
        border: Color(hex: 0x34415E),
        text: Color(hex: 0xD7E0FF),
        secondaryText: Color(hex: cyberpunkSecondaryTextHex),
        accent: Color(hex: 0x2FE6D0),
        emphasizedBackground: Color(hex: 0x26334B),
        emphasizedText: Color(hex: 0xF2F5FF),
        warningSecondaryText: Color(hex: 0xFF8FB3),
        prominentButtonText: Color(hex: 0x081319),
        nicknameColors: cyberpunkNicknameHexValues.map { Color(hex: $0) }
    )

    // Inspired by the C64's blue startup screen and 16-color VIC-II palette.
    // Foreground shades are brightened for comfortable reading on modern displays.
    static let c64 = IRCThemePalette(
        background: Color(hex: 0x40318D),
        bar: Color(hex: 0x30246E),
        panel: Color(hex: 0x4B3B9B),
        field: Color(hex: 0x352879),
        border: Color(hex: 0x7869C4),
        text: Color(hex: 0xF4F0FF),
        secondaryText: Color(hex: 0xC8C1F1),
        accent: Color(hex: 0xA99DF5),
        emphasizedBackground: Color(hex: 0x7869C4),
        emphasizedText: Color(hex: 0xFFFFFF),
        warningSecondaryText: Color(hex: 0xF6A09A),
        prominentButtonText: Color(hex: 0x241A58),
        nicknameColors: [
            Color(hex: 0xFFFFFF), Color(hex: 0x8DEDF5),
            Color(hex: 0xB8F5AE), Color(hex: 0xEAF69B),
            Color(hex: 0xF6A09A), Color(hex: 0xF0A0F7),
            Color(hex: 0xF4B27A), Color(hex: 0xB7ABFF)
        ]
    )

    // A neutral dark palette that uses luminance alone for hierarchy. The
    // stepped nickname shades remain distinct without introducing color.
    static let greyscale = IRCThemePalette(
        background: Color(hex: greyscaleBackgroundHex),
        bar: Color(hex: greyscaleBarHex),
        panel: Color(hex: 0x222222),
        field: Color(hex: 0x2A2A2A),
        border: Color(hex: 0x464646),
        text: Color(hex: 0xE8E8E8),
        secondaryText: Color(hex: greyscaleSecondaryTextHex),
        accent: Color(hex: 0xD0D0D0),
        emphasizedBackground: Color(hex: 0x383838),
        emphasizedText: Color(hex: 0xF3F3F3),
        warningSecondaryText: Color(hex: 0xC8C8C8),
        prominentButtonText: Color(hex: 0x101010),
        nicknameColors: greyscaleNicknameHexValues.map { Color(hex: $0) }
    )
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

extension IRCApplicationAppearance {
    var palette: IRCThemePalette? {
        switch self {
        case .system, .light, .dark: return nil
        case .catppuccinLatte: return .catppuccinLatte
        case .catppuccinMocha: return .catppuccinMocha
        case .githubLight: return .githubLight
        case .githubDark: return .githubDark
        case .rosePineDawn: return .rosePineDawn
        case .solarizedSepia: return .solarizedSepia
        case .rosePine: return .rosePine
        case .cyberpunk: return .cyberpunk
        case .c64: return .c64
        case .greyscale: return .greyscale
        }
    }

    var previewColor: Color {
        switch self {
        case .system:
            return Color(nsColor: .controlAccentColor)
        case .light:
            return Color(hex: 0xF2F2F0)
        case .dark:
            return Color(hex: 0x2C2C2E)
        default:
            return palette?.accent ?? .accentColor
        }
    }

    var previewImage: NSImage {
        let image = NSImage(
            size: NSSize(width: 12, height: 12),
            flipped: false
        ) { rect in
            let path = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
            NSColor(previewColor).setFill()
            path.fill()
            NSColor.separatorColor.withAlphaComponent(0.45).setStroke()
            path.lineWidth = 0.5
            path.stroke()
            return true
        }
        image.isTemplate = false
        return image
    }
}

private struct IRCThemePaletteKey: EnvironmentKey {
    static let defaultValue: IRCThemePalette? = nil
}

extension EnvironmentValues {
    var ircThemePalette: IRCThemePalette? {
        get { self[IRCThemePaletteKey.self] }
        set { self[IRCThemePaletteKey.self] = newValue }
    }
}

private struct IRCApplicationAppearanceModifier: ViewModifier {
    let appearance: IRCApplicationAppearance

    @ViewBuilder
    func body(content: Content) -> some View {
        if let palette = appearance.palette {
            content
                .preferredColorScheme(appearance.colorScheme)
                .environment(\.ircThemePalette, palette)
                .tint(palette.accent)
        } else {
            content
                .preferredColorScheme(appearance.colorScheme)
                .environment(\.ircThemePalette, nil)
        }
    }
}

private struct IRCWorkspaceThemeModifier: ViewModifier {
    @Environment(\.ircThemePalette) private var palette

    @ViewBuilder
    func body(content: Content) -> some View {
        if let palette {
            content
                .foregroundStyle(palette.text, palette.secondaryText)
                .background(palette.background.ignoresSafeArea())
                .toolbarBackground(palette.bar, for: .windowToolbar)
                .toolbarBackground(.visible, for: .windowToolbar)
        } else {
            content
        }
    }
}

private struct IRCBarBackgroundModifier: ViewModifier {
    @Environment(\.ircThemePalette) private var palette

    @ViewBuilder
    func body(content: Content) -> some View {
        if let palette {
            content.background(palette.bar)
        } else {
            content.background(.bar)
        }
    }
}

private struct IRCWindowBackgroundModifier: ViewModifier {
    @Environment(\.ircThemePalette) private var palette

    func body(content: Content) -> some View {
        content.background(palette?.background ?? Color(nsColor: .windowBackgroundColor))
    }
}

private struct IRCSidebarBackgroundModifier: ViewModifier {
    @Environment(\.ircThemePalette) private var palette

    @ViewBuilder
    func body(content: Content) -> some View {
        if let palette {
            content
                .scrollContentBackground(.hidden)
                .background(palette.bar)
        } else {
            content
        }
    }
}

private struct IRCControlBackgroundModifier<S: InsettableShape>: ViewModifier {
    @Environment(\.ircThemePalette) private var palette
    let shape: S

    func body(content: Content) -> some View {
        content.background(
            palette?.panel ?? Color(nsColor: .controlBackgroundColor),
            in: shape
        )
    }
}

private struct IRCFieldBackgroundModifier<S: InsettableShape>: ViewModifier {
    @Environment(\.ircThemePalette) private var palette
    let shape: S

    @ViewBuilder
    func body(content: Content) -> some View {
        if let palette {
            content.background(palette.field, in: shape)
        } else {
            content.background(.quaternary, in: shape)
        }
    }
}

private struct IRCBadgeStyleModifier: ViewModifier {
    @Environment(\.ircThemePalette) private var palette

    @ViewBuilder
    func body(content: Content) -> some View {
        if let palette {
            content
                .foregroundStyle(palette.emphasizedText)
                .background(palette.emphasizedBackground, in: Capsule())
        } else {
            content
                .foregroundStyle(.secondary)
                .background(.quaternary, in: Capsule())
        }
    }
}

private struct IRCSecondaryTextModifier: ViewModifier {
    @Environment(\.ircThemePalette) private var palette

    @ViewBuilder
    func body(content: Content) -> some View {
        if let palette {
            content.foregroundStyle(palette.secondaryText)
        } else {
            content.foregroundStyle(.secondary)
        }
    }
}

private struct IRCDividerModifier: ViewModifier {
    @Environment(\.ircThemePalette) private var palette

    @ViewBuilder
    func body(content: Content) -> some View {
        if let palette {
            content
                .overlay(palette.border)
                .opacity(0.65)
        } else {
            content
        }
    }
}

private struct IRCEmphasizedCalloutModifier<S: InsettableShape>: ViewModifier {
    @Environment(\.ircThemePalette) private var palette
    let shape: S

    @ViewBuilder
    func body(content: Content) -> some View {
        if let palette {
            content
                .foregroundStyle(palette.emphasizedText)
                .background(palette.emphasizedBackground, in: shape)
        } else {
            content.background(.quaternary, in: shape)
        }
    }
}

private struct IRCWarningSecondaryTextModifier: ViewModifier {
    @Environment(\.ircThemePalette) private var palette

    @ViewBuilder
    func body(content: Content) -> some View {
        if let palette {
            content.foregroundStyle(palette.warningSecondaryText)
        } else {
            content.foregroundStyle(.secondary)
        }
    }
}

private struct IRCCustomWindowBackgroundModifier: ViewModifier {
    @Environment(\.ircThemePalette) private var palette

    @ViewBuilder
    func body(content: Content) -> some View {
        if let palette {
            content.background(palette.background)
        } else {
            content
        }
    }
}

extension View {
    func ircApplicationAppearance(_ appearance: IRCApplicationAppearance) -> some View {
        modifier(IRCApplicationAppearanceModifier(appearance: appearance))
    }

    func ircWorkspaceTheme() -> some View {
        modifier(IRCWorkspaceThemeModifier())
    }

    func ircBarBackground() -> some View {
        modifier(IRCBarBackgroundModifier())
    }

    func ircWindowBackground() -> some View {
        modifier(IRCWindowBackgroundModifier())
    }

    func ircSidebarBackground() -> some View {
        modifier(IRCSidebarBackgroundModifier())
    }

    func ircControlBackground<S: InsettableShape>(in shape: S) -> some View {
        modifier(IRCControlBackgroundModifier(shape: shape))
    }

    func ircFieldBackground<S: InsettableShape>(in shape: S) -> some View {
        modifier(IRCFieldBackgroundModifier(shape: shape))
    }

    func ircBadgeStyle() -> some View {
        modifier(IRCBadgeStyleModifier())
    }

    func ircSecondaryText() -> some View {
        modifier(IRCSecondaryTextModifier())
    }

    func ircDivider() -> some View {
        modifier(IRCDividerModifier())
    }

    func ircEmphasizedCallout<S: InsettableShape>(in shape: S) -> some View {
        modifier(IRCEmphasizedCalloutModifier(shape: shape))
    }

    func ircWarningSecondaryText() -> some View {
        modifier(IRCWarningSecondaryTextModifier())
    }

    func ircCustomWindowBackground() -> some View {
        modifier(IRCCustomWindowBackgroundModifier())
    }
}
