import XCTest
import CoreGraphics
@testable import JoyCoding

final class HIDNormalizationTests: XCTestCase {
    func testXboxOneBasedHatBecomesZeroBasedAndRejectsCentre() {
        XCTAssertEqual(HIDNormalization.hat(raw: 1, logicalMin: 1, logicalMax: 8), 0)
        XCTAssertEqual(HIDNormalization.hat(raw: 3, logicalMin: 1, logicalMax: 8), 2)
        XCTAssertEqual(HIDNormalization.hat(raw: 5, logicalMin: 1, logicalMax: 8), 4)
        XCTAssertEqual(HIDNormalization.hat(raw: 7, logicalMin: 1, logicalMax: 8), 6)
        XCTAssertEqual(HIDNormalization.hat(raw: 8, logicalMin: 1, logicalMax: 8), 7)
        XCTAssertNil(HIDNormalization.hat(raw: 0, logicalMin: 1, logicalMax: 8))
        XCTAssertNil(HIDNormalization.hat(raw: 9, logicalMin: 1, logicalMax: 8))
    }

    func testZeroBasedHatRemainsCompatible() {
        XCTAssertEqual(HIDNormalization.hat(raw: 0, logicalMin: 0, logicalMax: 7), 0)
        XCTAssertEqual(HIDNormalization.hat(raw: 7, logicalMin: 0, logicalMax: 7), 7)
        XCTAssertNil(HIDNormalization.hat(raw: 8, logicalMin: 0, logicalMax: 7))
    }

    func testXboxTriggerUsesHysteresis() {
        XCTAssertFalse(HIDNormalization.triggerPressed(
            raw: 80, logicalMin: 0, logicalMax: 1023, wasPressed: false))
        XCTAssertTrue(HIDNormalization.triggerPressed(
            raw: 120, logicalMin: 0, logicalMax: 1023, wasPressed: false))
        XCTAssertTrue(HIDNormalization.triggerPressed(
            raw: 60, logicalMin: 0, logicalMax: 1023, wasPressed: true))
        XCTAssertFalse(HIDNormalization.triggerPressed(
            raw: 40, logicalMin: 0, logicalMax: 1023, wasPressed: true))
    }

    func testOnlyMicrosoftSimulationAxesBecomeTriggerButtons() {
        XCTAssertEqual(XboxHID.virtualButton(
            vendor: 0x045E, usagePage: 0x02, usage: 0xC5), XboxHID.leftTriggerButton)
        XCTAssertEqual(XboxHID.virtualButton(
            vendor: 0x045E, usagePage: 0x02, usage: 0xC4), XboxHID.rightTriggerButton)
        XCTAssertNil(XboxHID.virtualButton(vendor: 0x054C, usagePage: 0x02, usage: 0xC5))
        XCTAssertNil(XboxHID.virtualButton(vendor: 0x045E, usagePage: 0x09, usage: 0xC5))
    }

    func testElite2PaddleMaskUsesThePhysicallyRecordedOrder() {
        func buttons(_ mask: Int) -> Set<Int>? {
            XboxHID.paddleButtons(
                vendor: 0x045E, product: 0x0B22,
                usagePage: 0x0C, usage: 0x81, mask: mask)
        }
        XCTAssertEqual(buttons(4), [XboxHID.paddle1Button])
        XCTAssertEqual(buttons(1), [XboxHID.paddle2Button])
        XCTAssertEqual(buttons(8), [XboxHID.paddle3Button])
        XCTAssertEqual(buttons(2), [XboxHID.paddle4Button])
        XCTAssertEqual(buttons(15), Set([
            XboxHID.paddle1Button, XboxHID.paddle2Button,
            XboxHID.paddle3Button, XboxHID.paddle4Button,
        ]))
        XCTAssertEqual(buttons(0), [])
        XCTAssertNil(XboxHID.paddleButtons(
            vendor: 0x045E, product: 0x0B22,
            usagePage: 0x09, usage: 0x81, mask: 15))
        XCTAssertNil(XboxHID.paddleButtons(
            vendor: 0x054C, product: 0x0B22,
            usagePage: 0x0C, usage: 0x81, mask: 15))
    }

    func testElite2BLEButtonsUseCanonicalXboxNames() {
        let pairs = [1: 1, 2: 2, 4: 3, 5: 4, 7: 5, 8: 6,
                     11: 7, 12: 8, 13: 11, 14: 9, 15: 10]
        for (raw, canonical) in pairs {
            XCTAssertEqual(XboxHID.canonicalButton(
                vendor: 0x045E, product: 0x0B22,
                usagePage: XboxHID.buttonPage, usage: raw), canonical)
        }
        XCTAssertNil(XboxHID.canonicalButton(
            vendor: 0x045E, product: 0x0B22,
            usagePage: XboxHID.buttonPage, usage: 3))
        XCTAssertNil(XboxHID.canonicalButton(
            vendor: 0x045E, product: 0x0B22,
            usagePage: XboxHID.buttonPage, usage: 6))
        XCTAssertNil(XboxHID.canonicalButton(
            vendor: 0x045E, product: 0x0B22,
            usagePage: 0x0C, usage: 0xB2))
    }

    func testXboxAnalogAxesAreSeparateDirectionChannels() {
        XCTAssertEqual(XboxHID.stickAxis(
            vendor: 0x045E, usagePage: 0x01, usage: 0x30),
            XboxHID.StickAxis(channel: .left, component: .x))
        XCTAssertEqual(XboxHID.stickAxis(
            vendor: 0x045E, usagePage: 0x01, usage: 0x31),
            XboxHID.StickAxis(channel: .left, component: .y))
        XCTAssertEqual(XboxHID.stickAxis(
            vendor: 0x045E, usagePage: 0x01, usage: 0x32),
            XboxHID.StickAxis(channel: .right, component: .x))
        XCTAssertEqual(XboxHID.stickAxis(
            vendor: 0x045E, usagePage: 0x01, usage: 0x35),
            XboxHID.StickAxis(channel: .right, component: .y))
        XCTAssertNil(XboxHID.stickAxis(
            vendor: 0x054C, usagePage: 0x01, usage: 0x30))
    }

