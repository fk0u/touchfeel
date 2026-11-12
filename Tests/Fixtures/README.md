# Fixtures

Rekaman dari `touchlog --record nama.jsonl`. Satu `TouchFrame` per baris:

```json
{"contacts":[{"height":0.02,"id":1,"isTouching":true,"width":0.01,"x":0.25,"y":0.5}],"timestampNs":123456789}
```

- `x`, `y`, `width`, `height`: 0...1, origin kiri atas. `width`/`height` tidak ditulis kalau panel tidak mengeksposnya.
- `isTouching: false` muncul sekali saat jari diangkat.
- Penamaan: `<gesture>-<n>.jsonl`, mis. `tap-1.jsonl`, `drag-1.jsonl`, `scroll-1.jsonl`, `palm-1.jsonl`.

Semua `.jsonl` di sini otomatis divalidasi oleh `swift test`.
