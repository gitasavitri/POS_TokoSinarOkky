# Panduan server lokal di PC toko (Windows)

Keputusan 11 Nov 2026: **server memakai PC toko, bukan VPS.** Untuk sementara satu PC dipakai sebagai
**server sekaligus kasir**. 1–2 bulan lagi kasir pindah ke komputer sendiri dan PC ini menjadi server saja.

```
               jaringan toko (kabel/WiFi)                      internet (https, lewat Cloudflare Tunnel)
PC kasir kedua  ─── http://192.168.x.x:3000 ───┐            ┌─── https://pos.namadomain.com ─── Aplikasi Pusat (rumah)
                                               PC SERVER (Node.js + MySQL + Aplikasi Toko)                      └── PC cabang baru
Aplikasi Toko di PC ini ─ http://localhost:3000┘
```

- **Toko tetap bisa berjualan kalau server mati atau internet putus.** Data menunggu di PC kasir dan terkirim
  otomatis setelah tersambung lagi.
- Alamat `http://` hanya diterima untuk `localhost` dan IP jaringan lokal (192.168.x.x, 10.x.x.x, 172.16–31.x.x).
  Dari luar toko wajib `https://`.

---

## 1. Pasang sekali di PC server

**a. Node.js** — unduh versi **LTS** dari nodejs.org, Next sampai selesai.

**b. MySQL 8** — unduh *MySQL Installer for Windows*, pilih **Server only**.
Biarkan pilihan **Configure MySQL Server as a Windows Service** dan **Start at System Startup** tercentang.
Buat sandi `root` dan simpan baik-baik.

Buka **MySQL 8.0 Command Line Client**, masukkan sandi root, lalu tempel (ganti `SANDI-POS`):

```sql
CREATE DATABASE pos_pusat CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'pos'@'localhost' IDENTIFIED BY 'SANDI-POS';
GRANT ALL ON pos_pusat.* TO 'pos'@'localhost';
SET PERSIST log_bin_trust_function_creators = 1;
```

`SET PERSIST` (bukan `SET GLOBAL`) supaya pengaturannya tetap ada setelah PC restart. Ini dibutuhkan setiap kali
ada pembaruan database.

**c. Program server** — unduh repo dari GitHub (branch `pengembangan` → **Code → Download ZIP**),
ekstrak ke folder tetap, misalnya `C:\POS\`. Folder server-nya jadi `C:\POS\server`.

**d. Pasang supaya menyala otomatis**

1. Klik Start, ketik `PowerShell`, klik kanan **Windows PowerShell → Run as administrator**.
2. Jalankan:
   ```
   cd C:\POS\server
   powershell -ExecutionPolicy Bypass -File windows\pasang-server.ps1
   ```
3. Pertama kali, skrip membuat file `.env` lalu membukanya di Notepad. Ubah baris ini, simpan, tutup:
   ```
   DATABASE_URL=mysql://pos:SANDI-POS@127.0.0.1:3306/pos_pusat
   CADANGAN_FOLDER=D:\POS-Cadangan-Server
   ```
   Isi `CADANGAN_FOLDER` dengan disk lain atau flashdisk kalau ada, supaya cadangan tidak ikut hilang kalau
   hardisk utama rusak.
4. Jalankan lagi perintah di langkah 2. Skrip akan:
   - memasang paket server dan membuat tabel database;
   - membuat tugas **POS Server Sinar Okky**: server menyala sendiri setiap PC dinyalakan, **walaupun belum ada
     yang login Windows**, dan dinyalakan ulang otomatis kalau berhenti;
   - membuat tugas **POS Cadangan Server**: cadangan database tiap hari jam 21:30 (kalau PC mati jam segitu,
     cadangan dibuat saat PC menyala berikutnya), 30 cadangan terbaru disimpan;
   - membuka port 3000 di Firewall untuk jaringan **Private** (jaringan toko), bukan untuk jaringan publik;
   - menyalakan server dan menampilkan alamat untuk PC kasir lain.

**e. Akun Admin pusat** (sekali saja):
```
cd C:\POS\server
npm run buat-admin
```
Masukkan **kunci kode HP** ke Google Authenticator saat itu juga. Kunci hanya tampil sekali.

**f. Cek** — restart PC, jangan login dulu sebentar, lalu login dan buka `http://localhost:3000/api/sehat` di
browser. Harus muncul `{"ok":true,...}`. Catatan server ada di `C:\POS\server\log\server.log`.

> Jaringan toko harus berprofil **Private** di Windows (Settings → Network → klik jaringannya → *Private network*).
> Kalau masih *Public*, PC kasir lain tidak bisa tersambung.

## 2. Menyambungkan

### Aplikasi Toko di PC yang sama (sekarang)
1. Aplikasi Pusat (sementara boleh di PC ini juga): alamat `http://localhost:3000`, masuk Admin pusat,
   **Toko & perangkat → Buat kode pendaftaran**.
2. Aplikasi Toko: masuk Admin toko → **Pengaturan & printer → Kirim data ke kantor pusat** → alamat
   `http://localhost:3000` + kode tadi → **Daftarkan PC ini**.

### Kasir pindah ke komputer sendiri (1–2 bulan lagi)
1. **Beri PC server IP tetap**, misalnya `192.168.1.10`: atur *DHCP reservation* di router (paling mudah), atau
   IP manual di Windows. Tanpa ini alamatnya bisa berubah dan PC kasir tidak tersambung.
