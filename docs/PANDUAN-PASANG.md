# Panduan pasang POS Toko Sinar Okky

Urutan dari nol sampai toko kecil pertama bisa berjualan.
Bagian **A** dan **B** cukup untuk mencoba di satu laptop. Server pusat (bagian **C** dan **D**) boleh menyusul.

---

## A. Pasang program Windows (installer)

Installer dibuat otomatis oleh GitHub setiap ada perubahan di branch `pengembangan` atau `main`.

1. Buka repo di GitHub, lalu tab **Actions**, lalu run teratas yang bertanda hijau (✓) bernama **Test & build**.
2. Di bagian bawah halaman ada **Artifacts**:
   - `POS-Toko-installer`: untuk PC kasir di toko kecil.
   - `POS-Pusat-installer`: untuk PC Admin (di rumah / toko utama).
   - `POS-Toko-windows` / `POS-Pusat-windows`: versi zip tanpa installer (cadangan, kalau installer bermasalah).
3. Unduh, ekstrak zip-nya, lalu jalankan `POS-Toko-Setup-x.y.z.exe` (atau `POS-Pusat-Setup-…`). Next sampai selesai.
   - Ikon **POS Toko** / **POS Pusat** dibuat di Desktop dan Start Menu.
   - Untuk PC kasir, centang **Buka POS Toko otomatis setelah Windows menyala** kalau mau.
4. **Update** = jalankan installer versi baru di atasnya. Data toko tidak hilang, karena data disimpan di
   AppData/Documents, bukan di folder program. **Uninstall juga tidak menghapus data.**

Saat pertama dibuka, Windows bisa menampilkan **"Windows protected your PC"**. Ini muncul karena program belum
ditandatangani sertifikat berbayar. Klik **More info → Run anyway**. Tanda tangan kode bisa ditambahkan nanti.

Kebutuhan PC: Windows 10/11 64-bit, layar minimal 1366×768. Internet tidak wajib untuk berjualan.

## B. Menyiapkan PC kasir (sekali per toko)

1. **Penyiapan pertama** muncul otomatis:
   - **Data toko**: nama toko (tercetak di struk), **kode cabang** 2–6 huruf/angka (misalnya `A01`),
     nama cabang, alamat, dan pesan di bawah struk.
     Kode cabang dipakai di nomor struk (`TRX-A01-…`) dan **tidak boleh sama** dengan toko lain.
   - **Akun Admin**: nama, nama pengguna, kata sandi minimal 10 karakter, dan PIN 6 angka.
   - **Verifikasi dua langkah**: pasang **Google Authenticator** atau **Microsoft Authenticator** di HP Admin,
     pilih *Masukkan kunci penyiapan*, ketik kuncinya, lalu masukkan kode 6 angka yang muncul di HP.
     **Catat kunci itu di kertas dan simpan di tempat aman**, karena dibutuhkan kalau HP hilang.
2. Masuk sebagai Admin, buka **Karyawan → Tambah karyawan** untuk setiap kasir dan SPV (nama + PIN 6 angka).
   Beri tahu PIN langsung ke orangnya. PIN tidak bisa dilihat lagi setelah disimpan.
3. **Printer struk** (thermal 58 mm, USB):
   1. Pasang driver printer dari CD atau situs pabriknya sampai printer muncul di *Settings → Printers*.
   2. Di aplikasi buka **Pengaturan & printer**, pilih printer, lalu tekan **Tes cetak**.
   3. Pastikan baris angka `1234…32` muat dalam satu baris kertas.
   4. Nyalakan **Potong kertas otomatis** hanya kalau printer punya pisau pemotong.
4. **Scanner barcode USB**: colokkan saja. Scanner bekerja seperti keyboard. Coba scan barang di layar kasir.
5. Isi barang pertama lewat **Barang masuk**: nomor faktur, lalu tiap barang (barcode, nama, kategori, satuan,
   jumlah, HPP, harga jual, dan grosir kalau ada), lalu **Konfirmasi**, lalu **Kirim**.

