//
//  C64Theme.swift
//  Netsplit
//

import SwiftUI

extension IRCThemePalette {
  // Inspired by the C64's blue startup screen and 16-color VIC-II palette.
  // Foreground shades are brightened for comfortable reading on modern displays.
  static let c64 = IRCThemePalette(
    background: Color(hex: 0x40318D),
    bar: Color(hex: 0x30246E),
    panel: Color(hex: 0x4B3B9B),
    field: Color(hex: 0x352879),
    border: Color(hex: 0x7869C4),
    text: Color(hex: 0xF4F0FF),
    secondaryText: Color(hex: 0xC8C1F1),
    accent: Color(hex: 0xA99DF5),
    emphasizedBackground: Color(hex: 0x7869C4),
    emphasizedText: Color(hex: 0xFFFFFF),
    warningSecondaryText: Color(hex: 0xF6A09A),
    prominentButtonText: Color(hex: 0x241A58),
    nicknameColors: [
      Color(hex: 0xFFFFFF), Color(hex: 0x8DEDF5),
      Color(hex: 0xB8F5AE), Color(hex: 0xEAF69B),
      Color(hex: 0xF6A09A), Color(hex: 0xF0A0F7),
      Color(hex: 0xF4B27A), Color(hex: 0xB7ABFF),
    ]
  )
}
