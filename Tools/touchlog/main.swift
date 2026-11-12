import CoreGraphics
import Foundation
import HIDInput
import IOKit.hid
import TouchCore

// MARK: - Args

let usage = """
touchlog — Fase 0 TouchFeel: inspeksi HID touchscreen.

  touchlog                         Dump semua device HID (elemen ditampilkan untuk kandidat touchscreen)
  touchlog --all-elements          Dump elemen untuk semua device
  touchlog --watch [--raw]         Cetak kontak per frame (--raw: tiap nilai elemen juga)
  touchlog --record FILE.jsonl     Rekam frame ke JSON Lines (format fixture). Ctrl-C untuk berhenti
  touchlog --probe-seize [--seconds N]
                                   Uji jalur A (tanpa seize) lalu B (seize), default 8 detik per jalur

  --device VID:PID                 Pilih device (hex), mis. --device 04f3:2a1c
"""

var args = Array(CommandLine.arguments.dropFirst())
@MainActor func flag(_ name: String) -> Bool {
    guard let i = args.firstIndex(of: name) else { return false }
    args.remove(at: i)
    return true
}
@MainActor func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    let v = args[i + 1]
    args.removeSubrange(i...(i + 1))
    return v
}
@MainActor func fail(_ msg: String) -> Never {
    FileHandle.standardError.write(Data("touchlog: \(msg)\n".utf8))
    exit(1)
}

if flag("--help") || flag("-h") { print(usage); exit(0) }
let allElements = flag("--all-elements")
let watch = flag("--watch")
let raw = flag("--raw")
let probe = flag("--probe-seize")
let recordPath = option("--record")
let deviceFilter = option("--device")?.lowercased()
let seconds = option("--seconds").flatMap(Double.init) ?? 8
if !args.isEmpty { fail("argumen tidak dikenal: \(args.joined(separator: " "))\n\n\(usage)") }

// MARK: - Helpers

@MainActor func hex(_ v: UInt32, _ w: Int = 2) -> String { "0x" + String(format: "%0\(w)x", v) }
@MainActor func usageLabel(_ p: UInt32, _ u: UInt32) -> String {
    let n = HIDUsage.name(page: p, usage: u)
    return "\(hex(p))/\(hex(u))" + (n.isEmpty ? "" : " \(n)")
}
@MainActor func ioReturnString(_ r: IOReturn) -> String {
    let code = String(format: "0x%08x", UInt32(bitPattern: r))
    switch r {
    case kIOReturnExclusiveAccess: return "\(code) kIOReturnExclusiveAccess"
    case kIOReturnNotPermitted: return "\(code) kIOReturnNotPermitted"
    case kIOReturnNotPrivileged: return "\(code) kIOReturnNotPrivileged"
    default: return code
    }
}
@MainActor func fmt(_ d: Double?) -> String { d.map { String(format: "%.4f", $0) } ?? "-" }
@MainActor func describe(_ f: TouchFrame, prev: UInt64?) -> String {
    let dt = prev.map { String(format: "%6.2fms", Double(f.timestampNs &- $0) / 1e6) } ?? "      - "
    let cs = f.contacts.map { c in
        "#\(c.id) \(c.isTouching ? "tip" : "up ") x=\(fmt(c.x)) y=\(fmt(c.y)) w=\(fmt(c.width)) h=\(fmt(c.height))"
    }.joined(separator: " | ")
    return "t=\(f.timestampNs) dt=\(dt) n=\(f.contacts.count) | \(cs)"
}

@MainActor func checkAccess() {
    let a = InputMonitoringAccess.check()
    print("Input Monitoring: \(a.rawValue)")
    if a != .granted {
        InputMonitoringAccess.request()
        print("""
          ! Izin Input Monitoring belum diberikan ke app terminal ini.
            Buka System Settings > Privacy & Security > Input Monitoring, aktifkan Terminal
            (atau app terminal yang dipakai), tutup lalu buka lagi terminalnya, dan jalankan ulang.
          """)
    }
}

@MainActor func selectDevices(_ all: [HIDDeviceSummary]) -> [HIDDeviceSummary] {
    if let filter = deviceFilter {
        let picked = all.filter { $0.vidpid == filter }
        if picked.isEmpty { fail("tidak ada device \(filter). Jalankan touchlog tanpa argumen untuk daftar device.") }
        // One physical device often appears several times (one per top-level collection).
        return picked.filter { $0.isTouchScreen || $0.hasContactID }.isEmpty
            ? picked : picked.filter { $0.isTouchScreen || $0.hasContactID }
    }
    let c = HIDDevices.touchScreenCandidates(from: all)
    if c.isEmpty {
        fail("tidak ada device touchscreen (Digitizer 0x0D/0x04 atau elemen Contact ID). Jalankan touchlog tanpa argumen dan tempel outputnya.")
    }
    return c
}

