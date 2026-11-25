// Login Admin pusat, sesi, pendaftaran perangkat toko.
import { satu, transaksi } from './db.js';
import { cocokSandi, cocokTotp, hashToken, kodePendaftaran, normalKode, tokenAcak } from './keamanan.js';
import { simpanBaris } from './sinkron.js';
import { GalatPengguna, adalahUuid, buatId, isoUtc, tambahDetik, teks, wajib } from './umum.js';

export const BATAS_SALAH_LOGIN = 5;
export const SESI_DIAM_MENIT = 10; // sama dengan keluar otomatis di aplikasi
export const SESI_MAKS_JAM = 12;
export const KODE_BERLAKU_JAM = 24;

/** Satu pesan untuk semua kegagalan login, supaya tidak membocorkan mana yang salah. */
const PESAN_LOGIN_GAGAL = 'Nama pengguna, kata sandi, atau kode tidak cocok';

export async function masukAdmin(pool, { nama_pengguna, sandi, kode }, sekarang = new Date()) {
  wajib(typeof nama_pengguna === 'string' && typeof sandi === 'string', PESAN_LOGIN_GAGAL, 401);
  const p = await satu(
    pool,
    "SELECT * FROM pengguna WHERE nama_pengguna = ? AND cabang_id IS NULL AND peran = 'admin'",
    [nama_pengguna.trim()],
  );
  if (!p || !p.aktif) throw new GalatPengguna(PESAN_LOGIN_GAGAL, 401);
  if (p.terkunci) throw new GalatPengguna('Akun terkunci karena salah masuk 5 kali. Buka dengan perintah buka-kunci di server.', 423);

  const cocok = (await cocokSandi(sandi, p.sandi_hash)) && !!p.totp_secret && cocokTotp(p.totp_secret, kode, sekarang);
  const t = isoUtc(sekarang);
  if (!cocok) {
    const salah = p.gagal_login + 1;
    await pool.query('UPDATE pengguna SET gagal_login = ?, terkunci = ?, updated_at = ? WHERE id = ?', [
      salah,
      salah >= BATAS_SALAH_LOGIN ? 1 : 0,
      t,
      p.id,
    ]);
    await catatLog(pool, { penggunaId: p.id, aksi: salah >= BATAS_SALAH_LOGIN ? 'akun_terkunci' : 'login_gagal', detail: { percobaan: salah } });
    if (salah >= BATAS_SALAH_LOGIN) throw new GalatPengguna('Salah 5 kali. Akun dikunci.', 423);
    throw new GalatPengguna(PESAN_LOGIN_GAGAL, 401);
  }

  const token = tokenAcak();
  await pool.query('UPDATE pengguna SET gagal_login = 0 WHERE id = ?', [p.id]);
  await pool.query(
    'INSERT INTO sesi_admin (token_hash, pengguna_id, dibuat_pada, terakhir_dipakai, berakhir_pada) VALUES (?,?,?,?,?)',
    [hashToken(token), p.id, t, t, isoUtc(tambahDetik(sekarang, SESI_MAKS_JAM * 3600))],
  );
  await catatLog(pool, { penggunaId: p.id, aksi: 'login_pusat' });
  return { token, pengguna: { id: p.id, nama: p.nama, nama_pengguna: p.nama_pengguna } };
}

export async function cekSesi(pool, token, sekarang = new Date()) {
  if (!token) return null;
  const h = hashToken(token);
  const s = await satu(
    pool,
    'SELECT s.*, p.nama, p.aktif FROM sesi_admin s JOIN pengguna p ON p.id = s.pengguna_id WHERE s.token_hash = ?',
    [h],
  );
  if (!s || !s.aktif) return null;
  const t = isoUtc(sekarang);
  if (s.berakhir_pada <= t || s.terakhir_dipakai <= isoUtc(tambahDetik(sekarang, -SESI_DIAM_MENIT * 60))) {
    await pool.query('DELETE FROM sesi_admin WHERE token_hash = ?', [h]);
    return null;
  }
  await pool.query('UPDATE sesi_admin SET terakhir_dipakai = ? WHERE token_hash = ?', [t, h]);
  return { id: s.pengguna_id, nama: s.nama };
}

