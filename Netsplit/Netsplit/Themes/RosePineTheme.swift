//
//  RosePineTheme.swift
//  Netsplit
//

import SwiftUI

extension IRCThemePalette {
  static let rosePineBackgroundHex: UInt32 = 0x191724
  static let rosePineBarHex: UInt32 = 0x1F1D2E
  static let rosePineSecondaryTextHex: UInt32 = 0x908CAA
  static let rosePineNicknameHexValues: [UInt32] = [
    0x9CCFD8, 0xC4A7E7, 0xF6C177, 0xEBBCBA,
    0xEB6F92, 0x3E8FB0, 0x908CAA, 0xE0DEF4,
  ]

  // Adapted from the canonical Rosé Pine palette. The brighter Moon pine is
  // used for small nickname text so every identity color remains readable.
  static let rosePine = IRCThemePalette(
    background: Color(hex: rosePineBackgroundHex),
    bar: Color(hex: rosePineBarHex),
    panel: Color(hex: 0x1F1D2E),
    field: Color(hex: 0x26233A),
    border: Color(hex: 0x524F67),
    text: Color(hex: 0xE0DEF4),
    secondaryText: Color(hex: rosePineSecondaryTextHex),
    accent: Color(hex: 0xEBBCBA),
    emphasizedBackground: Color(hex: 0x403D52),
    emphasizedText: Color(hex: 0xE0DEF4),
    warningSecondaryText: Color(hex: 0xEB6F92),
    prominentButtonText: Color(hex: 0x191724),
    nicknameColors: rosePineNicknameHexValues.map { Color(hex: $0) }
  )
}
