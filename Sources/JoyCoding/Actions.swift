import Foundation

/// How an action is delivered. Keeping delivery separate from menu metadata
/// means controller mappings can stay stable while shortcut providers evolve.
enum ActionInvocation {
    case appShortcut(String)
    case raycast(String)
    case focusApp(String)
    case handler(() -> Void)
}

enum ActionProvider: Equatable {
    case local
    case appProfile
    case raycast
    case appFocus
}

enum ActionExecutor {
    private static let ctx = AppContext.shared

    static func execute(_ invocation: ActionInvocation) {
        switch invocation {
        case .appShortcut(let action):
            guard let spec = AppProfiles.key(action, app: ctx.frontBundle) else {
                NSLog("[JoyCoding] No shortcut for \(action) in \(ctx.frontBundle)")
                return
            }
            execute(spec)
        case .raycast(let action):
            RaycastShortcuts.trigger(action)
        case .focusApp(let bundleID):
            ctx.focus(bundleID)
        case .handler(let handler):
            handler()
        }
    }

    private static func execute(_ spec: KeySpec) {
        if spec.isText {
            KeySynth.type(spec.text)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                KeySynth.keyStroke([], "return")
            }
        } else if let (modifiers, key) = spec.parsed {
            KeySynth.keyStroke(modifiers, key)
        }
    }
}

struct ActionDef: Identifiable {
    let id: String
    let name: String
    let detail: String
    let group: String
    /// 按住是否连发 (退格、方向、翻页这类)
    let repeatable: Bool
    /// nil means global. A set allows one semantic action to be shared by
    /// several apps without duplicating action IDs or execution closures.
    let supportedApps: Set<String>?
    let invocation: ActionInvocation

    var onlyIn: String? {
        guard supportedApps?.count == 1 else { return nil }
        return supportedApps?.first
    }

    var provider: ActionProvider {
        switch invocation {
        case .appShortcut: return .appProfile
        case .raycast: return .raycast
        case .focusApp: return .appFocus
        case .handler: return .local
        }
    }

    init(_ id: String, _ name: String, _ detail: String = "",
         group: String? = nil, repeatable: Bool = false,
         onlyIn: String? = nil, run: @escaping () -> Void) {
        self.id = id; self.name = name; self.detail = detail
        self.group = group ?? L("通用"); self.repeatable = repeatable
        self.supportedApps = onlyIn.map { [$0] }
        self.invocation = .handler(run)
    }

    init(_ id: String, _ name: String, _ detail: String = "",
         group: String? = nil, repeatable: Bool = false,
         supportedIn: Set<String>? = nil, invocation: ActionInvocation) {
        self.id = id; self.name = name; self.detail = detail
        self.group = group ?? L("通用"); self.repeatable = repeatable
        self.supportedApps = supportedIn
        self.invocation = invocation
    }

    func isAvailable(in app: String) -> Bool {
        guard let supportedApps else { return true }
        return supportedApps.contains(app) || AppProfiles.hasShortcut(id, app: app)
    }
}

/// 菜单模式。
///
/// 打开模型/权限/effort 菜单后, 摇杆上下应该是"选项上下移动"而不是"翻页"。
/// 本想用无障碍接口检测菜单是否打开, 但 Claude Code 是 Web 界面, 菜单是
/// 网页渲染的, AXFocusedUIElement 根本看不到。所以改成显式模式:
/// 触发菜单的动作顺手进入模式, 确认/取消或超时自动退出。
enum MenuMode {
    static private(set) var active = false
    private static var timer: Timer?

    static func enter(_ seconds: Double = 6) {
        active = true
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { _ in
            active = false
        }
    }

    static func exit() {
        active = false
        timer?.invalidate(); timer = nil
    }
}

enum Actions {
    static let ctx = AppContext.shared
    private static func key(_ m: [String], _ k: String) { KeySynth.keyStroke(m, k) }

    struct AppFocusTarget: Equatable {
        let actionID: String
        let labelKey: String
        let bundleID: String
    }

