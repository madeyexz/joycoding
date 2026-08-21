import Foundation
import IOKit.hid

private func intProperty(_ device: IOHIDDevice, _ key: CFString) -> Int? {
    IOHIDDeviceGetProperty(device, key) as? Int
}

private func stringProperty(_ device: IOHIDDevice, _ key: CFString) -> String? {
    IOHIDDeviceGetProperty(device, key) as? String
}

private func boolProperty(_ device: IOHIDDevice, _ key: CFString) -> Bool {
    (IOHIDDeviceGetProperty(device, key) as? Bool) == true
}

private func deviceDescription(_ device: IOHIDDevice) -> String {
    let vendor = intProperty(device, kIOHIDVendorIDKey as CFString) ?? 0
    let product = intProperty(device, kIOHIDProductIDKey as CFString) ?? 0
    let name = stringProperty(device, kIOHIDProductKey as CFString) ?? "?"
    let transport = stringProperty(device, kIOHIDTransportKey as CFString) ?? "?"
    let virtual = boolProperty(device, "HIDVirtualDevice" as CFString)
        || boolProperty(device, "GCSyntheticDevice" as CFString)
    return String(
        format: "%@ vid=0x%04X pid=0x%04X transport=%@ virtual=%@",
        name, vendor, product, transport, virtual ? "yes" : "no")
}

private final class HIDProbe {
    private let manager: IOHIDManager
    private var eventCount = 0

    init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    func start() {
        IOHIDManagerSetDeviceMatchingMultiple(manager, [
            [kIOHIDDeviceUsagePageKey: 0x01, kIOHIDDeviceUsageKey: 0x05],
            [kIOHIDDeviceUsagePageKey: 0x01, kIOHIDDeviceUsageKey: 0x04],
        ] as CFArray)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputValueCallback(manager, { context, _, _, value in
            guard let context else { return }
            Unmanaged<HIDProbe>.fromOpaque(context).takeUnretainedValue().handle(value)
        }, context)
        IOHIDManagerScheduleWithRunLoop(
            manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else {
            fputs("ERROR IOHIDManagerOpen returned \(result)\n", stderr)
            exit(1)
        }

        let devices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
        print("DEVICE_COUNT \(devices.count)")
        for device in devices.sorted(by: { deviceDescription($0) < deviceDescription($1) }) {
            print("DEVICE \(deviceDescription(device))")
        }
        fflush(stdout)
    }

    func stop() {
        IOHIDManagerUnscheduleFromRunLoop(
            manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    private func handle(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let page = Int(IOHIDElementGetUsagePage(element))
        let usage = Int(IOHIDElementGetUsage(element))
        guard [0x01, 0x02, 0x09, 0x0C].contains(page) else { return }

        eventCount += 1
        let raw = Int(IOHIDValueGetIntegerValue(value))
        let logicalMin = IOHIDElementGetLogicalMin(element)
        let logicalMax = IOHIDElementGetLogicalMax(element)
        let reportID = IOHIDElementGetReportID(element)
        let device = IOHIDElementGetDevice(element)
        print(String(
            format: "EVENT %04d %@ page=0x%02X usage=0x%02X value=%d min=%d max=%d report=%d",
            eventCount, deviceDescription(device), page, usage, raw,
            logicalMin, logicalMax, reportID))
        fflush(stdout)
    }
}

private let seconds = CommandLine.arguments.dropFirst().first.flatMap(Double.init) ?? 15
private let probe = HIDProbe()
probe.start()
print("CAPTURE_SECONDS \(seconds)")
fflush(stdout)
RunLoop.current.run(until: Date().addingTimeInterval(seconds))
probe.stop()
print("CAPTURE_COMPLETE")
