// Membuka akun Admin pusat yang terkunci karena salah masuk 5 kali. npm run buka-kunci -- nama.pengguna
import { catatLog } from '../src/akun.js';
import { pastikanDatabaseUrl } from '../src/config.js';
import { buatPool, satu } from '../src/db.js';
import { isoUtc } from '../src/umum.js';

const namaPengguna = process.argv[2];
if (!namaPengguna) {
  console.error('Pakai: npm run buka-kunci -- <nama_pengguna>');
  process.exit(1);
}
const pool = buatPool(pastikanDatabaseUrl());
try {
  const p = await satu(pool, "SELECT id FROM pengguna WHERE nama_pengguna = ? AND cabang_id IS NULL AND peran = 'admin'", [namaPengguna]);
  if (!p) throw new Error('Admin pusat tidak ditemukan');
  await pool.query('UPDATE pengguna SET terkunci = 0, gagal_login = 0, updated_at = ? WHERE id = ?', [isoUtc(), p.id]);
  await catatLog(pool, { penggunaId: p.id, aksi: 'buka_kunci_admin_pusat' });
  console.log(`Akun ${namaPengguna} sudah dibuka.`);
} catch (e) {
  console.error(`Gagal: ${e.message}`);
  process.exitCode = 1;
} finally {
  await pool.end();
}
