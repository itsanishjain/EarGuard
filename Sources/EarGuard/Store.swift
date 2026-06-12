import Foundation

final class Store {
    private(set) var history: HistoryFile
    private let fileURL: URL
    private let calendar = Calendar.autoupdatingCurrent
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var lastFlush = Date.distantPast

    init(fileURL: URL = Store.defaultURL()) {
        self.fileURL = fileURL
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        history = (try? Store.load(from: fileURL, decoder: decoder)) ?? HistoryFile()
    }

    static func defaultURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("EarGuard", isDirectory: true).appendingPathComponent("history.json")
    }

    func today() -> DailyAggregate {
        history.days[dayKey(for: Date())] ?? DailyAggregate()
    }

    func lastDays(_ count: Int) -> [(Date, DailyAggregate)] {
        let todayStart = calendar.startOfDay(for: Date())
        return (0..<count).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: todayStart) else { return nil }
            return (day, history.days[dayKey(for: day)] ?? DailyAggregate())
        }
    }

    func addListeningInterval(from start: Date, to end: Date, volume: Double?, deviceName: String) {
        guard end > start else { return }

        var cursor = start
        while cursor < end {
            let nextMidnight = calendar.nextDate(
                after: cursor,
                matching: DateComponents(hour: 0, minute: 0, second: 0),
                matchingPolicy: .nextTime
            ) ?? end
            let segmentEnd = min(end, nextMidnight)
            addSegment(from: cursor, to: segmentEnd, volume: volume, deviceName: deviceName)
            cursor = segmentEnd
        }
    }

    func flushIfNeeded(force: Bool = false) {
        let now = Date()
        guard force || now.timeIntervalSince(lastFlush) >= 60 else { return }
        do {
            try flush()
            lastFlush = now
        } catch {
            NSLog("EarGuard failed to write history: \(error.localizedDescription)")
        }
    }

    private static func load(from url: URL, decoder: JSONDecoder) throws -> HistoryFile {
        let data = try Data(contentsOf: url)
        return try decoder.decode(HistoryFile.self, from: data)
    }

    private func addSegment(from start: Date, to end: Date, volume: Double?, deviceName: String) {
        let seconds = end.timeIntervalSince(start)
        guard seconds > 0 else { return }

        let key = dayKey(for: start)
        var aggregate = history.days[key] ?? DailyAggregate()
        aggregate.seconds += seconds
        aggregate.byDevice[deviceName, default: 0] += seconds

        if let volume {
            aggregate.volumeWeightedSeconds += volume * seconds
            aggregate.volumeSampledSeconds += seconds
            if volume >= ExposureModel.loudVolumeThreshold {
                aggregate.loudSeconds += seconds
            }
        }

        history.days[key] = aggregate
    }

    private func flush() throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(history)
        try data.write(to: fileURL, options: [.atomic])
    }

    private func dayKey(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}
