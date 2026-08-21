import Foundation
import IOKit.hid
import Combine

struct ConnectedDevice: Identifiable, Equatable {
    let vendorID: Int
    let productID: Int
    let name: String
    var id: String { DeviceProfile.key(vendorID, productID) }
}

/// 原始输入, 给 GUI 的"按一下要绑的键"用
enum RawInput: Equatable {
    case button(Int, down: Bool)
    case hat(Int?, StickChannel)
}

/// 手柄输入层。按 HID 用途匹配而不是写死厂商 —— Joy-Con / PS / Xbox / 8BitDo
/// 上报的都是 usagePage=1(GenericDesktop) + usage=5(GamePad) 或 4(Joystick)。
final class HIDInput: ObservableObject {
    static let shared = HIDInput()

    @Published private(set) var devices: [ConnectedDevice] = []
    /// 旁观者: 界面用来实时点亮按下的键。【绝不拦截】动作派发 ——
    /// 早期版本把它做成拦截式的, 结果一打开设置页手柄就在所有地方失效了。
    var previewHandler: ((RawInput) -> Void)?
    /// 拦截式: 只在"学习摇杆方向"时设上, 期间摇杆不触发动作
    var captureHandler: ((RawInput) -> Void)?
    /// 排查用: 最后一次收到的输入, 不管来自哪只手柄
    @Published private(set) var lastInput = L("还没收到任何输入")
    /// 排查用: 按键走到哪一步了
    @Published private(set) var lastDispatch = "—"
    @Published private(set) var inputCount = 0
    /// Mapping 页的安全试按模式。输入仍会高亮和解析绑定，但绝不派发动作。
    @Published private(set) var testMode = false

    private var manager: IOHIDManager?
    private var lastButton: [String: Int] = [:]
    private var lastHat: [String: Int?] = [:]   // 通道 -> 上次方向
    private var triggerState: [String: Bool] = [:]
    private struct StickAxisState {
        var x = 0.0
        var y = 0.0
        var direction: Int?
    }
    private var stickAxes: [String: StickAxisState] = [:]
    /// 走原始报告解析的设备。这些设备的标准 HID 元素不再上报,
    /// 也不能让元素路径和原始路径同时派发, 否则会触发两次。
    private var rawDevices: Set<String> = []
    private var rawButtons: [String: Set<Int>] = [:]

    // 手势状态
    private var pressTime: [Int: Date] = [:]
    private var longTimers: [Int: Timer] = [:]
    private var longFired: Set<Int> = []
    private var pendingTap: [Int: Timer] = [:]
    private var repeatTimer: Timer?
    private var repeatButton: Int?
    private var pttActive = false
    private var activeButtons: Set<String> = []
    /// A press that began while Test Mode was on stays suppressed through release,
    /// even if the toggle is turned off while the physical button is still held.
    private var testSuppressedButtons: Set<String> = []

    private let doubleWindow: TimeInterval = 0.28
    private let longDelay: TimeInterval = 0.45

    private init() {}

    func setTestMode(_ enabled: Bool) {
        guard testMode != enabled else { return }
        cancelPendingGestures()
        if enabled { testSuppressedButtons.formUnion(activeButtons) }
        // 如果是在按住 PTT 时打开测试模式，先补发松开，不能留下卡住的修饰键。
        if enabled, pttActive {
            Actions.pttStop()
            pttActive = false
        }
        testMode = enabled
        lastDispatch = enabled ? L("测试模式：动作已暂停") : L("测试模式已关闭")
        HIDProof.shared.record("testMode", ["enabled": enabled])
    }

    static func suppressesActions(inTestMode: Bool,
                                  pressBeganInTestMode: Bool = false) -> Bool {
        inTestMode || pressBeganInTestMode
    }

    private func cancelPendingGestures() {
        for timer in longTimers.values { timer.invalidate() }
        for timer in pendingTap.values { timer.invalidate() }
        longTimers.removeAll()
        pendingTap.removeAll()
        pressTime.removeAll()
        longFired.removeAll()
        repeatTimer?.invalidate(); repeatTimer = nil; repeatButton = nil
    }

    // MARK: - 启动

