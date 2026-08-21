import SwiftUI
import AppKit

/// JoyCoding owns its AppKit lifecycle directly. The previous SwiftUI
/// `MenuBarExtra` scene could leave the process alive without registering a
/// status item, which made an LSUIElement app impossible to reopen.
@main
enum JoyCodingApp {
    @MainActor private static let delegate = AppDelegate()

    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}

/// 自己管设置窗口。菜单栏和 Dock 都走同一个窗口实例，避免重复窗口。
final class SettingsWindow: NSObject, NSWindowDelegate {
    static let shared = SettingsWindow()
    private var window: NSWindow?

    private override init() { super.init() }

    func show(tab: SettingsNav.Tab? = nil) {
        HIDProof.shared.record("settingsWindow", ["stage": "show"])
        if let tab { SettingsNav.shared.tab = tab }
        NSApp.activate(ignoringOtherApps: true)

        if let w = window {
            w.makeKeyAndOrderFront(nil)
            return
        }

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1320, height: 880),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        w.title = L("JoyCoding 设置")
        w.contentView = NSHostingView(rootView: SettingsView())
        w.contentMinSize = NSSize(width: 1120, height: 720)
        w.center()
        w.isReleasedWhenClosed = false
        w.delegate = self
        window = w
        w.makeKeyAndOrderFront(nil)
        HIDProof.shared.record("settingsWindow", [
            "stage": "visible", "windowNumber": w.windowNumber,
        ])
    }

    func close() {
        window?.performClose(nil)
    }

    func windowWillClose(_ notification: Notification) {
        HIDInput.shared.setTestMode(false)
    }
}

/// Native AppKit status item. Keeping the NSStatusItem strongly referenced is
/// the deterministic contract: if this object is alive, WindowServer owns a
/// concrete JoyCoding menu-bar window.
@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private var refreshTimer: Timer?

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        menu.delegate = self
        statusItem.menu = menu
        statusItem.button?.toolTip = "JoyCoding"
        refreshStatusItem()
        rebuildMenu()

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshStatusItem() }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    deinit {
        refreshTimer?.invalidate()
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu()
        refreshStatusItem()
    }

    private func refreshStatusItem() {
        guard let button = statusItem.button else { return }
        let devices = HIDInput.shared.devices
        let symbolName = devices.isEmpty ? "gamecontroller" : "gamecontroller.fill"
        let image = NSImage(systemSymbolName: symbolName,
                            accessibilityDescription: "JoyCoding")
        image?.isTemplate = true
        button.image = image
        button.imagePosition = .imageLeading

        if ConfigStore.shared.config.showBatteryInMenuBar,
           let device = devices.first,
           let level = JoyConBattery.shared.levels[device.id] {
            let charging = JoyConBattery.shared.charging[device.id] == true ? " ⚡" : ""
            button.title = " \(level)%\(charging)"
        } else {
            button.title = ""
        }
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        let devices = HIDInput.shared.devices
        if devices.isEmpty {
            addItem(L("没有手柄 — 按一下手柄任意键唤醒"), action: #selector(openMapping))
        } else {
            for device in devices {
                var title = "🎮 \(device.name)"
                if let level = JoyConBattery.shared.levels[device.id] {
                    title += "   \(level)%"
                    if JoyConBattery.shared.charging[device.id] == true { title += " ⚡" }
                }
                addItem(title, action: #selector(openMapping))
            }
        }

        menu.addItem(.separator())
        if KeySynth.hasAccessibility {
            addItem(L("辅助功能 ✓"), action: #selector(openGeneral))
        } else {
            addItem(L("⚠️ 辅助功能未授权 — 去授权"),
                    action: #selector(openAccessibilitySettings))
        }

        if ConfigStore.shared.config.httpEnabled {
            let title = HTTPServer.shared.running
                ? L("遥控端口 %@ ✓", String(ConfigStore.shared.config.httpPort))
                : L("⚠️ 遥控端口未监听")
            addItem(title, action: #selector(openRemote))
        }

        menu.addItem(.separator())
        addItem(L("设置…"), action: #selector(openSettings), keyEquivalent: ",")
        addItem(L("退出 JoyCoding"), action: #selector(quit), keyEquivalent: "q")
    }

    private func addItem(_ title: String, action: Selector,
                         keyEquivalent: String = "") {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        if !keyEquivalent.isEmpty { item.keyEquivalentModifierMask = [.command] }
        menu.addItem(item)
    }

    @objc private func openMapping() { SettingsWindow.shared.show(tab: .mapping) }
    @objc private func openGeneral() { SettingsWindow.shared.show(tab: .general) }
    @objc private func openRemote() { SettingsWindow.shared.show(tab: .remote) }
    @objc private func openSettings() { SettingsWindow.shared.show() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func openAccessibilitySettings() {
        guard let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        else { return }
        NSWorkspace.shared.open(url)
    }
}

/// 外观。默认跟随系统 —— NSApp.appearance = nil 就是“不覆盖”。
enum Appearance {
    static func apply(_ mode: String) {
        switch mode {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark":  NSApp.appearance = NSAppearance(named: .darkAqua)
        default:      NSApp.appearance = nil
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Keep a normal Dock presence as a permanent recovery path.
        NSApp.setActivationPolicy(.regular)
        installMainMenu()
        statusBarController = StatusBarController()

        // 只触发系统授权提示, 不弹自己的模态框 —— 模态框会阻塞后面的启动流程,
        // HTTP 服务就起不来了; 而且每次启动都弹很烦。状态在菜单栏和设置里显示。
        if !HIDProof.shared.dryRun && !KeySynth.hasAccessibility {
            KeySynth.requestAccessibility()
        }

        Appearance.apply(ConfigStore.shared.config.appearance)

        _ = AppContext.shared
        HIDInput.shared.start()
        HTTPServer.shared.restart()

        let configured = ConfigStore.shared.config.devices.contains { !$0.buttons.isEmpty }
        if HIDProof.shared.enabled {
            SettingsWindow.shared.show(tab: .mapping)
        } else if !configured || CommandLine.arguments.contains("--settings") {
            SettingsWindow.shared.show()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindow.shared.show()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        HIDInput.shared.releaseHeldModifiers()
    }

    /// A pure AppKit lifecycle does not synthesize the standard SwiftUI menu
    /// commands. Install the small native menu this utility needs so keyboard
    /// equivalents travel through macOS's normal command routing.
    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "JoyCoding")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let aboutItem = NSMenuItem(
            title: L("关于 JoyCoding"),
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: "")
        aboutItem.target = NSApp
        appMenu.addItem(aboutItem)
        appMenu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: L("设置…"), action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.keyEquivalentModifierMask = [.command]
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: L("退出 JoyCoding"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        quitItem.target = NSApp
        quitItem.keyEquivalentModifierMask = [.command]
        appMenu.addItem(quitItem)

        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: L("文件"))
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        let closeItem = NSMenuItem(
            title: L("关闭窗口"), action: #selector(closeKeyWindow), keyEquivalent: "w")
        closeItem.target = self
        closeItem.keyEquivalentModifierMask = [.command]
        fileMenu.addItem(closeItem)

        NSApp.mainMenu = mainMenu
    }

    @objc private func openSettings() {
        SettingsWindow.shared.show()
    }

    @objc private func closeKeyWindow(_ sender: Any?) {
        SettingsWindow.shared.close()
    }
}
