import Foundation
import IOKit.hid
import TouchCore

/// Opens one digitizer device on the main run loop and turns its element values into frames.
/// Phase 0 tool plumbing; the production engine (serial queue, no per-frame allocation) comes later.
public final class DigitizerReader: @unchecked Sendable {
    public let device: IOHIDDevice
    public private(set) var valueCount = 0
    public private(set) var frameCount = 0
    public private(set) var isOpen = false

    private var assembler = FrameAssembler()
    private let onFrame: (TouchFrame) -> Void
    private let onValue: ((HIDElementValue, HIDElementInfo) -> Void)?
    private var elementCache: [Int: HIDElementInfo] = [:]
    private var lastValueNs: UInt64 = 0
    private var flushTimer: Timer?

    /// IOKit can still deliver a queued value for a callback context after the device is closed
    /// (seen on L390 when the same device is reopened with seize). Readers are therefore never
    /// freed: a stale callback always lands on a live, closed reader and is ignored.
    nonisolated(unsafe) private static var retained: [DigitizerReader] = []

    public init(device: IOHIDDevice,
                onValue: ((HIDElementValue, HIDElementInfo) -> Void)? = nil,
                onFrame: @escaping (TouchFrame) -> Void) {
        self.device = device
        self.onValue = onValue
        self.onFrame = onFrame
    }

    public func start(seize: Bool) -> IOReturn {
        let options = seize ? IOOptionBits(kIOHIDOptionsTypeSeizeDevice) : IOOptionBits(kIOHIDOptionsTypeNone)
        let r = IOHIDDeviceOpen(device, options)
        guard r == kIOReturnSuccess else { return r }
        isOpen = true
        Self.retained.append(self)
        IOHIDDeviceRegisterInputValueCallback(device, { ctx, _, _, value in
            guard let ctx else { return }
            Unmanaged<DigitizerReader>.fromOpaque(ctx).takeUnretainedValue().handle(value)
        }, Unmanaged.passUnretained(self).toOpaque())
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        // Report that never gets a following report still has to be emitted.
        let timer = Timer(timeInterval: 0.008, repeats: true) { [weak self] _ in self?.flushIfIdle() }
        RunLoop.main.add(timer, forMode: .default)
        flushTimer = timer
        return r
    }

    public func stop() {
        guard isOpen else { return }
        flushTimer?.invalidate()
        flushTimer = nil
        if let f = assembler.flush() { emit(f) }
        IOHIDDeviceRegisterInputValueCallback(device, nil, nil)
        IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        isOpen = false
    }

    private func handle(_ value: IOHIDValue) {
        guard isOpen else { return }
        valueCount += 1
        let element = IOHIDValueGetElement(value)
        let cookie = Int(IOHIDElementGetCookie(element))
        let info: HIDElementInfo
        if let cached = elementCache[cookie] {
            info = cached
        } else {
            info = HIDElementInfo(element)
            elementCache[cookie] = info
        }
        let ts = MachTime.toNanoseconds(IOHIDValueGetTimeStamp(value))
        lastValueNs = ts
        let v = HIDElementValue(
            slot: info.parentCookie ?? -1, usagePage: info.usagePage, usage: info.usage,
            value: IOHIDValueGetIntegerValue(value),
            logicalMin: info.logicalMin, logicalMax: info.logicalMax, timestampNs: ts)
        onValue?(v, info)
        if let f = assembler.ingest(v) { emit(f) }
    }

    private func flushIfIdle() {
        guard assembler.hasPending else { return }
        let now = MachTime.toNanoseconds(mach_absolute_time())
        if now &- lastValueNs > 6_000_000, let f = assembler.flush() { emit(f) }
    }

    private func emit(_ f: TouchFrame) {
        frameCount += 1
        onFrame(f)
    }
}
