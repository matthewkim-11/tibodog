import Foundation
import Combine
import ServiceManagement

/// Single source of truth for the UI: polls the usage endpoint, refreshes the
/// token when needed, and exposes user settings.
@MainActor
final class UsageStore: ObservableObject {
    static let shared = UsageStore()

    @Published private(set) var usage: Usage?
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoading = false
    @Published private(set) var plan: String?
    @Published private(set) var sourceName: String?

    @Published var provider: UsageProvider {
        didSet {
            guard provider != oldValue else { return }
            defaults.set(provider.rawValue, forKey: "usageProvider")
            usage = nil; plan = nil; sourceName = nil; lastUpdated = nil
            errorMessage = nil; backoffUntil = nil
            if Self.mock || Self.mockUsageOnly { start() } else { refresh(force: true) }
        }
    }

    var primaryLabel: String { usage?.fiveHour?.durationLabel ?? (provider == .claude ? "5H" : "Session") }
    var secondaryLabel: String { usage?.sevenDay?.durationLabel ?? (provider == .claude ? "7D" : "Quota") }
    var primaryTitle: String { provider == .claude ? "5-hour session" : "Session · \(primaryLabel)" }
    var secondaryTitle: String { provider == .claude ? "Weekly · all models" : "Quota · \(secondaryLabel)" }

    // Settings (persisted in UserDefaults)
    @Published var showNotch: Bool { didSet { defaults.set(showNotch, forKey: "showNotch") } }
    @Published var autoRefreshToken: Bool { didSet { defaults.set(autoRefreshToken, forKey: "autoRefreshToken") } }
    @Published var showMenuBarText: Bool { didSet { defaults.set(showMenuBarText, forKey: "showMenuBarText") } }
    @Published var showMenuBarIcon: Bool { didSet { defaults.set(showMenuBarIcon, forKey: "showMenuBarIcon") } }
    @Published var showNowPlaying: Bool { didSet { defaults.set(showNowPlaying, forKey: "showNowPlaying") } }
    @Published var launchAtLogin: Bool {
        didSet { if launchAtLogin != oldValue { applyLaunchAtLogin() } }
    }

    var pollInterval: TimeInterval = 60
    private let defaults = UserDefaults.standard
    private var timer: Timer?
    private var backoffUntil: Date?
    private var inFlight = false