    func start() {
        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = mgr

        IOHIDManagerSetDeviceMatchingMultiple(mgr, [
            [kIOHIDDeviceUsagePageKey: 0x01, kIOHIDDeviceUsageKey: 0x05],   // GamePad
            [kIOHIDDeviceUsagePageKey: 0x01, kIOHIDDeviceUsageKey: 0x04],   // Joystick
        ] as CFArray)

        let ctx = Unmanaged.passUnretained(self).toOpaque()

        IOHIDManagerRegisterInputValueCallback(mgr, { ctx, _, _, value in
            guard let ctx else { return }
            Unmanaged<HIDInput>.fromOpaque(ctx).takeUnretainedValue().handle(value)
        }, ctx)

        IOHIDManagerRegisterDeviceMatchingCallback(mgr, { ctx, _, _, _ in
            guard let ctx else { return }
            let s = Unmanaged<HIDInput>.fromOpaque(ctx).takeUnretainedValue()
            DispatchQueue.main.async { s.refreshDevices() }
        }, ctx)

        IOHIDManagerRegisterDeviceRemovalCallback(mgr, { ctx, _, _, _ in
            guard let ctx else { return }
            let s = Unmanaged<HIDInput>.fromOpaque(ctx).takeUnretainedValue()
            DispatchQueue.main.async { s.refreshDevices() }
        }, ctx)

        IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        // 非独占打开: 别的程序(比如系统的手柄框架)也能同时读, 不互相踢
        IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        refreshDevices()
    }

    /// 新设备第一次接上时套用内置默认配置。已有配置的绝不覆盖 ——
    /// 用户改过的东西不能被"默认值"冲掉。
    static func seedDefaults(_ d: ConnectedDevice) {
        let store = ConfigStore.shared
        guard !store.config.devices.contains(where: { $0.id == d.id }),
              var p = DefaultProfiles.make(vendor: d.vendorID, product: d.productID, name: d.name)
        else { return }
        p.productID = d.productID       // PS 系列产品号不止一个, 用实际连上的
        store.config.devices.append(p)
        store.save()
        NSLog("[JoyCoding] 为 \(d.name) 套用了内置默认配置")
    }

    private func refreshDevices() {
        guard let mgr = manager,
              let set = IOHIDManagerCopyDevices(mgr) as? Set<IOHIDDevice> else {
            devices = []; return
        }
        let found: [ConnectedDevice] = set.compactMap { d in
            guard let v = IOHIDDeviceGetProperty(d, kIOHIDVendorIDKey as CFString) as? Int,
                  let p = IOHIDDeviceGetProperty(d, kIOHIDProductIDKey as CFString) as? Int
            else { return nil }
            let reported = IOHIDDeviceGetProperty(d, kIOHIDProductKey as CFString) as? String ?? L("手柄")
            let n = XboxHID.displayName(vendor: v, product: p, reported: reported)
            let dev = ConnectedDevice(vendorID: v, productID: p, name: n)
            JoyConBattery.shared.attach(d, id: dev.id)
            HIDInput.seedDefaults(dev)
            let profile = ConfigStore.shared.config.devices.first { $0.id == dev.id }
            HIDProof.shared.record("device", [
                "name": n, "vendorID": v, "productID": p,
                "deviceID": dev.id, "mappedButtons": profile?.buttons.count ?? 0,
                "mappedDirections": profile?.sticks.values.reduce(0) { $0 + $1.count } ?? 0,
            ])
            return dev
        }.sorted { $0.name < $1.name }

        for gone in devices where !found.contains(gone) { JoyConBattery.shared.detach(id: gone.id) }
        devices = found
    }

    // MARK: - 事件分发

