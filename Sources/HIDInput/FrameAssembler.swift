import TouchCore

/// One HID element value, already stripped of IOKit types so assembly is testable.
public struct HIDElementValue: Equatable, Sendable {
    /// Identifies the finger collection the element belongs to (parent collection cookie).
    public var slot: Int
    public var usagePage: UInt32
    public var usage: UInt32
    public var value: Int
    public var logicalMin: Int
    public var logicalMax: Int
    public var timestampNs: UInt64

    public init(slot: Int, usagePage: UInt32, usage: UInt32, value: Int, logicalMin: Int, logicalMax: Int, timestampNs: UInt64) {
        self.slot = slot
        self.usagePage = usagePage
        self.usage = usage
        self.value = value
        self.logicalMin = logicalMin
        self.logicalMax = logicalMax
        self.timestampNs = timestampNs
    }
}

/// Groups element values into TouchFrames. Values of one input report share a timestamp,
/// so a timestamp change closes the frame; `flush()` closes it on idle.
///
/// IOKit only delivers values that changed, so slot state persists across frames: a finger
/// that holds still still appears in every frame. Slots that never reported tip on are skipped;
/// a slot whose tip goes off is emitted once with `isTouching == false`.
public struct FrameAssembler: Sendable {
    private struct Slot: Sendable {
        var id: Int?
        var x: Double?
        var y: Double?
        var width: Double?
        var height: Double?
        var tip: Bool?
        var wasTouching = false
    }

    private var slots: [Int: Slot] = [:]
    private var slotOrder: [Int] = []
    private var currentTimestamp: UInt64?

    public init() {}

    public var hasPending: Bool { currentTimestamp != nil }

    public mutating func ingest(_ v: HIDElementValue) -> TouchFrame? {
        var finished: TouchFrame?
        if let ts = currentTimestamp, ts != v.timestampNs {
            finished = flush()
        }
        currentTimestamp = v.timestampNs
        apply(v)
        return finished
    }

    /// Seeds slot state (e.g. element values read right after opening the device) without
    /// starting a frame. Needed because IOKit only reports changes: a Contact ID equal to the
    /// last one before the device was opened is never delivered again.
    public mutating func prime(_ v: HIDElementValue) {
        apply(v)
    }

    private mutating func apply(_ v: HIDElementValue) {
        switch (v.usagePage, v.usage) {
        case (HIDUsage.pageGenericDesktop, HIDUsage.x): set(v, \.x)
        case (HIDUsage.pageGenericDesktop, HIDUsage.y): set(v, \.y)
        case (HIDUsage.pageDigitizer, HIDUsage.width): set(v, \.width)
        case (HIDUsage.pageDigitizer, HIDUsage.height): set(v, \.height)
        case (HIDUsage.pageDigitizer, HIDUsage.contactID): update(v.slot) { $0.id = v.value }
        case (HIDUsage.pageDigitizer, HIDUsage.tipSwitch): update(v.slot) { $0.tip = v.value != 0 }
        default: break
        }
    }

    public mutating func flush() -> TouchFrame? {
        guard let ts = currentTimestamp else { return nil }
        currentTimestamp = nil
        var contacts: [Contact] = []
        for key in slotOrder {
            guard var s = slots[key] else { continue }
            // Panels without a Tip Switch: a slot with coordinates counts as touching.
            let touching = s.tip ?? (s.x != nil && s.y != nil)
            // Contact ID is only sent when it changes; if it was never seen (and priming failed),
            // fall back to an id derived from the slot, which stays stable while the finger is down.
            if let x = s.x, let y = s.y, touching || s.wasTouching {
                let id = s.id ?? Self.syntheticIDBase + key
                contacts.append(Contact(id: id, x: x, y: y, width: s.width, height: s.height, isTouching: touching))
            }
            s.wasTouching = touching
            slots[key] = s
        }
        return contacts.isEmpty ? nil : TouchFrame(timestampNs: ts, contacts: contacts)
    }

    private mutating func set(_ v: HIDElementValue, _ field: WritableKeyPath<Slot, Double?>) {
        guard let n = Self.normalize(v) else { return }
        update(v.slot) { $0[keyPath: field] = n }
    }

    private mutating func update(_ key: Int, _ body: (inout Slot) -> Void) {
        if slots[key] == nil {
            slots[key] = Slot()
            slotOrder.append(key)
        }
        if var s = slots[key] {
            body(&s)
            slots[key] = s
        }
    }

    /// Ids at or above this value are synthetic (slot-derived), not reported by the panel.
    public static let syntheticIDBase = 1000

    static func normalize(_ v: HIDElementValue) -> Double? {
        guard v.logicalMax > v.logicalMin else { return nil }
        let n = Double(v.value - v.logicalMin) / Double(v.logicalMax - v.logicalMin)
        return min(max(n, 0), 1)
    }
}
