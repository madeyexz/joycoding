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
    }

    func testXboxShipsWithUsableDefaults() throws {
        let profile = try XCTUnwrap(DefaultProfiles.make(
            vendor: 0x045E, product: 0x0B22, name: "Xbox Wireless Controller"))
        XCTAssertEqual(profile.productID, 0x0B22)
        XCTAssertEqual(profile.buttons["1"]?.tap, "confirm")
        XCTAssertEqual(profile.buttons[String(XboxHID.leftTriggerButton)]?.tap, "ptt")
        XCTAssertEqual(profile.buttons[String(XboxHID.rightTriggerButton)]?.tap, "switchApp")
        XCTAssertEqual(profile.buttons["5"]?.tap, "appCyclePrevious")
        XCTAssertEqual(profile.buttons["3"]?.long, "raycastEmojiPicker")
        XCTAssertEqual(profile.buttons["5"]?.long, "raycastSlack")
        XCTAssertEqual(profile.buttons["6"], ButtonBinding(tap: "appCycleNext", long: "raycastWarp"))
        XCTAssertEqual(profile.buttons["7"]?.long, "raycastClipboardHistory")
        XCTAssertEqual(profile.buttons["8"], ButtonBinding(tap: "raycastLauncher", long: "raycastAIChat"))
        XCTAssertEqual(profile.buttons["9"]?.tap, "selectFocused")
        XCTAssertEqual(profile.buttons["9"]?.long, "raycastCodex")
        XCTAssertEqual(profile.buttons["10"]?.long, "raycastAmp")
        XCTAssertNil(profile.buttons["12"])
        XCTAssertEqual(profile.overrides[BundleID.arc]?.buttons["3"]?.tap, "arcReload")
        XCTAssertEqual(profile.overrides[BundleID.arc]?.buttons["3"]?.long, "raycastEmojiPicker")
        XCTAssertEqual(profile.overrides[BundleID.arc]?.buttons["7"]?.long, "raycastClipboardHistory")
        XCTAssertEqual(profile.overrides[BundleID.amp]?.buttons["8"],
                       ButtonBinding(tap: "ampNewSession", long: "raycastAIChat"))
        XCTAssertEqual(profile.sticks["hat"]?["up"],
                       StickDir(hat: 0, action: "scrollUp"))
        XCTAssertEqual(profile.sticks["hat"]?["down"],
                       StickDir(hat: 4, action: "scrollDown"))
        XCTAssertEqual(profile.sticks["hat"]?["right"], StickDir(hat: 2, action: "sessionNext"))
        XCTAssertEqual(profile.overrides[BundleID.amp]?.sticks["hat"]?["up"],
                       "ampPreviousThread")
        XCTAssertEqual(profile.overrides[BundleID.amp]?.sticks["hat"]?["down"],
                       "ampNextThread")
        XCTAssertEqual(profile.overrides[BundleID.codex]?.sticks["hat"]?["up"],
                       "codexPreviousThread")
        XCTAssertEqual(profile.overrides[BundleID.codex]?.sticks["hat"]?["down"],
                       "codexNextThread")
        XCTAssertEqual(profile.overrides[BundleID.wechat]?.sticks["hat"]?["up"], "up")
        XCTAssertEqual(profile.overrides[BundleID.wechat]?.sticks["hat"]?["down"], "down")
        XCTAssertEqual(profile.sticks["left"]?["up"],
                       StickDir(hat: 0, action: "focusPrevious"))
        XCTAssertEqual(profile.sticks["left"]?["right"],
                       StickDir(hat: 2, action: "focusNext"))
        XCTAssertEqual(profile.sticks["right"]?["up"], StickDir(hat: 0, action: "up"))
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

        XCTAssertEqual(config.xboxRaycastPresetVersion, 8)
        XCTAssertEqual(config.devices[0].buttons["5"]?.tap, "appCyclePrevious")
        XCTAssertEqual(config.devices[0].buttons["5"]?.long, "raycastSlack")
        XCTAssertEqual(config.devices[0].buttons["6"],
                       ButtonBinding(tap: "appCycleNext", long: "raycastWarp"))
        XCTAssertEqual(config.devices[0].buttons["8"],
                       ButtonBinding(tap: "raycastLauncher", long: "raycastAIChat"))
        XCTAssertEqual(config.devices[0].buttons["12"]?.tap, "customWeChat")
        XCTAssertEqual(config.devices[0].buttons["12"]?.long, "raycastHeptabase")
        XCTAssertEqual(config.devices[0].sticks["hat"], DefaultProfiles.dpad)
        XCTAssertEqual(config.devices[0].overrides[BundleID.amp]?.sticks["hat"]?["up"],
                       "ampPreviousThread")
        XCTAssertEqual(config.devices[0].overrides[BundleID.amp]?.sticks["hat"]?["down"],
                       "ampNextThread")
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

        XCTAssertEqual(config.xboxRaycastPresetVersion, 8)
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

        XCTAssertEqual(config.xboxRaycastPresetVersion, 8)
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

        XCTAssertEqual(config.xboxRaycastPresetVersion, 8)
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

        XCTAssertEqual(config.xboxRaycastPresetVersion, 8)
        XCTAssertEqual(config.devices[0].overrides[BundleID.amp]?.buttons["8"],
                       ButtonBinding(tap: "ampNewSession", long: "raycastAIChat"))
        XCTAssertEqual(config.devices[0].sticks["hat"], DefaultProfiles.dpad)
        XCTAssertEqual(config.devices[0].overrides[BundleID.amp]?.sticks["hat"]?["up"],
                       "ampPreviousThread")
        XCTAssertEqual(config.devices[0].overrides[BundleID.amp]?.sticks["hat"]?["down"],
                       "ampNextThread")
        XCTAssertEqual(config.devices[1].overrides[BundleID.amp]?.buttons["8"],
                       ButtonBinding(tap: "customMenu", long: "customHold"))
        XCTAssertEqual(config.devices[1].sticks["hat"]?["up"],
                       StickDir(hat: 1, action: "customUp"))
        XCTAssertEqual(config.devices[1].overrides[BundleID.amp]?.sticks["hat"]?["up"],
                       "customAmpUp")
        XCTAssertEqual(config.devices[1].overrides[BundleID.amp]?.sticks["hat"]?["down"],
                       "ampNextThread")
    }

    func testVersionFiveBaseDPadIsRepairedIntoAmpOnlyOverride() {
        var config = Config()
        config.xboxRaycastPresetVersion = 5
        var profile = DeviceProfile(vendorID: XboxHID.vendorID, productID: 0x0B22,
                                    name: "Xbox Elite Series 2")
        profile.sticks["hat"] = DefaultProfiles.xboxDpad
        config.devices = [profile]

        config.migrateXboxRaycastPresetIfNeeded()

        XCTAssertEqual(config.xboxRaycastPresetVersion, 8)
        XCTAssertEqual(config.devices[0].sticks["hat"], DefaultProfiles.dpad)
        XCTAssertEqual(config.devices[0].overrides[BundleID.amp]?.sticks["hat"]?["up"],
                       "ampPreviousThread")
        XCTAssertEqual(config.devices[0].overrides[BundleID.amp]?.sticks["hat"]?["down"],
                       "ampNextThread")
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

        XCTAssertEqual(config.xboxRaycastPresetVersion, 8)
        XCTAssertEqual(config.devices[0].overrides[BundleID.codex]?.sticks["hat"]?["up"],
                       "customCodexUp")
        XCTAssertEqual(config.devices[0].overrides[BundleID.codex]?.sticks["hat"]?["down"],
                       "codexNextThread")
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

        XCTAssertEqual(config.xboxRaycastPresetVersion, 8)
        XCTAssertEqual(config.devices[0].overrides[BundleID.wechat]?.sticks["hat"]?["up"],
                       "customWeChatUp")
        XCTAssertEqual(config.devices[0].overrides[BundleID.wechat]?.sticks["hat"]?["down"],
                       "down")
    }

    func testCommandAppSwitcherChordKeepsAAsTapAndConsumesShoulders() {
        var chord = CommandAppSwitcherChord()

        XCTAssertEqual(chord.handle(button: 1, down: true, device: "xbox", isXbox: true),
                       .begin)
        XCTAssertEqual(chord.handle(button: 6, down: true, device: "xbox", isXbox: true),
                       .next)
        XCTAssertEqual(chord.handle(button: 6, down: false, device: "xbox", isXbox: true),
                       .consume)
        XCTAssertEqual(chord.handle(button: 5, down: true, device: "xbox", isXbox: true),
                       .previous)
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
        XCTAssertTrue(chord.cancel(suppressAUntilRelease: true))
        XCTAssertEqual(chord.handle(button: 1, down: false, device: "xbox", isXbox: true),
                       .consume)
        XCTAssertFalse(chord.cancel(suppressAUntilRelease: true))

        XCTAssertEqual(chord.handle(button: 1, down: true, device: "xbox", isXbox: true),
                       .begin)
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
    }
}
