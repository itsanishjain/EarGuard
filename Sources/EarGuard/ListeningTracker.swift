import Foundation
import AppKit

final class ListeningTracker {
    var onStateChanged: (() -> Void)?

    private let monitor: AudioDeviceMonitor
    private let store: Store
    private let exposureModel: ExposureModel
    private let notifier: Notifier
    private var tickTimer: Timer?
    private var currentDeviceName: String?
    private var sessionStartedAt: Date?
    private var lastSampleDate: Date?

    var isCounting: Bool {
        lastSampleDate != nil
    }

    var warningIsActive: Bool {
        exposureModel.isWarningActive
    }

    var loudSecondsInWindow: TimeInterval {
        exposureModel.loudSecondsInWindow()
    }

    var currentSessionSeconds: TimeInterval {
        guard let sessionStartedAt else { return 0 }
        return Date().timeIntervalSince(sessionStartedAt)
    }

    init(monitor: AudioDeviceMonitor, store: Store, exposureModel: ExposureModel, notifier: Notifier) {
        self.monitor = monitor
        self.store = store
        self.exposureModel = exposureModel
        self.notifier = notifier

        monitor.onSnapshotChanged = { [weak self] snapshot in
            self?.evaluate(snapshot: snapshot)
        }
    }

    func start() {
        if let snapshot = monitor.snapshot {
            evaluate(snapshot: snapshot)
        } else {
            monitor.refresh()
        }
    }

    func closeSessionAndFlush() {
        closeSession(at: Date())
        store.flushIfNeeded(force: true)
    }

    func handleSleep() {
        closeSessionAndFlush()
    }

    func handleWake() {
        exposureModel.reset()
        monitor.refresh()
    }

    private func evaluate(snapshot: AudioDeviceSnapshot) {
        let shouldCount = snapshot.isHeadphone && snapshot.isRunning

        if shouldCount {
            if !isCounting {
                openSession(deviceName: snapshot.name, at: Date())
            } else if currentDeviceName != snapshot.name {
                let now = Date()
                sampleThrough(date: now)
                currentDeviceName = snapshot.name
                lastSampleDate = now
            }
            ensureTimer()
        } else if isCounting {
            closeSession(at: Date())
        }

        onStateChanged?()
    }

    private func openSession(deviceName: String, at date: Date) {
        currentDeviceName = deviceName
        sessionStartedAt = date
        lastSampleDate = date
        ensureTimer()
    }

    private func closeSession(at date: Date) {
        sampleThrough(date: date)
        lastSampleDate = nil
        sessionStartedAt = nil
        currentDeviceName = nil
        tickTimer?.invalidate()
        tickTimer = nil
        store.flushIfNeeded(force: true)
        onStateChanged?()
    }

    private func ensureTimer() {
        guard tickTimer == nil else { return }
        tickTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(tickTimer!, forMode: .common)
    }

    private func tick() {
        monitor.refresh()
        sampleThrough(date: Date())
        store.flushIfNeeded()
        onStateChanged?()
    }

    private func sampleThrough(date: Date) {
        guard
            let start = lastSampleDate,
            let deviceName = currentDeviceName,
            date > start
        else {
            return
        }

        let snapshot = monitor.snapshot
        let volume = snapshot?.volume
        store.addListeningInterval(from: start, to: date, volume: volume, deviceName: deviceName)

        let seconds = date.timeIntervalSince(start)
        if exposureModel.addSample(seconds: seconds, volume: volume, at: date) {
            notifier.sendLoudListeningWarning()
        }

        lastSampleDate = date
    }
}
