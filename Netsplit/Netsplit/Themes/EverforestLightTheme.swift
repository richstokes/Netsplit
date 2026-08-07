//
//  EverforestLightTheme.swift
//  Netsplit
//

import SwiftUI

extension IRCThemePalette {
  static let everforestLightBackgroundHex: UInt32 = 0xFDF6E3
  static let everforestLightBarHex: UInt32 = 0xEFEBD4
  static let everforestLightSecondaryTextHex: UInt32 = 0x5C6A72
  static let everforestLightNicknameHexValues: [UInt32] = [
    0xB34240, 0xA65418, 0x7A5D00, 0x586900,
    0x186B51, 0x206584, 0x8B3F75, 0x53665D,
  ]

  // Adapted from the canonical Everforest Light medium palette:
  // https://github.com/sainnhe/everforest/blob/master/palette.md
  // Identity hues are darkened for normal-size text on the light background.
  static let everforestLight = IRCThemePalette(
    background: Color(hex: everforestLightBackgroundHex),
    bar: Color(hex: everforestLightBarHex),
    panel: Color(hex: 0xF4F0D9),
    field: Color(hex: 0xE6E2CC),
    border: Color(hex: 0xBDC3AF),
    text: Color(hex: 0x3F4D54),
    secondaryText: Color(hex: everforestLightSecondaryTextHex),
    accent: Color(hex: 0x267A5E),
    emphasizedBackground: Color(hex: 0xEAEDC8),
    emphasizedText: Color(hex: 0x3F4D54),
    warningSecondaryText: Color(hex: 0xB34240),
    prominentButtonText: Color(hex: 0xFFFBEF),
    nicknameColors: everforestLightNicknameHexValues.map { Color(hex: $0) }
  )
}