    func testXboxAnalogStickDirectionUsesDeadZoneAndHysteresis() {
        XCTAssertEqual(HIDNormalization.axis(
            raw: 0, logicalMin: 0, logicalMax: 65535), -1, accuracy: 0.0001)
        XCTAssertEqual(HIDNormalization.axis(
            raw: 65535, logicalMin: 0, logicalMax: 65535), 1, accuracy: 0.0001)
        XCTAssertEqual(HIDNormalization.axis(
            raw: 32768, logicalMin: 0, logicalMax: 65535), 0, accuracy: 0.0001)

        XCTAssertNil(HIDNormalization.stickDirection(x: 0.30, y: 0, previous: nil))
        XCTAssertEqual(HIDNormalization.stickDirection(x: 0.70, y: 0, previous: nil), 2)
        XCTAssertEqual(HIDNormalization.stickDirection(x: -0.70, y: 0, previous: nil), 6)
        XCTAssertEqual(HIDNormalization.stickDirection(x: 0, y: -0.70, previous: nil), 0)
        XCTAssertEqual(HIDNormalization.stickDirection(x: 0, y: 0.70, previous: nil), 4)
        XCTAssertEqual(HIDNormalization.stickDirection(x: 0.40, y: 0, previous: 2), 2)
        XCTAssertNil(HIDNormalization.stickDirection(x: 0.30, y: 0, previous: 2))
    }

    func testOtherControllersKeepTheirButtonUsages() {
        XCTAssertEqual(XboxHID.canonicalButton(
            vendor: 0x045E, product: 0x0B13,
            usagePage: XboxHID.buttonPage, usage: 3), 3)
        XCTAssertEqual(XboxHID.canonicalButton(
            vendor: 0x057E, product: 0x2009,
            usagePage: XboxHID.buttonPage, usage: 4), 4)
    }

    func testElite2UsesItsPhysicalArtworkAndName() throws {
        XCTAssertEqual(XboxHID.displayName(
            vendor: 0x045E, product: 0x0B22,
            reported: "Xbox Wireless Controller"), "Xbox Elite Series 2")

        let anchors = DeviceArt.art(vendor: 0x045E, product: 0x0B22).anchors
        XCTAssertEqual(anchors.first { $0.id == 3 }?.label, "X")
        XCTAssertEqual(anchors.first { $0.id == 4 }?.label, "Y")
        XCTAssertEqual(anchors.first { $0.id == 5 }?.label, "LB")
        XCTAssertEqual(anchors.first { $0.id == 7 }?.label, "View")
        XCTAssertEqual(anchors.first { $0.id == 8 }?.label, "Menu")
        XCTAssertEqual(anchors.first { $0.id == 11 }?.label, "Xbox")
        XCTAssertEqual(anchors.first { $0.id == 12 }?.label, "Profile")
        XCTAssertEqual(anchors.first { $0.id == XboxHID.paddle1Button }?.label, "P1")
        XCTAssertEqual(anchors.first { $0.id == XboxHID.paddle2Button }?.label, "P2")
        XCTAssertEqual(anchors.first { $0.id == XboxHID.paddle3Button }?.label, "P3")
        XCTAssertEqual(anchors.first { $0.id == XboxHID.paddle4Button }?.label, "P4")
    }

    func testXboxShipsWithUsableDefaults() throws {
        let profile = try XCTUnwrap(DefaultProfiles.make(
            vendor: 0x045E, product: 0x0B22, name: "Xbox Wireless Controller"))
        XCTAssertEqual(profile.productID, 0x0B22)
        XCTAssertEqual(profile.buttons["1"]?.tap, "confirm")
        XCTAssertEqual(profile.buttons[String(XboxHID.leftTriggerButton)]?.tap, "ptt")
        XCTAssertEqual(profile.buttons[String(XboxHID.rightTriggerButton)]?.tap, "switchApp")
        XCTAssertEqual(profile.buttons["5"]?.tap, "raycastPreviousSpace")
        XCTAssertEqual(profile.buttons["3"]?.long, "raycastEmojiPicker")
        XCTAssertEqual(profile.buttons["5"]?.long, "raycastSlack")
        XCTAssertEqual(profile.buttons["6"],
                       ButtonBinding(tap: "raycastNextSpace", long: "raycastWarp"))
        XCTAssertEqual(profile.buttons["7"]?.long, "raycastClipboardHistory")
        XCTAssertEqual(profile.buttons["8"], ButtonBinding(tap: "raycastLauncher", long: "raycastAIChat"))
        XCTAssertEqual(profile.buttons["9"]?.tap, "selectFocused")
        XCTAssertEqual(profile.buttons["9"]?.long, "raycastCodex")
        XCTAssertEqual(profile.buttons["10"]?.long, "raycastAmp")
        XCTAssertNil(profile.buttons["12"])
        XCTAssertNil(profile.overrides[BundleID.arc]?.buttons["3"])
        XCTAssertEqual(profile.overrides[BundleID.arc]?.buttons["7"]?.long, "raycastClipboardHistory")
        XCTAssertEqual(profile.overrides[BundleID.amp]?.buttons["8"],
                       ButtonBinding(tap: "newSession", long: "raycastAIChat"))
        XCTAssertEqual(profile.overrides[BundleID.energy]?.buttons["8"],
                       ButtonBinding(tap: "newSession", long: "raycastAIChat"))
        XCTAssertEqual(profile.sticks["hat"]?["up"],
                       StickDir(hat: 0, action: "scrollUp"))
        XCTAssertEqual(profile.sticks["hat"]?["down"],
                       StickDir(hat: 4, action: "scrollDown"))
        XCTAssertEqual(profile.sticks["hat"]?["right"], StickDir(hat: 2, action: "sessionNext"))
        XCTAssertEqual(profile.overrides[BundleID.amp]?.sticks["hat"]?["up"],
                       "contextPrevious")
        XCTAssertEqual(profile.overrides[BundleID.amp]?.sticks["hat"]?["down"],
                       "contextNext")
        XCTAssertEqual(profile.overrides[BundleID.codex]?.sticks["hat"]?["up"],
                       "contextPrevious")
        XCTAssertEqual(profile.overrides[BundleID.codex]?.sticks["hat"]?["down"],
                       "contextNext")
        XCTAssertEqual(profile.overrides[BundleID.arc]?.sticks["hat"]?["up"],
                       "contextPrevious")
        XCTAssertEqual(profile.overrides[BundleID.arc]?.sticks["hat"]?["down"],
                       "contextNext")
        XCTAssertEqual(profile.overrides[BundleID.wechat]?.sticks["hat"]?["up"],
                       "contextPrevious")
        XCTAssertEqual(profile.overrides[BundleID.wechat]?.sticks["hat"]?["down"],
                       "contextNext")
        XCTAssertEqual(profile.overrides[BundleID.warp]?.sticks["hat"]?["up"],
                       "contextPrevious")
        XCTAssertEqual(profile.overrides[BundleID.warp]?.sticks["hat"]?["down"],
                       "contextNext")
        XCTAssertEqual(profile.sticks["left"]?["up"],
                       StickDir(hat: 0, action: "focusPrevious"))
        XCTAssertEqual(profile.sticks["left"]?["right"],
                       StickDir(hat: 2, action: "focusNext"))
        XCTAssertEqual(profile.sticks["right"]?["up"],
                       StickDir(hat: 0, action: "scrollUp"))
        XCTAssertEqual(profile.sticks["right"]?["down"],
                       StickDir(hat: 4, action: "scrollDown"))
    }

