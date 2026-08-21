import Foundation

/// HID details that are specific to Microsoft's Bluetooth controller descriptor.
/// Keep them at the input boundary so the rest of JoyCoding continues to deal in
/// ordinary button numbers and zero-based, clockwise hat directions.
enum XboxHID {
    static let vendorID = 0x045E
    static let elite2ProductID = 0x0B22

    static let buttonPage = 0x09
    static let consumerPage = 0x0C
    static let elite2ViewUsage = 0xB2

    // Xbox Bluetooth reports its analog triggers on the Simulation Controls page.
    static let simulationPage = 0x02
    static let rightTriggerUsage = 0xC4   // Accelerator
    static let leftTriggerUsage = 0xC5    // Brake

    // Virtual button IDs live outside the controller's physical Button-page range.
    static let leftTriggerButton = 20
    static let rightTriggerButton = 21

    /// JoyCoding stores the conventional Xbox numbering (1=A, 2=B, 3=X, ...),
    /// but the Elite Series 2 BLE descriptor deliberately leaves holes for the
    /// legacy C/Z and digital-trigger fields. Its View button is also exposed as
    /// Consumer/Record rather than on the Button page. Normalize at the HID
    /// boundary so profiles and the mapping UI remain conventional.
    static func canonicalButton(vendor: Int, product: Int, usagePage: Int,
                                usage: Int) -> Int? {
        guard usagePage == buttonPage ||
                (vendor == vendorID && product == elite2ProductID &&
                 usagePage == consumerPage && usage == elite2ViewUsage)
        else { return nil }

        guard vendor == vendorID && product == elite2ProductID else {
            return usagePage == buttonPage ? usage : nil
        }

        if usagePage == consumerPage { return 7 } // View
        return [
            1: 1,   // A
            2: 2,   // B
            4: 3,   // X
            5: 4,   // Y
            7: 5,   // LB
            8: 6,   // RB
            11: 8,  // Menu
            12: 12, // Profile
            13: 11, // Xbox / Guide (macOS may reserve it)
            14: 9,  // L3
            15: 10, // R3
        ][usage]
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
}