export async function keluarAdmin(pool, token) {
  if (token) await pool.query('DELETE FROM sesi_admin WHERE token_hash = ?', [hashToken(token)]);
}

export async function cekPerangkat(pool, token) {
  if (!token) return null;
  return satu(pool, 'SELECT id, cabang_id, nama FROM perangkat WHERE token_hash = ? AND aktif = 1', [hashToken(token)]);
}

// ------------------------------------------------------------------ pendaftaran perangkat

export async function buatKodePendaftaran(pool, olehId, sekarang = new Date()) {
  const kode = kodePendaftaran();
  const kedaluwarsa = isoUtc(tambahDetik(sekarang, KODE_BERLAKU_JAM * 3600));
  await pool.query('INSERT INTO kode_pendaftaran (kode_hash, dibuat_oleh, dibuat_pada, kedaluwarsa) VALUES (?,?,?,?)', [
    hashToken(normalKode(kode)),
    olehId,
    isoUtc(sekarang),
    kedaluwarsa,
  ]);
  if (olehId) await catatLog(pool, { penggunaId: olehId, aksi: 'buat_kode_pendaftaran', detail: { kedaluwarsa } });
  return { kode, kedaluwarsa };
}

/**
 * PC toko mendaftar dengan kode sekali pakai + data cabangnya. Kalau cabang sudah pernah terdaftar
 * (mis. PC diganti), perangkat lama otomatis dinonaktifkan.
 */
export async function daftarPerangkat(pool, { kode, nama_perangkat, cabang }, sekarang = new Date()) {
  wajib(cabang && typeof cabang === 'object', 'Data cabang wajib dikirim');
  wajib(adalahUuid(cabang.id), 'Id cabang tidak valid');
  const namaPerangkat = teks(nama_perangkat ?? 'PC kasir', 'Nama perangkat', { max: 100 });
  const t = isoUtc(sekarang);
  return transaksi(pool, async (kon) => {
    const k = await satu(kon, 'SELECT * FROM kode_pendaftaran WHERE kode_hash = ? FOR UPDATE', [hashToken(normalKode(kode))]);
    if (!k || k.dipakai_pada || k.kedaluwarsa <= t) throw new GalatPengguna('Kode pendaftaran salah, sudah dipakai, atau kedaluwarsa', 403);

    const kodeSama = await satu(kon, 'SELECT id FROM cabang WHERE kode = ? AND id <> ?', [String(cabang.kode ?? '').toUpperCase(), cabang.id]);
    if (kodeSama) throw new GalatPengguna(`Kode cabang ${cabang.kode} sudah dipakai toko lain. Pakai kode lain.`, 409);

    const perangkat = { id: buatId(), cabang_id: cabang.id };
    await kon.query('UPDATE perangkat SET aktif = 0 WHERE cabang_id = ?', [cabang.id]);
    const token = tokenAcak();
    await kon.query('INSERT INTO perangkat (id, cabang_id, nama, token_hash, terdaftar_pada) VALUES (?,?,?,?,?)', [
      perangkat.id,
      cabang.id,
      namaPerangkat,
      hashToken(token),
      t,
    ]);
    await simpanBaris(kon, perangkat, 'cabang', cabang);
    await kon.query('UPDATE kode_pendaftaran SET dipakai_pada = ?, perangkat_id = ? WHERE kode_hash = ?', [t, perangkat.id, k.kode_hash]);
    await catatLog(kon, { cabangId: cabang.id, penggunaId: k.dibuat_oleh, aksi: 'perangkat_terdaftar', detail: { perangkat: namaPerangkat } });
    return { perangkat_id: perangkat.id, token };
  });
}

/** Log aktivitas di server (aksi Admin pusat). Jangan pernah memasukkan sandi/kode ke detail. */
export async function catatLog(kon, { cabangId = null, penggunaId = null, aksi, detail = {} }) {
  await kon.query('INSERT INTO log_aktivitas (id, cabang_id, pengguna_id, aksi, detail, created_at) VALUES (?,?,?,?,?,?)', [
    buatId(),
    cabangId,
    penggunaId,
    aksi,
    JSON.stringify(detail),
    isoUtc(),
  ]);
}