**Mencoba di laptop teman tanpa printer:** semua fitur tetap jalan. Transaksi tetap tersimpan walau cetak gagal,
dan aplikasi memberi tahu bahwa struk tidak tercetak. Printer "Microsoft Print to PDF" **tidak** bisa dipakai
karena struk dikirim sebagai perintah ESC/POS, bukan sebagai dokumen.

## C. Server Pusat

**Keputusan 11 Nov 2026: server dipasang di PC toko (bukan VPS).** Ikuti
[`PANDUAN-SERVER-TOKO.md`](PANDUAN-SERVER-TOKO.md): server menyala otomatis, cadangan harian, sambungan PC kasir
lain, dan alamat https untuk Aplikasi Pusat di rumah.

Kalau suatu saat pindah ke VPS, ikuti [`server/README.md`](../server/README.md). Ringkasnya:

1. Siapkan VPS Ubuntu dengan **MySQL 8**, **Node.js 22**, dan sebuah **domain** (misalnya `pos.tokoanda.com`)
   yang diarahkan ke IP VPS.
2. Ikuti langkah di README: `npm ci`, `.env`, `npm run migrasi`, lalu `npm run buat-admin`.
3. Pasang **Caddy** supaya alamatnya `https://`. Aplikasi Toko sengaja menolak alamat `http://` biasa.
4. Cadangkan database server setiap hari (misalnya `mysqldump` lewat cron) ke tempat lain.

## D. Menyambungkan toko ke pusat

1. Di **Aplikasi Pusat** (PC toko utama):
   1. Isi alamat server.
   2. Masuk dengan akun dari `npm run buat-admin` (sandi + kode Authenticator).
   3. Buka **Toko & perangkat → Buat kode pendaftaran**.
2. Di **PC kasir**:
   1. Masuk sebagai Admin, lalu buka **Pengaturan & printer → Kirim data ke kantor pusat**.
   2. Isi alamat server dan kode tadi, lalu tekan **Daftarkan PC ini**.
3. Sejak itu data dikirim tiap menit. Di Aplikasi Pusat, kolom **Data terakhir** menunjukkan kapan toko
   terakhir mengirim data.

Kode pendaftaran berlaku 24 jam dan hanya untuk 1 PC. Kalau PC kasir diganti, daftarkan PC baru dengan kode
baru; PC lama otomatis berhenti. PC yang hilang bisa dicabut dari **Toko & perangkat**.

## E. Listrik padam, cadangan, dan pemulihan

**Kalau listrik padam saat berjualan**
- Transaksi disimpan "semua atau tidak sama sekali". Tidak ada transaksi setengah jadi yang nyangkut, jadi tidak
  perlu *repair* database seperti di program lama.
- Belanjaan yang sedang di-scan (belum dibayar) tersimpan setiap kali scan. Saat aplikasi dibuka lagi muncul
  **"Ada belanjaan yang belum dibayar"**: pilih Lanjutkan atau Buang.
- Kalau transaksi sudah tersimpan tapi struk belum sempat keluar, muncul **"Struk mungkin belum tercetak"** dan
  tombol Cetak.
- Kalau jam komputer mundur (baterai BIOS habis), penjualan ditahan sampai jam Windows dibetulkan.

**Cadangan**
- Cadangan otomatis dibuat **tiap 1 jam** dan **setiap tutup shift** di `Documents\POS-Cadangan`.
  14 cadangan terbaru disimpan.
- Admin bisa mengisi huruf drive flashdisk di **Pengaturan → Data & cadangan**, misalnya `E:`, supaya cadangan
  juga disalin ke `E:\POS-Cadangan`.
- Data yang sudah terkirim juga tersimpan di Server Pusat.