2. Di komputer kasir baru, pasang **POS-Toko-Setup** (installer).
3. **Pindahkan data kasir**, jangan mulai dari nol (stok, riwayat, dan karyawan ada di database kasir):
   1. Di PC server: tutup Aplikasi Toko, tutup shift dulu.
   2. Salin folder `%APPDATA%\id.sinarokky\POS Toko Sinar Okky\` ke flashdisk.
   3. Di komputer kasir baru: tempel ke lokasi yang sama (buka Aplikasi Toko sekali lalu tutup supaya foldernya
      ada, lalu timpa isinya).
   4. Buka Aplikasi Toko di komputer baru → Admin → **Pengaturan → Kirim data ke kantor pusat → Ganti alamat** →
      `http://192.168.1.10:3000`. Tidak perlu kode pendaftaran baru.
   5. Di PC server: hapus pintasan Aplikasi Toko supaya tidak dipakai berjualan dua tempat.
   **[Perlu dicoba dulu]** Langkah ini belum diuji di dua PC sungguhan. Coba saat toko tutup.

### Aplikasi Pusat di rumah dan cabang baru (lewat internet)
Butuh alamat **https** yang tetap. Caranya dengan **Cloudflare Tunnel** (gratis untuk pemakaian dasar,
**perlu dicek** di situs Cloudflare) + **domain** milik sendiri (biaya tahunan, perlu dicek di penjualnya).

**Uji coba (tanpa domain):** di PC server jalankan `cloudflared tunnel --url http://localhost:3000`.
Muncul alamat `https://….trycloudflare.com`. Alamat ini **berubah setiap kali dijalankan**, jadi hanya untuk tes.

**Tetap (dengan domain):**
1. Beli domain, lalu pindahkan pengaturan DNS-nya ke akun Cloudflare (gratis).
2. Di dashboard Cloudflare: **Networking → Tunnels → Create Tunnel**, beri nama, pilih **Windows**.
3. Salin perintah `cloudflared.exe service install <TOKEN>` yang ditampilkan, jalankan di
   **Command Prompt (Run as administrator)** di PC server. Tunnel sekarang menyala sendiri sebagai layanan Windows.
   **Token itu rahasia**, jangan difoto/dibagikan.
4. Tambahkan *public hostname*/route: misalnya `pos.namadomain.com` → `http://localhost:3000`.
5. Di rumah: Aplikasi Pusat → alamat `https://pos.namadomain.com`.
6. PC cabang baru: daftarkan dengan alamat `https://pos.namadomain.com` + kode pendaftaran baru.
7. PC kasir di toko ini boleh tetap memakai `http://localhost:3000` / `http://192.168.1.10:3000`
   (tetap jalan walau internet toko putus).

Nama menu Cloudflare bisa berubah; kalau tampilannya beda, kirim screenshot.

## 3. Cadangan dan pemulihan server

- Cadangan otomatis: `pos_pusat-YYYYMMDD-HHmm.zip` di `CADANGAN_FOLDER`. Cadangan manual kapan saja:
  ```
  powershell -ExecutionPolicy Bypass -File C:\POS\server\windows\cadangan-server.ps1
  ```
- **Memulihkan** (mis. PC server diganti): pasang MySQL + buat database & user seperti langkah 1b, ekstrak zip
  cadangan, lalu di Command Prompt:
  ```
  "C:\Program Files\MySQL\MySQL Server 8.0\bin\mysql.exe" -u pos -p pos_pusat < pos_pusat-YYYYMMDD-HHmm.sql
  ```
  lalu jalankan `pasang-server.ps1` lagi.
- Data yang masuk ke server **setelah** cadangan terakhir tidak ikut pulih di server (tapi tetap ada di PC kasir
  masing-masing, karena PC kasir menyimpan semua datanya sendiri). Makin sering cadangan, makin sedikit yang hilang.

## 4. Merawat

| Perlu | Caranya |
|---|---|
| Lihat apakah server jalan | Browser: `http://localhost:3000/api/sehat` |
| Lihat catatan galat | `C:\POS\server\log\server.log` |
| Update program server | Ganti isi `C:\POS\server` dengan versi baru (**kecuali** `.env`), lalu jalankan `pasang-server.ps1` lagi |
| Mematikan otomatisnya | `powershell -ExecutionPolicy Bypass -File windows\hapus-server.ps1` (database tidak dihapus) |
| Admin pusat terkunci | `npm run buka-kunci -- nama.pengguna` di folder server |
| Reset total data uji coba | Lihat bagian "Reset" di bawah |

**Reset data uji coba sebelum toko buka** — matikan dulu dengan `hapus-server.ps1`, lalu di MySQL Command Line:
```sql
DROP DATABASE pos_pusat;
CREATE DATABASE pos_pusat CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
```
Jalankan `pasang-server.ps1` dan `npm run buat-admin` lagi, hapus akun lama di Google Authenticator.
Data Aplikasi Toko juga harus direset bersamaan (hapus `%APPDATA%\id.sinarokky\POS Toko Sinar Okky\` dan
`Documents\POS-Cadangan\`), karena PC kasir masih membawa "kunci" untuk server lama.

## 5. Risiko yang perlu diingat

- **Selama satu PC jadi server + kasir, PC itu titik lemah.** Kalau mati, kasir tetap jalan setelah PC menyala
  lagi (offline), tapi Aplikasi Pusat di rumah tidak bisa melihat data sampai PC menyala. Pakai **UPS**.
- **Hardisk rusak = server hilang**, kecuali ada cadangan di disk lain/flashdisk. Isi `CADANGAN_FOLDER` ke disk lain
  dan sesekali salin cadangan ke tempat lain (Google Drive, HP).
- Jangan matikan PC dengan mencabut listrik. Pakai Shut down.
