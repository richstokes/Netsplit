//
//  GitHubDarkTheme.swift
//  Netsplit
//

import SwiftUI

extension IRCThemePalette {
  // Values follow the Primer primitives used by the official GitHub VS Code
  // theme: https://github.com/primer/github-vscode-theme
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
      Color(hex: 0x7EE787), Color(hex: 0x39C5CF),
    ]
  )
}
