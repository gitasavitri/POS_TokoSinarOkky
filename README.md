# POS Toko Sinar Okky

Program kasir (POS) untuk toko kecil dengan kantor pusat di toko utama.

| Bagian | Folder | Teknologi |
|---|---|---|
| Aplikasi Toko (kasir, offline) | `app_toko/` | Flutter desktop Windows + SQLite |
| Logika bersama (harga, struk, HPP) | `packages/pos_core/` | Dart |
| Server Pusat | `server/` | Node.js + Express + MySQL |
| Aplikasi Pusat (admin) | `app_pusat/` | Flutter desktop Windows |

Status: **fondasi**. Yang sudah ada:

- `AGENTS.md`: aturan proyek untuk developer dan asisten AI (wajib dibaca).
- `database/schema_toko.sql`: skema SQLite Aplikasi Toko.
- `database/test_schema.py`: uji skema. Jalankan `python database/test_schema.py`.
- `docs/`: desain tampilan (PDF).
- `LANGKAH-VIBE-CODING.md`: urutan pengerjaan dan prompt per fase.