    func testRightShiftReturnKeepsSidedModifierIdentity() {
        let config = Config()
        XCTAssertEqual(config.pttStyle, "hold")
        XCTAssertEqual(config.pttKey, "return")
        XCTAssertEqual(config.pttMods, ["rightshift"])

        let rightShift = KeySynth.modifierFlag["rightshift"]!
        let down = KeySynth.shortcutEvents(["rightshift"], "return", down: true)
        XCTAssertEqual(down, [
            KeySynth.ShortcutEvent(kind: .flagsChanged, keyCode: 60, flags: rightShift),
            KeySynth.ShortcutEvent(kind: .keyDown, keyCode: 36, flags: rightShift),
        ])

        let up = KeySynth.shortcutEvents(["rightshift"], "return", down: false)
        XCTAssertEqual(up, [
            KeySynth.ShortcutEvent(kind: .keyUp, keyCode: 36, flags: rightShift),
            KeySynth.ShortcutEvent(kind: .flagsChanged, keyCode: 60, flags: []),
        ])
    }

    func testClearLineUsesTextFieldFallbackAndKeepsTerminalOverride() {
        XCTAssertEqual(AppProfiles.clearLineKey(app: BundleID.codex), KeySpec("cmd+a"))
        XCTAssertEqual(AppProfiles.clearLineKey(app: BundleID.amp), KeySpec("cmd+a"))
        XCTAssertEqual(AppProfiles.clearLineKey(app: BundleID.ghostty), KeySpec("ctrl+u"))
    }

    func testEnergyShipsWithCommandNAndIsATargetApp() {
        XCTAssertEqual(AppProfiles.builtin[BundleID.energy]?["newSession"],
                       KeySpec("cmd+n"))
        XCTAssertTrue(Config().targetApps.contains(BundleID.energy))
        XCTAssertEqual(AppName.of(BundleID.energy), "Energy")
    }

    func testGhosttyIsRemovedFromLegacyTargetAppsOnlyOnce() {
        XCTAssertFalse(Config().targetApps.contains(BundleID.ghostty))

        var config = Config()
        config.targetApps = [BundleID.ghostty, BundleID.wechat]
        config.targetAppsVersion = 0
        config.migrateTargetAppsIfNeeded()

        XCTAssertEqual(config.targetApps, [BundleID.wechat, BundleID.warp])
        XCTAssertEqual(config.targetAppsVersion, 3)

        config.targetApps.append(BundleID.ghostty)
        config.migrateTargetAppsIfNeeded()
        XCTAssertTrue(config.targetApps.contains(BundleID.ghostty))
    }

    func testAmpBundleMigrationMovesEveryBundleKeyWithoutReplacingNewSettings() {
        XCTAssertEqual(BundleID.amp, "com.ampcode.amp.macos")
        XCTAssertEqual(BundleID.legacyAmp, "com.hamishbultitude.ampcode")

        var config = Config()
        config.targetAppsVersion = 2
        config.targetApps = [BundleID.legacyAmp, BundleID.wechat, BundleID.amp]
        config.remoteCorners = [BundleID.legacyAmp, BundleID.slack]
        config.appProfiles = [
            BundleID.legacyAmp: [
                "contextPrevious": KeySpec("legacy-up"),
                "contextNext": KeySpec("legacy-down"),
            ],
            BundleID.amp: [
                "contextPrevious": KeySpec("new-up"),
            ],
        ]

        var device = DeviceProfile(vendorID: XboxHID.vendorID, productID: 0x0B22,
                                   name: "Xbox Elite Series 2")
        device.overrides[BundleID.legacyAmp] = AppOverride(
            buttons: ["8": ButtonBinding(tap: "newSession", long: "legacyHold")],
            sticks: [StickChannel.hat.rawValue: [
                "up": "contextPrevious",
                "down": "contextNext",
            ]])
        device.overrides[BundleID.amp] = AppOverride(
            buttons: ["8": ButtonBinding(tap: "customNew")],
            sticks: [StickChannel.hat.rawValue: ["up": "customNewUp"]])
        config.devices = [device]

        config.migrateTargetAppsIfNeeded()

        XCTAssertEqual(config.targetAppsVersion, 3)
        XCTAssertEqual(config.targetApps, [BundleID.amp, BundleID.wechat])
        XCTAssertEqual(config.remoteCorners, [BundleID.amp, BundleID.slack])
        XCTAssertNil(config.appProfiles[BundleID.legacyAmp])
        XCTAssertEqual(config.appProfiles[BundleID.amp]?["contextPrevious"], KeySpec("new-up"))
        XCTAssertEqual(config.appProfiles[BundleID.amp]?["contextNext"], KeySpec("legacy-down"))
        XCTAssertNil(config.devices[0].overrides[BundleID.legacyAmp])
        XCTAssertEqual(config.devices[0].overrides[BundleID.amp]?.buttons["8"],
                       ButtonBinding(tap: "customNew"))
        XCTAssertEqual(config.devices[0].overrides[BundleID.amp]?.sticks["hat"]?["up"],
                       "customNewUp")
        XCTAssertEqual(config.devices[0].overrides[BundleID.amp]?.sticks["hat"]?["down"],
                       "contextNext")
    }

    func testDirectAppSwitchOptionsFollowTheComputerHistoryWorkset() {
        let expected: [(String, String)] = [
            ("focusArc", BundleID.arc),
            ("focusSlack", BundleID.slack),
            ("focusRaycast", BundleID.raycast),
            ("focusEnergy", BundleID.energy),
            ("focusCodex", BundleID.codex),
            ("focusWeChat", BundleID.wechat),
            ("focusAmp", BundleID.amp),
            ("focusMail", BundleID.mail),
            ("focusSignal", BundleID.signal),
            ("focusWhatsApp", BundleID.whatsapp),
            ("focusHeptabase", BundleID.heptabase),
            ("focusWarp", BundleID.warp),
            ("focusGhostty", BundleID.ghostty),
            ("focusChrome", BundleID.chrome),
            ("focusClaude", BundleID.claude),
        ]
        XCTAssertEqual(Actions.appFocusTargets.map { ($0.actionID, $0.bundleID) }.count,
                       expected.count)
        for (index, item) in expected.enumerated() {
            XCTAssertEqual(Actions.appFocusTargets[index].actionID, item.0)
            XCTAssertEqual(Actions.appFocusTargets[index].bundleID, item.1)
            XCTAssertEqual(Actions.byID[item.0]?.group, L("切换 app"))
        }
    }

