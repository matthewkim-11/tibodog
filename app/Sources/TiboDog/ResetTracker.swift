import Foundation

/// Whether a reset Tibo announced actually reached this Codex account.
enum ResetVerdict: Equatable {
    /// The weekly window started over after the post, while the old one still had time left.
    case windowRestarted(Date)
    /// It started over after the post, but there's no record from before it to rule out the old window
    /// simply running out.
    case windowRestartedLikely(Date)
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
        var weeklyMinutes: Int?
    }

    @Published private(set) var credits: Int?
    @Published private(set) var history: [Snapshot] = []
    @Published private(set) var reachable = true
    /// Spending a reset credit right now, and what Codex said last time.
    @Published private(set) var redeeming = false
    @Published private(set) var lastOutcome: String?
    /// When a credit was spent from here: that restart is ours, not Tibo's.
    private var spentAt: Date?

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
        // TIBODOG_MOCK=1 reads the history from TIBODOG_HOME and never asks Codex.
        guard !checking, !UsageStore.mock else { return }
        checking = true
        // A plain GCD thread, not the Swift concurrency pool: this blocks for up to 25s.
        DispatchQueue.global(qos: .utility).async {
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
        if UsageStore.mock {
            // Demos and screenshots: look like Codex said "reset", never spend a real credit.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                self.redeeming = false
                self.lastOutcome = "reset"
                self.credits = max(0, (self.credits ?? 1) - 1)
                self.spentAt = Date()
                UsageStore.shared.mockReset()
            }
            return
        }
        let key = UUID().uuidString
        DispatchQueue.global(qos: .userInitiated).async {
            var outcome = (try? CodexUsageAPI.consumeResetCredit(idempotencyKey: key)) ?? "error"
            // A dropped connection may still have gone through: asking again with the same key is safe.
            if outcome == "error" { outcome = (try? CodexUsageAPI.consumeResetCredit(idempotencyKey: key)) ?? "error" }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let tracker = ResetTracker.shared
                    tracker.redeeming = false
                    tracker.lastOutcome = outcome
                    if outcome == "reset" { tracker.spentAt = Date() }
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
        let snap = Snapshot(at: Date(), credits: newCredits, weeklyStart: start, weeklyUsed: weekly?.utilization,
                            weeklyMinutes: weekly?.durationMinutes)
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
        if let start = latest.weeklyStart, start >= postedAt.addingTimeInterval(-30 * 60),
           !(spentAt.map { abs($0.timeIntervalSince(start)) < 10 * 60 } ?? false) {
            // With a record from before the post, a reset is told apart from the old window running out.
            if let before = history.last(where: { $0.at < postedAt }), let oldStart = before.weeklyStart {
                let oldEnd = oldStart.addingTimeInterval(Double(before.weeklyMinutes ?? 10_080) * 60)
                if !sameWindow(oldStart, start), oldEnd > start.addingTimeInterval(60) { return .windowRestarted(start) }
            } else {
                return .windowRestartedLikely(start)
            }
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
