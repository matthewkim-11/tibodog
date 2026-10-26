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
        if unread != alert { alert = unread }
    }

    func markRead() {
        guard let a = alert else { return }
        try? a.id.write(toFile: seenPath, atomically: true, encoding: .utf8)
        alert = nil
    }

    /// The post on X; opening it counts as reading it.
    func openPost() {
        guard let s = alert?.url, let url = URL(string: s) else { return }
        NSWorkspace.shared.open(url)
        markRead()
    }
}
