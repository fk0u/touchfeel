# Fase 0: temuan di L390 (Sequoia 15.8.2)

## Kext
- VoodooI2C 2.9.1, VoodooI2CHID, VoodooI2CServices, VoodooGPIO 1.1 (CannonLakeLP), VoodooInput 1.1.7
- VoodooPS2 2.3.8 (keyboard, trackpad, mouse)

## Mode interrupt
- Device I2C: `"Interrupt Mode" = "Polling"`
- boot-args berisi `-vi2c-force-polling`, jadi polling dipaksa, bukan karena GPIO gagal.
- Risiko latency di plan berlaku. Coba hapus flag dan cek apakah GPIO interrupt jalan sebelum tuning latency.

## Panel
- `2386:3118`, I2C, Digitizer/Touch Screen. Dump lengkap: `touchlog-dump.txt`
- 10 slot Finger: Tip Switch, Contact ID 0..31, X 0..1920, Y 0..1080
- Scan Time 32 bit (+90 per ~10 ms), Contact Count 0..10
- **Tidak ada Width/Height** → palm rejection berbasis luas tidak bisa. Perlu revisi spec.
- Laju report ~100 Hz.

## Jalur input
- Jalur A: raw touch terbaca tanpa seize (`--watch --raw`).
- IOKit hanya mengirim nilai yang berubah; assembler menyimpan state slot antar frame.
- Probe seize (jalur B): belum valid, layar tidak disentuh saat tes. Ulangi.
