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
/// Unused finger slots (tip off, never seen touching) are dropped. A slot whose id was
/// touching in an earlier frame and now reports tip off is emitted once as a lift.
public struct FrameAssembler: Sendable {
    private struct Slot: Sendable {
        var id: Int?
        var x: Double?
        var y: Double?
        var width: Double?
        var height: Double?
        var tip: Bool?
    }

    private var slots: [Int: Slot] = [:]
    private var slotOrder: [Int] = []
    private var currentTimestamp: UInt64?
    private var activeIDs: Set<Int> = []

    public init() {}

    public var hasPending: Bool { currentTimestamp != nil }

    public mutating func ingest(_ v: HIDElementValue) -> TouchFrame? {
        var finished: TouchFrame?
        if let ts = currentTimestamp, ts != v.timestampNs {
            finished = flush()
        }
        currentTimestamp = v.timestampNs

        let field: WritableKeyPath<Slot, Double?>?
        switch (v.usagePage, v.usage) {
        case (HIDUsage.pageGenericDesktop, HIDUsage.x): field = \.x
        case (HIDUsage.pageGenericDesktop, HIDUsage.y): field = \.y
        case (HIDUsage.pageDigitizer, HIDUsage.width): field = \.width
        case (HIDUsage.pageDigitizer, HIDUsage.height): field = \.height
        case (HIDUsage.pageDigitizer, HIDUsage.contactID):
            update(v.slot) { $0.id = v.value }
            return finished
        case (HIDUsage.pageDigitizer, HIDUsage.tipSwitch):
            update(v.slot) { $0.tip = v.value != 0 }
            return finished
        default:
            return finished
        }
        if let field, let n = Self.normalize(v) {
            update(v.slot) { $0[keyPath: field] = n }
        }
        return finished
    }

    public mutating func flush() -> TouchFrame? {
        guard let ts = currentTimestamp else { return nil }
        var contacts: [Contact] = []
        var nowActive = activeIDs
        for key in slotOrder {
            guard let s = slots[key], let id = s.id, let x = s.x, let y = s.y else { continue }
            let touching = s.tip ?? true
            if touching {
                nowActive.insert(id)
            } else if activeIDs.contains(id) {
                nowActive.remove(id)
            } else {
                continue
            }
            contacts.append(Contact(id: id, x: x, y: y, width: s.width, height: s.height, isTouching: touching))
        }
        activeIDs = nowActive
        slots.removeAll(keepingCapacity: true)
        slotOrder.removeAll(keepingCapacity: true)
        currentTimestamp = nil
        return contacts.isEmpty ? nil : TouchFrame(timestampNs: ts, contacts: contacts)
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

    static func normalize(_ v: HIDElementValue) -> Double? {
        guard v.logicalMax > v.logicalMin else { return nil }
        let n = Double(v.value - v.logicalMin) / Double(v.logicalMax - v.logicalMin)
        return min(max(n, 0), 1)
    }
}