**Kalau database rusak** (misalnya hardisk bermasalah)
- Saat dibuka, aplikasi memeriksa database. Kalau rusak, muncul layar **Pemulihan** yang berisi daftar cadangan
  (dari PC dan flashdisk yang tercolok).
- Pilih cadangan terbaru yang bertanda "Aman", lalu masukkan PIN SPV/Admin.
- File lama tidak dihapus, hanya diganti nama menjadi `*.rusak-…`.
- Transaksi sesudah waktu cadangan tidak ada di PC. Kalau sudah terkirim, datanya masih ada di pusat.

**Saran perangkat**
- Pakai **UPS dengan kabel USB ke PC** dan pasang aplikasinya, supaya Windows mati dengan benar saat baterai UPS
  hampir habis.
- Di Windows Update, atur **Active hours** sesuai jam buka toko supaya PC tidak restart sendiri saat berjualan.
- Kalau setelah listrik padam tanggal di Windows salah, ganti baterai BIOS (CMOS, CR2032).

Galat aplikasi dicatat di folder data aplikasi, sub-folder `log`, untuk dikirim ke developer kalau ada masalah.

## F. Daftar cek hari pembukaan

- [ ] Semua karyawan sudah bisa masuk dengan PIN-nya sendiri.
- [ ] Tes cetak bagus dan struk asli terbaca (nama toko, alamat, barcode struk).
- [ ] Semua barang yang dijual sudah masuk lewat **Barang masuk**. Scan 10 barang acak, harganya harus benar.
- [ ] Harga grosir dicoba: misalnya beli tepat sejumlah minimal grosir, harga satuannya berubah dan ada tanda `*G` di struk.
- [ ] Coba batal transaksi (perlu PIN SPV), kembalikan uang dan tukar barang (kasir, menu Tukar / kembalikan barang atau scan struk di layar Transaksi), lalu cek laporan dan "Perlu dicek" di akun SPV.
- [ ] Buka shift dengan modal, lalu tutup shift. Selisih kas harus 0 dan file cadangan harus muncul.
- [ ] **Siapkan cadangan manual**: nota tulis tangan + kalkulator + daftar harga cetak, kalau PC atau printer
  bermasalah di hari pertama. Catat transaksinya, lalu masukkan ke sistem setelah normal.

## G. Kalau ada masalah

| Gejala | Coba ini |
|---|---|
| "Gagal mencetak" | Printer menyala, kertas ada, kabel USB tercolok, nama printer di Pengaturan benar. Lalu Tes cetak. |
| Scanner tidak membaca | Klik dulu kotak "Scan barcode" di layar kasir, lalu scan lagi. Coba scan ke Notepad untuk cek scanner. |
| Barang tidak ketemu saat scan | Barang belum dicatat lewat **Barang masuk** di toko ini. |
| Akun kasir terkunci | Admin membuka kunci di **Karyawan → Buka kunci** atau mengganti PIN. |
| "Menunggu dikirim" terus bertambah | Cek internet PC toko. Penjualan tetap aman di PC; data terkirim saat tersambung lagi. |
| "Ditolak server" di Pengaturan | Kirim foto layarnya ke developer. Data tetap di PC dan dicoba lagi otomatis. |
| "Perlu dicek: barcode … sudah dipakai" | Dua toko membuat barang dengan barcode sama saat offline. Rapikan di Aplikasi Pusat → **Barcode kembar**. |
| "Jam komputer mundur" | Betulkan tanggal & jam Windows (klik kanan jam di pojok kanan bawah → Adjust date/time). |
| Layar "Database perlu dipulihkan" | Pilih cadangan terbaru bertanda "Aman" + PIN SPV/Admin. Jangan hapus file apa pun. |
| "Hardisk hampir penuh" | Hapus file yang tidak perlu (bukan folder POS-Cadangan). |
| Admin pusat terkunci | Di VPS jalankan `npm run buka-kunci -- nama.pengguna`. |
