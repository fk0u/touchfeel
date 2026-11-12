import Foundation
import IOKit.hid

public enum MachTime {
    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    public static func toNanoseconds(_ abs: UInt64) -> UInt64 {
        let tb = timebase
        if tb.numer == tb.denom { return abs }
        return abs &* UInt64(tb.numer) / UInt64(tb.denom)
    }
}

public enum InputMonitoringAccess: String {
    case granted, denied, unknown

    public static func check() -> InputMonitoringAccess {
        switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
        case kIOHIDAccessTypeGranted: return .granted
        case kIOHIDAccessTypeDenied: return .denied
        default: return .unknown
        }
    }

    /// Triggers the system prompt if not yet decided. Returns true if granted.
    @discardableResult
    public static func request() -> Bool { IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) }
}

public struct HIDDeviceSummary {
    public let device: IOHIDDevice
    public let vendorID: Int
    public let productID: Int
    public let product: String
    public let manufacturer: String
    public let transport: String
    public let primaryUsagePage: UInt32
    public let primaryUsage: UInt32
    public let usagePairs: [(page: UInt32, usage: UInt32)]
    public let locationID: Int

    public var vidpid: String { String(format: "%04x:%04x", vendorID, productID) }

    public init(_ device: IOHIDDevice) {
        self.device = device
        vendorID = Self.int(device, kIOHIDVendorIDKey) ?? 0
        productID = Self.int(device, kIOHIDProductIDKey) ?? 0
        product = Self.string(device, kIOHIDProductKey) ?? "?"
        manufacturer = Self.string(device, kIOHIDManufacturerKey) ?? "?"
        transport = Self.string(device, kIOHIDTransportKey) ?? "?"
        primaryUsagePage = UInt32(Self.int(device, kIOHIDPrimaryUsagePageKey) ?? 0)
        primaryUsage = UInt32(Self.int(device, kIOHIDPrimaryUsageKey) ?? 0)
        locationID = Self.int(device, kIOHIDLocationIDKey) ?? 0
        let pairs = IOHIDDeviceGetProperty(device, kIOHIDDeviceUsagePairsKey as CFString) as? [[String: Any]] ?? []
        usagePairs = pairs.compactMap { d in
            guard let p = d[kIOHIDDeviceUsagePageKey] as? Int, let u = d[kIOHIDDeviceUsageKey] as? Int else { return nil }
            return (UInt32(p), UInt32(u))
        }
    }

    public var isTouchScreen: Bool {
        usagePairs.contains { $0.page == HIDUsage.pageDigitizer && $0.usage == HIDUsage.touchScreen }
            || (primaryUsagePage == HIDUsage.pageDigitizer && primaryUsage == HIDUsage.touchScreen)
    }

    public var hasContactID: Bool {
        HIDElements.all(of: device).contains { $0.usagePage == HIDUsage.pageDigitizer && $0.usage == HIDUsage.contactID }
    }

    public var reportDescriptor: Data? {
        IOHIDDeviceGetProperty(device, kIOHIDReportDescriptorKey as CFString) as? Data
    }

    static func int(_ d: IOHIDDevice, _ key: String) -> Int? {
        IOHIDDeviceGetProperty(d, key as CFString) as? Int
    }

    static func string(_ d: IOHIDDevice, _ key: String) -> String? {
        IOHIDDeviceGetProperty(d, key as CFString) as? String
    }
}

public struct HIDElementInfo {
    public let element: IOHIDElement
    public let cookie: Int
    public let type: IOHIDElementType
    public let usagePage: UInt32
    public let usage: UInt32
    public let logicalMin: Int
    public let logicalMax: Int
    public let reportID: Int
    public let reportSize: Int
    public let reportCount: Int
    public let parentCookie: Int?
    public let parentUsagePage: UInt32
    public let parentUsage: UInt32

    public init(_ e: IOHIDElement) {
        element = e
        cookie = Int(IOHIDElementGetCookie(e))
        type = IOHIDElementGetType(e)
        usagePage = IOHIDElementGetUsagePage(e)
        usage = IOHIDElementGetUsage(e)
        logicalMin = IOHIDElementGetLogicalMin(e)
        logicalMax = IOHIDElementGetLogicalMax(e)
        reportID = Int(IOHIDElementGetReportID(e))
        reportSize = Int(IOHIDElementGetReportSize(e))
        reportCount = Int(IOHIDElementGetReportCount(e))
        if let p = IOHIDElementGetParent(e) {
            parentCookie = Int(IOHIDElementGetCookie(p))
            parentUsagePage = IOHIDElementGetUsagePage(p)
            parentUsage = IOHIDElementGetUsage(p)
        } else {
            parentCookie = nil
            parentUsagePage = 0
            parentUsage = 0
        }
    }

    public var typeName: String {
        switch type {
        case kIOHIDElementTypeInput_Misc: return "in-misc"
        case kIOHIDElementTypeInput_Button: return "in-button"
        case kIOHIDElementTypeInput_Axis: return "in-axis"
        case kIOHIDElementTypeInput_ScanCodes: return "in-scancodes"
        case kIOHIDElementTypeOutput: return "output"
        case kIOHIDElementTypeFeature: return "feature"
        case kIOHIDElementTypeCollection: return "collection"
        default: return "type\(type.rawValue)"
        }
    }
}

public enum HIDElements {
    public static func all(of device: IOHIDDevice) -> [HIDElementInfo] {
        guard let cf = IOHIDDeviceCopyMatchingElements(device, nil, IOOptionBits(kIOHIDOptionsTypeNone)) else { return [] }
        return (0..<CFArrayGetCount(cf)).compactMap { i in
            guard let ptr = CFArrayGetValueAtIndex(cf, i) else { return nil }
            return HIDElementInfo(Unmanaged<IOHIDElement>.fromOpaque(ptr).takeUnretainedValue())
        }
    }
}

public enum HIDDevices {
    /// Enumerates every HID device visible to this process. Does not open any device.
    public static func all() -> [HIDDeviceSummary] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, nil)
        guard let set = IOHIDManagerCopyDevices(manager) else { return [] }
        let count = CFSetGetCount(set)
        var raw = [UnsafeRawPointer?](repeating: nil, count: count)
        raw.withUnsafeMutableBufferPointer { buf in
            if let base = buf.baseAddress { CFSetGetValues(set, base) }
        }
        return raw.compactMap { $0 }
            .map { HIDDeviceSummary(Unmanaged<IOHIDDevice>.fromOpaque($0).takeUnretainedValue()) }
            .sorted { ($0.primaryUsagePage, $0.primaryUsage, $0.locationID) < ($1.primaryUsagePage, $1.primaryUsage, $1.locationID) }
    }

    /// Touch screen candidates: usage pair Digitizer/Touch Screen, else any device with a Contact ID element.
    public static func touchScreenCandidates(from devices: [HIDDeviceSummary]) -> [HIDDeviceSummary] {
        let direct = devices.filter(\.isTouchScreen)
        return direct.isEmpty ? devices.filter(\.hasContactID) : direct
    }
}
