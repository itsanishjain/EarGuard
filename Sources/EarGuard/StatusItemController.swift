import AppKit
import ServiceManagement

final class StatusItemController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
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

    private var launchAtLoginEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
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
}