@MainActor func printDevice(_ d: HIDDeviceSummary, elements: Bool) {
    let pairs = d.usagePairs.map { usageLabel($0.page, $0.usage) }.joined(separator: ", ")
    print("""
    ── \(d.vidpid)  "\(d.product)"  maker="\(d.manufacturer)"  transport=\(d.transport)  location=\(String(format: "0x%x", d.locationID))
       primary=\(usageLabel(d.primaryUsagePage, d.primaryUsage))\(d.isTouchScreen ? "  [TOUCHSCREEN]" : "")
       usagePairs=[\(pairs)]
    """)
    guard elements else { return }
    if let desc = d.reportDescriptor {
        print("   reportDescriptor (\(desc.count) bytes):")
        stride(from: 0, to: desc.count, by: 32).forEach { i in
            let line = desc[desc.index(desc.startIndex, offsetBy: i)..<desc.index(desc.startIndex, offsetBy: min(i + 32, desc.count))]
            print("     " + line.map { String(format: "%02x", $0) }.joined(separator: " "))
        }
    } else {
        print("   reportDescriptor: tidak tersedia")
    }
    print("   elements: cookie type usage logical[min..max] reportID size x count parent")
    for e in HIDElements.all(of: d.device) {
        let parent = e.parentCookie.map { "#\($0) \(usageLabel(e.parentUsagePage, e.parentUsage))" } ?? "-"
        print("     #\(e.cookie) \(e.typeName) \(usageLabel(e.usagePage, e.usage)) [\(e.logicalMin)..\(e.logicalMax)] rid=\(e.reportID) \(e.reportSize)x\(e.reportCount) parent=\(parent)")
    }
}

// MARK: - Signal handling (always release devices, especially a seized one)

var activeReaders: [DigitizerReader] = []
var onExit: [() -> Void] = []
signal(SIGINT, SIG_IGN)
signal(SIGTERM, SIG_IGN)
let sigSources = [SIGINT, SIGTERM].map { sig -> DispatchSourceSignal in
    let s = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    s.setEventHandler {
        activeReaders.forEach { $0.stop() }
        onExit.forEach { $0() }
        exit(0)
    }
    s.resume()
    return s
}

// MARK: - Modes

