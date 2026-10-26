import Foundation
import Darwin

/// Uses Codex's supported local protocol; authentication stays owned by Codex.
enum CodexUsageAPI {
    enum Failure: LocalizedError {
        case notInstalled, timeout, unavailable, protocolError
        var errorDescription: String? {
            switch self {
            case .notInstalled: return "Codex not found. Install Codex, or set TIBODOG_CODEX_PATH to its executable."
            case .timeout: return "Codex usage request timed out. Try Refresh Now."
            case .unavailable: return "Codex usage unavailable. Sign in to Codex with ChatGPT and try again."
            case .protocolError: return "Unexpected Codex response. Update Codex and try again."
            }
        }
    }

    static func executable() throws -> URL {
        let env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [env["TIBODOG_CODEX_PATH"]].compactMap { $0 } + [
            "/Applications/Codex.app/Contents/Resources/codex",
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "\(home)/Applications/Codex.app/Contents/Resources/codex",
            "\(home)/Applications/ChatGPT.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex", "/usr/local/bin/codex", "\(home)/.local/bin/codex"
        ] + (env["PATH"] ?? "").split(separator: ":").map { "\($0)/codex" }
        guard let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw Failure.notInstalled
        }
        return URL(fileURLWithPath: path)
    }

    // Called off the main actor. poll() bounds every read, including partial JSON lines.
    static func fetch() throws -> (usage: Usage, plan: String?) {
        let process = Process()
        process.executableURL = try executable()
        process.arguments = ["app-server"]
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let pid = process.processIdentifier
        defer {
            try? input.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
            // Do not let a hung child accumulate across refreshes.
            let deadline = Date().addingTimeInterval(1)
            while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
            if process.isRunning { kill(pid, SIGKILL) }
            process.waitUntilExit()
            try? output.fileHandleForReading.close()
        }
        func send(_ message: [String: Any]) throws {
            var data = try JSONSerialization.data(withJSONObject: message)
            data.append(10)
            try input.fileHandleForWriting.write(contentsOf: data)
        }
        try send(["id": 1, "method": "initialize", "params": ["clientInfo": ["name": "islet", "version": "0.4.0"]]])
        let deadline = Date().addingTimeInterval(25)
        var buffer = Data()
        while Date() < deadline {
            var descriptor = pollfd(fd: output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, 200)
            if ready < 0 { if errno == EINTR { continue }; throw Failure.protocolError }
            if ready == 0 { continue }
            let chunk = output.fileHandleForReading.availableData
            guard !chunk.isEmpty else { throw Failure.unavailable }
            buffer.append(chunk)
            guard buffer.count < 4 * 1024 * 1024 else { throw Failure.protocolError }
            while let newline = buffer.firstIndex(of: 10) {
                let line = buffer.prefix(upTo: newline)
                buffer.removeSubrange(...newline)
                guard let message = try JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
                guard let id = message["id"] as? Int else { continue }
                guard message["error"] == nil else { throw Failure.unavailable }
                if id == 1 {
                    try send(["method": "initialized"])
                    try send(["id": 2, "method": "account/rateLimits/read"])
                } else if id == 2 {
                    guard let result = message["result"] as? [String: Any] else { throw Failure.protocolError }
                    return try decode(result)
                }
            }
        }
        throw Failure.timeout
    }

    static func decode(_ result: [String: Any]) throws -> (usage: Usage, plan: String?) {
        let buckets = result["rateLimitsByLimitId"] as? [String: Any]
        // Never substitute an unrelated model bucket for the Codex quota.
        guard let limits = (buckets?["codex"] as? [String: Any]) ?? (result["rateLimits"] as? [String: Any]) else {
            throw Failure.unavailable
        }
        func window(_ key: String) -> UsageWindow? {
            guard let raw = limits[key] as? [String: Any],
                  let used = (raw["usedPercent"] as? NSNumber)?.doubleValue, used.isFinite else { return nil }
            let reset = (raw["resetsAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
            return UsageWindow(utilization: used, resetsAt: reset,
                               durationMinutes: (raw["windowDurationMins"] as? NSNumber)?.intValue)
        }
        let primary = window("primary"), secondary = window("secondary")
        guard primary != nil || secondary != nil else { throw Failure.unavailable }
        return (Usage(fiveHour: primary, sevenDay: secondary), limits["planType"] as? String)
    }
}