    /// Direct-switch actions ordered by the user's current high-frequency work
    /// surfaces, followed by useful installed fallbacks. This is deliberately a
    /// plain catalog rather than a dependency on Computer History at runtime.
    static let appFocusTargets: [AppFocusTarget] = [
        .init(actionID: "focusArc", labelKey: "切到 Arc", bundleID: BundleID.arc),
        .init(actionID: "focusSlack", labelKey: "切到 Slack", bundleID: BundleID.slack),
        .init(actionID: "focusRaycast", labelKey: "切到 Raycast", bundleID: BundleID.raycast),
        .init(actionID: "focusEnergy", labelKey: "切到 Energy", bundleID: BundleID.energy),
        .init(actionID: "focusCodex", labelKey: "切到 Codex", bundleID: BundleID.codex),
        .init(actionID: "focusWeChat", labelKey: "切到微信", bundleID: BundleID.wechat),
        .init(actionID: "focusAmp", labelKey: "切到 ampcode", bundleID: BundleID.amp),
        .init(actionID: "focusMail", labelKey: "切到 Mail", bundleID: BundleID.mail),
        .init(actionID: "focusSignal", labelKey: "切到 Signal", bundleID: BundleID.signal),
        .init(actionID: "focusWhatsApp", labelKey: "切到 WhatsApp", bundleID: BundleID.whatsapp),
        .init(actionID: "focusHeptabase", labelKey: "切到 Heptabase",
              bundleID: BundleID.heptabase),
        .init(actionID: "focusWarp", labelKey: "切到 Warp", bundleID: BundleID.warp),
        .init(actionID: "focusGhostty", labelKey: "切到 Ghostty", bundleID: BundleID.ghostty),
        .init(actionID: "focusChrome", labelKey: "切到 Chrome", bundleID: BundleID.chrome),
        .init(actionID: "focusClaude", labelKey: "切到 Claude Code", bundleID: BundleID.claude),
    ]

    private static var appFocusActions: [ActionDef] {
        appFocusTargets.map { target in
            ActionDef(target.actionID, L(target.labelKey), group: L("切换 app"),
                      invocation: .focusApp(target.bundleID))
        }
    }

