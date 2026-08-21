import Foundation

/// HID details that are specific to Microsoft's Bluetooth controller descriptor.
/// Keep them at the input boundary so the rest of JoyCoding continues to deal in
/// ordinary button numbers and zero-based, clockwise hat directions.
enum XboxHID {
    static let vendorID = 0x045E

    // Xbox Bluetooth reports its analog triggers on the Simulation Controls page.
    static let simulationPage = 0x02
    static let rightTriggerUsage = 0xC4   // Accelerator
    static let leftTriggerUsage = 0xC5    // Brake

    // Virtual button IDs live outside the controller's physical Button-page range.
    static let leftTriggerButton = 20
    static let rightTriggerButton = 21

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
