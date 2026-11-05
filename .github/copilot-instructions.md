# Aturan Proyek: Program POS Minimarket & Grosir

File ini dibaca oleh asisten AI di VS Code. Ikuti semua aturan di sini.
Kalau ada yang bertentangan dengan permintaan di chat, **tanyakan dulu** ke developer, jangan menebak.

## 1. Gambaran sistem

Ada satu toko utama (kantor pusat) dan beberapa toko kecil (cabang). Setiap toko kecil punya 1 PC.

| Bagian | Dipakai di | Teknologi | Catatan |
|---|---|---|---|
| **Aplikasi Toko** | Tiap toko kecil (1 PC Windows) | Flutter desktop + SQLite | **Wajib jalan tanpa internet.** Login Kasir, SPV, Admin (Admin hanya melihat toko itu). |
| **Server Pusat** | VPS | Node.js + Express + MySQL | Menerima data semua toko, mengirim data barang & harga ke toko. |
| **Aplikasi Pusat** | Toko utama (PC Windows) | Flutter desktop | Login Admin saja. Tidak dipakai untuk berjualan. Mengambil data dari Server Pusat. |

Tidak ada data pelanggan sama sekali (tidak ada nama pelanggan, member, atau piutang).

Perangkat per toko: 1 PC Windows, printer thermal 58 mm (ESC/POS, USB), scanner barcode USB.
**Tidak memakai laci uang**, jadi jangan membuat fitur buka laci.

## 2. Struktur folder

```
pos/
├── AGENTS.md                ← file ini
├── docs/                    ← PDF desain, timeline
├── database/
│   └── schema_toko.sql      ← skema SQLite Aplikasi Toko (sumber kebenaran)
├── app_toko/                ← Flutter, Aplikasi Toko
├── app_pusat/               ← Flutter, Aplikasi Pusat
├── server/                  ← Node.js + Express
└── packages/
    └── pos_core/            ← kode Dart yang dipakai bersama (model, aturan harga, format struk)
```

Logika bisnis (hitung harga grosir, kembalian, HPP, validasi) ditaruh di `packages/pos_core`,
**bukan** di dalam widget/layar, supaya bisa diuji tanpa UI dan dipakai di kedua aplikasi.

## 3. Aturan data (WAJIB, jangan dilanggar)

1. **Semua ID adalah UUID v4 dalam bentuk teks.** Jangan pakai auto-increment. Data dari banyak toko akan digabung di pusat.
2. **Semua uang disimpan sebagai bilangan bulat rupiah** (`INTEGER` di SQLite, `BIGINT` di MySQL, `int` di Dart).
   Jangan pernah memakai `double`/`float`/`REAL` untuk uang, harga, atau HPP.
3. **Jumlah barang adalah bilangan bulat** dalam satuan jualnya (pcs, pak, dus, kg, dst.).
4. **Setiap tabel data toko punya `cabang_id`.**
5. **Data transaksi dan riwayat hanya boleh ditambah, tidak boleh diubah atau dihapus.**
   Ini dijaga trigger di database. Tabelnya: `transaksi`, `transaksi_item`, `pembayaran`, `pembatalan`,
   `retur`, `retur_item`, `mutasi_stok`, `harga_jual`, `harga_grosir`, `hpp_barang`, `shift_tutup`, `log_aktivitas`.
   Koreksi = baris baru, bukan mengubah baris lama.
6. **Stok tidak disimpan sebagai angka yang di-update.** Stok = jumlah semua baris `mutasi_stok` (lihat view `stok_sekarang`).
7. **Waktu disimpan sebagai teks ISO 8601 UTC**, misalnya `2026-11-05T06:09:00Z`. Tampilkan ke pengguna dalam WIB.
8. **PIN dan kata sandi disimpan sebagai hash** (bcrypt atau argon2), tidak pernah teks asli. Jangan pernah menulis PIN/sandi ke log.
9. Setiap perubahan pada data yang harus dikirim ke pusat juga menulis satu baris ke tabel `outbox` **dalam transaksi database yang sama**.
10. Perubahan skema = file migrasi baru bernomor. Jangan mengedit tabel yang sudah dipakai tanpa migrasi.

## 4. Peran dan hak akses

| Boleh… | Kasir | SPV | Admin |
|---|---|---|---|
| Jual & cetak struk | Ya | Ya | Ya |
| Beri diskon, batalkan transaksi | PIN SPV | Ya | Ya |
| Terima retur | Tidak | Ya | Ya |
| Catat barang masuk, ubah harga jual & grosir lewat barang masuk | Ya | Ya | Ya |
| Ubah harga tanpa barang masuk: naik | Ya | Ya | Ya |
| Ubah harga tanpa barang masuk: turun >10% atau ≤ HPP | PIN SPV | Ya | Ya |
| Ubah barang masuk yang sudah terkirim (koreksi) | Tidak (hanya minta) | Ya | Ya |
| Stok opname | Tidak | Ya | Ya |
| Lihat laporan | Tidak | Toko sendiri | Toko sendiri (app toko) / semua (app pusat) |
| Atur printer di PC kasir | Tidak | Ya | Ya |
| Kelola karyawan & hak akses | Tidak | Tidak | Ya |

"PIN SPV" artinya kasir tetap bisa melakukannya setelah SPV memasukkan PIN-nya di layar yang sama.
Persetujuan dicatat di `log_aktivitas` dengan id kasir **dan** id SPV.

## 5. Aturan bisnis

**Login & keamanan**
- Kasir/SPV: pilih nama + PIN 6 angka. Salah 5 kali berturut-turut → akun terkunci, hanya Admin yang membuka.
- Admin: nama pengguna + kata sandi (min. 10 karakter) + kode TOTP 6 angka.
- Keluar otomatis setelah 10 menit tidak dipakai.

