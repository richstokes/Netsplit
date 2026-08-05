//
//  GitHubLightTheme.swift
//  Netsplit
//

import SwiftUI

extension IRCThemePalette {
  // Values follow the Primer primitives used by the official GitHub VS Code
  // theme: https://github.com/primer/github-vscode-theme
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
      Color(hex: 0x1A7F37), Color(hex: 0x0A7A83),
    ]
  )
}
