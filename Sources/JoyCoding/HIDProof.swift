import Foundation

/// Opt-in JSONL tracing used by the physical-controller smoke test.
///
/// Set JOYCODING_PROOF_LOG to a path. JOYCODING_PROOF_DRY_RUN=1 keeps the full
/// HID -> profile -> semantic-action path active but suppresses CGEvent output,
/// so a proof capture cannot accidentally operate the frontmost app.
final class HIDProof {
    static let shared = HIDProof()

    let dryRun: Bool
    private let url: URL?
    private let lock = NSLock()

    private init() {
        let env = ProcessInfo.processInfo.environment
        url = env["JOYCODING_PROOF_LOG"].map { URL(fileURLWithPath: $0) }
        dryRun = env["JOYCODING_PROOF_DRY_RUN"] == "1"
    }

    var enabled: Bool { url != nil }

    func record(_ event: String, _ fields: [String: Any] = [:]) {
        guard let url else { return }
        var object = fields
        object["event"] = event
        object["time"] = ISO8601DateFormatter().string(from: Date())
        guard JSONSerialization.isValidJSONObject(object),
              var data = try? JSONSerialization.data(
                withJSONObject: object, options: [.sortedKeys])
        else { return }
        data.append(0x0A)

        lock.lock()
        defer { lock.unlock() }
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            _ = FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            NSLog("[JoyCoding] proof log write failed: \(error)")
        }
    }
}
