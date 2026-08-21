import AppKit
import Foundation

private final class ReceiverView: NSView {
    private let status = NSTextField(labelWithString: "Waiting for JoyCoding…")
    private let logURL = ProcessInfo.processInfo.environment["KEY_RECEIVER_LOG"]
        .map { URL(fileURLWithPath: $0) }

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        status.font = .monospacedSystemFont(ofSize: 20, weight: .medium)
        status.alignment = .center
        status.frame = bounds.insetBy(dx: 24, dy: 24)
        status.autoresizingMask = [.width, .height]
        addSubview(status)
    }

    required init?(coder: NSCoder) { nil }

    override func keyDown(with event: NSEvent) {
        record(event: event, kind: "keyDown")
    }

    override func keyUp(with event: NSEvent) {
        record(event: event, kind: "keyUp")
    }

    override func flagsChanged(with event: NSEvent) {
        record(event: event, kind: "flagsChanged")
    }

    private func record(event: NSEvent, kind: String) {
        let record: [String: Any] = [
            "event": kind,
            "keyCode": Int(event.keyCode),
            "characters": event.charactersIgnoringModifiers ?? "",
            "modifierFlags": Int(event.modifierFlags.rawValue),
            "time": ISO8601DateFormatter().string(from: Date()),
        ]
        status.stringValue = "RECEIVED \(kind) keyCode=\(event.keyCode)"
        guard let logURL,
              var data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        else { return }
        data.append(0x0A)
        let directory = logURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: logURL.path) {
            _ = FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: logURL) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 220),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false)
        window.title = "JoyCoding Key Receiver"
        let receiver = ReceiverView(frame: window.contentView!.bounds)
        receiver.autoresizingMask = [.width, .height]
        window.contentView = receiver
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(receiver)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

private let app = NSApplication.shared
private let delegate = AppDelegate()
app.delegate = delegate
app.run()
