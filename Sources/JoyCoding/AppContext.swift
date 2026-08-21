import Foundation
import AppKit
import CoreGraphics

/// 前台 app 追踪 + 使用历史。等价于 hs.application.watcher / hs.window.orderedWindows。
final class AppContext {
    static let shared = AppContext()

    /// 最近使用顺序, 下标 0 是当前 app
    private(set) var history: [String] = []

    private var cycleSnapshot: [String]?
    private var cycleIndex = 0
    private var cycleTimer: Timer?
    private var focusGeneration = 0

    private init() {
        seedHistory()
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication
            if let bid = app?.bundleIdentifier { self?.push(bid) }
        }
    }

    var frontBundle: String {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
    }

    /// 通知只能记录 app 启动之后的切换。不播种的话每次重启历史都只剩当前 app,
    /// "切到上一个 app" 会一直没反应。窗口层级顺序正好是"最近使用"的近似。
    private func seedHistory() {
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        let running = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isTerminated && $0.bundleIdentifier != nil
        }
        let windows = CGWindowListCopyWindowInfo(
            [.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let windowOrder = windows.compactMap { window -> String? in
            guard let pid = window[kCGWindowOwnerPID as String] as? pid_t else { return nil }
            return running.first(where: { $0.processIdentifier == pid })?.bundleIdentifier
        }

        history = AppContext.seedOrder(
            front: front,
            windowOrder: windowOrder,
            running: running.compactMap(\.bundleIdentifier),
            ownBundle: Bundle.main.bundleIdentifier ?? "com.meiease.joycoding"
        )
    }

    private func push(_ bid: String) {
        history.removeAll { $0 == bid }
        history.insert(bid, at: 0)
        if history.count > 12 { history.removeLast(history.count - 12) }
    }

    func focus(_ bundleID: String) {
        focusGeneration += 1
        let generation = focusGeneration
        let requestFocus = { [weak self] in
            guard let self, self.focusGeneration == generation,
                  self.frontBundle != bundleID else { return }
            let workspace = NSWorkspace.shared
            if let url = workspace.urlForApplication(withBundleIdentifier: bundleID) {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                configuration.addsToRecentItems = false
                workspace.openApplication(at: url, configuration: configuration)
            } else if let app = workspace.runningApplications
                .first(where: { $0.bundleIdentifier == bundleID }) {
                _ = app.activate(options: [.activateAllWindows])
            }
        }
        requestFocus()

        // WindowServer can transiently reject a second activation while the
        // preceding app switch is still settling. Retry only the newest request;
        // pressing the opposite shoulder increments the generation and cancels
        // these callbacks before they can undo the user's latest direction.
        for delay in [0.12, 0.32] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: requestFocus)
        }
    }

    /// 不发 Cmd+Tab: Dock/WindowServer 对它有特殊处理, 合成事件经常打不进去。
    /// 自己维护同样的前后顺序更可靠，也让手柄的 RB/LB 能各走一个方向。
    /// 第一次按时给历史拍快照 —— 切 app 本身会改动历史, 不快照的话连按就在
    /// 两个 app 之间横跳, 翻不深。RB/LB 共用快照，所以可立即反向走回来。
    func switchToPrevious() {
        cycleApplications(by: 1)
    }

    func switchToNext() {
        cycleApplications(by: -1)
    }

    private func cycleApplications(by delta: Int) {
        if cycleSnapshot == nil {
            cycleSnapshot = AppContext.cycleOrder(
                front: frontBundle,
                history: history,
                ownBundle: Bundle.main.bundleIdentifier ?? "com.meiease.joycoding"
            )
            cycleIndex = 0
        }
        guard let snap = cycleSnapshot, snap.count >= 2 else {
            return
        }
        guard let next = AppContext.cycleIndex(
            from: cycleIndex, count: snap.count, delta: delta) else { return }
        cycleIndex = next
        let target = snap[cycleIndex]
        focus(target)

        cycleTimer?.invalidate()
        cycleTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            self?.cycleSnapshot = nil
        }
    }

    /// Pure index math kept separate so forward, reverse, and wrap semantics are testable.
    static func cycleIndex(from current: Int, count: Int, delta: Int) -> Int? {
        guard count >= 2, delta != 0 else { return nil }
        return (current + delta % count + count) % count
    }

    /// Activation notifications can arrive just after the physical press. Anchor
    /// every new cycle to live frontmost state, then append the deduplicated MRU list.
    static func cycleOrder(front: String, history: [String], ownBundle: String = "") -> [String] {
        guard !front.isEmpty else { return history }
        var seen = Set([front])
        return [front] + history.filter {
            ($0 == front || $0 != ownBundle) && seen.insert($0).inserted
        }
    }

    /// Build a useful first-run MRU approximation from every Space/minimized window,
    /// then use normal running apps as a fallback. JoyCoding itself is not a cycle
    /// destination unless the settings window is the live starting point.
    static func seedOrder(
        front: String,
        windowOrder: [String],
        running: [String],
        ownBundle: String,
        limit: Int = 12
    ) -> [String] {
        guard limit > 0 else { return [] }
        var result: [String] = []
        var seen = Set<String>()
        for bundleID in [front] + windowOrder + running {
            guard !bundleID.isEmpty,
                  bundleID == front || bundleID != ownBundle,
                  seen.insert(bundleID).inserted
            else { continue }
            result.append(bundleID)
            if result.count == limit { break }
        }
        return result
    }

    /// 通用按键是否该在当前 app 生效。白名单查表, 免得在 Finder、
    /// 确认对话框之类的地方误触回车。
    func inTarget() -> Bool {
        let cfg = ConfigStore.shared.config
        if !cfg.restrictToTargets { return true }
        return cfg.targetApps.contains(frontBundle)
    }

    var inGhostty: Bool { frontBundle == BundleID.ghostty }
    var inClaude:  Bool { frontBundle == BundleID.claude }
    var inWeChat:  Bool { frontBundle == BundleID.wechat }
    var inChrome:  Bool { frontBundle == BundleID.chrome }
}
