import Foundation

/// 内置默认配置。
///
/// 配置本身存在 ~/.config/joycoding/config.json (每台机器各一份), 但【默认值
/// 随 app 一起发布】—— 新设备第一次接上时自动套用, 不用从零绑一遍。
/// 这对把 app 交给别人用很重要: 开箱就能用, 只需要授权辅助功能。
enum DefaultProfiles {

    static func make(vendor: Int, product: Int, name: String) -> DeviceProfile? {
        switch (vendor, product) {
        case (XboxHID.vendorID, _): return xbox(name, product: product)
        case (0x057E, 0x2009): return proController(name)
        case (0x054C, _):      return playstation(name)
        case (0x057E, 0x2007): return joyconRight(name)
        default:               return nil
        }
    }

    private static func b(_ pairs: [Int: String]) -> [String: ButtonBinding] {
        Dictionary(uniqueKeysWithValues: pairs.map { (String($0.key), ButtonBinding(tap: $0.value)) })
    }

    /// 十字键的帽子开关值是 HID 标准 (0=上 2=右 4=下 6=左), 不用学。
    /// Joy-Con 的摇杆才需要现场学 —— 横持竖持会整体旋转。
    static let dpad: [String: StickDir] = [
        "up":    .init(hat: 0, action: "scrollUp"),
        "right": .init(hat: 2, action: "sessionNext"),
        "down":  .init(hat: 4, action: "scrollDown"),
        "left":  .init(hat: 6, action: "sessionPrev"),
    ]
    /// Version-5 preset retained so migration can recognize and repair it.
    static let xboxDpad: [String: StickDir] = [
        "up":    .init(hat: 0, action: "commandRightBracket"),
        "right": .init(hat: 2, action: "sessionNext"),
        "down":  .init(hat: 4, action: "commandLeftBracket"),
        "left":  .init(hat: 6, action: "sessionPrev"),
    ]
    /// Version-8 right-stick preset retained so migration can recognize it.
    static let rightStickV8: [String: StickDir] = [
        "up":    .init(hat: 0, action: "up"),
        "right": .init(hat: 2, action: "right"),
        "down":  .init(hat: 4, action: "down"),
        "left":  .init(hat: 6, action: "left"),
    ]
    /// 右摇杆上下滚动；左右仍然移动光标或菜单选择。
    static let rightStick: [String: StickDir] = [
        "up":    .init(hat: 0, action: "scrollUp"),
        "right": .init(hat: 2, action: "right"),
        "down":  .init(hat: 4, action: "scrollDown"),
        "left":  .init(hat: 6, action: "left"),
    ]
    /// 左摇杆在 UI 中移动键盘焦点；按下 L3 激活当前焦点。
    static let leftStickSelection: [String: StickDir] = [
        "up":    .init(hat: 0, action: "focusPrevious"),
        "right": .init(hat: 2, action: "focusNext"),
        "down":  .init(hat: 4, action: "focusNext"),
        "left":  .init(hat: 6, action: "focusPrevious"),
    ]

    // MARK: - Xbox

    private static func xbox(_ name: String, product: Int) -> DeviceProfile {
        var p = DeviceProfile(vendorID: XboxHID.vendorID, productID: product, name: name)
        p.buttons = b([
            1: "confirm",       // A
            2: "cancel",        // B
            3: "clearLine",     // X
            4: "delete",        // Y
            5: "raycastPreviousSpace", // LB — Raycast Switch to Previous Space
            6: "raycastNextSpace",     // RB — Raycast Switch to Next Space
            7: "focusInput",    // View
            8: "raycastLauncher", // Menu
            9: "selectFocused", // left stick click — activate keyboard focus
            10: "sideChat",     // right stick click
            XboxHID.leftTriggerButton: "ptt",
            XboxHID.rightTriggerButton: "switchApp",
            // 11 = Xbox button: macOS reserves the guide/menu behaviour.
            // Elite Profile is handled by the controller and emits no HID event.
        ])
        // Long presses preserve every existing tap while exposing common work apps directly.
        p.buttons["3"]?.long = "raycastEmojiPicker" // X tap still clears input
        p.buttons["5"]?.long = "raycastSlack"
        p.buttons["6"] = ButtonBinding(tap: "raycastNextSpace", long: "raycastWarp")
        p.buttons["7"]?.long = "raycastClipboardHistory"
        p.buttons["8"]?.long = "raycastAIChat"
        p.buttons["9"]?.long = "raycastCodex"
        p.buttons["10"]?.long = "raycastAmp"        // R3 tap still opens side chat
        p.sticks = [
            StickChannel.hat.rawValue: dpad,
            StickChannel.left.rawValue: leftStickSelection,
            StickChannel.right.rawValue: rightStick,
        ]
        p.overrides = [
            BundleID.chrome: AppOverride(buttons: [
                "4": ButtonBinding(tap: "navBack"),
                "7": ButtonBinding(tap: "closeTab", long: "raycastClipboardHistory"),
            ]),
            BundleID.arc: AppOverride(buttons: [
                "4": ButtonBinding(tap: "arcNavBack"),
                "7": ButtonBinding(tap: "arcCloseTab", long: "raycastClipboardHistory"),
            ]),
            BundleID.amp: AppOverride(
                buttons: [
                    "8": ButtonBinding(tap: "ampNewSession", long: "raycastAIChat"),
                ],
                sticks: [
                    StickChannel.hat.rawValue: [
                        "up": "ampPreviousThread",
                        "down": "ampNextThread",
                    ],
                ]),
            BundleID.codex: AppOverride(sticks: [
                StickChannel.hat.rawValue: [
                    "up": "codexPreviousThread",
                    "down": "codexNextThread",
                ],
            ]),
            BundleID.wechat: AppOverride(sticks: [
                StickChannel.hat.rawValue: [
                    "up": "up",
                    "down": "down",
                ],
            ]),
        ]
        return p
    }

