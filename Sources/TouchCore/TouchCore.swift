import Foundation

/// One finger on the panel. Coordinates are normalized to 0...1 (origin top-left).
public struct Contact: Equatable, Sendable, Codable {
    public let id: Int
    public var x: Double
    public var y: Double
    /// Normalized to 0...1 of the element's logical range; nil if the panel doesn't expose it.
    public var width: Double?
    public var height: Double?
    public var isTouching: Bool

    public init(id: Int, x: Double, y: Double, width: Double? = nil, height: Double? = nil, isTouching: Bool) {
        self.id = id
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.isTouching = isTouching
    }
}

public struct TouchFrame: Equatable, Sendable, Codable {
    public let timestampNs: UInt64
    public let contacts: [Contact]

    public init(timestampNs: UInt64, contacts: [Contact]) {
        self.timestampNs = timestampNs
        self.contacts = contacts
    }
}

public protocol Clock: Sendable {
    var nowNs: UInt64 { get }
}

/// JSON Lines: one TouchFrame per line. Recording format == fixture format.
public enum FixtureFormat {
    public static func encodeLine(_ frame: TouchFrame) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var data = try encoder.encode(frame)
        data.append(0x0A)
        return data
    }

    public static func decode(_ data: Data) throws -> [TouchFrame] {
        let decoder = JSONDecoder()
        return try data.split(separator: 0x0A)
            .filter { !$0.allSatisfy { $0 == 0x20 || $0 == 0x0D || $0 == 0x09 } }
            .map { try decoder.decode(TouchFrame.self, from: Data($0)) }
    }
}