    // 同一颗键在不同 app 里做语义相同、快捷键不同的事。按键不够用时
    // 这是最划算的扩展方式 —— 肌肉记忆通用, 行为跟着场景走。
    static let all: [ActionDef] = [

        // ── 通用 ──────────────────────────────────────────────
        ActionDef("confirm", L("确认 / 发送"), L("所有 app 都发送回车；菜单打开时是「选中」")) {
            key([], "return")
            MenuMode.exit()
        },
        ActionDef("cancel", L("打断 / 取消"), L("Esc；菜单打开时是「关掉菜单」")) {
            if ctx.inTarget() { key([], "escape") }
            MenuMode.exit()
        },
        ActionDef("delete", L("退格删除"), repeatable: true) {
            if ctx.inTarget() { key([], "delete") }
        },
        ActionDef("clearLine", L("清空当前输入"), L("终端是 Ctrl+U，输入框是全选再删")) {
            guard ctx.inTarget() else { return }
            let spec = AppProfiles.clearLineKey(app: ctx.frontBundle)
            if let (m, k) = spec.parsed {
                key(m, k)
                // 全选之后还得删一下
                if k == "a" && m.contains("cmd") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { key([], "delete") }
                }
            }
        },
        ActionDef("scrollUp", L("向上翻页"), L("菜单打开时变成「上一项」"), repeatable: true) {
            guard ctx.inTarget() else { return }
            if MenuMode.active { key([], "up") } else { KeySynth.scroll(lines: 8) }
        },
        ActionDef("scrollDown", L("向下翻页"), L("菜单打开时变成「下一项」"), repeatable: true) {
            guard ctx.inTarget() else { return }
            if MenuMode.active { key([], "down") } else { KeySynth.scroll(lines: -8) }
        },
        ActionDef("up", L("上"), repeatable: true) { if ctx.inTarget() { key([], "up") } },
        ActionDef("down", L("下"), repeatable: true) { if ctx.inTarget() { key([], "down") } },
        ActionDef("left", L("左"), repeatable: true) { if ctx.inTarget() { key([], "left") } },
        ActionDef("right", L("右"), repeatable: true) { if ctx.inTarget() { key([], "right") } },
        ActionDef("commandRightBracket", L("Command + ]"), repeatable: true) {
            key(["cmd"], "]")
        },
        ActionDef("commandLeftBracket", L("Command + ["), repeatable: true) {
            key(["cmd"], "[")
        },
        ActionDef("focusPrevious", L("上一个可选项"), L("Shift+Tab 移动焦点"),
                  repeatable: true) {
            key(["shift"], "tab")
        },
        ActionDef("focusNext", L("下一个可选项"), L("Tab 移动焦点"),
                  repeatable: true) {
            key([], "tab")
        },
        ActionDef("selectFocused", L("选择当前项"), L("Return 激活焦点")) {
            key([], "return")
            MenuMode.exit()
        },
        ActionDef("ptt", L("语音输入"), L("按住录, 松开出字")) { /* 按下/松开另行处理 */ },
        ActionDef("focusInput", L("聚焦输入框"), L("点一下底部输入区")) {
            // Prefer a recorded/native app shortcut. The click fallback exists
            // only for apps such as Claude and WeChat that expose none.
            if AppProfiles.hasShortcut("focusInput", app: ctx.frontBundle) {
                ActionExecutor.execute(.appShortcut("focusInput"))
                return
            }
            // Claude Code / 微信都没有聚焦输入框的快捷键(文档和菜单都查过),
            // Web 界面也不暴露无障碍元素。只能按窗口比例点 —— 聊天界面的
            // 输入框总在底部, 这个位置很稳。
            let offset: CGFloat
            switch ctx.frontBundle {
            case BundleID.claude: offset = 72
            case BundleID.wechat: offset = 52
            default:              offset = 60
            }
            guard ctx.inTarget(), !ctx.inGhostty,     // 终端本来就一直有焦点
                  let p = KeySynth.composerPoint(bottomOffset: offset) else { return }
            KeySynth.click(at: p)
        },

        // ── 会话 / 标签 ────────────────────────────────────────
        ActionDef("sessionPrev", L("上一个会话"), L("Session / 聊天 / 标签 / 窗口，看 app"),
                  group: L("会话"), repeatable: true,
                  invocation: .appShortcut("sessionPrev")),
        ActionDef("sessionNext", L("下一个会话"), L("Session / 聊天 / 标签 / 窗口，看 app"),
                  group: L("会话"), repeatable: true,
                  invocation: .appShortcut("sessionNext")),
        ActionDef("contextPrevious", L("上一个上下文"),
                  L("侧边栏线程 / 浏览器项目 / 输入历史，看 app"),
                  group: L("会话"), repeatable: true,
                  supportedIn: [BundleID.amp, BundleID.codex, BundleID.arc,
                                BundleID.wechat, BundleID.warp],
                  invocation: .appShortcut("contextPrevious")),
        ActionDef("contextNext", L("下一个上下文"),
                  L("侧边栏线程 / 浏览器项目 / 输入历史，看 app"),
                  group: L("会话"), repeatable: true,
                  supportedIn: [BundleID.amp, BundleID.codex, BundleID.arc,
                                BundleID.wechat, BundleID.warp],
                  invocation: .appShortcut("contextNext")),
        ActionDef("wechatNextUnread", L("下一个未读会话"), L("微信 · Cmd+Opt+↓"),
                  group: L("会话"), supportedIn: [BundleID.wechat],
                  invocation: .appShortcut("wechatNextUnread")),
        ActionDef("windowNext", L("下一个窗口"), L("同一个 app 的窗口间切换"),
                  group: L("会话"), invocation: .appShortcut("windowNext")),

