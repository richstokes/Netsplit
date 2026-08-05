//
//  CyberpunkTheme.swift
//  Netsplit
//

import SwiftUI

extension IRCThemePalette {
  static let cyberpunkBackgroundHex: UInt32 = 0x101521
  static let cyberpunkBarHex: UInt32 = 0x0B0F19
  static let cyberpunkSecondaryTextHex: UInt32 = 0x9AA8CC
  static let cyberpunkNicknameHexValues: [UInt32] = [
    0x4FE6D5, 0xFF6BCE, 0x9D8CFF, 0x5AAEFF,
    0xFFB454, 0xB7E36A, 0xFFD166, 0xF28FAD,
  ]

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
}
