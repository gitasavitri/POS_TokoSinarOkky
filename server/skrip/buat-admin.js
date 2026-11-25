// Membuat akun Admin pusat (untuk Aplikasi Pusat). Jalankan di VPS: npm run buat-admin
// Kata sandi diketik tanpa tampil di layar. Rahasia TOTP ditampilkan SEKALI untuk dimasukkan ke aplikasi
// Google Authenticator / Microsoft Authenticator di HP Admin.
import { stdin, stdout } from 'node:process';
import { createInterface } from 'node:readline/promises';

import { catatLog } from '../src/akun.js';
import { pastikanDatabaseUrl } from '../src/config.js';
import { buatPool, satu } from '../src/db.js';
import { buatHashSandi, buatRahasiaTotp, periksaSandiBaru, tautanOtpAuth } from '../src/keamanan.js';
import { jalankanMigrasi } from '../src/migrasi.js';
import { buatId, isoUtc } from '../src/umum.js';

async function tanyaRahasia(rl, pertanyaan) {
  // Sembunyikan ketikan: ganti tampilan setiap karakter dengan '*'.
  const tulisAsli = rl._writeToOutput;
  rl._writeToOutput = (s) => stdout.write(s.startsWith(pertanyaan) ? s : '*'.repeat(s.length));
  const jawab = await rl.question(pertanyaan);
  rl._writeToOutput = tulisAsli;
  stdout.write('\n');
  return jawab;
}

const pool = buatPool(pastikanDatabaseUrl());
await jalankanMigrasi(pool);
const rl = createInterface({ input: stdin, output: stdout, terminal: true });
try {
  const nama = (await rl.question('Nama lengkap Admin: ')).trim();
  const namaPengguna = (await rl.question('Nama pengguna (untuk login): ')).trim().toLowerCase();
  if (!nama || !/^[a-z0-9._-]{3,60}$/.test(namaPengguna)) throw new Error('Nama wajib diisi; nama pengguna 3–60 huruf kecil/angka/titik');
  if (await satu(pool, 'SELECT 1 AS ada FROM pengguna WHERE nama_pengguna = ? AND cabang_id IS NULL', [namaPengguna])) {
    throw new Error('Nama pengguna sudah dipakai');
  }
  const sandi = await tanyaRahasia(rl, 'Kata sandi (min. 10 karakter): ');
  const masalah = periksaSandiBaru(sandi);
  if (masalah) throw new Error(masalah);
  if ((await tanyaRahasia(rl, 'Ulangi kata sandi: ')) !== sandi) throw new Error('Kata sandi tidak sama');

  const rahasia = buatRahasiaTotp();
  const id = buatId();
  const t = isoUtc();
  await pool.query(
    "INSERT INTO pengguna (id, cabang_id, nama, nama_pengguna, peran, sandi_hash, totp_secret, created_at, updated_at) VALUES (?, NULL, ?, ?, 'admin', ?, ?, ?, ?)",
    [id, nama, namaPengguna, await buatHashSandi(sandi), rahasia, t, t],
  );
  await pool.query('INSERT INTO perubahan (tabel, baris_id, cabang_id, perangkat_id, created_at) VALUES (?,?,NULL,NULL,?)', ['pengguna', id, t]);
  await catatLog(pool, { penggunaId: id, aksi: 'buat_admin_pusat', detail: { nama_pengguna: namaPengguna } });

  console.log('\nAkun Admin pusat dibuat.');
  console.log('Masukkan kode ini ke aplikasi Authenticator di HP (pilih "Masukkan kunci penyiapan"):');
  console.log(`\n   ${rahasia.match(/.{1,4}/g).join(' ')}\n`);
  console.log(`Atau buka tautan ini di HP: ${tautanOtpAuth(rahasia, namaPengguna)}`);
  console.log('\nKode ini hanya ditampilkan sekarang. Jangan difoto/dikirim lewat chat.');
} catch (e) {
  console.error(`Gagal: ${e.message}`);
  process.exitCode = 1;
} finally {
  rl.close();
  await pool.end();
}