print("touchlog · macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
checkAccess()
let devices = HIDDevices.all()

if !watch && !probe && recordPath == nil {
    print("\(devices.count) device HID\n")
    for d in devices {
        printDevice(d, elements: allElements || d.isTouchScreen || d.hasContactID)
    }
    let c = HIDDevices.touchScreenCandidates(from: devices)
    print("\nKandidat touchscreen: " + (c.isEmpty ? "tidak ada" : c.map { "\($0.vidpid) \"\($0.product)\"" }.joined(separator: ", ")))
    exit(0)
}

let targets = selectDevices(devices)

if watch || recordPath != nil {
    var writer: FileHandle?
    if let path = recordPath {
        FileManager.default.createFile(atPath: path, contents: nil)
        guard let h = FileHandle(forWritingAtPath: path) else { fail("tidak bisa menulis \(path)") }
        writer = h
        onExit.append { try? h.close() }
    }
    var prev: UInt64?
    var frames = 0
    for d in targets {
        let reader = DigitizerReader(
            device: d.device,
            onValue: raw ? { v, e in
                print("  raw slot=\(v.slot) cookie=#\(e.cookie) \(usageLabel(v.usagePage, v.usage)) value=\(v.value) [\(v.logicalMin)..\(v.logicalMax)] t=\(v.timestampNs)")
            } : nil,
            onFrame: { f in
                frames += 1
                if let w = writer {
                    do { try w.write(contentsOf: FixtureFormat.encodeLine(f)) } catch { fail("gagal menulis: \(error)") }
                    if frames % 100 == 0 { print("  \(frames) frame terekam") }
                } else {
                    print(describe(f, prev: prev))
                }
                prev = f.timestampNs
            })
        let r = reader.start(seize: false)
        if r != kIOReturnSuccess { fail("gagal membuka \(d.vidpid): \(ioReturnString(r))") }
        activeReaders.append(reader)
        print("Membaca \(d.vidpid) \"\(d.product)\"" + (recordPath.map { " → \($0)" } ?? "") + ". Ctrl-C untuk berhenti.")
    }
    onExit.append { print("\nSelesai: \(frames) frame.") }
    RunLoop.main.run()
}

// MARK: - Probe

struct PhaseResult {
    var open = "-"
    var values = 0
    var frames = 0
    var maxContacts = 0
    var firstFrame: String?
    var systemEvents: [String: UInt32] = [:]
}

let counted: [(String, CGEventType)] = [
    ("mouseMoved", .mouseMoved), ("leftMouseDown", .leftMouseDown),
    ("leftMouseDragged", .leftMouseDragged), ("scrollWheel", .scrollWheel),
]
@MainActor func counters() -> [String: UInt32] {
    Dictionary(uniqueKeysWithValues: counted.map { ($0.0, CGEventSource.counterForEventType(.combinedSessionState, eventType: $0.1)) })
}

@MainActor func runPhase(_ d: HIDDeviceSummary, seize: Bool) -> PhaseResult {
    var res = PhaseResult()
    let reader = DigitizerReader(device: d.device) { f in
        res.maxContacts = max(res.maxContacts, f.contacts.count)
        if res.firstFrame == nil { res.firstFrame = describe(f, prev: nil) }
    }
    let label = seize ? "B (seize)" : "A (tanpa seize)"
    print("\n[\(label)] \(d.vidpid): dalam 2 detik, SENTUH dan GESER satu jari di layar selama \(Int(seconds)) detik.")
    print("  Jangan sentuh trackpad/mouse selama tes. Device dilepas otomatis setelah waktu habis.")
    RunLoop.main.run(until: Date().addingTimeInterval(2))
    let before = counters()
    let r = reader.start(seize: seize)
    res.open = r == kIOReturnSuccess ? "ok" : ioReturnString(r)
    if r == kIOReturnSuccess {
        activeReaders.append(reader)
        print("  ...mulai")
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
        reader.stop()
        activeReaders.removeAll { $0 === reader }
    }
    let after = counters()
    res.values = reader.valueCount
    res.frames = reader.frameCount
    res.systemEvents = Dictionary(uniqueKeysWithValues: counted.map { ($0.0, after[$0.0, default: 0] &- before[$0.0, default: 0]) })
    print("  selesai: open=\(res.open) values=\(res.values) frames=\(res.frames)")
    return res
}

var report: [String] = ["=== touchlog probe-seize ===", "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)", "Input Monitoring: \(InputMonitoringAccess.check().rawValue)"]
for d in targets {
    let a = runPhase(d, seize: false)
    let b = runPhase(d, seize: true)
    func line(_ n: String, _ p: PhaseResult) -> String {
        let ev = counted.map { "\($0.0)=\(p.systemEvents[$0.0, default: 0])" }.joined(separator: " ")
        return "  \(n): open=\(p.open) values=\(p.values) frames=\(p.frames) maxContacts=\(p.maxContacts)\n     systemEvents: \(ev)\n     firstFrame: \(p.firstFrame ?? "-")"
    }
    func pointerEvents(_ p: PhaseResult) -> UInt32 { p.systemEvents.values.reduce(0, &+) }
    var verdict: String
    if a.values == 0 && b.values == 0 {
        verdict = "Raw touch TIDAK terlihat di A maupun B → kemungkinan jalur C (cek izin Input Monitoring dulu)."
    } else if a.values > 0 && b.values > 0 && pointerEvents(b) == 0 {
        verdict = "Raw terlihat; seize menghentikan event pointer sistem → jalur B layak (pastikan keyboard/trackpad tetap jalan)."
    } else if a.values > 0 && pointerEvents(b) > 0 {
        verdict = "Raw terlihat, tapi event pointer sistem tetap muncul saat seize → event dobel; perlu jalur C atau matikan output pointer VoodooI2C."
    } else {
        verdict = "Hasil campuran, perlu dianalisis manual."
    }
    report += ["device \(d.vidpid) \"\(d.product)\" transport=\(d.transport)", line("A", a), line("B", b), "  dugaan: \(verdict)"]
}
report += [
    "Jawab manual: (1) Saat A, kursor ikut bergerak/klik? (2) Saat B, kursor diam? (3) Saat B, keyboard & trackpad masih jalan?",
    "=== akhir ===",
]
print("\n" + report.joined(separator: "\n"))
exit(0)
