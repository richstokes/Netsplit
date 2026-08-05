//
//  CatppuccinMochaTheme.swift
//  Netsplit
//

import SwiftUI

extension IRCThemePalette {
  // Values are adapted from the canonical Catppuccin palette:
  // https://github.com/catppuccin/palette
  static let catppuccinMocha = IRCThemePalette(
    background: Color(hex: 0x1E1E2E),
    bar: Color(hex: 0x181825),
    panel: Color(hex: 0x313244),
    field: Color(hex: 0x313244),
    border: Color(hex: 0x45475A),
    text: Color(hex: 0xCDD6F4),
    secondaryText: Color(hex: 0xA6ADC8),
    accent: Color(hex: 0xCBA6F7),
    emphasizedBackground: Color(hex: 0x45475A),
    emphasizedText: Color(hex: 0xCDD6F4),
    warningSecondaryText: Color(hex: 0xA6ADC8),
    prominentButtonText: Color(hex: 0x11111B),
    nicknameColors: [
      Color(hex: 0x89B4FA), Color(hex: 0xCBA6F7),
      Color(hex: 0xFAB387), Color(hex: 0xF5C2E7),
      Color(hex: 0xA6E3A1), Color(hex: 0xB4BEFE),
      Color(hex: 0x94E2D5), Color(hex: 0xF38BA8),
    ]
  )
}
