import Foundation

/// Whether a reset Tibo announced actually reached this Codex account.
enum ResetVerdict: Equatable {
    /// The weekly window started over after the post.
    case windowRestarted(Date)
    /// A reset credit came in after the post.
    case creditAdded(from: Int, to: Int)
    /// Nothing yet; Codex is checked every few minutes.
    case pending
    /// Codex isn't signed in or reachable, so there's no way to tell.
    case unknown
}

/// Keeps a small history of the Codex account (reset credits, when the weekly window started) in
/// ~/.tibodog/codex-history.json, so a reset can be checked against it: did the weekly window start over
/// after Tibo's post, or did a reset credit come in? When a credit comes in, the dog barks.
@MainActor
final class ResetTracker: ObservableObject {
    static let shared = ResetTracker()

    struct Snapshot: Codable, Equatable {
        var at: Date
        var credits: Int?
        var weeklyStart: Date?
        var weeklyUsed: Double?
    }

    @Published private(set) var credits: Int?
    @Published private(set) var history: [Snapshot] = []
    @Published private(set) var reachable = true
    /// Spending a reset credit right now, and what Codex said last time.
    @Published private(set) var redeeming = false
    @Published private(set) var lastOutcome: String?

    private var timer: Timer?
    private var checking = false
    private let path = ((ProcessInfo.processInfo.environment["TIBODOG_HOME"]
        ?? (NSHomeDirectory() as NSString).appendingPathComponent(".tibodog")) as NSString)
        .appendingPathComponent("codex-history.json")

    private init() {
        if let data = FileManager.default.contents(atPath: path) {
            let d = JSONDecoder()
            d.dateDecodingStrategy = .secondsSince1970
            history = (try? d.decode([Snapshot].self, from: data)) ?? []
        }
        credits = history.last?.credits
        guard !UsageStore.mock else { return }
        // Codex is read even while Claude is the provider shown, so resets are checked either way.
        timer = Timer.scheduledTimer(withTimeInterval: 10 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.check() }
        }
        check()
    }

    /// Reads Codex now (off the main thread) and records what it says.
    func check() {
        guard !checking else { return }
        checking = true
        Task.detached(priority: .utility) {
            let result = try? CodexUsageAPI.fetch()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let tracker = ResetTracker.shared
                    tracker.checking = false
                    tracker.reachable = result != nil
                    if let r = result { tracker.record(usage: r.usage, credits: r.resetCredits) }
                }
            }
        }
    }

    /// Spends one reset credit on the current Codex windows. Only ever called from the confirm button.
    func useCredit() {
        guard !redeeming else { return }
        redeeming = true
        lastOutcome = nil
        let key = UUID().uuidString
        Task.detached(priority: .userInitiated) {
            var outcome = (try? CodexUsageAPI.consumeResetCredit(idempotencyKey: key)) ?? "error"
            // A dropped connection may still have gone through: asking again with the same key is safe.
            if outcome == "error" { outcome = (try? CodexUsageAPI.consumeResetCredit(idempotencyKey: key)) ?? "error" }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let tracker = ResetTracker.shared
                    tracker.redeeming = false
                    tracker.lastOutcome = outcome
                    tracker.check()
                    UsageStore.shared.refresh(force: true)
                }
            }
        }
    }

    /// Called with every Codex read (also UsageStore's, when Codex is the provider).
    func record(usage: Usage, credits newCredits: Int?) {
        let weekly = usage.sevenDay
        let start = weekly.flatMap { w -> Date? in
            guard let r = w.resetsAt, let m = w.durationMinutes else { return nil }
            return r.addingTimeInterval(-Double(m) * 60)
        }
        let snap = Snapshot(at: Date(), credits: newCredits, weeklyStart: start, weeklyUsed: weekly?.utilization)
        let last = history.last
        credits = newCredits
        // Only keep changes: a new credit count or a weekly window that started over.
        guard last == nil || last?.credits != snap.credits || !sameWindow(last?.weeklyStart, snap.weeklyStart) else { return }
        history.append(snap)
        history = Array(history.suffix(200))
        save()
        if let before = last?.credits, let now = newCredits, now > before {
            DogMonitor.shared.creditArrived(from: before, to: now)
        }
    }

    /// Did the reset announced at `postedAt` reach this account?
    func verdict(after postedAt: Date) -> ResetVerdict {
        guard let latest = history.last else { return reachable ? .pending : .unknown }
        // A global reset starts the weekly window over (Codex's windows start at the reset, or at the
        // first use after it). Allow a little slack for clocks and propagation.
        if let start = latest.weeklyStart, start >= postedAt.addingTimeInterval(-30 * 60) {
            return .windowRestarted(start)
        }
        let before = history.last { $0.at < postedAt }?.credits
        if let b = before, let after = history.filter({ $0.at >= postedAt }).compactMap(\.credits).max(), after > b {
            return .creditAdded(from: b, to: after)
        }
        return reachable ? .pending : .unknown
    }

    private func sameWindow(_ a: Date?, _ b: Date?) -> Bool {
        switch (a, b) {
        case let (a?, b?): return abs(a.timeIntervalSince(b)) < 120
        case (nil, nil): return true
        default: return false
        }
    }

    private func save() {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        guard let data = try? e.encode(history) else { return }
        try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                                 withIntermediateDirectories: true)
        try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}
