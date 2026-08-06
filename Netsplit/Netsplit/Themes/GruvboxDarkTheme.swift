//
//  GruvboxDarkTheme.swift
//  Netsplit
//

import SwiftUI

extension IRCThemePalette {
  static let gruvboxDarkBackgroundHex: UInt32 = 0x282828
  static let gruvboxDarkBarHex: UInt32 = 0x1D2021
  static let gruvboxDarkSecondaryTextHex: UInt32 = 0xBDAE93
  static let gruvboxDarkNicknameHexValues: [UInt32] = [
    0x83A598, 0xD3869B, 0xFE8019, 0xFABD2F,
    0xB8BB26, 0x8EC07C, 0xFB5B4B, 0xD5C4A1,
  ]

  // Adapted from Gruvbox's warm retro palette. The red identity color is
  // slightly brightened so every nickname remains readable at normal sizes.
  static let gruvboxDark = IRCThemePalette(
    background: Color(hex: gruvboxDarkBackgroundHex),
    bar: Color(hex: gruvboxDarkBarHex),
    panel: Color(hex: 0x32302F),
    field: Color(hex: 0x3C3836),
    border: Color(hex: 0x665C54),
    text: Color(hex: 0xEBDBB2),
    secondaryText: Color(hex: gruvboxDarkSecondaryTextHex),
    accent: Color(hex: 0xFE8019),
    emphasizedBackground: Color(hex: 0x504945),
    emphasizedText: Color(hex: 0xFBF1C7),
    warningSecondaryText: Color(hex: 0xFB5B4B),
    prominentButtonText: Color(hex: 0x282828),
    nicknameColors: gruvboxDarkNicknameHexValues.map { Color(hex: $0) }
  )
}
