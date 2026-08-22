//
//  DCCFileTransferWindow.swift
//  Netsplit
//

import SwiftUI

enum DCCFileTransferWindow {
    static let sceneID = "dcc-file-transfers"
}

struct DCCFileTransferWindowView: View {
    @ObservedObject var transferStore: IRCDCCFileTransferStore
    let cancel: (IRCDCCFileTransferPresentation) -> Void
    let dismiss: (IRCDCCFileTransferPresentation) -> Void
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        Group {
            if transferStore.transfers.isEmpty {
                ContentUnavailableView(
                    "No Active Transfers",
                    systemImage: "arrow.down.doc",
                    description: Text("Accepted file transfers will appear here.")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(transferStore.transfers) { transfer in
                            DCCFileTransferProgressView(
                                transfer: transfer,
                                cancel: { cancel(transfer) },
                                dismiss: { dismiss(transfer) }
                            )
                            .padding(20)

                            if transfer.id != transferStore.transfers.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
        .frame(minWidth: 480, idealWidth: 560, minHeight: 210, idealHeight: 280)
        .onAppear {
            dismissIfInactive()
        }
        .onChange(of: transferStore.transfers.count) { oldCount, newCount in
            guard oldCount > 0, newCount == 0 else { return }
            dismissWindow(id: DCCFileTransferWindow.sceneID)
        }
    }

    private func dismissIfInactive() {
        guard transferStore.transfers.isEmpty else { return }
        dismissWindow(id: DCCFileTransferWindow.sceneID)
    }
}

private struct DCCFileTransferProgressView: View {
    let transfer: IRCDCCFileTransferPresentation
    let cancel: () -> Void
    let dismiss: () -> Void

    private var offer: IRCDCCFileOffer { transfer.offer }
    private var progress: IRCDCCTransferProgress { transfer.progress }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: statusIcon)
                    .font(.system(size: 26))
                    .foregroundStyle(statusColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(offer.request.filename)
                        .font(.headline)
                        .lineLimit(2)
                        .textSelection(.enabled)
                    Text(statusSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if let outcome = transfer.outcome {
                terminalStatus(outcome)
            } else if let fractionCompleted = progress.fractionCompleted {
                ProgressView(value: fractionCompleted)
                    .progressViewStyle(.linear)
                    .animation(.easeOut(duration: 0.15), value: fractionCompleted)
                    .accessibilityLabel("Download progress for \(offer.request.filename)")
                    .accessibilityValue(progressAccessibilityValue(fractionCompleted))

                HStack(spacing: 12) {
                    Text("\(formattedByteCount(progress.receivedByteCount)) of \(formattedByteCount(progress.totalByteCount))")
                    Spacer()
                    if progress.phase == .receiving {
                        if let bytesPerSecond = progress.bytesPerSecond {
                            Text("\(formattedSpeed(bytesPerSecond))")
                                .accessibilityLabel("Current download speed \(formattedSpeed(bytesPerSecond))")
                        } else {
                            Text("Calculating speed…")
                        }
                    }
                    Text(fractionCompleted.formatted(.percent.precision(.fractionLength(0))))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

                if progress.phase == .finalizing {
                    Label("Finishing download…", systemImage: "externaldrive.badge.timemachine")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Connecting to file sender")
                    Text("Connecting to \(offer.endpointLabel)…")
                        .foregroundStyle(.secondary)
                }
            }

            HStack(alignment: .firstTextBaseline) {
                if transfer.outcome == nil {
                    Text("Saving to \(displayPath(proposedDestination))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 16)
                if transfer.outcome == nil {
                    Button("Cancel Download", role: .destructive, action: cancel)
                } else {
                    Button("Dismiss", action: dismiss)
                }
            }
        }
    }

    private var statusIcon: String {
        switch transfer.outcome {
        case .completed:
            "checkmark.circle.fill"
        case .failed:
            "exclamationmark.triangle.fill"
        case .canceled:
            "xmark.circle.fill"
        case nil:
            "arrow.down.doc.fill"
        }
    }

    private var statusColor: Color {
        switch transfer.outcome {
        case .completed:
            .green
        case .failed:
            .red
        case .canceled:
            .secondary
        case nil:
            .accentColor
        }
    }

    private var statusSubtitle: String {
        switch transfer.outcome {
        case .completed:
            "Download complete"
        case .failed:
            "Download failed"
        case .canceled:
            "Download canceled"
        case nil:
            "From \(offer.sender) on \(offer.networkName)"
        }
    }

    @ViewBuilder
    private func terminalStatus(_ outcome: IRCDCCFileTransferOutcome) -> some View {
        switch outcome {
        case .completed(let destination):
            Label("Saved to \(displayPath(destination))", systemImage: "folder.fill")
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        case .failed(let message):
            Text(message)
                .foregroundStyle(.red)
                .textSelection(.enabled)
        case .canceled:
            Text("No file was saved.")
                .foregroundStyle(.secondary)
        }
    }

    private func displayPath(_ url: URL) -> String {
        url.dccDisplayPath
    }

    private var proposedDestination: URL {
        transfer.downloadDirectory.appendingPathComponent(
            offer.request.filename,
            isDirectory: false
        )
    }

    private func progressAccessibilityValue(_ fractionCompleted: Double) -> String {
        let percent = fractionCompleted.formatted(.percent.precision(.fractionLength(0)))
        guard let bytesPerSecond = progress.bytesPerSecond else { return percent }
        return "\(percent), \(formattedSpeed(bytesPerSecond))"
    }

    private func formattedSpeed(_ bytesPerSecond: Double) -> String {
        // Keep the floating-point-to-integer conversion safely below Int64's
        // boundary even if a malformed model value reaches this view.
        let safelyRepresentableMaximum = 9_000_000_000_000_000_000.0
        guard bytesPerSecond < safelyRepresentableMaximum else { return "Over 9 EB/s" }
        return "\(ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond), countStyle: .file))/s"
    }

    private func formattedByteCount(_ byteCount: UInt64) -> String {
        guard byteCount <= UInt64(Int64.max) else {
            return "\(byteCount.formatted()) bytes"
        }
        return ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
    }
}
