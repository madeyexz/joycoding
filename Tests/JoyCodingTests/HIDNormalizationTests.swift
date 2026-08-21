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
                     11: 8, 12: 12, 13: 11, 14: 9, 15: 10]
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
        XCTAssertEqual(XboxHID.canonicalButton(
            vendor: 0x045E, product: 0x0B22,
            usagePage: XboxHID.consumerPage, usage: XboxHID.elite2ViewUsage), 7)
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
        XCTAssertEqual(profile.buttons["5"]?.long, "focusSlack")
        XCTAssertEqual(profile.buttons["6"], ButtonBinding(tap: "focusArc", long: "focusGhostty"))
        XCTAssertEqual(profile.buttons["9"]?.long, "focusCodex")
        XCTAssertEqual(profile.buttons["12"]?.long, "focusHeptabase")
        XCTAssertEqual(profile.overrides[BundleID.arc]?.buttons["3"]?.tap, "arcReload")
        XCTAssertEqual(profile.sticks["hat"]?["up"], StickDir(hat: 0, action: "scrollUp"))
        XCTAssertEqual(profile.sticks["hat"]?["right"], StickDir(hat: 2, action: "sessionNext"))
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
}
