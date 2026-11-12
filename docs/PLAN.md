# TouchFeel macOS — Project Plan

Nov 12, 2026 · @Al-Ghani Desta Setyawan

## Ringkasan & Problem Statement

**TouchFeel** = daemon userspace di macOS yang mengubah input touchscreen laptop non-Apple (target awal: ThinkPad L390) dari "mouse palsu" jadi gesture yang terasa seperti touch: tap, drag, scroll dengan inertia, long-press, dan pinch.

**Masalah.** Touchscreen sudah terbaca di macOS lewat VoodooI2C, tapi semua kontak diperlakukan sebagai pointer. Hasilnya kursor ikut loncat, tap terasa seperti klik mouse, scroll kaku, dan palm sering ikut terbaca.

**Tujuan**

- Touch terasa langsung dan natural: tap = klik atomik tanpa kursor berjalan, drag halus, scroll dengan momentum.
- Latency tambahan dari daemon sekecil mungkin (target di bawah 5 ms).
- Ringan: CPU idle hampir 0%, tanpa kext baru.
- Bisa dituning (sensitivity, palm rejection) lewat menu bar app.

**Non-goals**

- Bukan driver I2C/ACPI baru. Layer itu sudah ditangani VoodooI2C dan tetap di luar scope.
- Bukan UI touch-first ala iPadOS. Ukuran elemen dan layout macOS tidak berubah.
- Bukan "satu pkg untuk semua laptop" di versi awal. Validasi dulu di L390, baru generalisasi.

**Target.** ThinkPad L390 dengan macOS Ventura 13 sampai Tahoe 26 (Hackintosh via OpenCore). Perangkat dev saat ini Sequoia 15, rinciannya di Matrix Dukungan macOS.

## Realitas Teknis & Batasan

Project ini layak dikerjakan solo, asal ekspektasinya jujur: hasil akhirnya "touch yang smooth dan natural di atas model pointer macOS", bukan rasa iPad 100%.

| Batasan | Dampak | Respons di desain |
| --- | --- | --- |
| macOS berbasis pointer + keyboard (AppKit) | Konten tidak "menempel di jari" seperti iPadOS | Tap = warp + klik atomik, drag dengan mouseDown/Drag/Up sintetis |
| Tidak ada API publik untuk gesture sistem (pinch, rotate, swipe) | Gesture sistem bergantung field CGEvent private | Mulai dari tap, drag, scroll. Pinch/swipe fase belakangan dan opsional |
| Fitur touchscreen resmi macOS terbaru tidak bisa diverifikasi | Jangan dijadikan asumsi arsitektur | Seluruh desain memakai API publik |
| Event datang dari VoodooI2C yang sudah mengirim input ke sistem | Bisa dobel event atau tabrakan | Tes seize device / baca HID report langsung di Fase 0 |
| Inject event butuh izin Accessibility + Input Monitoring | Setup awal lebih ribet | Onboarding checklist di app |
| Hackintosh berada di luar EULA Apple dan runway Intel macOS pendek | Basis pengguna terbatas, ada risiko jangka panjang | Scope dikunci Ventura sampai Tahoe 26, macOS 27 tidak ditarget (lihat Matrix Dukungan macOS) |

Catatan: "mouse atau touch" tidak perlu dideteksi dari pola gerakan. Sumber event sudah jelas (device touchscreen). Yang dibangun adalah **intent recognizer**: menebak maksud kontak (tap, drag, scroll, long-press, pinch) dari pola kontak.

## Matrix Dukungan macOS

Target dukungan: **Ventura 13 sampai Tahoe 26**. Perangkat dev saat ini Sequoia 15, jadi tiga versi lain diuji lewat volume terpisah di L390 yang sama dan lewat replay fixture.