    private func handle(_ value: IOHIDValue) {
        let elem = IOHIDValueGetElement(value)
        let page = IOHIDElementGetUsagePage(elem)
        let usage = Int(IOHIDElementGetUsage(elem))
        let v = Int(IOHIDValueGetIntegerValue(value))

        // 来自哪只手柄。只记真实输入 —— 厂商页上那些 0x21 子命令回复是
        // 电量轮询的产物, 混在里面会盖掉真正的按键记录。
        let dev = IOHIDElementGetDevice(elem)
        let reportedName = IOHIDDeviceGetProperty(dev, kIOHIDProductKey as CFString) as? String ?? "?"
        let vendor = IOHIDDeviceGetProperty(dev, kIOHIDVendorIDKey as CFString) as? Int
        let product = IOHIDDeviceGetProperty(dev, kIOHIDProductIDKey as CFString) as? Int
        let name = vendor.flatMap { v0 in product.map {
            XboxHID.displayName(vendor: v0, product: $0, reported: reportedName)
        }} ?? reportedName
        let canonicalButton = vendor.flatMap { v0 in product.flatMap {
            XboxHID.canonicalButton(vendor: v0, product: $0,
                                    usagePage: Int(page), usage: usage)
        }}
        if page == UInt32(kHIDPage_Button) || page == UInt32(kHIDPage_GenericDesktop)
            || page == UInt32(XboxHID.simulationPage) || canonicalButton != nil {
            DispatchQueue.main.async {
                self.inputCount += 1
                self.lastInput = "#\(self.inputCount) \(name) page=0x\(String(page, radix: 16)) "
                    + "usage=\(usage) v=\(v)"
            }
            HIDProof.shared.record("rawInput", [
                "name": name, "usagePage": Int(page), "usage": usage, "value": v,
                "logicalMin": IOHIDElementGetLogicalMin(elem),
                "logicalMax": IOHIDElementGetLogicalMax(elem),
            ])
        }
        let devID = vendor.flatMap { v0 in product.map { DeviceProfile.key(v0, $0) } } ?? ""

        if rawDevices.contains(devID) {
            return      // 这只手柄走原始报告, 元素事件丢弃
        }

        // Xbox 的两根模拟摇杆是四条 Generic Desktop 轴。归一化并加迟滞后,
        // 复用帽子开关的方向/连发/测试模式路径。
        if let vendor,
           let axis = XboxHID.stickAxis(
                vendor: vendor, usagePage: Int(page), usage: usage) {
            let key = "\(devID)/\(axis.channel.rawValue)"
            var state = stickAxes[key] ?? StickAxisState()
            let value = HIDNormalization.axis(
                raw: v,
                logicalMin: IOHIDElementGetLogicalMin(elem),
                logicalMax: IOHIDElementGetLogicalMax(elem))
            switch axis.component {
            case .x: state.x = value
            case .y: state.y = value
            }
            let previous = state.direction
            let direction = HIDNormalization.stickDirection(
                x: state.x, y: state.y, previous: previous)
            state.direction = direction
            stickAxes[key] = state
            guard direction != previous else { return }
            DispatchQueue.main.async {
                self.onHat(direction, device: devID, ch: axis.channel)
            }
            return
        }

        // 摇杆走帽子开关, 逻辑范围 0...7, 越界即回中
        if page == UInt32(kHIDPage_GenericDesktop) && usage == 0x39 {
            let dir = HIDNormalization.hat(
                raw: v,
                logicalMin: IOHIDElementGetLogicalMin(elem),
                logicalMax: IOHIDElementGetLogicalMax(elem))
            let key = "\(devID)/\(StickChannel.hat.rawValue)"
            if lastHat[key] ?? -1 == dir { return }
            lastHat[key] = dir
            DispatchQueue.main.async { self.onHat(dir, device: devID, ch: .hat) }
            return
        }

        // Xbox LT/RT are analog axes, not Button-page elements. Expose them as
        // ordinary buttons so tap/hold/PTT semantics need no Xbox-specific path.
        if let vendor,
           let button = XboxHID.virtualButton(vendor: vendor, usagePage: Int(page), usage: usage) {
            let key = "\(devID)/axis/\(usage)"
            let wasPressed = triggerState[key] ?? false
            let pressed = HIDNormalization.triggerPressed(
                raw: v,
                logicalMin: IOHIDElementGetLogicalMin(elem),
                logicalMax: IOHIDElementGetLogicalMax(elem),
                wasPressed: wasPressed)
            guard pressed != wasPressed else { return }
            triggerState[key] = pressed
            DispatchQueue.main.async { self.onButton(button, down: pressed, device: devID) }
            return
        }

        guard let button = canonicalButton else { return }
        let buttonKey = "\(devID)/\(page)/\(usage)"
        if lastButton[buttonKey] == v { return }        // 去抖
        lastButton[buttonKey] = v
        DispatchQueue.main.async { self.onButton(button, down: v == 1, device: devID) }
    }

