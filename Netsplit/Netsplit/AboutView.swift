//
//  AboutView.swift
//  Netsplit
//

import AppKit
import SwiftUI

struct AboutView: View {
  private let website = URL(string: "https://github.com/richstokes/Netsplit")!
  private let supportWebsite = URL(string: "https://buymeacoffee.com/richstokes")!

  private var version: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.5"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .top, spacing: 20) {
        Image(nsImage: NSApp.applicationIconImage)
          .resizable()
          .interpolation(.high)
          .frame(width: 88, height: 88)
          .accessibilityLabel("Netsplit app icon")

        VStack(alignment: .leading, spacing: 3) {
          HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text("Netsplit")
              .font(.title3.weight(.semibold))
            Text("v\(version)")
              .font(.callout)
              .foregroundStyle(.secondary)
          }

          Text("Internet Relay Chat Client")
            .font(.callout)

          Text("By Rich Stokes")
            .font(.callout)
            .padding(.top, 7)

          Text("Copyright © 2026 Rich Stokes")
            .font(.callout)
            .padding(.top, 7)

          Link(destination: website) {
            Text("github.com/richstokes/Netsplit")
              .font(.callout)
          }
          .padding(.top, 7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        Image("AboutPortrait")
          .resizable()
          .scaledToFill()
          .frame(width: 96, height: 96)
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
          .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
              .stroke(.separator, lineWidth: 1)
          }
          .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
          .accessibilityLabel("Rich Stokes")
      }

      Divider()
        .padding(.vertical, 20)

      HStack(spacing: 10) {
        Image(systemName: "quote.opening")
          .font(.body.weight(.semibold))
          .foregroundStyle(.secondary)

        Text("If you ain’t first, you’re last!")
          .font(.system(.body, design: .rounded, weight: .medium))
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 14)
      .padding(.vertical, 12)
      .background(.quaternary, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

      Divider()
        .padding(.vertical, 20)

      HStack(spacing: 5) {
        Text("Enjoying Netsplit? Feel free to show your support!")
          .foregroundStyle(.secondary)

        Link("Buy me a coffee", destination: supportWebsite)
      }
      .font(.callout)
      .frame(maxWidth: .infinity, alignment: .center)
    }
    .padding(28)
    .frame(width: 540)
    .fixedSize(horizontal: false, vertical: true)
  }
}

#Preview {
  AboutView()
}
