import Foundation
import TouchCore
import XCTest

final class FixtureFormatTests: XCTestCase {
    func testRoundTrip() throws {
        let frames = [
            TouchFrame(timestampNs: 1_000, contacts: [Contact(id: 0, x: 0.25, y: 0.5, width: 0.01, height: 0.02, isTouching: true)]),
            TouchFrame(timestampNs: 9_000, contacts: [Contact(id: 0, x: 0.26, y: 0.5, isTouching: false)]),
        ]
        var data = Data()
        for f in frames { data.append(try FixtureFormat.encodeLine(f)) }
        XCTAssertEqual(try FixtureFormat.decode(data), frames)
    }

    func testNilSizeIsOmittedAndBlankLinesIgnored() throws {
        let line = try FixtureFormat.encodeLine(TouchFrame(timestampNs: 1, contacts: [Contact(id: 3, x: 0, y: 1, isTouching: true)]))
        let text = String(decoding: line, as: UTF8.self)
        XCTAssertFalse(text.contains("width"))
        XCTAssertEqual(try FixtureFormat.decode(Data("\n".utf8) + line + Data("\n\n".utf8)).count, 1)
    }

    /// Every recording dropped into Tests/Fixtures must parse.
    func testAllFixturesParse() throws {
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        for url in files where url.pathExtension == "jsonl" {
            let frames = try FixtureFormat.decode(Data(contentsOf: url))
            XCTAssertFalse(frames.isEmpty, url.lastPathComponent)
            XCTAssertEqual(frames.map(\.timestampNs), frames.map(\.timestampNs).sorted(), "\(url.lastPathComponent): timestamp tidak urut")
        }
    }
}
