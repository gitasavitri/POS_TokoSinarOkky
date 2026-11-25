// Sinkronisasi toko ⇄ pusat.
//
// KIRIM (toko → pusat): toko mengirim isi tabel outbox-nya. Setiap item diproses di dalam SAVEPOINT,
// jadi satu item yang gagal tidak membatalkan item lain. Id outbox dicatat supaya kiriman ulang aman.
//
// AMBIL (pusat → toko): toko meminta perubahan sesudah `seq` terakhir yang sudah ia terima.
import { kolomTabel, pilih, satu } from './db.js';
import { TABEL, TABEL_TARIK, barisIdDari, kunciDariBarisId } from './tabel.js';
import { adalahUuid, isoUtc, tambahDetik } from './umum.js';

export const MAKS_KIRIM = 500;
export const MAKS_AMBIL = 500;

/** Perubahan yang lebih muda dari ini belum dikirim ke toko, supaya transaksi database yang
 *  belum selesai (seq sudah dipakai tapi belum commit) tidak terlewat. */
export const JEDA_AMAN_DETIK = 30;

// ------------------------------------------------------------------ kirim

/**
 * @param kon koneksi yang SUDAH berada di dalam transaksi
 * @param perangkat {id, cabang_id}
 * @param item [{id, tabel, baris_id, payload, created_at}]
 * @returns {{diterima: string[], ditolak: {id: string, alasan: string}[]}}
 */
export async function terimaKiriman(kon, perangkat, item) {
  const diterima = [];
  const ditolak = [];
  const sekarang = isoUtc();
  for (const [i, it] of item.entries()) {
    const id = it?.id;
    if (!adalahUuid(id)) {
      ditolak.push({ id: String(id ?? `#${i}`), alasan: 'id outbox tidak valid' });
      continue;
    }
    if (await satu(kon, 'SELECT 1 AS ada FROM sinkron_diterima WHERE outbox_id = ?', [id])) {
      diterima.push(id);
      continue;
    }
    await kon.query('SAVEPOINT item');
    try {
      const payload = typeof it.payload === 'string' ? JSON.parse(it.payload) : it.payload;
      await simpanBaris(kon, perangkat, it.tabel, payload);
      await kon.query('INSERT INTO sinkron_diterima (outbox_id, perangkat_id, tabel, diterima_pada) VALUES (?,?,?,?)', [
        id,
        perangkat.id,
        it.tabel,
        sekarang,
      ]);
      await kon.query('RELEASE SAVEPOINT item');
      diterima.push(id);
    } catch (e) {
      await kon.query('ROLLBACK TO SAVEPOINT item');
      ditolak.push({ id, alasan: e.pesanSinkron ?? `galat server: ${e.code ?? e.message}` });
    }
  }
  await kon.query('UPDATE perangkat SET terakhir_sinkron = ? WHERE id = ?', [sekarang, perangkat.id]);
  return { diterima, ditolak };
}

function tolak(pesan) {
  const e = new Error(pesan);
  e.pesanSinkron = pesan;
  return e;
}

async function cabangBaris(kon, def, baris) {
  switch (def.cabang.jenis) {
    case 'diri':
      return baris.id;
    case 'kolom':
      return baris.cabang_id ?? null;
    case 'global':
      return undefined;
    case 'induk': {
      const r = await satu(kon, def.cabang.sql, [baris[def.cabang.kolom]]);
      if (!r) throw tolak(`data induk belum ada (${def.cabang.kolom})`);
      return r.cabang_id ?? null;
    }
    default:
      throw new Error('jenis cabang tidak dikenal');
  }
}

