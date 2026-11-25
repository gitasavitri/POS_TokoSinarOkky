// Membuat kode pendaftaran untuk PC toko baru (berlaku 24 jam, sekali pakai). npm run buat-kode
// Biasanya dibuat dari Aplikasi Pusat; skrip ini untuk saat Aplikasi Pusat belum dipasang.
import { buatKodePendaftaran } from '../src/akun.js';
import { pastikanDatabaseUrl } from '../src/config.js';
import { buatPool } from '../src/db.js';
import { jalankanMigrasi } from '../src/migrasi.js';

const pool = buatPool(pastikanDatabaseUrl());
try {
  await jalankanMigrasi(pool);
  const { kode, kedaluwarsa } = await buatKodePendaftaran(pool, null);
  console.log(`Kode pendaftaran: ${kode}`);
  console.log(`Berlaku sampai  : ${kedaluwarsa} (UTC)`);
  console.log('Masukkan di Aplikasi Toko → Pengaturan → Kirim ke kantor pusat.');
} finally {
  await pool.end();
}
