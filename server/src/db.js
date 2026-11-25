// Koneksi MySQL + pembantu transaksi.
import mysql from 'mysql2/promise';

export function buatPool(url) {
  return mysql.createPool({
    uri: url,
    connectionLimit: 10,
    // Uang = BIGINT. Angka di bawah 2^53 dikembalikan sebagai number biasa; SUM() juga.
    supportBigNumbers: true,
    bigNumberStrings: false,
    decimalNumbers: true,
    dateStrings: true,
    timezone: 'Z',
    charset: 'utf8mb4',
  });
}

/** Jalankan [fn] di dalam satu transaksi database. Gagal = semua dibatalkan. */
export async function transaksi(pool, fn) {
  const kon = await pool.getConnection();
  try {
    await kon.beginTransaction();
    const hasil = await fn(kon);
    await kon.commit();
    return hasil;
  } catch (e) {
    await kon.rollback().catch(() => {});
    throw e;
  } finally {
    kon.release();
  }
}

export async function satu(kon, sql, param = []) {
  const [baris] = await kon.query(sql, param);
  return baris[0] ?? null;
}

export async function pilih(kon, sql, param = []) {
  const [baris] = await kon.query(sql, param);
  return baris;
}

const cacheKolom = new Map();

/** Daftar kolom sebuah tabel (dibaca dari information_schema, disimpan di memori). */
export async function kolomTabel(kon, tabel) {
  if (cacheKolom.has(tabel)) return cacheKolom.get(tabel);
  const baris = await pilih(
    kon,
    'SELECT COLUMN_NAME AS c FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?',
    [tabel],
  );
  const kolom = new Set(baris.map((r) => r.c));
  if (kolom.size === 0) throw new Error(`Tabel ${tabel} tidak ada`);
  cacheKolom.set(tabel, kolom);
  return kolom;
}
