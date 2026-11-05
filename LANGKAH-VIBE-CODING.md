# Langkah Vibe Coding Program POS di VS Code

Vibe coding = kamu menjelaskan apa yang mau dibuat, AI di VS Code menulis kodenya,
lalu **kamu yang menjalankan, mengecek, dan memutuskan** kode itu dipakai atau tidak.

## 1. Persiapan (sekali saja)

1. Pasang: **VS Code**, **Git**, **Flutter SDK**, **Visual Studio 2022** (workload *Desktop development with C++*), **Node.js LTS**, **MySQL**.
2. Pasang extension VS Code: **Flutter**, **Dart**, dan **satu** asisten AI:
   - **Claude Code** (extension VS Code), membaca file `CLAUDE.md`
   - **GitHub Copilot** (Chat / mode agent), membaca file `.github/copilot-instructions.md`
   - Cek paket dan biayanya di situs masing-masing. Mahasiswa kadang dapat akses gratis lewat program pelajar; **perlu dicek**.
3. Buat folder `pos/`, lalu salin isi paket ini ke dalamnya.
4. Supaya AI membaca aturan proyek, salin `AGENTS.md`:
   - untuk Claude Code → salin jadi `CLAUDE.md`
   - untuk Copilot → salin jadi `.github/copilot-instructions.md`
5. Taruh PDF desain dan timeline di `docs/`.
6. Jalankan `git init`, lalu commit pertama.
7. Cek skema database: `python database/test_schema.py` → harus muncul "Semua 27 pengujian lulus."

## 2. Cara kerja setiap hari

1. **Satu prompt = satu tugas kecil.** Satu layar, satu fungsi, atau satu perbaikan.
2. **Minta rencana dulu**: "Sebutkan file yang akan kamu ubah dan rencananya, jangan menulis kode dulu." Setelah setuju, baru minta dikerjakan.
3. **Jalankan dan coba sendiri** setiap selesai. Error? Salin pesan error lengkap ke chat.
4. **Lihat perubahan (diff) sebelum diterima.** Tolak kalau AI mengubah file yang tidak diminta.
5. **Commit Git setiap kali berhasil.** Kalau AI merusak sesuatu, tinggal kembali ke commit terakhir.
6. **Mulai chat baru untuk fitur baru**, supaya AI tidak bingung dengan percakapan lama.
7. Kalau ada keputusan baru (misalnya harga boleh beda per toko), **tulis di `AGENTS.md`**, jangan hanya di chat.

## 3. Bagian yang wajib kamu pahami sendiri

Jangan asal terima kode AI di bagian ini. Baca baris per baris dan pastikan ada test-nya:

- **Uang**: AI sering memakai `double`. Di proyek ini uang **harus** `int` rupiah.
- **Stok dan harga grosir**: hitungan salah = rugi nyata di toko.
- **PIN, sandi, hak akses**: celah di sini = kecurangan kasir.
- **Sinkronisasi**: bagian paling rumit. AI sering membuat kode yang jalan saat internet lancar tapi kehilangan data saat internet putus.
- **Cetak ESC/POS**: AI kadang mengarang fungsi library yang tidak ada. Cek dokumentasi library-nya dan langsung tes ke printer.

## 4. Urutan prompt

Salin prompt di bawah satu per satu. Lanjut ke berikutnya hanya kalau "Selesai kalau…" sudah terpenuhi.

### Fase 0–1: Fondasi

**P1. Struktur proyek**
> Baca AGENTS.md. Buat struktur folder sesuai bagian 2: proyek Flutter desktop Windows `app_toko`, package Dart `packages/pos_core`, dan folder `server`. Jangan buat fitur apa pun dulu. Sebutkan dependency yang kamu usulkan beserta alasannya sebelum menambahkannya.

Selesai kalau: `app_toko` bisa dijalankan dan menampilkan jendela kosong.

**P2. Database lokal**
> Di `app_toko`, buat lapisan database SQLite yang menjalankan `database/schema_toko.sql` saat aplikasi pertama kali dibuka, dengan sistem migrasi bernomor. Database disimpan di folder data aplikasi (AppData), bukan di folder program.

Selesai kalau: file database terbentuk dan semua tabel ada.

