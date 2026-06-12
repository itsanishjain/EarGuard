import AppKit
import SwiftUI

final class DashboardWindowController {
    private var window: NSWindow?
    private var onToggleLaunchAtLogin: (() -> Void)?
    private var onCopyDebug: (() -> Void)?
    private var onQuit: (() -> Void)?

    func show(
        model: DashboardModel,
        onToggleLaunchAtLogin: @escaping () -> Void,
        onCopyDebug: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.onToggleLaunchAtLogin = onToggleLaunchAtLogin
        self.onCopyDebug = onCopyDebug
        self.onQuit = onQuit

        if window == nil {
            let hostingController = NSHostingController(rootView: makeView(model: model))
            let newWindow = NSWindow(contentViewController: hostingController)
            newWindow.title = "EarGuard"
            newWindow.setContentSize(NSSize(width: 1040, height: 620))
            newWindow.minSize = NSSize(width: 920, height: 540)
            newWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            newWindow.titlebarAppearsTransparent = true
            newWindow.toolbarStyle = .unified
            newWindow.isReleasedWhenClosed = false
            newWindow.center()
            window = newWindow
        }

        refresh(model: model)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func refresh(model: DashboardModel) {
        guard let hostingController = window?.contentViewController as? NSHostingController<EarGuardDashboardView> else {
            return
        }
        hostingController.rootView = makeView(model: model)
    }

    private func makeView(model: DashboardModel) -> EarGuardDashboardView {
        EarGuardDashboardView(
            model: model,
            onToggleLaunchAtLogin: { [weak self] in self?.onToggleLaunchAtLogin?() },
            onCopyDebug: { [weak self] in self?.onCopyDebug?() },
            onQuit: { [weak self] in self?.onQuit?() }
        )
    }
}

struct DashboardDay: Identifiable {
    let id = UUID()
    let date: Date
    let seconds: TimeInterval
    let averageVolume: Double?
    let loudSeconds: TimeInterval
}

struct DashboardModel {
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
    let days: [DashboardDay]
    let currentSafeStreak: Int
    let longestSafeStreak: Int
    let streakDays: [DashboardStreakDay]
}

enum DashboardStreakStatus {
    case unknown
    case restDay
    case safeListening
    case loudBreak
}

struct DashboardStreakDay: Identifiable {
    let id = UUID()
    let date: Date
    let status: DashboardStreakStatus
}

struct EarGuardDashboardView: View {
    let model: DashboardModel
    let onToggleLaunchAtLogin: () -> Void
    let onCopyDebug: () -> Void
    let onQuit: () -> Void

