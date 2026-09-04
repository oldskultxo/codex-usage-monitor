import AppKit
import SwiftUI
import UserNotifications

struct CodexQuota: Codable {
    let remainingPercent: Double?
    let resetAt: String?
    let source: String
    let capturedAt: String?
}

struct CodexSnapshot: Codable {
    let quota5h: CodexQuota
    let quotaWeekly: CodexQuota
    let plan: String
}

struct UsageSnapshot: Codable {
    let generatedAt: String
    let codex: CodexSnapshot
}

struct MonitorSettings: Codable, Equatable {
    var fiveHourAlertPercent: Double
    var weeklyAlertPercent: Double
    static let defaults = MonitorSettings(fiveHourAlertPercent: 10, weeklyAlertPercent: 10)
}

@MainActor
final class MonitorModel: ObservableObject {
    @Published var snapshot: UsageSnapshot?
    @Published var settings = MonitorSettings.defaults
    @Published var lastError: String?
    @Published var isRefreshing = false
    private var timer: Timer?
    private var consecutiveFailures = 0
    var onDataUpdated: (() -> Void)?

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        var request = URLRequest(url: URL(string: "http://127.0.0.1:47931/refresh")!)
        request.httpMethod = "POST"
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            Task { @MainActor in
                self?.isRefreshing = false
                guard error == nil, let data, let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    self?.consecutiveFailures += 1
                    if self?.consecutiveFailures ?? 0 >= 4 { self?.lastError = "Core unavailable" }
                    else {
                        self?.lastError = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self?.refresh() }
                    }
                    return
                }
                do {
                    self?.snapshot = try JSONDecoder().decode(UsageSnapshot.self, from: data)
                    self?.consecutiveFailures = 0
                    self?.lastError = nil
                    self?.onDataUpdated?()
                } catch { self?.lastError = "Invalid core response" }
            }
        }.resume()
    }

    func loadSettings() {
        URLSession.shared.dataTask(with: URL(string: "http://127.0.0.1:47931/config")!) { [weak self] data, response, _ in
            Task { @MainActor in
                guard let data, let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return }
                self?.settings = (try? JSONDecoder().decode(MonitorSettings.self, from: data)) ?? .defaults; self?.onDataUpdated?()
            }
        }.resume()
    }

    func saveSettings(_ settings: MonitorSettings) {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:47931/config")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(settings)
        URLSession.shared.dataTask(with: request) { [weak self] _, _, _ in
            Task { @MainActor in self?.settings = settings; self?.onDataUpdated?(); self?.refresh() }
        }.resume()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coreProcess: Process?
    private var window: NSWindow?
    private var miniwindowTimer: Timer?
    private var showingWeeklyQuota = false
    let model = MonitorModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        startCore()
        model.onDataUpdated = { [weak self] in self?.updateMiniwindowPreview() }
        miniwindowTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.showingWeeklyQuota.toggle()
                self?.updateMiniwindowPreview()
            }
        }
        model.refresh()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        showMonitor()
    }

    func applicationWillTerminate(_ notification: Notification) { miniwindowTimer?.invalidate(); coreProcess?.terminate() }

    func showMonitor() {
        if let window { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 300), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Codex Usage Monitor"
        window.contentMinSize = NSSize(width: 420, height: 280)
        window.contentMaxSize = NSSize(width: 650, height: 380)
        window.level = (UserDefaults.standard.object(forKey: "floatingWindow") as? Bool ?? true) ? .floating : .normal
        window.contentView = NSHostingView(rootView: MonitorView().environmentObject(model))
        window.center(); window.makeKeyAndOrderFront(nil); self.window = window
        updateMiniwindowPreview()
    }

    private func updateMiniwindowPreview() {
        guard let window else { return }
        let quota = showingWeeklyQuota ? model.snapshot?.codex.quotaWeekly : model.snapshot?.codex.quota5h
        let threshold = showingWeeklyQuota ? model.settings.weeklyAlertPercent : model.settings.fiveHourAlertPercent
        let title = showingWeeklyQuota ? "Week" : "5h"
        let value = quota?.remainingPercent.map { String(format: "%.0f%%", $0) } ?? "—"
        let color: NSColor = (quota?.remainingPercent ?? 101) <= threshold ? .systemOrange : .systemGreen
        let size = NSSize(width: 180, height: 96)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        let titleAttributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 22, weight: .semibold), .foregroundColor: NSColor.white]
        let valueAttributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 38, weight: .bold), .foregroundColor: color]
        let titleSize = (title as NSString).size(withAttributes: titleAttributes)
        let valueSize = (value as NSString).size(withAttributes: valueAttributes)
        (title as NSString).draw(at: NSPoint(x: (size.width - titleSize.width) / 2, y: 62), withAttributes: titleAttributes)
        (value as NSString).draw(at: NSPoint(x: (size.width - valueSize.width) / 2, y: 12), withAttributes: valueAttributes)
        image.unlockFocus()
        window.miniwindowTitle = title
        window.miniwindowImage = image
    }

    private func startCore() {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("core/monitor.mjs").path
        let development = "\(FileManager.default.homeDirectoryForCurrentUser.path)/projects/codex-usage-monitor/core/monitor.mjs"
        let script = [bundled, development].compactMap { $0 }.first { FileManager.default.fileExists(atPath: $0) }
        guard let script else { return }
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/env"); process.arguments = ["node", script]
        try? process.run(); coreProcess = process
    }
}

