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

/// The dog widget: from the moment tibodog sees Tibo reset the limits, a dog barks beside the notch until
/// the person opens the island and reads the post. Read every two seconds from tibodog's folder; once read,
/// the post's id goes to alert-seen there so the dog stays quiet after a restart.
@MainActor
final class DogMonitor: ObservableObject {
    static let shared = DogMonitor()

    /// The reset not read yet, or nil.
    @Published private(set) var alert: DogAlert?

    private var timer: Timer?
    private let dir = ProcessInfo.processInfo.environment["TIBODOG_HOME"]
        ?? (NSHomeDirectory() as NSString).appendingPathComponent(".tibodog")
    private var alertPath: String { (dir as NSString).appendingPathComponent("alert.json") }
    private var seenPath: String { (dir as NSString).appendingPathComponent("alert-seen") }

    private init() {
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        poll()
    }

    func poll() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let data = FileManager.default.contents(atPath: alertPath),
              let a = try? decoder.decode(DogAlert.self, from: data) else {
            if alert != nil { alert = nil }
            return
        }
        let seen = (try? String(contentsOfFile: seenPath, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
        let unread = seen == a.id ? nil : a
        if unread != alert {
            alert = unread
            // A new reset: check right away whether it reached this Codex account.
            if unread != nil, !unread!.isCredit { ResetTracker.shared.check() }
        }
    }

    func markRead() {
        guard let a = alert else { return }
        try? a.id.write(toFile: seenPath, atomically: true, encoding: .utf8)
        alert = nil
    }

    /// A reset credit came in: the dog barks about that too.
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
        try? data.write(to: URL(fileURLWithPath: alertPath), options: .atomic)
        poll()
    }

    /// The post on X; opening it counts as reading it.
    func openPost() {
        guard let s = alert?.url, let url = URL(string: s) else { return }
        NSWorkspace.shared.open(url)
        markRead()
    }
}