        // ── App-profile shortcuts ─────────────────────────────
        ActionDef("newSession", L("新建会话"), L("每个 app 使用自己的快捷键"),
                  group: L("会话"),
                  supportedIn: [BundleID.claude, BundleID.wechat, BundleID.amp,
                                BundleID.energy, "com.openai.chat",
                                "com.todesktop.230313mzl4w4u92", "com.microsoft.VSCode"],
                  invocation: .appShortcut("newSession")),
        ActionDef("modelMenu", L("切换模型"), L("Claude 开菜单 / Codex 打 /model"),
                  group: "Claude Code", supportedIn: [BundleID.claude, BundleID.ghostty],
                  invocation: .appShortcut("modelMenu")),
        ActionDef("effortMenu", L("切换 effort"), "Cmd+Shift+E", group: "Claude Code",
                  supportedIn: [BundleID.claude], invocation: .appShortcut("effortMenu")),
        ActionDef("mode", L("切权限模式"), "Codex:Shift+Tab / Claude:Cmd+Shift+M",
                  group: "Claude Code", supportedIn: [BundleID.claude, BundleID.ghostty],
                  invocation: .appShortcut("mode")),
        ActionDef("diffPane", L("切换 diff 面板"), L("看改了什么"), group: "Claude Code",
                  supportedIn: [BundleID.claude], invocation: .appShortcut("diffPane")),
        ActionDef("terminalPane", L("切换终端面板"), L("内置 shell"), group: "Claude Code",
                  supportedIn: [BundleID.claude], invocation: .appShortcut("terminalPane")),
        ActionDef("browserPane", L("切换 Browser 面板"), group: "Claude Code",
                  supportedIn: [BundleID.claude], invocation: .appShortcut("browserPane")),
        ActionDef("sideChat", L("打开 side chat"), group: "Claude Code",
                  supportedIn: [BundleID.claude], invocation: .appShortcut("sideChat")),
        ActionDef("closePane", L("关闭当前分栏"), group: "Claude Code",
                  supportedIn: [BundleID.claude], invocation: .appShortcut("closePane")),
        ActionDef("viewMode", L("循环视图模式"), L("控制正文详细程度"),
                  group: "Claude Code", supportedIn: [BundleID.claude],
                  invocation: .appShortcut("viewMode")),

        // ── 终端 ──────────────────────────────────────────────
        ActionDef("interrupt", "Ctrl+C", L("⚠️ Codex 里这是退出 CLI, 打断请用 Esc"),
                  group: L("终端"), supportedIn: [BundleID.ghostty],
                  invocation: .appShortcut("interrupt")),

        // ── Browsers ──────────────────────────────────────────
        ActionDef("navBack", L("后退"), "Cmd+[", group: L("浏览器"), repeatable: true,
                  supportedIn: [BundleID.chrome, BundleID.arc],
                  invocation: .appShortcut("navBack")),
        ActionDef("navForward", L("前进"), "Cmd+]", group: L("浏览器"), repeatable: true,
                  supportedIn: [BundleID.chrome, BundleID.arc],
                  invocation: .appShortcut("navForward")),
        ActionDef("reload", L("刷新页面"), "Cmd+R", group: L("浏览器"),
                  supportedIn: [BundleID.chrome, BundleID.arc],
                  invocation: .appShortcut("reload")),
        ActionDef("newTab", L("新建标签"), "Cmd+T", group: L("浏览器"),
                  supportedIn: [BundleID.chrome, BundleID.arc],
                  invocation: .appShortcut("newTab")),
        ActionDef("closeTab", L("关闭当前标签"), L("Cmd+W；最后一个标签会连窗口一起关"),
                  group: L("浏览器"), supportedIn: [BundleID.chrome, BundleID.arc],
                  invocation: .appShortcut("closeTab")),