    // MARK: - Switch Pro

    private static func proController(_ name: String) -> DeviceProfile {
        var p = DeviceProfile(vendorID: 0x057E, productID: 0x2009, name: name)
        p.buttons = b([
            1: "confirm",       // A
            2: "clearLine",     // X
            3: "cancel",        // B
            4: "delete",        // Y
            5: "confirm",       // L   单手时左手也能发送
            6: "focusGhostty",  // R
            7: "ptt",           // ZL  按住说话
            8: "switchApp",     // ZR
            9: "focusInput",    // −
            10: "modelMenu",    // +
            11: "cancel",       // 左摇杆按下
            12: "sideChat",     // 右摇杆按下
            14: "focusWeChat",  // 截图键
            // 13 = Home 故意留空: macOS 原生接管 Pro 手柄, 这个键被系统
            // 截去开游戏覆盖层, 绑什么都不会生效
        ])
        p.sticks = ["hat": dpad, "right": rightStick]
        p.overrides = [BundleID.chrome: AppOverride(
            buttons: b([2: "reload", 4: "navBack"]))]
        return p
    }

    // MARK: - PlayStation

    private static func playstation(_ name: String) -> DeviceProfile {
        var p = DeviceProfile(vendorID: 0x054C, productID: 0, name: name)
        p.buttons = b([
            // 面键按【西方惯例】: ✕ 确认、○ 取消。位置上 ✕ 在下、○ 在右,
            // 和任天堂的 A/B 正好相反, 照搬位置反而不合 PS 用户的手感。
            2: "confirm",       // ✕
            3: "cancel",        // ○
            4: "clearLine",     // △
            1: "delete",        // □
            5: "confirm",       // L1
            6: "focusGhostty",  // R1
            7: "ptt",           // L2
            8: "switchApp",     // R2
            9: "focusInput",    // Create / Share
            10: "modelMenu",    // Options
            11: "cancel",       // L3
            12: "sideChat",     // R3
            14: "focusWeChat",  // 触摸板按下
            // 13 = PS 键留空, 多半和 Pro 的 Home 一样被系统截走
        ])
        p.sticks = ["hat": dpad, "right": rightStick]
        p.overrides = [BundleID.chrome: AppOverride(
            buttons: b([4: "reload", 1: "navBack"]))]
        return p
    }

    // MARK: - Joy-Con (R)

    private static func joyconRight(_ name: String) -> DeviceProfile {
        var p = DeviceProfile(vendorID: 0x057E, productID: 0x2007, name: name)
        p.buttons = b([
            1: "confirm", 2: "clearLine", 3: "cancel", 4: "delete",
            5: "focusClaude", 6: "focusGhostty",
            10: "focusInput", 12: "modelMenu", 13: "focusWeChat",
            15: "ptt", 16: "switchApp",
        ])
        // Chrome 里 X/Y/加号 本来的动作都是死键, 让给浏览器操作
        p.overrides = [BundleID.chrome: AppOverride(
            buttons: b([2: "reload", 4: "navBack", 10: "closeTab"]))]
        // 摇杆方向【不给默认值】: Joy-Con 横持和竖持会让帽子开关整体转 90°,
        // 猜错了比不给更糟。首次使用要跑一次"学习方向"。
        return p
    }
}