    func testActionProvidersSeparateMetadataFromExecution() throws {
        let contextual = try XCTUnwrap(Actions.action(for: "contextPrevious"))
        XCTAssertEqual(contextual.provider, .appProfile)
        XCTAssertEqual(contextual.supportedApps,
                       [BundleID.amp, BundleID.codex, BundleID.arc,
                        BundleID.wechat, BundleID.warp])
        XCTAssertEqual(Actions.action(for: "ampPreviousThread")?.id, "contextPrevious")
        XCTAssertEqual(Actions.action(for: "arcNavBack")?.id, "navBack")
        XCTAssertEqual(Actions.action(for: "raycastClipboardHistory")?.provider, .raycast)
        XCTAssertEqual(Actions.action(for: "focusSlack")?.provider, .appFocus)
    }

    func testActionPickerSearchUnderstandsIntentAndResolvedShortcuts() throws {
        let confirm = try XCTUnwrap(Actions.action(for: "confirm"))
        let newSession = try XCTUnwrap(Actions.action(for: "newSession"))
        let previous = try XCTUnwrap(Actions.action(for: "contextPrevious"))
        let slack = try XCTUnwrap(Actions.action(for: "focusSlack"))

        XCTAssertNotNil(ActionPickerSearch.score(confirm, query: "enter", layer: ""))
        XCTAssertNotNil(ActionPickerSearch.score(
            newSession, query: "cmd n", layer: BundleID.amp))
        XCTAssertNotNil(ActionPickerSearch.score(
            previous, query: "previous thread", layer: BundleID.codex))
        XCTAssertNotNil(ActionPickerSearch.score(slack, query: "slack", layer: ""))
        XCTAssertNil(ActionPickerSearch.score(confirm, query: "open slack", layer: ""))
    }

    func testSemanticContextShortcutsResolvePerApp() {
        XCTAssertEqual(AppProfiles.builtin[BundleID.amp]?["contextPrevious"],
                       KeySpec("ctrl+alt+up"))
        XCTAssertEqual(AppProfiles.builtin[BundleID.codex]?["contextNext"],
                       KeySpec("alt+cmd+down"))
        XCTAssertEqual(AppProfiles.builtin[BundleID.arc]?["contextPrevious"],
                       KeySpec("cmd+shift+up"))
        XCTAssertEqual(AppProfiles.builtin[BundleID.wechat]?["contextNext"],
                       KeySpec("down"))
        XCTAssertEqual(AppProfiles.builtin[BundleID.warp]?["contextPrevious"],
                       KeySpec("cmd+shift+["))
        XCTAssertEqual(AppProfiles.builtin[BundleID.warp]?["contextNext"],
                       KeySpec("cmd+shift+]"))
        XCTAssertEqual(KeySpec("cmd+shift+[").display, "⌘⇧[")
        XCTAssertEqual(KeySpec("cmd+shift+]").display, "⌘⇧]")
        XCTAssertTrue(AppProfiles.configurable.contains("contextPrevious"))
        XCTAssertTrue(AppProfiles.configurable.contains("contextNext"))
    }

