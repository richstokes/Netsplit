//
//  IRCTheme.swift
//  Netsplit
//

import SwiftUI

struct IRCConnectionPresentation {
  let title: String
  let description: String
  let connectingLabel: String
  let fontDesign: Font.Design
}

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
}

extension Color {
  init(hex: UInt32) {
    self.init(
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255
    )
  }
}

extension IRCApplicationAppearance {
  var connectionPresentation: IRCConnectionPresentation {
    let standardDescription =
      "Choose a network to connect, or add a profile for your own server. Active networks and their channels stay focused in the sidebar."
    let profileDescription =
      "Choose a server profile to connect. Active networks and channels remain available in the sidebar."

    switch self {
    case .system, .light, .dark:
      return IRCConnectionPresentation(
        title: "Connections",
        description: standardDescription,
        connectingLabel: "Connecting…",
        fontDesign: .default
      )
    case .catppuccinLatte, .catppuccinMocha:
      return IRCConnectionPresentation(
        title: "Network Connections",
        description: profileDescription,
        connectingLabel: "Opening connection…",
        fontDesign: .rounded
      )
    case .githubLight, .githubDark:
      return IRCConnectionPresentation(
        title: "Server Connections",
        description: profileDescription,
        connectingLabel: "Connecting to server…",
        fontDesign: .default
      )
    case .rosePineDawn, .rosePine:
      return IRCConnectionPresentation(
        title: "Networks",
        description: profileDescription,
        connectingLabel: "Joining network…",
        fontDesign: .rounded
      )
    case .solarizedSepia:
      return IRCConnectionPresentation(
        title: "Network Directory",
        description: profileDescription,
        connectingLabel: "Opening connection…",
        fontDesign: .default
      )
    case .cyberpunk:
      return IRCConnectionPresentation(
        title: "COMMUNICATION LINKS",
        description:
          "Select a server profile to establish a network link. Active links remain available in the sidebar.",
        connectingLabel: "ESTABLISHING LINK…",
        fontDesign: .monospaced
      )
    case .c64:
      return IRCConnectionPresentation(
        title: "READY.",
        description:
          "SELECT A SERVER PROFILE TO CONNECT. ACTIVE NETWORKS AND CHANNELS APPEAR IN THE SIDEBAR.",
        connectingLabel: "CONNECTING...",
        fontDesign: .monospaced
      )
    case .greyscale:
      return IRCConnectionPresentation(
        title: "Connections",
        description:
          "Select a server profile to connect. Active networks and channels remain in the sidebar.",
        connectingLabel: "Connecting…",
        fontDesign: .default
      )
    }
  }

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
