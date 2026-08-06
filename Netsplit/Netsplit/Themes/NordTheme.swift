//
//  NordTheme.swift
//  Netsplit
//

import SwiftUI

extension IRCThemePalette {
  static let nordBackgroundHex: UInt32 = 0x2E3440
  static let nordBarHex: UInt32 = 0x272C36
  static let nordSecondaryTextHex: UInt32 = 0xD8DEE9
  static let nordNicknameHexValues: [UInt32] = [
    0x88C0D0, 0x81A1C1, 0x8FBCBB, 0xA3BE8C,
    0xEBCB8B, 0xD98975, 0xC39BBB, 0xDD818B,
  ]

  // Adapted from Nord's polar-night and aurora palettes. The warm identity
  // colors are lifted slightly to preserve normal-text contrast.
  static let nord = IRCThemePalette(
    background: Color(hex: nordBackgroundHex),
    bar: Color(hex: nordBarHex),
    panel: Color(hex: 0x3B4252),
    field: Color(hex: 0x434C5E),
    border: Color(hex: 0x4C566A),
    text: Color(hex: 0xECEFF4),
    secondaryText: Color(hex: nordSecondaryTextHex),
    accent: Color(hex: 0x88C0D0),
    emphasizedBackground: Color(hex: 0x4C566A),
    emphasizedText: Color(hex: 0xECEFF4),
    warningSecondaryText: Color(hex: 0xDD818B),
    prominentButtonText: Color(hex: 0x2E3440),
    nicknameColors: nordNicknameHexValues.map { Color(hex: $0) }
  )
}
