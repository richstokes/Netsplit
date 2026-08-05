//
//  CatppuccinLatteTheme.swift
//  Netsplit
//

import SwiftUI

extension IRCThemePalette {
  static let catppuccinLatteBackgroundHex: UInt32 = 0xEFF1F5
  static let catppuccinLatteBarHex: UInt32 = 0xE6E9EF
  static let catppuccinLatteSecondaryTextHex: UInt32 = 0x5C5F77
  static let catppuccinLatteNicknameHexValues: [UInt32] = [
    0x1C60E6, 0x8839EF, 0xB44708, 0x9D4F88,
    0x307820, 0x5363B9, 0x12757A, 0xD20F39,
  ]

  // Values are adapted from the canonical Catppuccin palette:
  // https://github.com/catppuccin/palette
  static let catppuccinLatte = IRCThemePalette(
    background: Color(hex: catppuccinLatteBackgroundHex),
    bar: Color(hex: catppuccinLatteBarHex),
    panel: Color(hex: 0xE6E9EF),
    field: Color(hex: 0xCCD0DA).opacity(0.62),
    border: Color(hex: 0xBCC0CC),
    text: Color(hex: 0x4C4F69),
    secondaryText: Color(hex: catppuccinLatteSecondaryTextHex),
    accent: Color(hex: 0x8839EF),
    emphasizedBackground: Color(hex: 0xCCD0DA),
    emphasizedText: Color(hex: 0x4C4F69),
    warningSecondaryText: Color(hex: 0x5C5F77),
    prominentButtonText: Color(hex: 0xFFFFFF),
    // These preserve the canonical accent hues while darkening only as
    // needed to remain readable when used as small text on Latte's base.
    nicknameColors: catppuccinLatteNicknameHexValues.map { Color(hex: $0) }
  )
}
