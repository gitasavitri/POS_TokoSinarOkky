# Server Pusat

Menerima data penjualan, stok, dan log dari semua toko; mengirim data barang, harga pusat, dan info cabang ke toko.
Dipakai juga oleh Aplikasi Pusat (laporan gabungan, harga semua toko).

**Toko tetap bisa berjualan walau server mati atau internet putus.** Data menunggu di PC toko (tabel `outbox`)
dan terkirim otomatis begitu tersambung lagi.

## Kebutuhan

| | Versi | Catatan |
|---|---|---|
| Node.js | 20 atau lebih baru | |
| MySQL | 8.0+ (atau MariaDB 10.6+) | Test dijalankan di MariaDB 10.11 |
| Caddy atau Nginx | | Untuk HTTPS. Aplikasi Toko menolak alamat `http://` |

Paket npm: `express` (rute HTTP), `mysql2` (koneksi MySQL), `hash-wasm` (Argon2id, sama dengan hash di aplikasi Flutter, tanpa kompilasi native).

## Pasang di VPS (ringkas)

```bash
# 1. Database
sudo mysql -e "CREATE DATABASE pos_pusat CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
  CREATE USER 'pos'@'localhost' IDENTIFIED BY 'SANDI-PANJANG-ACAK';
  GRANT ALL ON pos_pusat.* TO 'pos'@'localhost';"
# Membuat TRIGGER saat binary log aktif (bawaan MySQL 8) butuh ini, sekali saja:
sudo mysql -e "SET GLOBAL log_bin_trust_function_creators = 1;"

# 2. Program
cd server
npm ci --omit=dev
cp .env.contoh .env        # lalu isi DATABASE_URL
npm run migrasi            # membuat tabel
npm run buat-admin         # akun Admin pusat + kode TOTP untuk HP

# 3. Jalankan terus (contoh dengan systemd, lihat di bawah), lalu HTTPS dengan Caddy:
#    pos.tokoanda.com {
#        reverse_proxy 127.0.0.1:3000
#    }
```

Contoh `/etc/systemd/system/pos-server.service`:

```ini
[Service]
WorkingDirectory=/opt/pos/server
ExecStart=/usr/bin/node src/server.js
Restart=always
User=pos
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
```

## Menyambungkan PC toko

1. Admin pusat membuat kode pendaftaran (Aplikasi Pusat → Perangkat, atau `npm run buat-kode` di VPS).
   Kode berlaku 24 jam dan hanya bisa dipakai sekali.
2. Di PC toko, Admin toko membuka **Pengaturan → Kirim data ke kantor pusat**, lalu mengisi alamat server dan kode.
3. Sejak itu data dikirim tiap menit. PC yang hilang/diganti bisa dicabut dari Aplikasi Pusat.

## Cara kerja sinkronisasi

- **Toko → pusat**: semua tabel toko, kecuali rahasia TOTP Admin toko (dibuang sebelum dikirim dan diabaikan server).
  Server menolak data yang bukan milik cabang perangkat pengirim, dan menolak harga "semua toko" dari PC toko.
  Kiriman ulang aman (id outbox dicatat di `sinkron_diterima`).
- **Pusat → toko**: `barang`, `kategori`, `harga_jual` + `harga_grosir` (harga pusat dan harga khusus toko itu),
  `barang_cabang` toko itu, akun Admin pusat (tanpa sandi/TOTP, tidak bisa dipakai masuk di toko), dan info cabang.
  Perubahan baru dikirim setelah berumur 30 detik supaya tidak ada yang terlewat.
- Data riwayat (transaksi, stok, harga, log) di server juga tidak bisa diubah/dihapus (trigger, `sql/002_kunci_riwayat.sql`).

**Batasan yang perlu diketahui**

- Dua toko yang sama-sama membuat barang baru dengan barcode sama **saat offline** akan menghasilkan dua barang di pusat.
  Daftarnya ada di `GET /api/pusat/barang-ganda`; toko yang menerima barang kembar mendapat pesan "Perlu dicek".
- Data barang (nama/kategori/satuan) yang diubah di toko lewat barang masuk ikut berubah di pusat (versi terbaru menang).

## Test

```bash
npm test   # butuh MySQL/MariaDB; atur DB_UJI_URL=mysql://user:sandi@127.0.0.1:3306 (tanpa nama database)
```

Tanpa MySQL, test yang butuh database dilewati dan hanya test logika yang jalan.

Uji ujung-ke-ujung dengan Aplikasi Toko: jalankan server dengan `SINKRON_JEDA_DETIK=0`, buat dua kode, lalu
`POS_SERVER_UJI=http://127.0.0.1:3000 POS_KODE_UJI=KODE1,KODE2 flutter test test/sinkron_test.dart` di `app_toko`.

## API

| Metode | Alamat | Untuk |
|---|---|---|
| GET | `/api/sehat` | cek server hidup |
| POST | `/api/perangkat/daftar` | PC toko mendaftar `{kode, nama_perangkat, cabang}` → `{perangkat_id, token}` |
| POST | `/api/sinkron/kirim` | PC toko kirim outbox `{item: [...]}` (maks. 500) → `{diterima, ditolak}` |
| GET | `/api/sinkron/ambil?sejak=N` | PC toko ambil perubahan → `{perubahan, kursor, masih_ada}` |
| POST | `/api/pusat/masuk` | Admin pusat `{nama_pengguna, sandi, kode}` → `{token}` (sesi habis 10 menit tidak dipakai) |
| GET | `/api/pusat/ringkasan`, `/penjualan-harian`, `/terlaris`, `/transaksi`, `/log` | laporan; wajib `dari` & `sampai` (ISO UTC), opsional `cabang_id` |
| GET | `/api/pusat/cabang`, `/perangkat`, `/karyawan`, `/stok?cabang_id=`, `/barang`, `/kategori`, `/barang-ganda` | data |
| POST | `/api/pusat/harga` | harga baru untuk semua toko `{barang_id, harga, grosir: [{min_qty, harga}], alasan}` |
| POST | `/api/pusat/barang`, `/kategori`, `/barang-cabang`, `/kode-pendaftaran`, `/perangkat/:id/cabut` | kelola |

Semua `/api/pusat/*` (kecuali `masuk`) dan `/api/sinkron/*` memakai header `Authorization: Bearer <token>`.