    private var profile: DeviceProfile? {
        guard let d = devices.first else { return nil }
        return ConfigStore.shared.config.devices
            .first { $0.vendorID == d.vendorID && $0.productID == d.productID }
    }

    /// 按设备 id 取配置 —— 两只手柄同时连着时各用各的
    private func profile(_ id: String) -> DeviceProfile? {
        ConfigStore.shared.config.devices.first { $0.id == id }
    }

    /// 原始报告解析出的状态。和元素路径复用同一套手势/动作逻辑,
    /// 只是入口不同 —— 这样 Pro 手柄和 Joy-Con 的行为完全一致。
    func injectRaw(deviceID: String, buttons: Set<Int>, dirs: [StickChannel: Int?]) {
        rawDevices.insert(deviceID)

        let prev = rawButtons[deviceID] ?? []
        rawButtons[deviceID] = buttons
        for n in buttons.subtracting(prev) { onButton(n, down: true, device: deviceID) }
        for n in prev.subtracting(buttons) { onButton(n, down: false, device: deviceID) }

        for (ch, dir) in dirs {
            let key = "\(deviceID)/\(ch.rawValue)"
            if lastHat[key] ?? -1 == dir { continue }
            lastHat[key] = dir
            onHat(dir, device: deviceID, ch: ch)
        }
    }

    // MARK: - 按键手势

    private func onButton(_ n: Int, down: Bool, device: String) {
        HIDProof.shared.record("button", ["deviceID": device, "button": n, "down": down])
        previewHandler?(.button(n, down: down))
        let physicalKey = "\(device)/\(n)"
        if down { activeButtons.insert(physicalKey) } else { activeButtons.remove(physicalKey) }
        // 覆盖优先, 回落基础层
        let app = AppContext.shared.frontBundle
        guard let prof = profile(device) else {
            HIDProof.shared.record("unmapped", ["deviceID": device, "button": n, "reason": "noProfile"])
            if down { lastDispatch = L("按键%@ [%@] 找不到配置", String(n), device) }
            return
        }
        guard let b = prof.binding(button: n, app: app), !b.isEmpty else {
            HIDProof.shared.record("unmapped", ["deviceID": device, "button": n, "reason": "noBinding"])
            if down { lastDispatch = L("按键%@ [%@] 没绑动作", String(n), device) }
            return
        }
        if down {
            lastDispatch = L("按键 %@ [%@] -> %@", String(n), device, b.tap ?? "?")
            HIDProof.shared.record("binding", [
                "deviceID": device, "button": n, "action": b.tap ?? "?", "app": app,
            ])
        }

        if testMode && down { testSuppressedButtons.insert(physicalKey) }
        if HIDInput.suppressesActions(
            inTestMode: testMode,
            pressBeganInTestMode: testSuppressedButtons.contains(physicalKey)) {
            if down {
                let gestures = [
                    b.tap.map { L("单击：%@", Actions.byID[$0]?.name ?? $0) },
                    b.double.map { L("双击：%@", Actions.byID[$0]?.name ?? $0) },
                    b.long.map { L("长按：%@", Actions.byID[$0]?.name ?? $0) },
                ].compactMap { $0 }.joined(separator: " · ")
                lastDispatch = L("测试 按键 %@：%@", String(n), gestures)
                HIDProof.shared.record("suppressed", [
                    "reason": "testMode", "deviceID": device, "button": n,
                    "actions": gestures,
                ])
            }
            if !down { testSuppressedButtons.remove(physicalKey) }
            return
        }

        // 语音是按下/松开语义, 不参与单击双击长按
        if b.tap == "ptt" {
            pttActive = down
            proofAction(down ? "pttStart" : "pttStop") {
                down ? Actions.pttStart() : Actions.pttStop()
            }
            return
        }

        if down {
            pressTime[n] = Date()
            longFired.remove(n)

            if let long = b.long {
                longTimers[n] = Timer.scheduledTimer(withTimeInterval: longDelay, repeats: false) { _ in
                    self.longFired.insert(n)
                    self.runAction(long)
                }
            } else if let tap = b.tap, b.double == nil, Actions.isRepeatable(tap) {
                // 没绑长按才连发, 否则两者会打架
                startRepeat(n, tap)
            }
        } else {
            longTimers[n]?.invalidate(); longTimers[n] = nil
            stopRepeat(n)
            if longFired.contains(n) { longFired.remove(n); return }

            guard let tap = b.tap else { return }

            guard b.double != nil else { runAction(tap); return }

            // 绑了双击才需要等 —— 否则每次单击都白白多等 0.28 秒
            if let pending = pendingTap[n] {
                pending.invalidate(); pendingTap[n] = nil
                runAction(b.double!)
            } else {
                pendingTap[n] = Timer.scheduledTimer(withTimeInterval: doubleWindow, repeats: false) { _ in
                    self.pendingTap[n] = nil
                    self.runAction(tap)
                }
            }
        }
    }

