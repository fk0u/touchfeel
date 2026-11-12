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
