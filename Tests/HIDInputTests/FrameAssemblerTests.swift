import HIDInput
import TouchCore
import XCTest

final class FrameAssemblerTests: XCTestCase {
    private func finger(slot: Int, id: Int, tip: Bool, x: Int, y: Int, ts: UInt64) -> [HIDElementValue] {
        [
            HIDElementValue(slot: slot, usagePage: 0x0D, usage: 0x42, value: tip ? 1 : 0, logicalMin: 0, logicalMax: 1, timestampNs: ts),
            HIDElementValue(slot: slot, usagePage: 0x0D, usage: 0x51, value: id, logicalMin: 0, logicalMax: 255, timestampNs: ts),
            HIDElementValue(slot: slot, usagePage: 0x01, usage: 0x30, value: x, logicalMin: 0, logicalMax: 4000, timestampNs: ts),
            HIDElementValue(slot: slot, usagePage: 0x01, usage: 0x31, value: y, logicalMin: 0, logicalMax: 2000, timestampNs: ts),
        ]
    }

    private func feed(_ a: inout FrameAssembler, _ values: [HIDElementValue]) -> [TouchFrame] {
        values.compactMap { a.ingest($0) }
    }

    func testTimestampChangeClosesFrameWithTwoFingers() {
        var a = FrameAssembler()
        XCTAssertTrue(feed(&a, finger(slot: 10, id: 1, tip: true, x: 1000, y: 500, ts: 100)
            + finger(slot: 20, id: 2, tip: true, x: 4000, y: 2000, ts: 100)).isEmpty)
        let out = feed(&a, finger(slot: 10, id: 1, tip: true, x: 1000, y: 500, ts: 200))
        XCTAssertEqual(out, [TouchFrame(timestampNs: 100, contacts: [
            Contact(id: 1, x: 0.25, y: 0.25, isTouching: true),
            Contact(id: 2, x: 1, y: 1, isTouching: true),
        ])])
    }

    func testUnusedSlotsDroppedAndLiftEmittedOnce() {
        var a = FrameAssembler()
        _ = feed(&a, finger(slot: 10, id: 1, tip: true, x: 0, y: 0, ts: 1) + finger(slot: 20, id: 0, tip: false, x: 0, y: 0, ts: 1))
        XCTAssertEqual(a.flush()?.contacts.map(\.id), [1])
        _ = feed(&a, [HIDElementValue(slot: 10, usagePage: 0x0D, usage: 0x42, value: 0, logicalMin: 0, logicalMax: 1, timestampNs: 2)])
        XCTAssertEqual(a.flush()?.contacts, [Contact(id: 1, x: 0, y: 0, isTouching: false)])
        _ = feed(&a, [HIDElementValue(slot: 1, usagePage: 0x0D, usage: 0x56, value: 7, logicalMin: 0, logicalMax: 99, timestampNs: 3)])
        XCTAssertNil(a.flush())
    }

    /// IOKit only reports changed values: a finger moving only in X keeps its id, tip and Y.
    func testUnchangedValuesPersistAcrossFrames() {
        var a = FrameAssembler()
        _ = feed(&a, finger(slot: 10, id: 4, tip: true, x: 1000, y: 1000, ts: 1))
        _ = a.flush()
        _ = feed(&a, [HIDElementValue(slot: 10, usagePage: 0x01, usage: 0x30, value: 2000, logicalMin: 0, logicalMax: 4000, timestampNs: 2)])
        XCTAssertEqual(a.flush(), TouchFrame(timestampNs: 2, contacts: [Contact(id: 4, x: 0.5, y: 0.5, isTouching: true)]))
        // Stationary finger: only Scan Time changes, contact still reported.
        _ = feed(&a, [HIDElementValue(slot: 1, usagePage: 0x0D, usage: 0x56, value: 9, logicalMin: 0, logicalMax: 99, timestampNs: 3)])
        XCTAssertEqual(a.flush()?.contacts.count, 1)
    }

    func testNormalizationClampsAndRejectsBadRange() {
        var a = FrameAssembler()
        _ = feed(&a, [
            HIDElementValue(slot: 1, usagePage: 0x0D, usage: 0x51, value: 5, logicalMin: 0, logicalMax: 9, timestampNs: 1),
            HIDElementValue(slot: 1, usagePage: 0x01, usage: 0x30, value: 9999, logicalMin: 0, logicalMax: 100, timestampNs: 1),
            HIDElementValue(slot: 1, usagePage: 0x01, usage: 0x31, value: 50, logicalMin: 0, logicalMax: 100, timestampNs: 1),
            HIDElementValue(slot: 1, usagePage: 0x0D, usage: 0x48, value: 3, logicalMin: 0, logicalMax: 0, timestampNs: 1),
        ])
        XCTAssertEqual(a.flush()?.contacts, [Contact(id: 5, x: 1, y: 0.5, width: nil, isTouching: true)])
    }
}
