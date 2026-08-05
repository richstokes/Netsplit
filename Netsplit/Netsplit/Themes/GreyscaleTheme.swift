//
//  GreyscaleTheme.swift
//  Netsplit
//

import SwiftUI

extension IRCThemePalette {
  static let greyscaleBackgroundHex: UInt32 = 0x161616
  static let greyscaleBarHex: UInt32 = 0x101010
  static let greyscaleSecondaryTextHex: UInt32 = 0xA6A6A6
  static let greyscaleNicknameHexValues: [UInt32] = [
    0x8B8B8B, 0x9A9A9A, 0xAAAAAA, 0xBABABA,
    0xCACACA, 0xD9D9D9, 0xE7E7E7, 0xF5F5F5,
  ]

  // A neutral dark palette that uses luminance alone for hierarchy. The
  // stepped nickname shades remain distinct without introducing color.
  static let greyscale = IRCThemePalette(
    background: Color(hex: greyscaleBackgroundHex),
    bar: Color(hex: greyscaleBarHex),
    panel: Color(hex: 0x222222),
    field: Color(hex: 0x2A2A2A),
    border: Color(hex: 0x464646),
    text: Color(hex: 0xE8E8E8),
    secondaryText: Color(hex: greyscaleSecondaryTextHex),
    accent: Color(hex: 0xD0D0D0),
    emphasizedBackground: Color(hex: 0x383838),
    emphasizedText: Color(hex: 0xF3F3F3),
    warningSecondaryText: Color(hex: 0xC8C8C8),
    prominentButtonText: Color(hex: 0x101010),
    nicknameColors: greyscaleNicknameHexValues.map { Color(hex: $0) }
  )
}
