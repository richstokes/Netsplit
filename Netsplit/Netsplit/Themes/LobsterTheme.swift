//
//  LobsterTheme.swift
//  Netsplit
//

import SwiftUI

extension IRCThemePalette {
  static let lobsterBackgroundHex: UInt32 = 0x111827
  static let lobsterBarHex: UInt32 = 0x0F172A
  static let lobsterSecondaryTextHex: UInt32 = 0xA1A1AA
  static let lobsterNicknameHexValues: [UInt32] = [
    0xFF5C5C, 0x22C55E, 0x3B82F6, 0xF59E0B,
    0xC084FC, 0x2DD4BF, 0xF472B6, 0xFBBF24,
  ]

  // Based on Codex's Lobster theme. Its core colors are preserved exactly;
  // supporting shades extend the navy surface across native macOS controls.
  static let lobster = IRCThemePalette(
    background: Color(hex: lobsterBackgroundHex),
    bar: Color(hex: lobsterBarHex),
    panel: Color(hex: 0x172033),
    field: Color(hex: 0x1F2937),
    border: Color(hex: 0x374151),
    text: Color(hex: 0xE4E4E7),
    secondaryText: Color(hex: lobsterSecondaryTextHex),
    accent: Color(hex: 0xFF5C5C),
    emphasizedBackground: Color(hex: 0x293548),
    emphasizedText: Color(hex: 0xE4E4E7),
    warningSecondaryText: Color(hex: 0xFF5C5C),
    prominentButtonText: Color(hex: 0x111827),
    nicknameColors: lobsterNicknameHexValues.map { Color(hex: $0) }
  )
}
