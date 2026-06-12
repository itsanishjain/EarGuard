import AppKit
import ServiceManagement

final class StatusItemController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let dashboardController = DashboardWindowController()
    private let store: Store
    private let monitor: AudioDeviceMonitor
    private let tracker: ListeningTracker
    private var refreshTimer: Timer?

    init(store: Store, monitor: AudioDeviceMonitor, tracker: ListeningTracker) {
        self.store = store
        self.monitor = monitor
        self.tracker = tracker
        super.init()
        configure()
    }

    func refresh() {
        let today = store.today()
        let iconName = tracker.warningIsActive ? "headphones.circle.fill" : "headphones"

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: iconName, accessibilityDescription: "EarGuard")
            button.imagePosition = .imageLeading
            button.title = Formatters.menuBarDuration(today.seconds)
        }

        statusItem.menu = buildMenu()
        dashboardController.refresh(model: makeDashboardModel())
    }

    private func configure() {
        refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        if let refreshTimer {
            RunLoop.main.add(refreshTimer, forMode: .common)
        }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        let today = store.today()

        let todayItem = NSMenuItem(
            title: "Today: \(Formatters.duration(today.seconds))  ·  avg today \(Formatters.volume(today.averageVolume))",
            action: nil,
            keyEquivalent: ""
        )
        todayItem.isEnabled = false
        menu.addItem(todayItem)

        let nowItem = NSMenuItem(title: nowText(), action: nil, keyEquivalent: "")
        nowItem.isEnabled = false
        menu.addItem(nowItem)

        if tracker.isCounting {
            let sessionItem = NSMenuItem(
                title: "Current session: \(Formatters.duration(tracker.currentSessionSeconds))",
                action: nil,
                keyEquivalent: ""
            )
            sessionItem.isEnabled = false
            menu.addItem(sessionItem)
        }

        menu.addItem(.separator())
        let openDashboardItem = NSMenuItem(title: "Open Dashboard...", action: #selector(openDashboard), keyEquivalent: "d")
        openDashboardItem.target = self
        menu.addItem(openDashboardItem)

        menu.addItem(.separator())
        let heading = NSMenuItem(title: "Last 7 days", action: nil, keyEquivalent: "")
        heading.isEnabled = false
        menu.addItem(heading)

        let maxSeconds = max(1, store.lastDays(7).map { $0.1.seconds }.max() ?? 1)
        for (date, aggregate) in store.lastDays(7) {
            let title = "\(dayFormatter.string(from: date))      \(Formatters.duration(aggregate.seconds).padding(toLength: 7, withPad: " ", startingAt: 0)) \(bar(for: aggregate.seconds, max: maxSeconds))"
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }

        if tracker.warningIsActive {
            menu.addItem(.separator())
            let loud = Formatters.duration(tracker.loudSecondsInWindow)
            let item = NSMenuItem(title: "Loud listening: \(loud) at >=75% in the last 30m", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let launchItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchItem.target = self
        launchItem.state = launchAtLoginEnabled ? .on : .off
        menu.addItem(launchItem)

        menu.addItem(.separator())
        let debugItem = NSMenuItem(title: "Copy Debug Snapshot", action: #selector(copyDebugSnapshot), keyEquivalent: "")
        debugItem.target = self
        menu.addItem(debugItem)

        let quitItem = NSMenuItem(title: "Quit EarGuard", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    private func nowText() -> String {
        guard let snapshot = monitor.snapshot else {
            return "Now: No output device"
        }

        guard snapshot.isHeadphone else {
            return "Now: No headphones"
        }

        let state = snapshot.isRunning ? "playing" : "connected, silent"
        return "Now: \(snapshot.name) (\(state))  ·  current volume \(Formatters.volume(snapshot.volume))"
    }

    private func bar(for seconds: TimeInterval, max maximum: TimeInterval) -> String {
        let filled = Int((seconds / maximum * 8).rounded())
        guard filled > 0 else { return "" }
        return String(repeating: "|", count: Swift.max(1, filled))
    }

    private func makeDashboardModel() -> DashboardModel {
        let snapshot = monitor.snapshot
        let today = store.today()
        let days = store.lastDays(7).reversed().map {
            DashboardDay(date: $0.0, seconds: $0.1.seconds, averageVolume: $0.1.averageVolume, loudSeconds: $0.1.loudSeconds)
        }
        let streak = makeStreakSummary()

        let deviceName: String
        let deviceState: String
        if let snapshot, snapshot.isHeadphone {
            deviceName = snapshot.name
            deviceState = snapshot.isRunning ? "Playing" : "Connected, silent"
        } else if snapshot == nil {
            deviceName = "No output device"
            deviceState = "Idle"
        } else {
            deviceName = "No headphones"
            deviceState = snapshot?.name ?? "Idle"
        }

        return DashboardModel(
            todaySeconds: today.seconds,
            averageVolume: today.averageVolume,
            currentVolume: snapshot?.volume,
            currentSessionSeconds: tracker.currentSessionSeconds,
            isCounting: tracker.isCounting,
            warningIsActive: tracker.warningIsActive,
            loudSecondsInWindow: tracker.loudSecondsInWindow,
            deviceName: deviceName,
            deviceState: deviceState,
            launchAtLoginEnabled: launchAtLoginEnabled,
            days: days,
            currentSafeStreak: streak.current,
            longestSafeStreak: streak.longest,
            streakDays: streak.days
        )
    }

    private func makeStreakSummary() -> (current: Int, longest: Int, days: [DashboardStreakDay]) {
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: Date())
        let parsedHistory = store.history.days.reduce(into: [Date: DailyAggregate]()) { result, entry in
            guard let date = Self.historyDateFormatter.date(from: entry.key) else { return }
            result[calendar.startOfDay(for: date)] = entry.value
        }

        let firstKnownDay = parsedHistory.keys.min() ?? today
        let heatmapStart = calendar.date(byAdding: .day, value: -83, to: today) ?? today
        let streakStart = min(firstKnownDay, today)

        var current = 0
        var cursor = today
        while cursor >= streakStart {
            let aggregate = parsedHistory[cursor] ?? DailyAggregate()
            guard Self.isSafeDay(aggregate) else { break }
            current += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }

        var longest = 0
        var running = 0
        cursor = streakStart
        while cursor <= today {
            let aggregate = parsedHistory[cursor] ?? DailyAggregate()
            if Self.isSafeDay(aggregate) {
                running += 1
                longest = max(longest, running)
            } else {
                running = 0
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        let heatmapDays: [DashboardStreakDay] = (0..<84).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: heatmapStart) else { return nil }
            let day = calendar.startOfDay(for: date)
            let aggregate = parsedHistory[day]
            let status: DashboardStreakStatus
            if day < firstKnownDay {
                status = .unknown
            } else if let aggregate, !Self.isSafeDay(aggregate) {
                status = .loudBreak
            } else if let aggregate, aggregate.seconds > 0 {
                status = .safeListening
            } else {
                status = .restDay
            }
            return DashboardStreakDay(date: day, status: status)
        }

        return (current, longest, heatmapDays)
    }

    private static func isSafeDay(_ aggregate: DailyAggregate) -> Bool {
        aggregate.loudSeconds < 5 * 60
    }

    private var launchAtLoginEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    @objc private func openDashboard() {
        dashboardController.show(
            model: makeDashboardModel(),
            onToggleLaunchAtLogin: { [weak self] in self?.toggleLaunchAtLogin() },
            onCopyDebug: { [weak self] in self?.copyDebugSnapshot() },
            onQuit: { [weak self] in self?.quit() }
        )
    }

    @objc private func toggleLaunchAtLogin() {
        if #available(macOS 13.0, *) {
            do {
                if launchAtLoginEnabled {
                    try SMAppService.mainApp.unregister()
                } else {
                    try SMAppService.mainApp.register()
                }
            } catch {
                NSLog("EarGuard launch-at-login update failed: \(error.localizedDescription)")
            }
        }
        refresh()
    }

    @objc private func copyDebugSnapshot() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(monitor.debugDescription(), forType: .string)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE MMM d"
        return formatter
    }()

    private static let historyDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