**Tahoe 26 adalah plafon proyek.** Apple menyatakan Tahoe sebagai rilis macOS terakhir untuk Mac Intel, dan macOS 27 hanya untuk Apple Silicon ([AppleInsider](https://appleinsider.com/articles/25/06/17/opencore-and-hackintosh-are-sadly-dead-after-apple-ends-intel-mac-support), [MacGeneration, Okt 2026](https://www.macg.co/macos/2026/10/macos-tahoe-arrive-enfin-sur-les-vieux-mac-grace-opencore-legacy-patcher-311479)). OpenCore tidak bisa menambal itu, jadi macOS 27 tidak ditarget.

| Versi | Peran | Yang diketahui | Yang harus dites |
| --- | --- | --- | --- |
| Ventura 13 | Lantai minimum | `SMAppService` (auto-start LaunchAgent) dan `MenuBarExtra` (SwiftUI) mulai ada di versi ini, jadi cocok jadi deployment target | Gesture dasar, izin Accessibility dan Input Monitoring, auto-start |
| Sonoma 14 | Titik regresi | Tidak ada keputusan khusus, dipakai sebagai titik tengah | Scroll phase + momentum, perilaku kursor tersembunyi |
| Sequoia 15 | Baseline dev (perangkat sekarang) | Semua fixture, tuning awal, dan latency baseline diambil di sini | Seluruh metrik di bagian Testing & Metrik |
| Tahoe 26 | Plafon (Intel terakhir) | Hackintosh jalan, dan ada laporan touchscreen via VoodooI2C di Tahoe 26.7.1 pada laptop lain ([wiki repo XPS 13 Plus](https://github.com/JulioNectar/Hackintosh-XPS13Plus-IrisXe-Tahoe/wiki)) | Tampilan app menu bar (Liquid Glass), izin, field CGEvent private, stabilitas VoodooI2C |

**Strategi kompatibilitas**

1. Deployment target macOS 13.0, build dengan SDK terbaru. Fitur khusus versi dibungkus `#available` (mis. gaya Liquid Glass hanya di 26+).
2. Semua kode yang bergantung versi masuk modul `Compat/` dengan feature flag, terutama field CGEvent private untuk pinch dan swipe.
3. Recognizer murni (`TouchCore` + `Recognizer`) tidak menyentuh API sistem, jadi perilakunya identik di semua versi dan diuji lewat fixture.

**Cara tes tanpa ganti laptop**

- Pasang Ventura, Sonoma, dan Tahoe di volume APFS terpisah di L390, boot lewat OpenCore picker. Sequoia tetap untuk kerja harian. Konfigurasi kext mungkin perlu penyesuaian per versi.
- Fixture rekaman dari Sequoia diputar ulang di CI untuk semua versi. Yang wajib dites langsung per versi cuma `EventOutput`, izin, dan app menu bar.
- Hasil checklist regresi (tap, drag, scroll, long-press di Safari, Finder, editor teks) dicatat per versi.

**Konsekuensi plafon**

- Umur proyek di Hackintosh dibatasi umur Tahoe. Karena `TouchCore` portabel, daemon yang sama berpotensi dipakai untuk layar sentuh USB-HID di Mac Apple Silicon asli. Ini opsional dan belum divalidasi.
- Prior art yang wajib dipelajari sebelum Fase 1: repo XPS 13 Plus di atas punya tool `xe-toque` untuk scroll satu jari, hold untuk klik kanan, edge swipe, pen, dan magnifier di atas VoodooI2C.

## Arsitektur

&#91;embedded content: arsitektur touchfeeld · 5 komponen\]

VoodooI2C tetap jadi lapisan hardware. Daemon userspace membaca HID report, mengenali intent, lalu menyuntik event sintetis ke macOS. Recognizer adalah satu-satunya bagian yang benar-benar baru.

## Spesifikasi Gesture Recognizer

Recognizer adalah state machine yang tidak menggerakkan kursor selama niat jari belum jelas. Angka di bawah adalah titik awal untuk dituning dengan data raw L390, bukan nilai final.

| Gesture | Sinyal | Threshold awal | Output event |
| --- | --- | --- | --- |
| Tap | 1 kontak, gerak kecil, durasi singkat | slop 9 px, durasi di bawah 200 ms | Warp kursor + klik atomik |
| Drag | 1 kontak, gerak melewati slop | lebih dari 9 px | mouseDown di titik awal, lalu mouseDragged, mouseUp saat jari lepas |
| Long-press | 1 kontak diam | lebih dari 500 ms | Klik kanan |
| Scroll | 2 kontak bergerak searah | jarak antar jari relatif tetap | Scroll wheel dengan phase began/changed/ended |
| Momentum | Velocity saat jari lepas | Dihitung dari beberapa frame terakhir | momentumPhase dengan decay |
| Pinch | 2 kontak, jarak antar jari berubah | Perubahan jarak melebihi perubahan posisi tengah | Magnify (opsional, Fase 3) |
| Palm rejection | Luas kontak besar atau kontak tidak wajar | Area di atas 1800 (unit panel, dituning) | Kontak diabaikan |

**Aturan yang bikin terasa touch, bukan mouse**

1. Fase `pending`: jangan gerakkan kursor sama sekali sampai intent jelas.
2. Tap = warp + klik dalam satu langkah, tanpa kursor "berjalan" ke titik tap.
3. Slop adaptif: diperbesar kalau jari cepat atau area kontak besar.
4. Scroll memakai phase events asli supaya inertia dan rubber-band bekerja seperti trackpad.
5. Kursor disembunyikan saat touch aktif, muncul lagi saat mouse atau trackpad asli bergerak.

**Skeleton state**

```swift
enum TouchState {
    case idle
    case pending(start: Contact, t0: TimeInterval)
    case dragging
    case scrolling(velocity: CGVector)
    case longPress
    case pinching(startDistance: CGFloat)
}
```

## Struktur Repo & Tech Stack

Swift Package untuk core logic, supaya recognizer bisa dites tanpa hardware. App shell (menu bar + preferences) terpisah dari engine.

```text
touchfeel/
├── Package.swift
├── Sources/
│   ├── TouchCore/          # model Contact, Frame, math (tanpa dependency sistem)
│   ├── Recognizer/         # state machine, config, velocity tracker
│   ├── HIDInput/           # IOHIDManager, parser HID report -> Frame
│   ├── EventOutput/        # CGEvent injector, scroll phase, cursor hide
│   └── touchfeeld/         # entry point daemon
├── App/                    # menu bar app + preferences (SwiftUI)
├── Tools/
│   └── touchlog/           # CLI logger raw contact (x, y, area, t)
├── Tests/
│   ├── RecognizerTests/    # replay rekaman raw touch -> assert event
│   └── Fixtures/           # file rekaman sesi dari L390
└── docs/
```

| Bagian | Pilihan | Alasan |
| --- | --- | --- |
| Bahasa utama | Swift | API macOS native, IOKit dan CGEvent mudah diakses |
| Hot path | Swift dengan struct dan tanpa alokasi per frame | Hindari GC-like jitter, cukup untuk beban ini |
| UI | SwiftUI menu bar + Preferences | Ringan, terasa native |
| Config | JSON/plist di Application Support | Mudah di-hot-reload oleh daemon |
| Auto-start | App tunggal + SMAppService.mainApp (D1) | Auto-start per user, tanpa kext |
| Testing | XCTest + replay fixtures | Recognizer bisa diuji deterministik |

C++ hanya dipakai kalau profiling membuktikan ada bottleneck di parser HID.

## Roadmap & Milestone

&#91;embedded content: roadmap · 5 fase, 5 gate\]

Estimasi di atas kasar dan belum diukur, dengan asumsi kerja paruh waktu di sela kuliah dan proyek lain. Jangan lanjut ke fase berikutnya sebelum gate fase sekarang lolos; Fase 0 yang paling menentukan.

## Risiko & Mitigasi

Risiko terbesar ada di hubungan dengan VoodooI2C, karena itu dites paling awal. Kalau Fase 0 gagal, scope diubah sebelum sempat menulis recognizer.

| Risiko | Kemungkinan | Dampak | Mitigasi |
| --- | --- | --- | --- |
| Daemon tabrakan dengan event multitouch dari VoodooI2C (event dobel) | Tinggi | Tinggi | Fase 0: tes seize device, baca HID report langsung, atau matikan output multitouch VoodooI2C lewat konfigurasi |
| Izin Accessibility / Input Monitoring ditolak atau di-reset sistem | Sedang | Sedang | Onboarding checklist, deteksi izin hilang dan tampilkan peringatan |
| Field CGEvent private untuk pinch/swipe berubah antar versi macOS | Tinggi | Sedang | Isolasi di modul terpisah, feature flag, fallback ke gesture dasar |
| Latency kurang karena VoodooI2C masih polling, bukan GPIO interrupt | Sedang | Tinggi | Cek mode dulu. Kalau polling, perbaiki GPIO pinning sebelum menyalahkan recognizer |
| Threshold tidak cocok di panel lain | Tinggi | Sedang | Semua angka di config, mode kalibrasi, profil per panel |
| Dukungan macOS Intel berakhir | Pasti: Tahoe 26 rilis Intel terakhir | Tinggi | Plafon proyek = Tahoe 26. Jaga TouchCore tetap portabel supaya bisa dipakai di luar Hackintosh |
| Palm rejection salah (jari sah ikut ditolak) | Sedang | Sedang | Tuning dari data nyata, tombol "ignore large contacts" yang bisa dimatikan |

## Testing & Metrik

Recognizer diuji dengan replay: rekam sesi sentuhan nyata dari L390, simpan sebagai fixture, lalu jalankan ulang dan cek event yang keluar. Dengan begitu tuning tidak butuh duduk di depan laptop setiap kali.

| Metrik | Cara ukur | Target awal |
| --- | --- | --- |
| Latency tambahan daemon | Timestamp frame masuk vs event keluar | Di bawah 5 ms |
| Akurasi tap | 100 tap di grid tombol, hitung yang meleset atau jadi drag | Di atas 98% |
| Salah deteksi drag saat tap | Sesi tap cepat 2 menit, hitung drag palsu | Di bawah 1% |
| False positive palm | Sesi mengetik dengan telapak menyentuh layar | Nol klik tak sengaja |
| Kelancaran scroll | Perbandingan visual dengan trackpad di halaman panjang, frame drop | Tanpa patah, momentum mirip trackpad |
| CPU saat idle | Activity Monitor | Mendekati 0% |
| CPU saat touch aktif | Activity Monitor | Di bawah 3% |

**Jenis tes**

- Unit test recognizer dengan fixture rekaman (otomatis, jalan di CI).
- Tes manual terstruktur: checklist tap, drag, scroll, long-press di Safari, Finder, dan editor teks.
- Tes regresi tiap update macOS minor.

## Langkah Pertama & Open Questions

Ukur dulu sebelum menulis recognizer. Checklist 48 jam pertama:

- [ ] Cek versi VoodooI2C dan satellite kext yang terpasang di L390
- [ ] Cek mode VoodooI2C: polling atau GPIO interrupt (log di Console, `ioreg`)
- [ ] Dapatkan hardware ID panel touchscreen (vendor, product, report descriptor)
- [ ] Buat `touchlog`: CLI yang mencetak raw contact (id, x, y, area, timestamp) lewat IOHIDManager
- [ ] Tes apakah device bisa di-seize tanpa mematikan input VoodooI2C, atau event jadi dobel
- [ ] Rekam 5 sesi sentuhan (tap, drag, scroll, palm) sebagai fixture awal
- [ ] Catat latency mentah sentuh ke event sebagai baseline

**Open questions**

- Gejala mana yang paling mengganggu sekarang: lag, scroll, atau gesture?
- Versi macOS dan VoodooI2C yang dipakai persisnya apa?
- Project ini open-source dari awal atau tertutup dulu? Pengaruhnya ke lisensi dan distribusi.
- Setelah L390 stabil, model laptop kedua mana yang dipakai untuk validasi generalisasi?

## Keputusan Desain

Keputusan ini dikunci sebelum coding supaya Claude Code tidak mengarang arah sendiri. Ubah hanya kalau Fase 0 membuktikan salah.

| # | Keputusan | Alternatif yang ditolak | Alasan |
| --- | --- | --- | --- |
| D1 | **V1 = satu proses**: `TouchFeel.app` (menu bar, `LSUIElement`) menjalankan engine di background queue. Auto-start lewat `SMAppService.mainApp` | LaunchAgent + helper terpisah | Izin TCC (Accessibility, Input Monitoring) menempel ke satu binary, setup izin sekali saja. Helper dipisah baru kalau ada alasan nyata |
| D2 | Target `touchfeeld` tetap ada sebagai **CLI headless** yang memakai library `Engine` yang sama | Hanya app | Dev loop cepat dan bisa jalan tanpa UI. Output log bisa langsung dibaca Claude Code |
| D3 | **IPC v1 = file config + file watcher** (`DispatchSource`). Tanpa XPC | XPC service | Cukup untuk tuning. XPC baru kalau butuh status realtime dua arah |
| D4 | Engine = library Swift. `TouchCore` dan `Recognizer` **tanpa import IOKit/CoreGraphics** | Satu target besar | Recognizer bisa diuji deterministik lewat fixture dan portabel |
| D5 | Recognizer **digerakkan clock yang di-inject** + `tick(now)` | Timer di dalam recognizer | Long-press dan momentum butuh waktu tanpa frame baru. Clock palsu membuat tes deterministik |
| D6 | Bahasa: **Swift only** di v1 | C++ untuk parser | Optimasi hanya setelah profiling menunjuk bottleneck |
| D7 | Signing dev: **identitas self-signed yang stabil** (mis. `TouchFeel Dev`) | Ad-hoc signing | Ad-hoc membuat TCC reset izin tiap rebuild |
| D8 | Fitur private API (pinch, swipe, sembunyi kursor) **di balik feature flag**, default mati | Langsung aktif | Bisa rusak antar versi macOS. Gesture dasar tidak boleh bergantung padanya |
| D9 | Distribusi awal: **build sendiri dan GitHub release tanpa notarization** | Notarized pkg | Notarization butuh Apple Developer Program berbayar. Audiens Hackintosh biasa membuka app manual. Revisit saat rilis publik |

## Spesifikasi Input (HID)

**Unknown terbesar** ada di sini: apakah daemon bisa melihat raw touch dari device, atau VoodooI2C sudah "menelan" datanya jadi event pointer. Ini tidak bisa dijawab tanpa hardware, jadi Fase 0 memutuskan jalurnya.

| Jalur | Cara | Syarat | Kalau gagal |
| --- | --- | --- | --- |
| A (diutamakan) | `IOHIDManager` membaca device digitizer langsung, tanpa seize | Device terlihat di `ioreg` dengan usage page 0x0D dan input value callback menerima kontak | Lanjut ke B |
| B | Sama seperti A tapi open dengan `kIOHIDOptionsTypeSeizeDevice` | Seize tidak mematikan keyboard/trackpad lain dan event VoodooI2C berhenti dobel | Lanjut ke C |
| C | Konfigurasi VoodooI2C supaya mengekspos raw digitizer, atau baca lewat satellite kext | Perubahan kecil di konfigurasi/kext yang sudah ada | Scope direvisi: jadi patch/contribution ke VoodooI2C |

**Matching.** Cari device dengan usage page `0x0D` (Digitizer) dan usage `0x04` (Touch Screen). Kalau tidak ketemu, dump semua device HID dan cari yang punya elemen Contact ID.

**Elemen yang dibaca per kontak** (usage page Digitizer kecuali dicatat)

| Elemen | Usage | Dipakai untuk |
| --- | --- | --- |
| Tip Switch | 0x42 | Jari menyentuh atau tidak |
| Contact ID | 0x51 | Identitas jari lintas frame |
| X, Y (Generic Desktop 0x01) | 0x30, 0x31 | Posisi |
| Width, Height | 0x48, 0x49 | Luas kontak untuk palm rejection |
| Contact Count | 0x54 | Jumlah kontak di frame |
| Scan Time | 0x56 | Sinkronisasi frame, kalau ada |

Tidak semua panel mengekspos semua elemen. Parser harus membaca **report descriptor** untuk tahu elemen mana yang ada, bukan menganggap layout tetap. Elemen yang tidak ada diberi nilai default dan dicatat di log.

**Normalisasi.** Ambil logical min/max X dan Y dari elemen, ubah ke 0.0 sampai 1.0, baru dipetakan ke `CGDisplayBounds` display bawaan (`CGDisplayIsBuiltin`). Rotasi layar dan multi-display di luar scope v1.

**Timestamp.** Pakai `IOHIDValueGetTimeStamp` (mach absolute time), dikonversi ke nanodetik lewat `mach_timebase_info`. Frame disusun dengan mengumpulkan value sampai ada pemisah frame (Scan Time berubah atau Contact Count tercapai).

**Threading.** Jadwalkan manager ke satu serial queue berprioritas tinggi (`IOHIDManagerSetDispatchQueue`). Hot path tanpa alokasi per frame dan tanpa log level info per frame.

**Izin.** Input Monitoring untuk membaca HID (`IOHIDCheckAccess` / `IOHIDRequestAccess`), Accessibility untuk menyuntik event (`AXIsProcessTrusted`). App harus mendeteksi kalau salah satu hilang dan menampilkan status di menu bar.

## Kontrak Core & Recognizer

Ini batas API antar modul. `TouchCore` dan `Recognizer` hanya bergantung pada Foundation, tanpa IOKit dan CoreGraphics (keputusan D4).

```swift
// TouchCore
public struct Contact: Equatable, Sendable {
    public let id: Int
    public var x: Double          // 0...1, kiri ke kanan
    public var y: Double          // 0...1, atas ke bawah
    public var width: Double?     // 0...1, nil kalau panel tidak mengekspos
    public var height: Double?
    public var isTouching: Bool
}

public struct TouchFrame: Equatable, Sendable {
    public let timestampNs: UInt64
    public let contacts: [Contact]
}

public protocol Clock: Sendable {
    var nowNs: UInt64 { get }
}

// Recognizer
public enum OutputEvent: Equatable, Sendable {
    case click(at: Point, button: Button, count: Int)
    case mouseDown(at: Point, button: Button)
    case mouseDragged(to: Point)
    case mouseUp(at: Point, button: Button)
    case scroll(dx: Double, dy: Double, phase: ScrollPhase)
    case momentum(dx: Double, dy: Double, phase: MomentumPhase)
    case magnify(delta: Double, phase: ScrollPhase)   // di balik flag
}

public final class GestureRecognizer {
    public init(config: RecognizerConfig, clock: Clock)
    /// Dipanggil tiap frame dari HID.
    public func handle(_ frame: TouchFrame) -> [OutputEvent]
    /// Dipanggil periodik (~8 ms) selama ada state berbasis waktu.
    public func tick() -> [OutputEvent]
    /// Kembalikan ke idle dan batalkan gesture yang sedang berjalan.
    public func reset() -> [OutputEvent]
}
```

**Kenapa ada `tick()`.** Long-press (500 ms tanpa gerak) dan momentum scroll terjadi saat tidak ada frame baru. Recognizer yang hanya bereaksi pada frame tidak bisa melakukan keduanya. Engine menjalankan timer ringan hanya saat `isTimeDriven == true`, supaya CPU idle tetap mendekati 0%.

**Transisi state**

| State | Kejadian | State berikutnya | Output |
| --- | --- | --- | --- |
| idle | 1 kontak valid muncul | pending | Tidak ada (kursor tidak bergerak) |
| pending | Gerak melewati slop | dragging | mouseDown di titik awal, mouseDragged |
| pending | Jari lepas sebelum batas tap | idle | click di titik awal |
| pending | Diam melewati batas long-press | longPress | click kanan |
| pending | Kontak kedua muncul | twoFinger | Tidak ada |
| twoFinger | Gerak searah | scrolling | scroll(began), lalu scroll(changed) |
| twoFinger | Jarak antar jari berubah dominan | pinching | magnify (hanya kalau flag aktif) |
| scrolling | Jari lepas dengan velocity di atas batas | momentum | scroll(ended), momentum(begin) |
| momentum | Velocity di bawah batas atau kontak baru | idle | momentum(end) |
| dragging | Jari lepas | idle | mouseUp |
| apa saja | Kontak melebihi batas palm | state sama, kontak itu diabaikan | Tidak ada |

**Velocity tracker.** Simpan sampel posisi dalam jendela sekitar 100 ms terakhir, hitung velocity dari sampel awal dan akhir jendela. Momentum meluruh per tick dengan faktor gesekan konstan dan berhenti di bawah batas minimum. Semua angka (jendela, gesekan, batas) masuk `RecognizerConfig`, nilai awalnya ditebak lalu dituning dari fixture nyata.

**Aturan invarian yang harus dites**

- Setiap `mouseDown` selalu punya `mouseUp`, termasuk saat `reset()` atau device dicabut.
- Setiap `scroll(began)` selalu ditutup `scroll(ended)`.
- Fase `pending` tidak pernah menghasilkan event yang menggerakkan kursor.

## Spesifikasi Output (CGEvent)

`EventOutput` menerjemahkan `OutputEvent` jadi `CGEvent` dan mengirimnya lewat `CGEvent.post(tap: .cghidEventTap)`. Modul ini satu-satunya yang boleh import CoreGraphics di sisi output.

| OutputEvent | CGEvent | Catatan |
| --- | --- | --- |
| click | `mouseMoved` ke titik (warp), lalu `leftMouseDown` + `leftMouseUp` | Dikirim berurutan dalam satu panggilan, tanpa jeda render di antaranya. Atur `mouseEventClickState` untuk double-tap |
| click kanan | `rightMouseDown` + `rightMouseUp` | Dari long-press |
| mouseDown / mouseDragged / mouseUp | `leftMouseDown`, `leftMouseDragged`, `leftMouseUp` | Dragged memakai posisi absolut, bukan delta |
| scroll | `CGEvent(scrollWheelEvent2Source:units:.pixel ...)` | Set `scrollWheelEventIsContinuous = 1` dan `scrollWheelEventScrollPhase` (began=1, changed=2, ended=4) |
| momentum | Event scroll yang sama | Set `scrollWheelEventMomentumPhase` (begin=1, continue=2, end=3). Nilai konstanta diverifikasi dari header `CGEventTypes.h` SDK yang dipakai, bukan dari memori |
| magnify | Event gesture private | Di balik feature flag D8 |

**Penanda anti-loop.** Setiap event hasil suntikan diberi `eventSourceUserData` dengan nilai khusus TouchFeel. Event dengan penanda itu diabaikan oleh komponen mana pun yang mendengarkan event, supaya tidak terjadi feedback loop.

**Arah scroll.** Ikuti pengaturan "natural scrolling" sistem. Jangan di-hardcode, tapi sediakan opsi invert di config.

**Kursor.** Pendekatan default: kursor tetap ada tapi tidak "berjalan" ke titik tap (warp + klik atomik). Menyembunyikan kursor saat touch aktif adalah fitur opsional di balik flag D8, karena API publik untuk itu terbatas pada app yang sedang aktif.

**Keamanan state.** Kalau device dicabut, izin dicabut, atau app berhenti saat gesture berjalan, `EventOutput` wajib mengirim `mouseUp` dan `scroll(ended)` yang tertunda. Tidak boleh ada tombol mouse yang "nyangkut".

## Config & IPC

Config disimpan di `~/Library/Application Support/TouchFeel/config.json`. Menu bar app menulis, engine memantau file dan menerapkan perubahan tanpa restart (keputusan D3). Nilai di bawah adalah default awal, semuanya bisa dituning.

```json
{
  "version": 1,
  "recognizer": {
    "tapSlopPx": 9,
    "tapMaxMs": 200,
    "longPressMs": 500,
    "adaptiveSlop": true,
    "velocityWindowMs": 100,
    "momentumFriction": 0.95,
    "momentumMinVelocity": 20
  },
  "palm": {
    "enabled": true,
    "maxContactArea": 0.04
  },
  "scroll": {
    "naturalDirection": "system",
    "speedMultiplier": 1.0
  },
  "features": {
    "pinch": false,
    "hideCursor": false
  },
  "device": {
    "vendorId": null,
    "productId": null
  },
  "logging": {
    "level": "info",
    "recordSession": false
  }
}
```

**Aturan config**

- Config tidak valid tidak boleh membuat engine mati. Engine memakai nilai terakhir yang valid dan menampilkan peringatan di menu bar.
- Nilai di luar rentang waras di-clamp, bukan ditolak.
- `maxContactArea` dinyatakan sebagai fraksi luas layar supaya tidak bergantung pada resolusi panel.

**Mode rekam.** Dengan `recordSession: true`, engine menulis frame mentah ke file JSON Lines, satu frame per baris: timestamp nanodetik dan daftar kontak. File inilah yang menjadi fixture untuk replay test, jadi format rekaman dan format fixture harus identik.

**Logging.** Pakai `os.Logger` dengan kategori per modul. Latency diukur dengan `os_signpost` dari frame masuk sampai event diposting, supaya bisa dibaca di Instruments tanpa menambah beban di hot path.

## Task Breakdown untuk Claude Code

Satu fase = satu sesi Claude Code. Jangan lanjut ke fase berikutnya sebelum semua acceptance criteria fase sekarang tercentang dan Ghani sudah mengonfirmasi hasil di hardware.

**Fase 0: Riset dan baseline**

- [ ] Scaffold Swift Package sesuai struktur repo, dengan target `TouchCore`, `Recognizer`, `HIDInput`, `EventOutput`, executable `touchlog` dan `touchfeeld`
- [ ] `touchlog`: dump semua device HID (vendor, product, usage page, usage, elemen) ke stdout
- [ ] `touchlog --watch`: cetak raw contact (id, x, y, width, height, tip, timestamp) untuk device digitizer
- [ ] `touchlog --record file.jsonl`: rekam frame ke JSON Lines sesuai format fixture
- [ ] `touchlog --probe-seize`: coba jalur A lalu B dari decision tree Spesifikasi Input, laporkan hasilnya
- [ ] Acceptance: Ghani menjalankan `touchlog` di L390 dan hasilnya cukup untuk memilih jalur A, B, atau C

**Fase 1: MVP (tap, drag, long-press)**

- [ ] Implementasi `TouchCore` (Contact, TouchFrame, Clock) dan `RecognizerConfig`
- [ ] Implementasi `GestureRecognizer` untuk idle, pending, dragging, longPress, plus `tick()`
- [ ] Palm rejection dasar berdasarkan luas kontak
- [ ] `EventOutput`: click, mouseDown/Dragged/Up, penanda anti-loop, pembersihan state saat berhenti
- [ ] `touchfeeld` headless menghubungkan HIDInput, Recognizer, dan EventOutput
- [ ] Unit test: tiap baris tabel transisi punya tes, ditambah tiga invarian
- [ ] Replay test dengan fixture rekaman dari Fase 0
- [ ] Acceptance: akurasi tap di atas 98% dan drag palsu di bawah 1% pada sesi uji Ghani

**Fase 2: Scroll dan feel**

- [ ] State twoFinger dan scrolling dengan event scroll berfase
- [ ] Velocity tracker dan momentum lewat `tick()`
- [ ] Slop adaptif
- [ ] Opsi invert scroll dan `speedMultiplier`
- [ ] Signpost latency dari frame masuk sampai event diposting
- [ ] Acceptance: scroll terasa setara trackpad di Safari dan Finder, latency tambahan di bawah 5 ms

**Fase 3: App menu bar dan tuning**

- [ ] `TouchFeel.app` (SwiftUI `MenuBarExtra`, `LSUIElement`) yang menjalankan engine di background queue
- [ ] Onboarding izin (Input Monitoring dan Accessibility) dengan status live
- [ ] Preferences: slider untuk nilai config, tombol rekam sesi, tombol reset
- [ ] Auto-start lewat `SMAppService.mainApp`
- [ ] Mode kalibrasi: layar target tap untuk mengukur slop dan akurasi
- [ ] Pinch di balik feature flag (opsional)
- [ ] Acceptance: semua tuning bisa dilakukan tanpa mengedit file config

**Fase 4: Generalisasi dan rilis**

- [ ] Profil per model panel dan pemilihan device lewat vendor/product ID
- [ ] Lulus regresi di Ventura, Sonoma, Sequoia, Tahoe
- [ ] README, panduan izin, panduan troubleshooting
- [ ] Rilis GitHub dengan build tanpa notarization (D9)
- [ ] Acceptance: jalan di dua model laptop dan empat versi macOS

## CLAUDE.md & Prompt Awal

Simpan blok pertama sebagai `CLAUDE.md` di root repo, supaya setiap sesi Claude Code mulai dengan konteks dan aturan yang sama.

```markdown
# TouchFeel

macOS menu bar app + engine yang membuat touchscreen laptop non-Apple terasa seperti touch asli,
bukan mouse. Target awal: ThinkPad L390 (Hackintosh, VoodooI2C), macOS 13 sampai 26.
Perangkat dev: macOS Sequoia 15.

## Sumber kebenaran
Spec lengkap ada di dokumen plan proyek (bagian Keputusan Desain D1-D9, Spesifikasi Input,
Kontrak Core, Spesifikasi Output, Config, Task Breakdown). Jangan menyimpang dari keputusan
desain tanpa diskusi. Kalau menemukan fakta yang bertentangan dengan spec, berhenti dan laporkan.

## Aturan arsitektur
- TouchCore dan Recognizer: hanya Foundation. Dilarang import IOKit, CoreGraphics, AppKit.
- Recognizer tidak memegang timer. Waktu masuk lewat Clock yang di-inject dan tick().
- Hanya EventOutput yang boleh memposting CGEvent. Hanya HIDInput yang menyentuh IOKit.
- Fitur private API ada di balik feature flag dan default mati.

## Aturan kode
- Swift 5.9+, strict concurrency, tidak ada force unwrap di kode produksi.
- Hot path (HID callback sampai event diposting): tanpa alokasi per frame, tanpa log info.
- Semua angka tuning ada di RecognizerConfig, bukan hardcode.
- Error handling eksplisit: device hilang, izin hilang, config invalid tidak boleh crash
  dan tidak boleh meninggalkan tombol mouse nyangkut.
- Konstanta CoreGraphics (scroll phase dsb) diverifikasi dari header SDK, bukan dari ingatan.

## Testing
- swift test harus hijau sebelum tugas dianggap selesai.
- Setiap baris tabel transisi state punya unit test. Tiga invarian wajib dites.
- Replay test memakai fixture JSON Lines di Tests/Fixtures.

## Batasan lingkungan
- Claude Code TIDAK punya akses ke touchscreen. Apa pun yang butuh hardware (touchlog,
  tes gesture nyata, izin TCC) dijalankan Ghani, hasilnya ditempel kembali ke sesi.
- Jangan ubah signing identity atau bundle ID tanpa bilang, karena izin TCC akan reset.

## Perintah
- Build: swift build
- Test: swift test
- Log live: log stream --predicate 'subsystem == "com.touchfeel"'
```

Prompt pembuka sesi pertama:

```text
Baca CLAUDE.md dan dokumen plan. Kerjakan Fase 0 saja dari Task Breakdown.
Mulai dengan scaffold Swift Package dan unit test kosong yang lolos, lalu bangun touchlog
bertahap sesuai checklist. Setelah tiap sub-task, jalankan swift build dan swift test.
Jangan menulis Recognizer atau EventOutput dulu. Di akhir, beri aku daftar perintah persis
yang harus kujalankan di L390 dan format output yang kamu butuhkan kembali dari aku.
```

## Pembagian Kerja

Claude Code tidak punya touchscreen L390. Alurnya: Claude Code menulis dan menguji logika, Ghani menjalankan di hardware lalu menempel hasilnya balik.

| Pekerjaan | Siapa | Cara serah-terima |
| --- | --- | --- |
| Scaffold, parser, recognizer, output, unit test | Claude Code | Commit di repo, `swift test` hijau |
| Menjalankan `touchlog` di L390 | Ghani | Tempel output ke sesi, atau commit file rekaman ke `Tests/Fixtures` |
| Merekam sesi sentuhan (tap, drag, scroll, palm) | Ghani | File `.jsonl` dari `touchlog --record` |
| Menentukan jalur A, B, atau C | Ghani + Claude Code | Claude Code menganalisis output probe, Ghani mengonfirmasi |
| Memberi izin Accessibility dan Input Monitoring | Ghani | Manual di System Settings, ulang tiap ganti signing identity |
| Tuning angka threshold | Ghani + Claude Code | Ghani melaporkan gejala, Claude Code menyesuaikan config atau recognizer, replay test sebagai penjaga regresi |
| Tes regresi di Ventura, Sonoma, Tahoe | Ghani | Checklist per versi, hasil ditempel ke sesi |
| Setup volume multi-boot dan konfigurasi kext | Ghani | Di luar repo |

**Aturan kerja yang disarankan**

- Satu fase per sesi, satu commit per sub-task, supaya gampang di-revert.
- Tiap kali Ghani melaporkan bug "rasanya aneh", minta rekaman sesi dulu. Bug yang bisa diputar ulang bisa dijadikan tes, bug yang hanya dirasakan akan muncul lagi.
- Kalau Fase 0 memilih jalur C, hentikan sesi coding dan revisi plan sebelum lanjut, karena scope proyek berubah.

## Sources

- [AppleInsider: OpenCore and Hackintosh after Apple ends Intel Mac support](https://appleinsider.com/articles/25/06/17/opencore-and-hackintosh-are-sadly-dead-after-apple-ends-intel-mac-support)
- [MacGeneration: macOS Tahoe di Mac lama lewat OpenCore Legacy Patcher, 7 Okt 2026](https://www.macg.co/macos/2026/10/macos-tahoe-arrive-enfin-sur-les-vieux-mac-grace-opencore-legacy-patcher-311479)
- [Wiki repo Hackintosh XPS 13 Plus di Tahoe 26.7.1](https://github.com/JulioNectar/Hackintosh-XPS13Plus-IrisXe-Tahoe/wiki)
- [Dortania: panduan macOS 26 Tahoe](https://dortania.github.io/OpenCore-Install-Guide/extras/tahoe.html)

Halaman dicek 12 Nov 2026. Catatan tentang `SMAppService` dan `MenuBarExtra` di Ventura berasal dari pengetahuan umum, bukan dari halaman di atas.
