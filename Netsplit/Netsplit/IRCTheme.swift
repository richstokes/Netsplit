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

    // Latte and Mocha values are adapted from the canonical Catppuccin palette:
    // https://github.com/catppuccin/palette
    static let catppuccinLatte = IRCThemePalette(
        background: Color(hex: 0xEFF1F5),
        bar: Color(hex: 0xE6E9EF),
        panel: Color(hex: 0xE6E9EF),
        field: Color(hex: 0xCCD0DA).opacity(0.62),
        border: Color(hex: 0xBCC0CC),
        text: Color(hex: 0x4C4F69),
        secondaryText: Color(hex: 0x6C6F85),
        accent: Color(hex: 0x8839EF),
        emphasizedBackground: Color(hex: 0xCCD0DA),
        emphasizedText: Color(hex: 0x4C4F69),
        warningSecondaryText: Color(hex: 0x5C5F77),
        prominentButtonText: Color(hex: 0xFFFFFF),
        nicknameColors: [
            Color(hex: 0x1E66F5), Color(hex: 0x8839EF),
            Color(hex: 0xFE640B), Color(hex: 0xEA76CB),
            Color(hex: 0x40A02B), Color(hex: 0x7287FD),
            Color(hex: 0x179299), Color(hex: 0xD20F39)
        ]
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
        }
    }

    var previewColor: Color {
        palette?.accent ?? .accentColor
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

private struct IRCApplicationThemeModifier: ViewModifier {
    let appearance: IRCApplicationAppearance

    @ViewBuilder
    func body(content: Content) -> some View {
        if let palette = appearance.palette {
            content
                .preferredColorScheme(appearance.colorScheme)
                .environment(\.ircThemePalette, palette)
                .tint(palette.accent)
                .foregroundStyle(palette.text, palette.secondaryText)
                .background(palette.background.ignoresSafeArea())
        } else {
            content
                .preferredColorScheme(appearance.colorScheme)
                .environment(\.ircThemePalette, nil)
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
    func ircApplicationTheme(_ appearance: IRCApplicationAppearance) -> some View {
        modifier(IRCApplicationThemeModifier(appearance: appearance))
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