    private init() {
        defaults.register(defaults: ["showNotch": true, "autoRefreshToken": true, "showMenuBarText": false, "showMenuBarIcon": true, "showNowPlaying": true])
        provider = UsageProvider(rawValue: defaults.string(forKey: "usageProvider") ?? "") ?? .claude
        showNotch = defaults.bool(forKey: "showNotch")
        autoRefreshToken = defaults.bool(forKey: "autoRefreshToken")
        showMenuBarText = defaults.bool(forKey: "showMenuBarText")
        showMenuBarIcon = defaults.bool(forKey: "showMenuBarIcon")
        showNowPlaying = defaults.bool(forKey: "showNowPlaying")
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    /// TIBODOG_MOCK=1 shows sample data without touching the Keychain or network (for screenshots/dev).
    static let mock = ProcessInfo.processInfo.environment["TIBODOG_MOCK"] == "1"
    /// TIBODOG_MOCK_USAGE=1 mocks only the usage numbers; activity and music stay real.
    static let mockUsageOnly = ProcessInfo.processInfo.environment["TIBODOG_MOCK_USAGE"] == "1"

    func start() {
        if Self.mock || Self.mockUsageOnly {
            usage = Usage(fiveHour: UsageWindow(utilization: 42, resetsAt: Date().addingTimeInterval(2 * 3600 + 13 * 60)),
                          sevenDay: UsageWindow(utilization: 71, resetsAt: Date().addingTimeInterval(3 * 86400 + 4 * 3600)),
                          sevenDayOpus: UsageWindow(utilization: 18, resetsAt: Date().addingTimeInterval(3 * 86400 + 4 * 3600)))
            if provider == .codex {
                usage?.fiveHour?.durationMinutes = 300
                usage?.sevenDay?.durationMinutes = 10080
                usage?.sevenDayOpus = nil
            }
            plan = provider == .claude ? "max" : "plus"; sourceName = "mock"; lastUpdated = Date()
            if Self.mock {
                NowPlayingMonitor.shared.installMock()
            }
            return
        }
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh(force: Bool = false) {
        if Self.mock || Self.mockUsageOnly { start(); return }
        if inFlight { return }
        if !force, let b = backoffUntil, b > Date() { return }
        inFlight = true
        isLoading = true
        let allowRefresh = autoRefreshToken
        let selected = provider
        // Run all Keychain + network work off the main actor. Results are published back
        // through the GCD main queue (which the run loop always drains), never through a
        // cooperative main-actor await — those don't reliably resume in this app's runloop.
        Task.detached(priority: .userInitiated) { [weak self] in
            await self?.performRefresh(provider: selected, allowRefresh: allowRefresh)
        }
    }

    /// Convenience for callers that used to await the refresh; the work is fire-and-forget.
    func refreshNow(force: Bool = false) async { refresh(force: force) }

    private nonisolated func publish(_ block: @escaping @MainActor (UsageStore) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            MainActor.assumeIsolated { block(self) }
        }
    }

    private nonisolated func publish(for provider: UsageProvider, _ block: @escaping @MainActor (UsageStore) -> Void) {
        publish { store in
            guard store.provider == provider else { return }
            block(store)
        }
    }

    private nonisolated func performRefresh(provider: UsageProvider, allowRefresh: Bool) async {
        defer {
            publish {
                $0.inFlight = false; $0.isLoading = false
                if $0.provider != provider { $0.refresh(force: true) }
            }
        }
        do {
            if provider == .codex {
                let result = try CodexUsageAPI.fetch()
                publish(for: provider) {
                    $0.usage = result.usage; $0.plan = result.plan; $0.sourceName = "Codex"
                    $0.lastUpdated = Date(); $0.backoffUntil = nil; $0.errorMessage = nil
                }
                return
            }
            var (creds, source) = try await CredentialStore.loadAsync()
            publish(for: provider) { $0.plan = creds.subscriptionType; $0.sourceName = source.description }
            var refreshed = false
            Log.info("credentials from \(source), plan=\(creds.subscriptionType ?? "?"), expired=\(creds.isExpired), canRefresh=\(creds.canRefresh)")

            if creds.isExpired {
                creds = try await refreshAndSave(creds, source, allowRefresh: allowRefresh)
                refreshed = true
            }
            let result: Usage
            do {
                result = try await UsageAPI.fetch(token: creds.accessToken)
            } catch UsageAPI.Failure.unauthorized where !refreshed {
                creds = try await refreshAndSave(creds, source, allowRefresh: allowRefresh)
                result = try await UsageAPI.fetch(token: creds.accessToken)
            } catch UsageAPI.Failure.rateLimited where !refreshed && creds.canRefresh && allowRefresh {
                // The endpoint answers 429 (not 401) to stale tokens; one refresh usually clears it.
                creds = try await refreshAndSave(creds, source, allowRefresh: allowRefresh)
                result = try await UsageAPI.fetch(token: creds.accessToken)
            }
            Log.info("usage ok: 5h=\(result.fiveHour?.percentText ?? "-") 7d=\(result.sevenDay?.percentText ?? "-")")
            publish(for: provider) { $0.usage = result; $0.lastUpdated = Date(); $0.backoffUntil = nil; $0.errorMessage = nil }
        } catch UsageAPI.Failure.rateLimited(let retryAfter) {
            let wait = min(max(retryAfter ?? 300, 60), 15 * 60)
            Log.error("rate limited, retry-after=\(retryAfter ?? -1), waiting \(wait)s")
            publish(for: provider) {
                $0.backoffUntil = Date().addingTimeInterval(wait)
                $0.errorMessage = UsageAPI.Failure.rateLimited(retryAfter: wait).errorDescription
            }
        } catch {
            Log.error(error.localizedDescription)
            publish(for: provider) { $0.errorMessage = error.localizedDescription }
        }
    }

    private nonisolated func refreshAndSave(_ creds: Credentials, _ source: CredentialSource, allowRefresh: Bool) async throws -> Credentials {
        guard allowRefresh else { throw StoreError.tokenExpired }
        Log.info("refreshing token…")
        let fresh = try await OAuth.refresh(creds)
        do { try await CredentialStore.saveAsync(fresh, to: source) }
        catch { Log.error("token saved in memory but not written back: \(error.localizedDescription)") }
        Log.info("token refreshed and saved to \(source)")
        return fresh
    }

    /// Short text for the menu bar item, e.g. "42% · 18%".
    var menuBarTitle: String {
        guard let u = usage else { return errorMessage == nil ? "…" : "!" }
        let a = u.fiveHour?.percentText ?? "–"
        let b = u.sevenDay?.percentText ?? "–"
        return "\(a) · \(b)"
    }

    var planText: String {
        guard let p = plan, !p.isEmpty else { return provider.title }
        return provider.title + " " + p.prefix(1).uppercased() + p.dropFirst()
    }

    private func applyLaunchAtLogin() {
        do {
            if launchAtLogin { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            errorMessage = "Launch at login: \(error.localizedDescription)"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    enum StoreError: LocalizedError {
        case tokenExpired
        var errorDescription: String? {
            "Claude token expired. Run `claude` in Terminal, or enable “Auto-refresh token” in the menu."
        }
    }
}