        // ── 切换 app (不受白名单限制, 任何地方都能用) ──────────
        ActionDef("appCycleNext", L("下一个 app"), L("像 ⌘Tab，一按就切换"),
                  group: L("切换 app")) {
            ctx.switchToPrevious()
        },
        ActionDef("appCyclePrevious", L("上一个 app"), L("像 ⌘⇧Tab，一按就切换"),
                  group: L("切换 app")) {
            ctx.switchToNext()
        },
        ActionDef("switchApp", L("切换到上一个 app"), L("连按继续往前翻"), group: L("切换 app")) {
            ctx.switchToPrevious()
        },
    ] + appFocusActions + RaycastShortcuts.actionDefinitions

    /// Old IDs remain resolvable for imported configs and phone bookmarks, but
    /// they are hidden from new mapping menus. Version 14 rewrites only shipped
    /// defaults; genuinely custom bindings are never replaced.
    static let legacyAliases: [String: String] = [
        "ampNewSession": "newSession",
        "energyNewSession": "newSession",
        "ampPreviousThread": "contextPrevious",
        "ampNextThread": "contextNext",
        "codexPreviousThread": "contextPrevious",
        "codexNextThread": "contextNext",
        "arcCommandShiftUp": "contextPrevious",
        "arcCommandShiftDown": "contextNext",
        "arcNavBack": "navBack",
        "arcNavForward": "navForward",
        "arcReload": "reload",
        "arcNewTab": "newTab",
        "arcCloseTab": "closeTab",
    ]

    private static let canonicalByID: [String: ActionDef] =
        Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    static let byID: [String: ActionDef] = {
        var result = canonicalByID
        for (legacy, canonical) in legacyAliases {
            if let action = canonicalByID[canonical] { result[legacy] = action }
        }
        return result
    }()

    static func canonicalID(_ id: String) -> String { legacyAliases[id] ?? id }

    static func action(for id: String) -> ActionDef? { byID[id] }

    static var groups: [String] {
        var seen: [String] = []
        for a in all where !seen.contains(a.group) { seen.append(a.group) }
        return seen
    }

    static func run(_ id: String) {
        guard let a = byID[id] else { return }
        DispatchQueue.main.async { ActionExecutor.execute(a.invocation) }
    }

    static func isRepeatable(_ id: String) -> Bool { byID[id]?.repeatable ?? false }

    /// 在指定 app 下有效的动作。手机界面靠它动态过滤 ——
    /// 换个 app 就变死键的动作不该占着屏幕。
    static func available(in app: String) -> [ActionDef] {
        all.filter { $0.isAvailable(in: app) }
    }

    // MARK: - 语音 (按下/松开语义, 不走普通动作)

    private static var pttWatchdog: Timer?

    static func pttStart() {
        let cfg = ConfigStore.shared.config
        guard cfg.pttStyle == "hold" else {
            pttStroke(cfg); return
        }
        pttPost(down: true)
        // 保险丝: 手柄掉线 / 松开事件丢了, 也不能让修饰键永远卡住
        pttWatchdog?.invalidate()
        pttWatchdog = Timer.scheduledTimer(withTimeInterval: cfg.pttMaxHold, repeats: false) { _ in
            pttPost(down: false)
            NSLog("[JoyCoding] PTT 超过 \(cfg.pttMaxHold)s, 已强制松开")
        }
    }

    static func pttStop() {
        let cfg = ConfigStore.shared.config
        switch cfg.pttStyle {
        case "hold":
            pttWatchdog?.invalidate(); pttWatchdog = nil
            pttPost(down: false)
        case "toggle":
            pttStroke(cfg)
        default:
            break   // "tap": 松开不做事, 靠下次按下停止听写
        }
    }

    private static func pttPost(down: Bool) {
        let cfg = ConfigStore.shared.config
        if cfg.pttFollowRaycast,
           let shortcut = RaycastShortcuts.shortcut(for: "raycastDictation") {
            KeySynth.shortcutHold(shortcut.modifiers, keyCode: shortcut.keyCode, down: down)
            return
        }
        if KeySynth.isModifier(cfg.pttKey) {
            KeySynth.modifierHold(cfg.pttKey, down: down)
        } else {
            KeySynth.shortcutHold(cfg.pttMods, cfg.pttKey, down: down)
        }
    }

    private static func pttStroke(_ cfg: Config) {
        if cfg.pttFollowRaycast,
           let shortcut = RaycastShortcuts.shortcut(for: "raycastDictation") {
            KeySynth.shortcutStroke(shortcut.modifiers, keyCode: shortcut.keyCode)
        } else {
            KeySynth.shortcutStroke(cfg.pttMods, cfg.pttKey)
        }
    }
}
