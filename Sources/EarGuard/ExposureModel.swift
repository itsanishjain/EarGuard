import Foundation

final class ExposureModel {
    static let loudVolumeThreshold = 0.75
    private static let rollingWindow: TimeInterval = 30 * 60
    private static let loudWindowThreshold: TimeInterval = 25 * 60
    private static let warningCooldown: TimeInterval = 60 * 60

    private struct Sample {
        let date: Date
        let seconds: TimeInterval
        let isLoud: Bool
    }

    private var samples: [Sample] = []
    private var lastWarningDate = Date.distantPast
    private(set) var isWarningActive = false

    func addSample(seconds: TimeInterval, volume: Double?, at date: Date = Date()) -> Bool {
        guard let volume else {
            prune(now: date)
            isWarningActive = false
            return false
        }

        samples.append(Sample(date: date, seconds: seconds, isLoud: volume >= Self.loudVolumeThreshold))
        prune(now: date)

        let loudSeconds = samples.filter(\.isLoud).reduce(0) { $0 + $1.seconds }
        isWarningActive = loudSeconds >= Self.loudWindowThreshold

        if isWarningActive && date.timeIntervalSince(lastWarningDate) >= Self.warningCooldown {
            lastWarningDate = date
            return true
        }
        return false
    }

    func loudSecondsInWindow(now: Date = Date()) -> TimeInterval {
        prune(now: now)
        return samples.filter(\.isLoud).reduce(0) { $0 + $1.seconds }
    }

    func reset() {
        samples.removeAll()
        isWarningActive = false
    }

    private func prune(now: Date) {
        let cutoff = now.addingTimeInterval(-Self.rollingWindow)
        samples.removeAll { $0.date < cutoff }
    }
}
