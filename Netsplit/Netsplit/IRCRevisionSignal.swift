import Combine
import Foundation

@MainActor
final class IRCRevisionSignal: ObservableObject {
    @Published private(set) var revision = 0

    private let minimumPublicationInterval: Duration?
    private var lastPublication: ContinuousClock.Instant?
    private var pendingPublication: Task<Void, Never>?

    init(minimumPublicationInterval: Duration? = nil) {
        self.minimumPublicationInterval = minimumPublicationInterval
    }

    func advance() {
        guard let minimumPublicationInterval else {
            publish(at: ContinuousClock().now)
            return
        }

        let now = ContinuousClock().now
        if let lastPublication {
            let elapsed = lastPublication.duration(to: now)
            if elapsed < minimumPublicationInterval {
                schedulePublication(after: minimumPublicationInterval - elapsed)
                return
            }
        }

        publish(at: now)
    }

    private func schedulePublication(after delay: Duration) {
        guard pendingPublication == nil else { return }
        pendingPublication = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.pendingPublication = nil
            self.publish(at: ContinuousClock().now)
        }
    }

    private func publish(at instant: ContinuousClock.Instant) {
        lastPublication = instant
        revision &+= 1
    }
}
