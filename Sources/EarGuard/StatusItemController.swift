import AppKit
import ServiceManagement
import SwiftUI

final class StatusItemController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
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

        updatePopoverContent()
    }

    private func configure() {
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 390, height: 520)

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover)
        }

        refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        if let refreshTimer {
            RunLoop.main.add(refreshTimer, forMode: .common)
        }
    }

    private func updatePopoverContent() {
        let view = EarGuardPanelView(
            model: makePanelModel(),
            onToggleLaunchAtLogin: { [weak self] in self?.toggleLaunchAtLogin() },
            onCopyDebug: { [weak self] in self?.copyDebugSnapshot() },
            onQuit: { [weak self] in self?.quit() }
        )
        .frame(width: 390, height: 520)
        .preferredColorScheme(.dark)

        let hostedView = AnyView(view)
        if let controller = popover.contentViewController as? NSHostingController<AnyView> {
            controller.rootView = hostedView
        } else {
            popover.contentViewController = NSHostingController(rootView: hostedView)
        }
    }

    private func makePanelModel() -> EarGuardPanelModel {
        let snapshot = monitor.snapshot
        let today = store.today()
        let days = store.lastDays(7).reversed().map {
            EarGuardPanelDay(date: $0.0, seconds: $0.1.seconds, averageVolume: $0.1.averageVolume, loudSeconds: $0.1.loudSeconds)
        }

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

        return EarGuardPanelModel(
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
            days: days
        )
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            refresh()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private var launchAtLoginEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    private func toggleLaunchAtLogin() {
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

    private func copyDebugSnapshot() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(monitor.debugDescription(), forType: .string)
    }

    private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

struct EarGuardPanelDay: Identifiable {
    let id = UUID()
    let date: Date
    let seconds: TimeInterval
    let averageVolume: Double?
    let loudSeconds: TimeInterval
}

struct EarGuardPanelModel {
    let todaySeconds: TimeInterval
    let averageVolume: Double?
    let currentVolume: Double?
    let currentSessionSeconds: TimeInterval
    let isCounting: Bool
    let warningIsActive: Bool
    let loudSecondsInWindow: TimeInterval
    let deviceName: String
    let deviceState: String
    let launchAtLoginEnabled: Bool
    let days: [EarGuardPanelDay]
}

struct EarGuardPanelView: View {
    let model: EarGuardPanelModel
    let onToggleLaunchAtLogin: () -> Void
    let onCopyDebug: () -> Void
    let onQuit: () -> Void

    @AppStorage("EarGuardPanelChartMode") private var chartMode = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            summaryGrid
            deviceCard
            historyCard
            Spacer(minLength: 0)
            footer
        }
        .padding(18)
        .background(panelBackground)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: model.warningIsActive ? "headphones.circle.fill" : "headphones")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(model.warningIsActive ? .orange : .green)
                .frame(width: 42, height: 42)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text("EarGuard")
                    .font(.system(size: 22, weight: .semibold))
                Text(model.isCounting ? "Listening now" : "Monitoring headphone audio")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(model.isCounting ? "LIVE" : "IDLE")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(model.isCounting ? .green : .secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(model.isCounting ? .green.opacity(0.15) : .white.opacity(0.08), in: Capsule())
        }
    }

    private var summaryGrid: some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                metricCard(title: "Today", value: Formatters.duration(model.todaySeconds), symbol: "clock")
                metricCard(title: "Avg volume", value: Formatters.volume(model.averageVolume), symbol: "speaker.wave.2")
            }
            GridRow {
                metricCard(title: "Current volume", value: Formatters.volume(model.currentVolume), symbol: "slider.horizontal.3")
                metricCard(
                    title: "Session",
                    value: model.isCounting ? Formatters.duration(model.currentSessionSeconds) : "--",
                    symbol: "waveform"
                )
            }
        }
    }

    private func metricCard(title: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            Text(value)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 8))
    }

    private var deviceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.deviceName)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(1)
                    Text(model.deviceState)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(model.isCounting ? .green : .secondary)
                }
                Spacer()
                Image(systemName: model.isCounting ? "play.circle.fill" : "pause.circle")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(model.isCounting ? .green : .secondary)
            }

            volumeProgress

            if model.warningIsActive {
                Label("Loud listening: \(Formatters.duration(model.loudSecondsInWindow)) at >=75% in the last 30m", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.orange)
            }
        }
        .padding(14)
        .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 8))
    }

    private var volumeProgress: some View {
        VStack(alignment: .leading, spacing: 5) {
            GeometryReader { proxy in
                let volume = max(0, min(1, model.currentVolume ?? 0))
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.12))
                    Capsule()
                        .fill(volume >= 0.75 ? Color.orange : Color.green)
                        .frame(width: proxy.size.width * volume)
                }
            }
            .frame(height: 8)
            HStack {
                Text("0%")
                Spacer()
                Text("75%")
                Spacer()
                Text("100%")
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
        }
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("", selection: $chartMode) {
                Text("Listening").tag(0)
                Text("Volume").tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text(chartMode == 0 ? "Last 7 Days" : "Average Volume")
                .font(.system(size: 16, weight: .semibold))

            historyChart
        }
        .padding(14)
        .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 8))
    }

    private var historyChart: some View {
        let maximum = max(1, model.days.map { chartMode == 0 ? $0.seconds : (($0.averageVolume ?? 0) * 100) }.max() ?? 1)

        return HStack(alignment: .bottom, spacing: 8) {
            ForEach(model.days) { day in
                let value = chartMode == 0 ? day.seconds : ((day.averageVolume ?? 0) * 100)
                VStack(spacing: 7) {
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(.white.opacity(0.08))
                        RoundedRectangle(cornerRadius: 3)
                            .fill(chartColor(for: day))
                            .frame(height: max(4, 116 * value / maximum))
                    }
                    .frame(width: 34, height: 116)

                    Text(dayLabel.string(from: day.date))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Text(chartMode == 0 ? Formatters.duration(day.seconds) : Formatters.volume(day.averageVolume))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(width: 42)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func chartColor(for day: EarGuardPanelDay) -> Color {
        if chartMode == 1, let averageVolume = day.averageVolume, averageVolume >= 0.75 {
            return .orange
        }
        return chartMode == 0 ? .blue : .green
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button(action: onToggleLaunchAtLogin) {
                Label(model.launchAtLoginEnabled ? "Login On" : "Login Off", systemImage: model.launchAtLoginEnabled ? "checkmark.circle.fill" : "circle")
            }
            Button(action: onCopyDebug) {
                Label("Debug", systemImage: "doc.on.doc")
            }
            Spacer()
            Button(action: onQuit) {
                Label("Quit", systemImage: "power")
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 0)
            .fill(Color(nsColor: .windowBackgroundColor))
            .overlay(
                LinearGradient(
                    colors: [.white.opacity(0.06), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
    }

    private var dayLabel: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "E"
        return formatter
    }
}
