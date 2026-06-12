import AppKit

if CommandLine.arguments.contains("--probe") {
    let monitor = AudioDeviceMonitor()
    monitor.refresh()
    print(monitor.debugDescription())
    exit(0)
}

if CommandLine.arguments.contains("--probe-live") {
    let monitor = AudioDeviceMonitor()
    monitor.onSnapshotChanged = { snapshot in
        print("--- \(Date()) ---")
        print(monitor.debugDescription())
        fflush(stdout)
    }
    Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
        monitor.refresh()
    }
    monitor.refresh()
    RunLoop.main.run()
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let monitor = AudioDeviceMonitor()
    private let store = Store()
    private let exposureModel = ExposureModel()
    private let notifier = Notifier()
    private var tracker: ListeningTracker!
    private var statusController: StatusItemController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        notifier.requestAuthorization()

        tracker = ListeningTracker(
            monitor: monitor,
            store: store,
            exposureModel: exposureModel,
            notifier: notifier
        )
        statusController = StatusItemController(store: store, monitor: monitor, tracker: tracker)

        tracker.onStateChanged = { [weak self] in
            self?.statusController.refresh()
        }

        installLifecycleObservers()
        tracker.start()
        statusController.refresh()
    }

    func applicationWillTerminate(_ notification: Notification) {
        tracker.closeSessionAndFlush()
    }

    private func installLifecycleObservers() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(willSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(didWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc private func willSleep() {
        tracker.handleSleep()
    }

    @objc private func didWake() {
        tracker.handleWake()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
