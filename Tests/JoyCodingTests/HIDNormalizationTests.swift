import XCTest
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

    func testXboxShipsWithUsableDefaults() throws {
        let profile = try XCTUnwrap(DefaultProfiles.make(
            vendor: 0x045E, product: 0x0B22, name: "Xbox Wireless Controller"))
        XCTAssertEqual(profile.productID, 0x0B22)
        XCTAssertEqual(profile.buttons["1"]?.tap, "confirm")
        XCTAssertEqual(profile.buttons[String(XboxHID.leftTriggerButton)]?.tap, "ptt")
        XCTAssertEqual(profile.buttons[String(XboxHID.rightTriggerButton)]?.tap, "switchApp")
        XCTAssertEqual(profile.sticks["hat"]?["up"], StickDir(hat: 0, action: "scrollUp"))
        XCTAssertEqual(profile.sticks["hat"]?["right"], StickDir(hat: 2, action: "sessionNext"))
    }
}