**P3. Model & aturan harga**
> Di `packages/pos_core`, buat model Dart untuk barang, harga_jual, harga_grosir, transaksi, transaksi_item, pembayaran. Uang memakai `int`. Buat fungsi `hitungHargaBaris(eceran, tingkatGrosir, qty)` sesuai aturan harga di AGENTS.md bagian 5, dan `hitungKembalian(total, diterima)`. Tulis unit test termasuk kasus beli 9, 10, 15, 50, 60.

Selesai kalau: semua test lulus, dan kamu sudah membaca fungsinya sendiri.

### Fase 2: Penjualan

**P4. Login**
> Buat layar Masuk sesuai desain (pilih nama + PIN 6 angka dengan tombol angka besar). PIN dicek ke `pin_hash`. Salah 5 kali → akun terkunci. Catat login berhasil/gagal ke `log_aktivitas` tanpa menyimpan PIN. Tambahkan data contoh 1 cabang, 1 kasir, 1 SPV untuk pengembangan.

**P5. Layar kasir**
> Buat layar kasir sesuai desain: info toko/tanggal/no. transaksi/kasir di atas, total besar di kanan atas, tabel belanja di tengah, kolom scan + jumlah + tombol di bawah. Scan barcode = input keyboard yang diakhiri Enter. Harga diambil dari view `harga_jual_terkini` dan memakai `hitungHargaBaris`. Belum ada pembayaran.

**P6. Pembayaran & simpan transaksi**
> Buat dialog pembayaran di atas layar kasir: total dan kembalian di atas, dropdown cara bayar (default Tunai), input uang diterima, nomor referensi untuk kartu/transfer. Saat Selesai, simpan dalam SATU transaksi database: transaksi, transaksi_item (dengan hpp_satuan dari `hpp_terkini`), pembayaran, mutasi_stok jenis 'jual', log_aktivitas, outbox.

Selesai kalau: setelah bayar, stok di `stok_sekarang` berkurang, dan kalau aplikasi ditutup paksa di tengah penyimpanan tidak ada data setengah jadi.

**P7. Cetak struk**
> Buat fungsi yang menyusun struk 58 mm (32 karakter per baris) di `pos_core` sebagai teks, dengan unit test. Lalu di `app_toko`, kirim struk itu ke printer lewat perintah ESC/POS. Sebutkan library yang kamu pakai dan tunjukkan dokumentasinya.

Selesai kalau: struk keluar dari printer asli dan baris angka 1–32 muat satu baris.

**P8. Tahan & batalkan**
> Tambahkan tombol Tahan (simpan keranjang sementara) dan Batalkan. Batalkan transaksi yang sudah dibayar butuh PIN SPV, menulis tabel `pembatalan` + `mutasi_stok` jenis 'batal_jual', tanpa mengubah transaksi asli.

### Fase 3: Stok & SPV

**P9. Barang masuk**
> Buat layar barang masuk sesuai desain: daftar barang di kiri, form satu barang di kanan (barcode, nama, kategori dropdown, satuan, jumlah, HPP, harga jual, harga grosir bertingkat opsional). Simpan sebagai `draft`.

**P10. Konfirmasi & kunci**
> Buat halaman konfirmasi (barang baru / data diubah / stok masuk saja, harga lama dicoret → baru). Saat "Kirim & kunci", dalam satu transaksi database: ubah status jadi 'terkirim', tulis mutasi_stok, hpp_barang (rata-rata tertimbang, fungsi di pos_core + test), harga_jual + harga_grosir bila berubah, log_aktivitas, outbox.

**P11. Koreksi, ubah harga, pengaturan printer** (masing-masing satu prompt)

### Fase 4–6

- **Server pusat**: minta skema MySQL yang setara dengan `schema_toko.sql` (UUID, BIGINT untuk uang), lalu API penerima data dari `outbox`. Uji dengan internet diputus-sambung berkali-kali.
- **Aplikasi Pusat**: dashboard, laporan, karyawan, log. Data dari server.
- **Siap dipasang**: installer, update otomatis, backup harian.

## 5. Kalau AI bingung atau kodenya berantakan

- Jangan terus menambal. Kembali ke commit terakhir yang bagus, lalu ulangi dengan prompt yang lebih kecil.
- Tempel bagian AGENTS.md yang relevan ke prompt.
- Tanya "kenapa" sebelum menerima: "Jelaskan kenapa memakai cara ini, dan apa yang terjadi kalau internet putus di tengah proses?"
