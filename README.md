# POS Toko Sinar Okky

Program kasir (POS) untuk toko-toko kecil (1 PC kasir per toko), dengan kantor pusat di toko utama.
Kasir tetap bisa berjualan tanpa internet; data dikirim ke pusat begitu tersambung.

| Bagian | Folder | Teknologi | Dipakai di |
|---|---|---|---|
| Aplikasi Toko | `app_toko/` | Flutter Windows + SQLite | PC kasir tiap toko kecil (Kasir, SPV, Admin toko) |
| Aplikasi Pusat | `app_pusat/` | Flutter Windows | PC toko utama (Admin pusat, tidak untuk berjualan) |
| Server Pusat | `server/` | Node.js + Express + MySQL | PC Windows toko (lihat `docs/PANDUAN-SERVER-TOKO.md`) |
| Logika bersama | `packages/pos_core/` | Dart | harga & grosir, HPP, struk ESC/POS, hak akses, keamanan, klien server |
| Tampilan bersama | `packages/pos_ui/` | Flutter | warna, panel, tabel, grafik |

**Mulai dari sini:** [`docs/PANDUAN-PASANG.md`](docs/PANDUAN-PASANG.md), yang berisi cara mengambil file .exe,
menyiapkan PC kasir, printer, server, dan menyambungkan toko ke pusat.

## Status

Semua bagian sudah dibuat dan diuji otomatis. **Belum** dicoba di PC Windows sungguhan dengan printer thermal
dan di VPS sungguhan. Lakukan uji coba di satu toko sebelum dipakai penuh.

| Yang diuji | Jumlah test |
|---|---|
| Skema SQLite (`database/test_schema.py`) | 30 |
| `pos_core` | 54 |
| Aplikasi Toko (data, tampilan tiap layar, sinkronisasi) | 45 |
| Aplikasi Pusat (tampilan tiap layar, login, harga) | 14 |
| Server Pusat (logika + MySQL sungguhan) | 24 |
| Ujung-ke-ujung: Aplikasi Toko & Pusat ⇄ Server asli | jalan di GitHub Actions |

## Untuk developer

- Baca `AGENTS.md` dulu (aturan data dan bisnis, wajib).
- Jalankan test:
  - `pos_core`: `dart test`
  - aplikasi: `flutter test`
  - server: `npm test` (butuh MySQL, lihat `server/README.md`)
- GitHub Actions (`.github/workflows/ci.yml`) menjalankan semua test dengan MySQL 8, lalu membuat zip Windows
  untuk kedua aplikasi.
- `docs/`: desain tampilan (PDF) dan panduan pasang. `LANGKAH-VIBE-CODING.md`: urutan pengerjaan per fase.
