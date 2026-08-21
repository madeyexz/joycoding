import Foundation

/// HID details that are specific to Microsoft's Bluetooth controller descriptor.
/// Keep them at the input boundary so the rest of JoyCoding continues to deal in
/// ordinary button numbers and zero-based, clockwise hat directions.
enum XboxHID {
    static let vendorID = 0x045E
    static let elite2ProductID = 0x0B22

    static let buttonPage = 0x09
    static let genericDesktopPage = 0x01

    // Xbox Bluetooth reports its analog triggers on the Simulation Controls page.
    static let simulationPage = 0x02
    static let rightTriggerUsage = 0xC4   // Accelerator
    static let leftTriggerUsage = 0xC5    // Brake

    // Virtual button IDs live outside the controller's physical Button-page range.
    static let leftTriggerButton = 20
    static let rightTriggerButton = 21

    /// JoyCoding stores the conventional Xbox numbering (1=A, 2=B, 3=X, ...),
    /// but the Elite Series 2 BLE descriptor deliberately leaves holes for the
    /// legacy C/Z and digital-trigger fields. Normalize at the HID boundary so
    /// profiles and the mapping UI remain conventional.
    static func canonicalButton(vendor: Int, product: Int, usagePage: Int,
                                usage: Int) -> Int? {
        guard usagePage == buttonPage else { return nil }

        guard vendor == vendorID && product == elite2ProductID else {
            return usagePage == buttonPage ? usage : nil
        }

        return [
            1: 1,   // A
            2: 2,   // B
            4: 3,   // X
            5: 4,   // Y
            7: 5,   // LB
            8: 6,   // RB
            11: 7,  // View
            12: 8,  // Menu
            13: 11, // Xbox / Guide (macOS may reserve it)
            14: 9,  // L3
            15: 10, // R3
        ][usage]
    }

    enum AxisComponent: Equatable { case x, y }
    struct StickAxis: Equatable {
        let channel: StickChannel
        let component: AxisComponent
    }

    /// Xbox BLE exposes left X/Y as usages 0x30/0x31 and right X/Y as
    /// 0x32/0x35 on Generic Desktop. Profile remains hardware-only.
    static func stickAxis(vendor: Int, usagePage: Int, usage: Int) -> StickAxis? {
        guard vendor == vendorID, usagePage == genericDesktopPage else { return nil }
        switch usage {
        case 0x30: return StickAxis(channel: .left, component: .x)
        case 0x31: return StickAxis(channel: .left, component: .y)
        case 0x32: return StickAxis(channel: .right, component: .x)
        case 0x35: return StickAxis(channel: .right, component: .y)
        default: return nil
        }
    }

    static func displayName(vendor: Int, product: Int, reported: String) -> String {
        vendor == vendorID && product == elite2ProductID
            ? "Xbox Elite Series 2" : reported
    }

    static func virtualButton(vendor: Int, usagePage: Int, usage: Int) -> Int? {
        guard vendor == vendorID, usagePage == simulationPage else { return nil }
        switch usage {
        case leftTriggerUsage: return leftTriggerButton
        case rightTriggerUsage: return rightTriggerButton
        default: return nil
        }
    }
}

enum HIDNormalization {
    /// Convert any standard eight-way HID hat to JoyCoding's 0...7 clockwise form.
    ///
    /// Xbox Bluetooth uses 1...8 and reports 0 while centred. Nintendo and many
    /// other controllers use 0...7 and report 8 (or another out-of-range value)
    /// while centred. Checking the element's declared range handles both without
    /// a product-ID table.
    static func hat(raw: Int, logicalMin: Int, logicalMax: Int) -> Int? {
        if logicalMin == 1 && logicalMax == 8 {
            guard (1...8).contains(raw) else { return nil }
            return raw - 1
        }
        guard (0...7).contains(raw) else { return nil }
        return raw
    }

    /// Turn an analog trigger into a stable button with hysteresis. Xbox Elite
    /// trigger stops can cap reported travel around 17%, so 10% must count as a
    /// press; it must return below 5% to release, avoiding noisy transitions.
    static func triggerPressed(raw: Int, logicalMin: Int, logicalMax: Int,
                               wasPressed: Bool) -> Bool {
        guard logicalMax > logicalMin else { return false }
        let progress = Double(raw - logicalMin) / Double(logicalMax - logicalMin)
        return wasPressed ? progress >= 0.05 : progress >= 0.10
    }

    /// Normalize a signed or unsigned HID axis into -1...1.
    static func axis(raw: Int, logicalMin: Int, logicalMax: Int) -> Double {
        guard logicalMax > logicalMin else { return 0 }
        let progress = Double(raw - logicalMin) / Double(logicalMax - logicalMin)
        return min(1, max(-1, progress * 2 - 1))
    }

    /// Reduce an analog stick to the same clockwise cardinal values used by a
    /// HID hat: up=0, right=2, down=4, left=6. Separate engage/release thresholds
    /// stop centre noise from repeatedly starting and cancelling an action.
    static func stickDirection(x: Double, y: Double, previous: Int?) -> Int? {
        let magnitude = max(abs(x), abs(y))
        let threshold = previous == nil ? 0.55 : 0.35
        guard magnitude >= threshold else { return nil }
        if abs(x) > abs(y) { return x > 0 ? 2 : 6 }
        return y > 0 ? 4 : 0
    }
}
