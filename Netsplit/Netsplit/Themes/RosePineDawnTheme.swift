//
//  RosePineDawnTheme.swift
//  Netsplit
//

import SwiftUI

extension IRCThemePalette {
  static let rosePineDawnBackgroundHex: UInt32 = 0xFAF4ED
  static let rosePineDawnBarHex: UInt32 = 0xF2E9E1
  static let rosePineDawnSecondaryTextHex: UInt32 = 0x625D75
  static let rosePineDawnNicknameHexValues: [UInt32] = [
    0x286983, 0xA14360, 0x6E5A8A, 0xA8504D,
    0x8A5900, 0x356C75, 0x625D75, 0x3F5F8F,
  ]

  // Adapted from the canonical Rosé Pine Dawn palette. Identity colors retain
  // its muted hues while being darkened enough for small text on the light base.
  static let rosePineDawn = IRCThemePalette(
    background: Color(hex: rosePineDawnBackgroundHex),
    bar: Color(hex: rosePineDawnBarHex),
    panel: Color(hex: 0xFFFAF3),
    field: Color(hex: 0xEAE2DC),
    border: Color(hex: 0xCCC7C2),
    text: Color(hex: 0x575279),
    secondaryText: Color(hex: rosePineDawnSecondaryTextHex),
    accent: Color(hex: 0x286983),
    emphasizedBackground: Color(hex: 0xDFDAD9),
    emphasizedText: Color(hex: 0x575279),
    warningSecondaryText: Color(hex: 0xA14360),
    prominentButtonText: Color(hex: 0xFAF4ED),
    nicknameColors: rosePineDawnNicknameHexValues.map { Color(hex: $0) }
  )
}