    /// 长按连发, 和键盘重复一个手感
    private func startRepeat(_ n: Int, _ action: String) {
        repeatButton = n
        repeatTimer?.invalidate()
        repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { _ in
            self.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { _ in
                self.runAction(action)
            }
        }
    }

    private func stopRepeat(_ n: Int) {
        guard repeatButton == n else { return }
        repeatTimer?.invalidate(); repeatTimer = nil; repeatButton = nil
    }

    // MARK: - 摇杆

    private func onHat(_ dir: Int?, device: String, ch: StickChannel) {
        HIDProof.shared.record("hat", [
            "deviceID": device, "channel": ch.rawValue, "direction": dir ?? -1,
        ])
        previewHandler?(.hat(dir, ch))
        // 学习方向时才拦截, 免得学的过程中摇杆还在翻页
        if let cap = captureHandler { cap(.hat(dir, ch)); return }
        repeatTimer?.invalidate(); repeatTimer = nil; repeatButton = nil

        if HIDInput.suppressesActions(inTestMode: testMode) {
            guard let dir, let p = profile(device),
                  let key = HIDInput.nearestKey(dir, p.sticks[ch.rawValue] ?? [:]),
                  let action = p.stickAction(ch, dir: key,
                                             app: AppContext.shared.frontBundle)
            else { return }
            let name = Actions.byID[action]?.name ?? action
            lastDispatch = L("测试 %@ %@：%@", ch.label,
                             DeviceProfile.dirLabel[key] ?? key, name)
            HIDProof.shared.record("suppressed", [
                "reason": "testMode", "deviceID": device,
                "channel": ch.rawValue, "direction": dir, "action": action,
            ])
            return
        }

        guard let dir, let p = profile(device),
              let key = HIDInput.nearestKey(dir, p.sticks[ch.rawValue] ?? [:]),
              let action = p.stickAction(ch, dir: key, app: AppContext.shared.frontBundle)
        else { return }
        runAction(action)
        repeatButton = -1
        repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { _ in
            self.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { _ in
                self.runAction(action)
            }
        }
    }

    private func runAction(_ action: String) {
        proofAction(action) { Actions.run(action) }
    }

    private func proofAction(_ action: String, run: () -> Void) {
        HIDProof.shared.record("action", ["action": action])
        if !HIDProof.shared.dryRun { run() }
    }

    /// 帽子开关是 8 方向环形。取最近的已学方向, 斜推也能落到正确的一边。
    /// 当前推的方向对应哪个 "up"/"down"/"left"/"right", 给界面高亮用
    static func nearestKey(_ value: Int, _ dirs: [String: StickDir]) -> String? {
        var best: (String, Int)?
        for (key, d) in dirs {
            let diff = abs(value - d.hat) % 8
            let dist = min(diff, 8 - diff)
            if best == nil || dist < best!.1 { best = (key, dist) }
        }
        guard let b = best, b.1 <= 1 else { return nil }
        return b.0
    }
}