    @AppStorage("EarGuardDashboardChartMode") private var chartMode = 0

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            mainContent
        }
        .frame(minWidth: 720, minHeight: 500)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: model.warningIsActive ? "headphones.circle.fill" : "headphones")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(model.warningIsActive ? .orange : .green)
                    .frame(width: 44, height: 44)
                    .background(Color.green.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text("EarGuard")
                        .font(.system(size: 22, weight: .semibold))
                    Text(model.isCounting ? "Listening now" : "Monitoring")
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                sidebarMetric("Today", Formatters.duration(model.todaySeconds), "clock")
                sidebarMetric("Current volume", Formatters.volume(model.currentVolume), "slider.horizontal.3")
                sidebarMetric("Average today", Formatters.volume(model.averageVolume), "speaker.wave.2")
                sidebarMetric("Session", model.isCounting ? Formatters.duration(model.currentSessionSeconds) : "--", "waveform")
                sidebarMetric("Safe streak", "\(model.currentSafeStreak)d", "sparkles")
            }

            Spacer()

            Button(action: onToggleLaunchAtLogin) {
                Label(model.launchAtLoginEnabled ? "Launch at Login On" : "Launch at Login Off", systemImage: model.launchAtLoginEnabled ? "checkmark.circle.fill" : "circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button(action: onCopyDebug) {
                Label("Copy Debug Snapshot", systemImage: "doc.on.doc")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button(action: onQuit) {
                Label("Quit EarGuard", systemImage: "power")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .padding(24)
        .frame(width: 250)
        .background(Color(nsColor: .underPageBackgroundColor).opacity(0.82))
    }

    private func sidebarMetric(_ title: String, _ value: String, _ symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 18, weight: .semibold))
                    .monospacedDigit()
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            currentDeviceSection
            HStack(alignment: .top, spacing: 18) {
                chartSection
                    .frame(maxWidth: .infinity)
                streakSection
                    .frame(width: 300)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 28)
        .padding(.horizontal, 28)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Headphone Listening")
                .font(.system(size: 28, weight: .semibold))
            Text("Volume is system volume percentage, not measured decibels.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private var currentDeviceSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.deviceName)
                        .font(.system(size: 20, weight: .semibold))
                    Text(model.deviceState)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(model.isCounting ? .green : .secondary)
                }

                Spacer()

                Text(model.isCounting ? "LIVE" : "IDLE")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(model.isCounting ? .green : .secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(model.isCounting ? Color.green.opacity(0.14) : Color.secondary.opacity(0.12), in: Capsule())
            }

            volumeProgress

            if model.warningIsActive {
                Label("Loud listening: \(Formatters.duration(model.loudSecondsInWindow)) at >=75% in the last 30m", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.orange)
            }
        }
        .padding(18)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }

    private var streakSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(model.currentSafeStreak) day streak")
                        .font(.system(size: 20, weight: .semibold))
                    Text("Safe listening")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("Longest \(model.longestSafeStreak)d")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
            }

            Text("A safe day means under 5m at >=75% volume.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            streakHeatmap

            HStack(spacing: 10) {
                legendSwatch(.safeListening, "Safe")
                legendSwatch(.restDay, "Rest")
                legendSwatch(.loudBreak, "Loud")
            }
        }
        .padding(18)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }

    private var streakHeatmap: some View {
        let rows = ["S", "M", "T", "W", "T", "F", "S"]

        return HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .trailing, spacing: 6) {
                ForEach(rows.indices, id: \.self) { index in
                    Text(rows[index])
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(height: 13)
                }
            }

            HStack(alignment: .top, spacing: 5) {
                ForEach(0..<12, id: \.self) { week in
                    VStack(spacing: 6) {
                        ForEach(0..<7, id: \.self) { weekday in
                            let index = week * 7 + weekday
                            let day = model.streakDays[index]
                            RoundedRectangle(cornerRadius: 3)
                                .fill(streakColor(day.status))
                                .frame(width: 13, height: 13)
                                .help(streakHelp(for: day))
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func legendSwatch(_ status: DashboardStreakStatus, _ label: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3)
                .fill(streakColor(status))
                .frame(width: 12, height: 12)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private func streakColor(_ status: DashboardStreakStatus) -> Color {
        switch status {
        case .unknown:
            return Color.secondary.opacity(0.14)
        case .restDay:
            return Color.mint.opacity(0.28)
        case .safeListening:
            return Color.teal.opacity(0.82)
        case .loudBreak:
            return Color.orange.opacity(0.9)
        }
    }

    private func streakHelp(for day: DashboardStreakDay) -> String {
        let label = fullDayLabel.string(from: day.date)
        switch day.status {
        case .unknown:
            return "\(label): no EarGuard history"
        case .restDay:
            return "\(label): rest day"
        case .safeListening:
            return "\(label): safe listening"
        case .loudBreak:
            return "\(label): loud-listening break"
        }
    }

    private var volumeProgress: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                let volume = max(0, min(1, model.currentVolume ?? 0))
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.16))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(volume >= 0.75 ? Color.orange : Color.green)
                        .frame(width: proxy.size.width * volume)
                }
            }
            .frame(height: 10)

            HStack {
                Text("0%")
                Spacer()
                Text("75%")
                Spacer()
                Text("100%")
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
        }
    }

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(chartMode == 0 ? "Last 7 Days" : "Average Volume")
                    .font(.system(size: 20, weight: .semibold))

                Spacer()

                Picker("", selection: $chartMode) {
                    Text("Listening").tag(0)
                    Text("Volume").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }

            historyChart
        }
        .padding(18)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }

    private var historyChart: some View {
        let maximum = max(1, model.days.map { chartMode == 0 ? $0.seconds : (($0.averageVolume ?? 0) * 100) }.max() ?? 1)

        return HStack(alignment: .bottom, spacing: 14) {
            ForEach(model.days) { day in
                let value = chartMode == 0 ? day.seconds : ((day.averageVolume ?? 0) * 100)
                VStack(spacing: 8) {
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color.secondary.opacity(0.13))
                        RoundedRectangle(cornerRadius: 5)
                            .fill(chartColor(for: day))
                            .frame(height: max(5, 150 * value / maximum))
                    }
                    .frame(width: 42, height: 150)

                    Text(dayLabel.string(from: day.date))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Text(chartMode == 0 ? Formatters.duration(day.seconds) : Formatters.volume(day.averageVolume))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(width: 54)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 205)
    }

    private func chartColor(for day: DashboardDay) -> Color {
        if chartMode == 1, let averageVolume = day.averageVolume, averageVolume >= 0.75 {
            return .orange
        }
        return chartMode == 0 ? .blue : .green
    }

    private var dayLabel: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "E"
        return formatter
    }

    private var fullDayLabel: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }
}
