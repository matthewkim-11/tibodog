import AppKit
import Foundation

/// A reset Tibo announced on X, as tibodog leaves it in ~/.tibodog/alert.json (its strings already in
/// the person's language).
struct DogAlert: Decodable, Identifiable, Equatable {
    let id: String
    let title: String
    let body: String
    let url: String?
    let woof: String
    let open: String
    let at: Date
    /// When Tibo posted it (tibodog's `postedAt`); the reset is checked against this.
    let postedAt: Date?
    /// A reset credit that came in, rather than a post on X.
    var isCredit: Bool { id.hasPrefix("credit-") }
}

/// Korean when the Mac is set to Korean, else English.
func L(_ ko: String, _ en: String) -> String {
    Locale.preferredLanguages.first?.hasPrefix("ko") == true ? ko : en
}

/// Only a post on x.com/twitter.com over https: the link comes from a feed, which must not be able to
/// open a file, an app or another app's URL scheme.
func isPostURL(_ url: URL) -> Bool {
    guard url.scheme == "https", let host = url.host?.lowercased() else { return false }
    let hosts = ["x.com", "twitter.com", "www.x.com", "www.twitter.com", "mobile.twitter.com", "mobile.x.com"]
    return hosts.contains(host) && url.path.contains("/status/")
}

/// The dog widget: from the moment tibodog sees Tibo reset the limits, a dog barks beside the notch until
/// the person opens the island and reads the post. Read every two seconds from tibodog's folder: the CLI
/// writes alert.json, the widget writes credit.json when a reset credit comes in. Read ids go to
/// alert-seen there (one per line) so the dog stays quiet after a restart.
@MainActor
final class DogMonitor: ObservableObject {
    static let shared = DogMonitor()

    /// The reset not read yet, or nil (a post on X first, then a reset credit).
    @Published private(set) var alert: DogAlert?
    /// Whether the dog is moving right now: all the time for the first minute, then a short bark every
    /// ten seconds, so an alert left unread for days doesn't redraw the notch 30 times a second.
    @Published private(set) var barking = false

    private var timer: Timer?
    private var shownAt = Date()
    private let dir = ProcessInfo.processInfo.environment["TIBODOG_HOME"]
        ?? (NSHomeDirectory() as NSString).appendingPathComponent(".tibodog")
    private func path(_ name: String) -> String { (dir as NSString).appendingPathComponent(name) }

    private init() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        poll()
    }

    private var ticks = 0
    private func tick() {
        ticks += 1
        if ticks % 4 == 0 { poll() }
        let since = Date().timeIntervalSince(shownAt)
        let now = alert != nil && (since < 60 || since.truncatingRemainder(dividingBy: 10) < 2)
        if now != barking { barking = now }
    }

    private func read(_ name: String) -> DogAlert? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let data = FileManager.default.contents(atPath: path(name)) else { return nil }
        return try? decoder.decode(DogAlert.self, from: data)
    }

    private var seen: Set<String> {
        let text = (try? String(contentsOfFile: path("alert-seen"), encoding: .utf8)) ?? ""
        return Set(text.split(whereSeparator: \.isNewline).map(String.init))
    }

    func poll() {
        let seen = seen
        let unread = [read("alert.json"), read("credit.json")].compactMap { $0 }.first { !seen.contains($0.id) }
        if unread != alert {
            if unread?.id != alert?.id { shownAt = Date() }
            alert = unread
            // A new reset: check right away whether it reached this Codex account.
            if let a = unread, !a.isCredit { ResetTracker.shared.check() }
        }
    }

    /// Marks that alert read (only the one that was actually on screen, not whatever came in since).
    func markRead(_ id: String) {
        let kept = (try? String(contentsOfFile: path("alert-seen"), encoding: .utf8))?
            .split(whereSeparator: \.isNewline).map(String.init).suffix(50) ?? []
        let lines = (Array(kept) + [id]).joined(separator: "\n") + "\n"
        try? lines.write(toFile: path("alert-seen"), atomically: true, encoding: .utf8)
        poll()
    }

    /// A reset credit came in: the dog barks about that too (beside, not over, an unread post).
    func creditArrived(from before: Int, to now: Int) {
        let card: [String: Any] = [
            "id": "credit-\(now)-\(Int(Date().timeIntervalSince1970))",
            "title": L("리셋권이 들어왔어요!", "A reset credit came in!"),
            "body": L("Codex 리셋권 \(before)개 → \(now)개. Codex 탭에서 쓸 수 있어요.",
                      "Codex reset credits: \(before) → \(now). Use one from the Codex tab."),
            "woof": L("멍!", "WOOF!"),
            "open": "",
            "at": Date().timeIntervalSince1970,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: card) else { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? data.write(to: URL(fileURLWithPath: path("credit.json")), options: .atomic)
        poll()
    }

    /// The post on X; opening it counts as reading it.
    func openPost() {
        guard let a = alert else { return }
        if let s = a.url, let url = URL(string: s), isPostURL(url) { NSWorkspace.shared.open(url) }
        markRead(a.id)
    }
}