struct QuotaCard: View {
    let title: String
    let quota: CodexQuota
    let threshold: Double

    private var value: String { quota.remainingPercent.map { String(format: "%.1f%%", $0) } ?? "—" }
    private var color: Color { quota.remainingPercent.map { $0 <= threshold ? .orange : .green } ?? .secondary }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title.weight(.bold)).foregroundStyle(color)
            Text(resetLabel(quota.resetAt)).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    private func resetLabel(_ value: String?) -> String {
        guard let value else { return "Reset: —" }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: value) ?? { formatter.formatOptions = [.withInternetDateTime]; return formatter.date(from: value) }()
        guard let date else { return "Reset: —" }
        return "Reset: \(date.formatted(date: .abbreviated, time: .shortened))"
    }
}

struct MonitorView: View {
    @EnvironmentObject private var model: MonitorModel
    @State private var settingsOpen = false
    @AppStorage("floatingWindow") private var floatingWindow = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Codex").font(.title2.weight(.semibold))
                    Text("Plan: \(model.snapshot?.codex.plan.capitalized ?? "Personal")").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Settings…") { settingsOpen = true }
            }
            if let codex = model.snapshot?.codex {
                HStack(spacing: 12) {
                    QuotaCard(title: "5h", quota: codex.quota5h, threshold: model.settings.fiveHourAlertPercent)
                    QuotaCard(title: "Week", quota: codex.quotaWeekly, threshold: model.settings.weeklyAlertPercent)
                }
                Text("Source: \(codex.quota5h.source)").font(.caption).foregroundStyle(.secondary)
            } else {
                Spacer(); Text(model.lastError ?? "Loading Codex quota…").foregroundStyle(.secondary); Spacer()
            }
            Spacer(minLength: 18).frame(maxHeight: 18)
            HStack {
                Toggle("Floating window", isOn: $floatingWindow).toggleStyle(.checkbox)
                Spacer()
                if model.isRefreshing { ProgressView().controlSize(.small) }
                Button("Refresh") { model.refresh() }
            }
        }
        .padding(20).frame(minWidth: 420, minHeight: 280, maxHeight: 340)
        .sheet(isPresented: $settingsOpen) { SettingsView(settings: model.settings) { model.saveSettings($0) } }
        .task { model.loadSettings() }
        .onChange(of: floatingWindow) { floating in
            NSApp.windows.first(where: { $0.title == "Codex Usage Monitor" })?.level = floating ? .floating : .normal
        }
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    let settings: MonitorSettings
    let onSave: (MonitorSettings) -> Void
    @State private var fiveHour: String
    @State private var weekly: String
    @State private var error: String?

    init(settings: MonitorSettings, onSave: @escaping (MonitorSettings) -> Void) {
        self.settings = settings; self.onSave = onSave
        _fiveHour = State(initialValue: String(format: "%.2f", settings.fiveHourAlertPercent))
        _weekly = State(initialValue: String(format: "%.2f", settings.weeklyAlertPercent))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Alert settings").font(.title3.weight(.semibold))
            Form {
                TextField("5h alert when remaining (%)", text: $fiveHour)
                TextField("Weekly alert when remaining (%)", text: $weekly)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack { Spacer(); Button("Cancel") { dismiss() }; Button("Save") { save() }.keyboardShortcut(.defaultAction) }
        }.padding(18).frame(width: 390, height: 220)
    }

    private func save() {
        guard let fiveHourValue = Double(fiveHour.replacingOccurrences(of: ",", with: ".")), let weeklyValue = Double(weekly.replacingOccurrences(of: ",", with: ".")), (0...100).contains(fiveHourValue), (0...100).contains(weeklyValue) else { error = "Los límites deben estar entre 0 y 100%."; return }
        onSave(MonitorSettings(fiveHourAlertPercent: fiveHourValue, weeklyAlertPercent: weeklyValue)); dismiss()
    }
}

@main
struct CodexUsageMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    var body: some Scene {
        MenuBarExtra { Button("Open monitor") { appDelegate.showMonitor() }; Button("Refresh") { appDelegate.model.refresh() }; Divider(); Button("Quit") { NSApp.terminate(nil) } } label: { Image(systemName: "chart.bar") }
    }
}
