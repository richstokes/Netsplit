//
//  SolarizedSepiaTheme.swift
//  Netsplit
//

import SwiftUI

extension IRCThemePalette {
  static let solarizedSepiaBackgroundHex: UInt32 = 0xF7EEDB
  static let solarizedSepiaBarHex: UInt32 = 0xEDE2CA
  static let solarizedSepiaSecondaryTextHex: UInt32 = 0x665E4E
  static let solarizedSepiaNicknameHexValues: [UInt32] = [
    0x2D6F73, 0x7B5F17, 0x9A4738, 0x8B3F64,
    0x4F5F93, 0x3F6E45, 0x76547E, 0x81532D,
  ]

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
}