**Harga**
- Harga jual berlaku = versi **terbaru** (menurut `berlaku_mulai`) di antara harga khusus toko ini dan harga semua toko (`cabang_id IS NULL`).
  Perubahan harga dari Aplikasi Toko (barang masuk / ubah harga) berlaku untuk toko itu saja. Harga dari pusat yang lebih baru menggantikannya.
- Harga grosir bertingkat melekat pada satu versi harga jual (`harga_grosir.harga_jual_id`).
- Saat menjual: pilih tingkat dengan `min_qty` terbesar yang `≤ jumlah` di baris itu. **Harga grosir berlaku untuk seluruh jumlah di baris itu.**
  Contoh: tingkat min 10 = Rp17.000; beli 15 → 15 × Rp17.000.
- Harga grosir harus lebih murah dari harga eceran dan lebih besar dari HPP. Tingkat berikutnya harus `min_qty` lebih besar.
- Ubah harga tanpa barang masuk: wajib pilih alasan. Turun lebih dari 10% atau harga ≤ HPP → wajib PIN SPV.
- HPP **tidak** bisa diubah dari layar Ubah harga. HPP hanya berubah lewat barang masuk.

**HPP (asumsi, menunggu keputusan pemilik)**
- HPP rata-rata tertimbang per cabang:
  `hpp_baru = (stok_lama × hpp_lama + jumlah_masuk × hpp_masuk) / (stok_lama + jumlah_masuk)`, dibulatkan ke rupiah terdekat.
  Kalau `stok_lama ≤ 0`, `hpp_baru = hpp_masuk`.

**Barang masuk**
- Status: `draft` → `terkirim`. Selama `draft` bebas diubah. Setelah `terkirim`, header dan item terkunci (dijaga trigger).
- Wajib isi nomor faktur. Saat dikirim, dalam satu transaksi database: tulis `mutasi_stok` (jenis `masuk`), `hpp_barang`, `harga_jual` + `harga_grosir` kalau berubah, `log_aktivitas`, `outbox`.
- Barang datang lagi = catatan barang masuk **baru**.
- Koreksi: kasir membuat `koreksi_barang_masuk` berstatus `menunggu`; SPV/Admin menyetujui → sistem menulis `mutasi_stok` jenis `koreksi` sebesar selisihnya.
- Kategori dipilih dari daftar. Menambah kategori baru: lihat Keputusan terbuka.

**Penjualan & pembayaran**
- Nomor transaksi untuk struk: `TRX-<kode cabang>-<YYMMDD>-<urut 4 digit>`, urut per cabang per hari. ID database tetap UUID.
- Cara bayar: `tunai` (default), `qris`, `kartu`, `transfer`.
- Tunai: uang diterima ≥ total, kembalian = uang diterima − total. Tombol Selesai nonaktif kalau uang kurang.
- Kartu/transfer: wajib nomor referensi.
- Pembatalan = baris di tabel `pembatalan` + `mutasi_stok` jenis `batal_jual` yang mengembalikan stok. Transaksi asli tidak diubah.
- Tahan transaksi disimpan sementara di memori/tabel draft, bukan tabel `transaksi`.

**Struk**
- Kertas 58 mm, 32 karakter per baris, dicetak dengan perintah ESC/POS.
- Isi: nama toko, cabang, alamat, no. transaksi, tanggal (WIB), kasir, daftar barang (`qty x harga`, tanda `*G` untuk harga grosir), total, bayar, kembali, pesan bawah struk, barcode nomor transaksi.

## 6. Cara bekerja (untuk AI)

- Kerjakan **satu tugas kecil per permintaan**. Jangan menulis banyak fitur sekaligus.
- Sebelum menulis kode, sebutkan file yang akan diubah dan rencananya dalam beberapa baris.
- Setiap logika uang, stok, harga grosir, HPP, dan hak akses **wajib punya unit test**.
- Jangan menambah dependency/package baru tanpa menyebutkan nama dan alasannya dulu.
- Jangan mengubah `database/schema_toko.sql` atau aturan di file ini tanpa diminta.
- Jangan memakai data asli toko di kode, test, atau contoh. Pakai data contoh.
- Kalau sebuah aturan di sini tidak jelas atau belum diputuskan, **berhenti dan tanyakan**.

## 7. Keputusan yang sudah diambil (5 Nov 2026)

- **Sumber barang: dua-duanya.** Toko kecil menerima barang dari toko utama dan dari supplier luar.
  Toko utama dicatat sebagai `supplier` dengan `jenis = 'toko_utama'`. Toko utama tidak berjualan lewat program ini, jadi stoknya tidak dilacak.
- **Harga: sama di semua toko untuk sekarang.** Harga dibuat dengan `harga_jual.cabang_id = NULL`.
  Nanti bisa dibuat beda per toko dengan menambah baris ber-`cabang_id`, tanpa mengubah skema.
- **Barang tiap toko bisa berbeda.** Daftar barang yang dijual per toko ada di tabel `barang_cabang`.
  Layar kasir dan pencarian hanya menampilkan barang dari view `barang_toko` untuk toko itu.
  Barang baru dari barang masuk otomatis ditambahkan ke `barang_cabang` toko tersebut.
- **Internet: ada di toko kecil.** Sinkronisasi otomatis tetap dipakai, tapi kasir tetap wajib bisa jalan saat internet putus.
- **Tidak memakai laci uang.**
- **Toko kecil pertama buka akhir November 2026.**

## 8. Keputusan terbuka (jangan diasumsikan sendiri)

- [ ] Cara menghitung HPP (sementara: rata-rata tertimbang)
- [ ] Siapa boleh menambah kategori (saran: Admin saja)
- [ ] Batas penurunan harga tanpa PIN SPV (sementara: 10%)