    func testRaycastSnapshotParsesExactGlobalHotkeys() throws {
        let json = #"""
        {"tables":{"general_settings":[{"globalHotkey":{"kind":{"type":"SingleStep","shortcut":{"modifiers":[{"modifier":"Meta"}],"key":{"code":49}}}}}],"commands":[{"id":"c:r:dictation::-::dictateText","enabled":true,"macosHotkey":{"kind":{"type":"SingleStep","shortcut":{"modifiers":[{"modifier":"Shift","directionality":"right"}],"key":{"code":36}}}}},{"id":"c:r:clipboard-history::-::history","enabled":true,"macosHotkey":{"kind":{"type":"SingleStep","shortcut":{"modifiers":[{"modifier":"Shift"},{"modifier":"Meta"}],"key":{"code":8}}}}}]}}
        """#
        let shortcuts = RaycastShortcuts.parseSnapshot(try XCTUnwrap(json.data(using: .utf8)))
        XCTAssertEqual(shortcuts["raycastLauncher"],
                       RaycastShortcut(modifiers: ["cmd"], keyCode: 49))
        XCTAssertEqual(shortcuts["raycastClipboardHistory"],
                       RaycastShortcut(modifiers: ["shift", "cmd"], keyCode: 8))
        XCTAssertEqual(shortcuts["raycastDictation"],
                       RaycastShortcut(modifiers: ["rightshift"], keyCode: 36))
    }

    func testRaycastVirtualKeyCodeProducesFullShortcutChord() {
        let alt = KeySynth.modifierFlag["alt"]!
        XCTAssertEqual(KeySynth.shortcutEvents(["alt"], keyCode: 49, down: true), [
            KeySynth.ShortcutEvent(kind: .flagsChanged, keyCode: 58, flags: alt),
            KeySynth.ShortcutEvent(kind: .keyDown, keyCode: 49, flags: alt),
        ])
        XCTAssertEqual(KeySynth.shortcutEvents(["alt"], keyCode: 49, down: false), [
            KeySynth.ShortcutEvent(kind: .keyUp, keyCode: 49, flags: alt),
            KeySynth.ShortcutEvent(kind: .flagsChanged, keyCode: 58, flags: []),
        ])
    }

    func testRaycastSnapshotParsesLayoutDependentArrowShortcuts() throws {
        let json = #"""
        {"tables":{"commands":[{"id":"c:r:window-management::-::switchToPreviousSpace","enabled":true,"macosHotkey":{"kind":{"type":"SingleStep","shortcut":{"modifiers":[{"modifier":"Ctrl"}],"key":{"type":"LayoutDependent","keyType":{"type":"Control","key":"ArrowLeft"}}}}}},{"id":"c:r:window-management::-::switchToNextSpace","enabled":true,"macosHotkey":{"kind":{"type":"SingleStep","shortcut":{"modifiers":[{"modifier":"Ctrl"}],"key":{"type":"LayoutDependent","keyType":{"type":"Control","key":"ArrowRight"}}}}}}]}}
        """#
        let shortcuts = RaycastShortcuts.parseSnapshot(
            try XCTUnwrap(json.data(using: .utf8)))
        XCTAssertEqual(shortcuts["raycastPreviousSpace"],
                       RaycastShortcut(modifiers: ["ctrl"], keyCode: 123))
        XCTAssertEqual(shortcuts["raycastNextSpace"],
                       RaycastShortcut(modifiers: ["ctrl"], keyCode: 124))
    }

    func testExistingXboxProfileMigratesOnceWithoutOverwritingCustomBindings() {
        var config = Config()
        config.xboxRaycastPresetVersion = 0
        var profile = DeviceProfile(vendorID: XboxHID.vendorID, productID: 0x0B22,
                                    name: "Xbox Wireless Controller")
        profile.buttons = [
            "5": ButtonBinding(tap: "confirm", long: "focusSlack"),
            "6": ButtonBinding(tap: "focusArc", long: "focusGhostty"),
            "8": ButtonBinding(tap: "modelMenu"),
            "12": ButtonBinding(tap: "customWeChat", long: "focusHeptabase"),
        ]
        config.devices = [profile]

        config.migrateXboxRaycastPresetIfNeeded()

        XCTAssertEqual(config.xboxRaycastPresetVersion, 16)
        XCTAssertEqual(config.devices[0].buttons["5"]?.tap, "raycastPreviousSpace")
        XCTAssertEqual(config.devices[0].buttons["5"]?.long, "raycastSlack")
        XCTAssertEqual(config.devices[0].buttons["6"],
                       ButtonBinding(tap: "raycastNextSpace", long: "raycastWarp"))
        XCTAssertEqual(config.devices[0].buttons["8"],
                       ButtonBinding(tap: "raycastLauncher", long: "raycastAIChat"))
        XCTAssertEqual(config.devices[0].buttons["12"]?.tap, "customWeChat")
        XCTAssertEqual(config.devices[0].buttons["12"]?.long, "raycastHeptabase")
        XCTAssertEqual(config.devices[0].sticks["hat"], DefaultProfiles.dpad)
        XCTAssertEqual(config.devices[0].overrides[BundleID.amp]?.sticks["hat"]?["up"],
                       "contextPrevious")
        XCTAssertEqual(config.devices[0].overrides[BundleID.amp]?.sticks["hat"]?["down"],
                       "contextNext")
        XCTAssertEqual(config.devices[0].sticks["left"], DefaultProfiles.leftStickSelection)
        XCTAssertEqual(config.devices[0].sticks["right"], DefaultProfiles.rightStick)
    }

    func testXboxDirectionMigrationRepairsOnlyEmptyChannels() {
        var config = Config()
        config.xboxRaycastPresetVersion = 1
        var profile = DeviceProfile(vendorID: XboxHID.vendorID, productID: 0x0B22,
                                    name: "Xbox Elite Series 2")
        let customHat = ["up": StickDir(hat: 1, action: "custom")]
        profile.sticks = ["hat": customHat, "left": [:]]
        profile.buttons["12"] = ButtonBinding(
            tap: "raycastWeChat", long: "raycastHeptabase")
        config.devices = [profile]

        config.migrateXboxRaycastPresetIfNeeded()

        XCTAssertEqual(config.xboxRaycastPresetVersion, 16)
        XCTAssertEqual(config.devices[0].sticks["hat"], customHat)
        XCTAssertEqual(config.devices[0].sticks["left"], DefaultProfiles.leftStickSelection)
        XCTAssertEqual(config.devices[0].sticks["right"], DefaultProfiles.rightStick)
        XCTAssertNil(config.devices[0].buttons["12"])
    }

    func testXboxAppCycleMigrationPreservesCustomShoulderTaps() {
        var config = Config()
        config.xboxRaycastPresetVersion = 2
        var profile = DeviceProfile(vendorID: XboxHID.vendorID, productID: 0x0B22,
                                    name: "Xbox Elite Series 2")
        profile.buttons["5"] = ButtonBinding(tap: "customLB", long: "raycastSlack")
        profile.buttons["6"] = ButtonBinding(tap: "customRB", long: "raycastWarp")
        config.devices = [profile]

        config.migrateXboxRaycastPresetIfNeeded()

        XCTAssertEqual(config.xboxRaycastPresetVersion, 16)
        XCTAssertEqual(config.devices[0].buttons["5"],
                       ButtonBinding(tap: "customLB", long: "raycastSlack"))
        XCTAssertEqual(config.devices[0].buttons["6"],
                       ButtonBinding(tap: "customRB", long: "raycastWarp"))
    }

    func testXboxSelectionMigrationUpdatesOnlyShippedDefaults() {
        var config = Config()
        config.xboxRaycastPresetVersion = 3
        var shipped = DeviceProfile(vendorID: XboxHID.vendorID, productID: 0x0B22,
                                    name: "Xbox Elite Series 2")
        shipped.buttons["9"] = ButtonBinding(tap: "cancel", long: "raycastCodex")
        shipped.sticks["left"] = DefaultProfiles.dpad

        var custom = DeviceProfile(vendorID: XboxHID.vendorID, productID: 0x0B13,
                                   name: "Custom Xbox")
        custom.buttons["9"] = ButtonBinding(tap: "customClick", long: "customHold")
        let customStick = ["up": StickDir(hat: 7, action: "customUp")]
        custom.sticks["left"] = customStick
        config.devices = [shipped, custom]

        config.migrateXboxRaycastPresetIfNeeded()

        XCTAssertEqual(config.xboxRaycastPresetVersion, 16)
        XCTAssertEqual(config.devices[0].buttons["9"],
                       ButtonBinding(tap: "selectFocused", long: "raycastCodex"))
        XCTAssertEqual(config.devices[0].sticks["left"], DefaultProfiles.leftStickSelection)
        XCTAssertEqual(config.devices[1].buttons["9"],
                       ButtonBinding(tap: "customClick", long: "customHold"))
        XCTAssertEqual(config.devices[1].sticks["left"], customStick)
    }

    func testXboxAmpMenuAndDPadMigrationPreservesCustomOverrides() {
        var config = Config()
        config.xboxRaycastPresetVersion = 4

        var shipped = DeviceProfile(vendorID: XboxHID.vendorID, productID: 0x0B22,
                                    name: "Xbox Elite Series 2")
        shipped.sticks["hat"] = DefaultProfiles.dpad

        var custom = DeviceProfile(vendorID: XboxHID.vendorID, productID: 0x0B13,
                                   name: "Custom Xbox")
        custom.sticks["hat"] = ["up": StickDir(hat: 1, action: "customUp")]
        custom.overrides[BundleID.amp] = AppOverride(
            buttons: [
                "8": ButtonBinding(tap: "customMenu", long: "customHold"),
            ],
            sticks: [
                "hat": ["up": "customAmpUp"],
            ])
        config.devices = [shipped, custom]

        config.migrateXboxRaycastPresetIfNeeded()

        XCTAssertEqual(config.xboxRaycastPresetVersion, 16)
        XCTAssertEqual(config.devices[0].overrides[BundleID.amp]?.buttons["8"],
                       ButtonBinding(tap: "newSession", long: "raycastAIChat"))
        XCTAssertEqual(config.devices[0].sticks["hat"], DefaultProfiles.dpad)
        XCTAssertEqual(config.devices[0].overrides[BundleID.amp]?.sticks["hat"]?["up"],
                       "contextPrevious")
        XCTAssertEqual(config.devices[0].overrides[BundleID.amp]?.sticks["hat"]?["down"],
                       "contextNext")
        XCTAssertEqual(config.devices[1].overrides[BundleID.amp]?.buttons["8"],
                       ButtonBinding(tap: "customMenu", long: "customHold"))
        XCTAssertEqual(config.devices[1].sticks["hat"]?["up"],
                       StickDir(hat: 1, action: "customUp"))
        XCTAssertEqual(config.devices[1].overrides[BundleID.amp]?.sticks["hat"]?["up"],
                       "customAmpUp")
        XCTAssertEqual(config.devices[1].overrides[BundleID.amp]?.sticks["hat"]?["down"],
                       "contextNext")
    }

    func testVersionFiveBaseDPadIsRepairedIntoAmpOnlyOverride() {
        var config = Config()
        config.xboxRaycastPresetVersion = 5
        var profile = DeviceProfile(vendorID: XboxHID.vendorID, productID: 0x0B22,
                                    name: "Xbox Elite Series 2")
        profile.sticks["hat"] = DefaultProfiles.xboxDpad
        config.devices = [profile]

        config.migrateXboxRaycastPresetIfNeeded()

        XCTAssertEqual(config.xboxRaycastPresetVersion, 16)
        XCTAssertEqual(config.devices[0].sticks["hat"], DefaultProfiles.dpad)
        XCTAssertEqual(config.devices[0].overrides[BundleID.amp]?.sticks["hat"]?["up"],
                       "contextPrevious")
        XCTAssertEqual(config.devices[0].overrides[BundleID.amp]?.sticks["hat"]?["down"],
                       "contextNext")
    }

    func testCodexDPadMigrationPreservesCustomDirection() {
        var config = Config()
        config.xboxRaycastPresetVersion = 6
        var profile = DeviceProfile(vendorID: XboxHID.vendorID, productID: 0x0B22,
                                    name: "Xbox Elite Series 2")
        profile.overrides[BundleID.codex] = AppOverride(sticks: [
            "hat": ["up": "customCodexUp"],
        ])
        config.devices = [profile]

        config.migrateXboxRaycastPresetIfNeeded()

        XCTAssertEqual(config.xboxRaycastPresetVersion, 16)
        XCTAssertEqual(config.devices[0].overrides[BundleID.codex]?.sticks["hat"]?["up"],
                       "customCodexUp")
        XCTAssertEqual(config.devices[0].overrides[BundleID.codex]?.sticks["hat"]?["down"],
                       "contextNext")
    }

    func testWeChatDPadMigrationPreservesCustomDirection() {
        var config = Config()
        config.xboxRaycastPresetVersion = 7
        var profile = DeviceProfile(vendorID: XboxHID.vendorID, productID: 0x0B22,
                                    name: "Xbox Elite Series 2")
        profile.overrides[BundleID.wechat] = AppOverride(sticks: [
            "hat": ["up": "customWeChatUp"],
        ])
        config.devices = [profile]

        config.migrateXboxRaycastPresetIfNeeded()

        XCTAssertEqual(config.xboxRaycastPresetVersion, 16)
        XCTAssertEqual(config.devices[0].overrides[BundleID.wechat]?.sticks["hat"]?["up"],
                       "customWeChatUp")
        XCTAssertEqual(config.devices[0].overrides[BundleID.wechat]?.sticks["hat"]?["down"],
                       "down")
    }

    func testRightStickScrollMigrationPreservesCustomMap() {
        var config = Config()
        config.xboxRaycastPresetVersion = 8

        var shipped = DeviceProfile(vendorID: XboxHID.vendorID, productID: 0x0B22,
                                    name: "Xbox Elite Series 2")
        shipped.sticks["right"] = DefaultProfiles.rightStickV8

        var custom = DeviceProfile(vendorID: XboxHID.vendorID, productID: 0x0B13,
                                   name: "Custom Xbox")
        let customRight = ["up": StickDir(hat: 7, action: "customUp")]
        custom.sticks["right"] = customRight
        config.devices = [shipped, custom]

        config.migrateXboxRaycastPresetIfNeeded()

        XCTAssertEqual(config.xboxRaycastPresetVersion, 16)
        XCTAssertEqual(config.devices[0].sticks["right"], DefaultProfiles.rightStick)
        XCTAssertEqual(config.devices[1].sticks["right"], customRight)
    }

    func testBrowserClearInputMigrationPreservesCustomXOverride() {
        var config = Config()
        config.xboxRaycastPresetVersion = 10

        var shipped = DeviceProfile(vendorID: XboxHID.vendorID, productID: 0x0B22,
                                    name: "Xbox Elite Series 2")
        shipped.overrides[BundleID.chrome] = AppOverride(buttons: [
            "3": ButtonBinding(tap: "reload", long: "raycastEmojiPicker"),
        ])
        shipped.overrides[BundleID.arc] = AppOverride(buttons: [
            "3": ButtonBinding(tap: "arcReload", long: "raycastEmojiPicker"),
        ])

        var custom = DeviceProfile(vendorID: XboxHID.vendorID, productID: 0x0B13,
                                   name: "Custom Xbox")
        custom.overrides[BundleID.arc] = AppOverride(buttons: [
            "3": ButtonBinding(tap: "customX", long: "customHold"),
        ])
        config.devices = [shipped, custom]

        config.migrateXboxRaycastPresetIfNeeded()

        XCTAssertEqual(config.xboxRaycastPresetVersion, 16)
        XCTAssertNil(config.devices[0].overrides[BundleID.chrome]?.buttons["3"])
        XCTAssertNil(config.devices[0].overrides[BundleID.arc]?.buttons["3"])
        XCTAssertEqual(config.devices[1].overrides[BundleID.arc]?.buttons["3"],
                       ButtonBinding(tap: "customX", long: "customHold"))
    }

    func testEnergyMenuMigrationPreservesCustomOverride() {
        var config = Config()
        config.xboxRaycastPresetVersion = 11
        config.targetApps.removeAll { $0 == BundleID.energy }

        let shipped = DeviceProfile(vendorID: XboxHID.vendorID, productID: 0x0B22,
                                    name: "Xbox Elite Series 2")
        var custom = DeviceProfile(vendorID: XboxHID.vendorID, productID: 0x0B13,
                                   name: "Custom Xbox")
        custom.overrides[BundleID.energy] = AppOverride(buttons: [
            "8": ButtonBinding(tap: "customEnergyMenu", long: "customHold"),
        ])
        config.devices = [shipped, custom]

        config.migrateXboxRaycastPresetIfNeeded()

        XCTAssertEqual(config.xboxRaycastPresetVersion, 16)
        XCTAssertTrue(config.targetApps.contains(BundleID.energy))
        XCTAssertEqual(config.devices[0].overrides[BundleID.energy]?.buttons["8"],
                       ButtonBinding(tap: "newSession", long: "raycastAIChat"))
        XCTAssertEqual(config.devices[1].overrides[BundleID.energy]?.buttons["8"],
                       ButtonBinding(tap: "customEnergyMenu", long: "customHold"))
    }

    func testArcDPadMigrationAddsCommandShiftArrowsWithoutReplacingCustomDirections() {
        var config = Config()
        config.xboxRaycastPresetVersion = 12

        let shipped = DeviceProfile(vendorID: XboxHID.vendorID, productID: 0x0B22,
                                    name: "Xbox Elite Series 2")
        var custom = DeviceProfile(vendorID: XboxHID.vendorID, productID: 0x0B13,
                                   name: "Custom Xbox")
        custom.overrides[BundleID.arc] = AppOverride(sticks: [
            StickChannel.hat.rawValue: ["up": "customArcUp"],
        ])
        config.devices = [shipped, custom]

        config.migrateXboxRaycastPresetIfNeeded()

        XCTAssertEqual(config.xboxRaycastPresetVersion, 16)
        XCTAssertEqual(config.devices[0].overrides[BundleID.arc]?.sticks["hat"]?["up"],
                       "contextPrevious")
        XCTAssertEqual(config.devices[0].overrides[BundleID.arc]?.sticks["hat"]?["down"],
                       "contextNext")
        XCTAssertEqual(config.devices[1].overrides[BundleID.arc]?.sticks["hat"]?["up"],
                       "customArcUp")
        XCTAssertEqual(config.devices[1].overrides[BundleID.arc]?.sticks["hat"]?["down"],
                       "contextNext")
    }

    func testWarpDPadMigrationAddsCommandShiftBracketsWithoutReplacingCustomDirections() {
        var config = Config()
        config.targetApps.removeAll { $0 == BundleID.warp }
        config.targetAppsVersion = 1
        config.xboxRaycastPresetVersion = 15

        let shipped = DeviceProfile(vendorID: XboxHID.vendorID, productID: 0x0B22,
                                    name: "Xbox Elite Series 2")
        var custom = DeviceProfile(vendorID: XboxHID.vendorID, productID: 0x0B13,
                                   name: "Custom Xbox")
        custom.overrides[BundleID.warp] = AppOverride(sticks: [
            StickChannel.hat.rawValue: ["up": "customWarpUp"],
        ])
        config.devices = [shipped, custom]

        config.migrateTargetAppsIfNeeded()
        config.migrateXboxRaycastPresetIfNeeded()

        XCTAssertEqual(config.targetAppsVersion, 3)
        XCTAssertTrue(config.targetApps.contains(BundleID.warp))
        XCTAssertEqual(config.xboxRaycastPresetVersion, 16)
        XCTAssertEqual(config.devices[0].overrides[BundleID.warp]?.sticks["hat"]?["up"],
                       "contextPrevious")
        XCTAssertEqual(config.devices[0].overrides[BundleID.warp]?.sticks["hat"]?["down"],
                       "contextNext")
        XCTAssertEqual(config.devices[1].overrides[BundleID.warp]?.sticks["hat"]?["up"],
                       "customWarpUp")
        XCTAssertEqual(config.devices[1].overrides[BundleID.warp]?.sticks["hat"]?["down"],
                       "contextNext")
    }

    func testSemanticActionMigrationPreservesPaddlesAndCustomMappings() {
        var config = Config()
        config.xboxRaycastPresetVersion = 13
        var profile = DeviceProfile(vendorID: XboxHID.vendorID, productID: 0x0B22,
                                    name: "Xbox Elite Series 2")
        profile.buttons = [
            "13": ButtonBinding(tap: "focusSlack"),
            "14": ButtonBinding(tap: "focusWeChat"),
            "15": ButtonBinding(tap: "focusAmp"),
            "16": ButtonBinding(tap: "focusArc"),
        ]
        profile.overrides[BundleID.amp] = AppOverride(
            buttons: ["8": ButtonBinding(tap: "ampNewSession", long: "customHold")],
            sticks: ["hat": ["up": "ampPreviousThread", "down": "customDown"]])
        profile.overrides[BundleID.arc] = AppOverride(
            buttons: ["7": ButtonBinding(tap: "arcCloseTab")],
            sticks: ["hat": ["up": "arcCommandShiftUp", "down": "arcCommandShiftDown"]])
        profile.overrides[BundleID.wechat] = AppOverride(
            sticks: ["hat": ["up": "up", "down": "down"]])
        config.devices = [profile]

        config.migrateXboxRaycastPresetIfNeeded()

        XCTAssertEqual(config.xboxRaycastPresetVersion, 16)
        XCTAssertEqual(config.devices[0].buttons["13"]?.tap, "focusSlack")
        XCTAssertEqual(config.devices[0].buttons["14"]?.tap, "focusWeChat")
        XCTAssertEqual(config.devices[0].buttons["15"]?.tap, "focusAmp")
        XCTAssertEqual(config.devices[0].buttons["16"]?.tap, "focusArc")
        XCTAssertEqual(config.devices[0].overrides[BundleID.amp]?.buttons["8"],
                       ButtonBinding(tap: "newSession", long: "customHold"))
        XCTAssertEqual(config.devices[0].overrides[BundleID.amp]?.sticks["hat"]?["up"],
                       "contextPrevious")
        XCTAssertEqual(config.devices[0].overrides[BundleID.amp]?.sticks["hat"]?["down"],
                       "customDown")
        XCTAssertEqual(config.devices[0].overrides[BundleID.arc]?.buttons["7"]?.tap,
                       "closeTab")
        XCTAssertEqual(config.devices[0].overrides[BundleID.wechat]?.sticks["hat"]?["up"],
                       "contextPrevious")
        XCTAssertEqual(config.devices[0].overrides[BundleID.wechat]?.sticks["hat"]?["down"],
                       "contextNext")
    }

    func testVersionFourteenFinishesWeChatSemanticMigration() {
        var config = Config()
        config.xboxRaycastPresetVersion = 14
        var profile = DeviceProfile(vendorID: XboxHID.vendorID, productID: 0x0B22,
                                    name: "Xbox Elite Series 2")
        profile.buttons["13"] = ButtonBinding(tap: "focusSlack")
        profile.overrides[BundleID.wechat] = AppOverride(
            sticks: ["hat": ["up": "up", "down": "down"]])
        config.devices = [profile]

        config.migrateXboxRaycastPresetIfNeeded()

        XCTAssertEqual(config.xboxRaycastPresetVersion, 16)
        XCTAssertEqual(config.devices[0].buttons["13"]?.tap, "focusSlack")
        XCTAssertEqual(config.devices[0].overrides[BundleID.wechat]?.sticks["hat"]?["up"],
                       "contextPrevious")
        XCTAssertEqual(config.devices[0].overrides[BundleID.wechat]?.sticks["hat"]?["down"],
                       "contextNext")
    }

    func testCommandAppSwitcherChordKeepsAAsTapAndConsumesShoulders() {
        var chord = CommandAppSwitcherChord()

        XCTAssertEqual(chord.handle(button: 1, down: true, device: "xbox", isXbox: true),
                       .begin)
        XCTAssertEqual(chord.handle(button: 6, down: true, device: "xbox", isXbox: true),
                       .step(previous: false, beginCommand: true))
        XCTAssertEqual(chord.handle(button: 6, down: false, device: "xbox", isXbox: true),
                       .consume)
        XCTAssertEqual(chord.handle(button: 5, down: true, device: "xbox", isXbox: true),
                       .step(previous: true, beginCommand: false))
        XCTAssertEqual(chord.handle(button: 5, down: false, device: "xbox", isXbox: true),
                       .consume)
        XCTAssertEqual(chord.handle(button: 1, down: false, device: "xbox", isXbox: true),
                       .finish(tapA: false))

        XCTAssertEqual(chord.handle(button: 1, down: true, device: "xbox", isXbox: true),
                       .begin)
        XCTAssertEqual(chord.handle(button: 1, down: false, device: "xbox", isXbox: true),
                       .finish(tapA: true))
        XCTAssertEqual(chord.handle(button: 1, down: true, device: "other", isXbox: false),
                       .none)
    }

    func testCommandAppSwitcherChordFuseSuppressesLateARelease() {
        var chord = CommandAppSwitcherChord()
        XCTAssertEqual(chord.handle(button: 1, down: true, device: "xbox", isXbox: true),
                       .begin)
        XCTAssertFalse(chord.cancel(suppressAUntilRelease: true))
        XCTAssertEqual(chord.handle(button: 1, down: false, device: "xbox", isXbox: true),
                       .consume)
        XCTAssertFalse(chord.cancel(suppressAUntilRelease: true))

        XCTAssertEqual(chord.handle(button: 1, down: true, device: "xbox", isXbox: true),
                       .begin)
        XCTAssertEqual(chord.handle(button: 6, down: true, device: "xbox", isXbox: true),
                       .step(previous: false, beginCommand: true))
        XCTAssertTrue(chord.removeDevice("xbox"))
        XCTAssertNil(chord.deviceID)
    }

    func testAppCycleIndexMovesBothDirectionsAndWraps() {
        XCTAssertEqual(AppContext.cycleIndex(from: 0, count: 4, delta: 1), 1)
        XCTAssertEqual(AppContext.cycleIndex(from: 0, count: 4, delta: -1), 3)
        XCTAssertEqual(AppContext.cycleIndex(from: 3, count: 4, delta: 1), 0)
        XCTAssertEqual(AppContext.cycleIndex(from: 0, count: 4, delta: -5), 3)
        XCTAssertNil(AppContext.cycleIndex(from: 0, count: 1, delta: 1))
    }

    func testAppCycleAlwaysAnchorsToTheLiveFrontmostApp() {
        XCTAssertEqual(
            AppContext.cycleOrder(front: "amp", history: ["arc", "amp", "slack"]),
            ["amp", "arc", "slack"])
        XCTAssertEqual(
            AppContext.cycleOrder(front: "amp", history: ["amp", "amp", "arc"]),
            ["amp", "arc"])
        XCTAssertEqual(
            AppContext.cycleOrder(
                front: "arc", history: ["arc", "joycoding", "codex"],
                ownBundle: "joycoding"),
            ["arc", "codex"])
    }

    func testSeedOrderUsesOtherSpacesAndRunningFallback() {
        XCTAssertEqual(
            AppContext.seedOrder(
                front: "arc",
                windowOrder: ["joycoding", "codex", "arc", "slack", "codex"],
                running: ["finder", "warp", "joycoding"],
                ownBundle: "joycoding"
            ),
            ["arc", "codex", "slack", "finder", "warp"]
        )
    }

    func testSeedOrderKeepsJoyCodingWhenItIsFrontmost() {
        XCTAssertEqual(
            AppContext.seedOrder(
                front: "joycoding",
                windowOrder: ["joycoding", "arc"],
                running: ["codex"],
                ownBundle: "joycoding"
            ),
            ["joycoding", "arc", "codex"]
        )
    }

    func testControllerTestModeIsAnExplicitActionGate() {
        XCTAssertTrue(HIDInput.suppressesActions(inTestMode: true))
        XCTAssertFalse(HIDInput.suppressesActions(inTestMode: false))
        XCTAssertTrue(HIDInput.suppressesActions(
            inTestMode: false, pressBeganInTestMode: true))
    }

    func testCurrentMacRaycastBindingsWhenExplicitlyRequested() throws {
        guard ProcessInfo.processInfo.environment["JOYCODING_VERIFY_LOCAL_RAYCAST"] == "1"
        else { throw XCTSkip("local Raycast verification is opt-in") }
        XCTAssertEqual(RaycastShortcuts.shortcut(for: "raycastLauncher"),
                       RaycastShortcut(modifiers: ["cmd"], keyCode: 49))
        XCTAssertEqual(RaycastShortcuts.shortcut(for: "raycastDictation"),
                       RaycastShortcut(modifiers: ["rightshift"], keyCode: 36))
        XCTAssertEqual(RaycastShortcuts.shortcut(for: "raycastAIChat"),
                       RaycastShortcut(modifiers: ["alt"], keyCode: 49))
        XCTAssertEqual(RaycastShortcuts.shortcut(for: "raycastArc"),
                       RaycastShortcut(modifiers: ["alt"], keyCode: 0))
        XCTAssertEqual(RaycastShortcuts.shortcut(for: "raycastSlack"),
                       RaycastShortcut(modifiers: ["alt"], keyCode: 1))
        XCTAssertEqual(RaycastShortcuts.shortcut(for: "raycastCodex"),
                       RaycastShortcut(modifiers: ["alt"], keyCode: 8))
        XCTAssertEqual(RaycastShortcuts.shortcut(for: "raycastHeptabase"),
                       RaycastShortcut(modifiers: ["alt"], keyCode: 14))
        XCTAssertEqual(RaycastShortcuts.shortcut(for: "raycastAmp"),
                       RaycastShortcut(modifiers: ["alt"], keyCode: 7))
        XCTAssertEqual(RaycastShortcuts.shortcut(for: "raycastWarp"),
                       RaycastShortcut(modifiers: ["alt"], keyCode: 13))
        XCTAssertEqual(RaycastShortcuts.shortcut(for: "raycastPreviousSpace"),
                       RaycastShortcut(modifiers: ["ctrl"], keyCode: 123))
        XCTAssertEqual(RaycastShortcuts.shortcut(for: "raycastNextSpace"),
                       RaycastShortcut(modifiers: ["ctrl"], keyCode: 124))
    }
}
