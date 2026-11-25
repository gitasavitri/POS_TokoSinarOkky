// Menjalankan file sql/NNN_*.sql yang belum pernah dijalankan, berurutan.
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const folderSql = fileURLToPath(new URL('../sql/', import.meta.url));

/** Pecah file SQL menjadi perintah. Semua perintah di file migrasi diakhiri ';' di akhir baris. */
export function pecahSql(isi) {
  return isi
    .split('\n')
    .filter((b) => !b.trim().startsWith('--'))
    .join('\n')
    .split(/;\s*\n/)
    .map((s) => s.trim().replace(/;$/, ''))
    .filter(Boolean);
}

export async function jalankanMigrasi(pool, { cetak = () => {} } = {}) {
  await pool.query(
    'CREATE TABLE IF NOT EXISTS skema_versi (versi INT NOT NULL PRIMARY KEY, nama VARCHAR(200) NOT NULL, dijalankan_pada VARCHAR(25) NOT NULL)',
  );
  const [sudah] = await pool.query('SELECT versi FROM skema_versi');
  const versiSudah = new Set(sudah.map((r) => r.versi));
  const file = readdirSync(folderSql)
    .filter((f) => /^\d{3}_.+\.sql$/.test(f))
    .sort();
  for (const f of file) {
    const versi = Number(f.slice(0, 3));
    if (versiSudah.has(versi)) continue;
    cetak(`Migrasi ${f} ...`);
    // DDL MySQL tidak bisa dibatalkan; kalau gagal di tengah, perbaiki manual lalu jalankan lagi.
    for (const perintah of pecahSql(readFileSync(folderSql + f, 'utf8'))) await pool.query(perintah);
    await pool.query('INSERT INTO skema_versi (versi, nama, dijalankan_pada) VALUES (?,?,?)', [
      versi,
      f,
      new Date().toISOString().replace(/\.\d{3}Z$/, 'Z'),
    ]);
  }
}
