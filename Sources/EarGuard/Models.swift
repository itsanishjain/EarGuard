import Foundation
import CoreAudio

struct AudioDeviceSnapshot {
    let id: AudioDeviceID
    let name: String
    let transportType: UInt32?
    let dataSource: UInt32?
    let isRunning: Bool
    let volume: Double?

    var isHeadphone: Bool {
        HeadphoneClassifier.isHeadphone(
            transportType: transportType,
            dataSource: dataSource,
            name: name
        )
    }

    var statusText: String {
        if !isHeadphone {
            return "No headphones"
        }
        return "\(name) (\(isRunning ? "playing" : "connected, silent"))"
    }
}

struct DailyAggregate: Codable {
    var seconds: TimeInterval
    var volumeWeightedSeconds: Double
    var volumeSampledSeconds: TimeInterval
    var loudSeconds: TimeInterval
    var byDevice: [String: TimeInterval]

    init(
        seconds: TimeInterval = 0,
        volumeWeightedSeconds: Double = 0,
        volumeSampledSeconds: TimeInterval = 0,
        loudSeconds: TimeInterval = 0,
        byDevice: [String: TimeInterval] = [:]
    ) {
        self.seconds = seconds
        self.volumeWeightedSeconds = volumeWeightedSeconds
        self.volumeSampledSeconds = volumeSampledSeconds
        self.loudSeconds = loudSeconds
        self.byDevice = byDevice
    }

    enum CodingKeys: String, CodingKey {
        case seconds
        case volumeWeightedSeconds
        case volumeSampledSeconds
        case loudSeconds
        case byDevice
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        seconds = try container.decodeIfPresent(TimeInterval.self, forKey: .seconds) ?? 0
        volumeWeightedSeconds = try container.decodeIfPresent(Double.self, forKey: .volumeWeightedSeconds) ?? 0
        volumeSampledSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .volumeSampledSeconds) ?? seconds
        loudSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .loudSeconds) ?? 0
        byDevice = try container.decodeIfPresent([String: TimeInterval].self, forKey: .byDevice) ?? [:]
    }

    var averageVolume: Double? {
        guard volumeSampledSeconds > 0 else { return nil }
        return volumeWeightedSeconds / volumeSampledSeconds
    }
}

struct HistoryFile: Codable {
    var days: [String: DailyAggregate]

    init(days: [String: DailyAggregate] = [:]) {
        self.days = days
    }
}

enum Formatters {
    static func duration(_ seconds: TimeInterval, compact: Bool = false) -> String {
        let totalMinutes = max(0, Int(seconds.rounded(.down)) / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if compact {
            return "\(hours):\(String(format: "%02d", minutes))"
        }
        if hours == 0 {
            return "\(minutes)m"
        }
        return "\(hours)h \(minutes)m"
    }

    static func volume(_ value: Double?) -> String {
        guard let value else { return "n/a" }
        return "\(Int((value * 100).rounded()))%"
    }
}