/** Simpan satu baris dari toko ke tabel yang sama di server. Dipakai juga untuk perubahan dari pusat. */
export async function simpanBaris(kon, perangkat, tabel, payload) {
  const def = TABEL[tabel];
  if (!def) throw tolak(`tabel ${tabel} tidak diterima server`);
  if (!payload || typeof payload !== 'object' || Array.isArray(payload)) throw tolak('isi baris tidak valid');

  const kolom = await kolomTabel(kon, tabel);
  const baris = {};
  for (const [k, v] of Object.entries(payload)) {
    if (!kolom.has(k) || def.buang?.includes(k)) continue;
    if (v !== null && typeof v === 'object') throw tolak(`kolom ${k} tidak valid`);
    baris[k] = v;
  }
  for (const k of def.kunci) if (baris[k] == null || baris[k] === '') throw tolak(`kolom kunci ${k} kosong`);

  // Toko hanya boleh menulis data cabangnya sendiri.
  const cabang = await cabangBaris(kon, def, baris);
  if (perangkat && cabang !== undefined && cabang !== perangkat.cabang_id) {
    throw tolak('data ini bukan milik cabang perangkat pengirim');
  }

  const kunci = def.kunci.map((k) => `${k} = ?`).join(' AND ');
  const nilaiKunci = def.kunci.map((k) => baris[k]);
  const lama = await satu(kon, `SELECT * FROM ${tabel} WHERE ${kunci} FOR UPDATE`, nilaiKunci);

  let berubah = false;
  if (!lama) {
    const k = Object.keys(baris);
    await kon.query(`INSERT INTO ${tabel} (${k.join(', ')}) VALUES (${k.map(() => '?').join(', ')})`, k.map((x) => baris[x]));
    berubah = true;
  } else {
    const bolehUbah =
      (def.mode === 'ubah' && String(baris.updated_at ?? '') > String(lama.updated_at ?? '')) ||
      (def.mode === 'status' && lama.status === 'menunggu' && baris.status && baris.status !== 'menunggu') ||
      (def.mode === 'draft' && lama.status === 'draft');
    if (bolehUbah) {
      const k = Object.keys(baris).filter((x) => !def.kunci.includes(x));
      if (k.length > 0) {
        await kon.query(`UPDATE ${tabel} SET ${k.map((x) => `${x} = ?`).join(', ')} WHERE ${kunci}`, [...k.map((x) => baris[x]), ...nilaiKunci]);
        berubah = true;
      }
    }
  }

  if (berubah && TABEL_TARIK.has(tabel)) {
    await kon.query('INSERT INTO perubahan (tabel, baris_id, cabang_id, perangkat_id, created_at) VALUES (?,?,?,?,?)', [
      tabel,
      barisIdDari(def, baris),
      cabang ?? null,
      perangkat?.id ?? null,
      isoUtc(),
    ]);
  }
  return berubah;
}

// ------------------------------------------------------------------ ambil

/** Akun yang dikirim ke toko: rahasia TOTP tidak pernah ikut, dan Admin pusat tidak bisa dipakai masuk di toko. */
function bersihkanPengguna(p) {
  const { totp_secret: _t, ...sisa } = p;
  if (sisa.cabang_id == null) return { ...sisa, sandi_hash: '!', pin_hash: null, gagal_login: 0, terkunci: 0 };
  return sisa;
}

/**
 * @returns {{perubahan: {seq:number, tabel:string, baris:object}[], kursor:number, masih_ada:boolean}}
 */
export async function ambilPerubahan(kon, perangkat, sejak, batas = MAKS_AMBIL, sekarang = new Date(), jedaDetik = JEDA_AMAN_DETIK) {
  const batasWaktu = isoUtc(tambahDetik(sekarang, -jedaDetik));
  const daftar = await pilih(
    kon,
    'SELECT seq, tabel, baris_id FROM perubahan WHERE seq > ? AND created_at <= ?' +
      ' AND (cabang_id IS NULL OR cabang_id = ?) AND (perangkat_id IS NULL OR perangkat_id <> ?)' +
      ' ORDER BY seq LIMIT ?',
    [sejak, batasWaktu, perangkat.cabang_id, perangkat.id, batas],
  );

  const hasil = [];
  const sudah = new Set();
  for (const p of daftar) {
    if (!TABEL_TARIK.has(p.tabel)) continue;
    const def = TABEL[p.tabel];
    const kunciBaris = kunciDariBarisId(def, p.baris_id);
    // Baris yang muncul beberapa kali cukup dikirim sekali (isi terbarunya).
    const tanda = `${p.tabel}:${p.baris_id}`;
    if (sudah.has(tanda)) continue;
    sudah.add(tanda);
    let baris = await satu(kon, `SELECT * FROM ${p.tabel} WHERE ${def.kunci.map((k) => `${k} = ?`).join(' AND ')}`, def.kunci.map((k) => kunciBaris[k]));
    if (!baris) continue;
    if (p.tabel === 'pengguna') baris = bersihkanPengguna(baris);
    if (p.tabel === 'barang') {
      // Nama kategori ikut dikirim supaya toko bisa mencocokkan kategori yang namanya sama.
      const k = await satu(kon, 'SELECT nama FROM kategori WHERE id = ?', [baris.kategori_id]);
      baris = { ...baris, kategori_nama: k?.nama ?? null };
    }
    hasil.push({ seq: p.seq, tabel: p.tabel, baris });
  }

  let kursor = daftar.length > 0 ? daftar[daftar.length - 1].seq : sejak;
  const masihAda = daftar.length >= batas;
  if (!masihAda) {
    // Lompati perubahan yang memang bukan untuk toko ini, supaya kursor tidak tertinggal.
    const r = await satu(kon, 'SELECT MAX(seq) AS m FROM perubahan WHERE created_at <= ?', [batasWaktu]);
    if (r?.m != null && r.m > kursor) kursor = r.m;
  }
  return { perubahan: hasil, kursor, masih_ada: masihAda };
}
