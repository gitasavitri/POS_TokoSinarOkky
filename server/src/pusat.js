// Data untuk Aplikasi Pusat: cabang, perangkat, barang & harga semua toko, laporan gabungan.
import { catatLog } from './akun.js';
import { pilih, satu, transaksi } from './db.js';
import { periksaTingkatGrosir } from './harga.js';
import { simpanBaris } from './sinkron.js';
import { GalatPengguna, adalahIso, adalahUuid, bulat, buatId, isoUtc, teks, waktuSesudah, wajib } from './umum.js';

// ------------------------------------------------------------------ rentang & filter

/** dari (inklusif) dan sampai (eksklusif) dalam ISO UTC. Aplikasi Pusat menghitung batas hari WIB. */
export function rentang(q) {
  wajib(adalahIso(q.dari) && adalahIso(q.sampai), 'Parameter dari/sampai harus waktu ISO UTC, mis. 2026-11-04T17:00:00Z');
  wajib(q.dari < q.sampai, 'dari harus sebelum sampai');
  return { dari: q.dari, sampai: q.sampai };
}

function filterCabang(q, alias = 't') {
  if (q.cabang_id == null || q.cabang_id === '') return { sql: '', param: [] };
  wajib(adalahUuid(q.cabang_id), 'cabang_id tidak valid');
  return { sql: ` AND ${alias}.cabang_id = ?`, param: [q.cabang_id] };
}

// ------------------------------------------------------------------ cabang & perangkat

export const daftarCabang = (kon) =>
  pilih(
    kon,
    'SELECT c.id, c.kode, c.nama, c.alamat, c.aktif,' +
      ' (SELECT MAX(p.terakhir_sinkron) FROM perangkat p WHERE p.cabang_id = c.id AND p.aktif = 1) AS terakhir_sinkron,' +
      ' (SELECT COUNT(*) FROM perangkat p WHERE p.cabang_id = c.id AND p.aktif = 1) AS jumlah_perangkat' +
      ' FROM cabang c ORDER BY c.kode',
  );

export const daftarPerangkat = (kon) =>
  pilih(
    kon,
    'SELECT p.id, p.nama, p.aktif, p.terdaftar_pada, p.terakhir_sinkron, c.kode AS kode_cabang, c.nama AS nama_cabang' +
      ' FROM perangkat p JOIN cabang c ON c.id = p.cabang_id ORDER BY p.aktif DESC, c.kode',
  );

export async function cabutPerangkat(kon, id, olehId) {
  wajib(adalahUuid(id), 'id tidak valid');
  const [r] = await kon.query('UPDATE perangkat SET aktif = 0 WHERE id = ?', [id]);
  wajib(r.affectedRows === 1, 'Perangkat tidak ditemukan', 404);
  await catatLog(kon, { penggunaId: olehId, aksi: 'cabut_perangkat', detail: { perangkat_id: id } });
}

// ------------------------------------------------------------------ barang, kategori, harga

const SQL_HARGA_GLOBAL =
  'SELECT h.* FROM harga_jual h WHERE h.barang_id = ? AND h.cabang_id IS NULL AND h.berlaku_mulai <= ?' +
  ' ORDER BY h.berlaku_mulai DESC, h.created_at DESC LIMIT 1';

export async function hargaGlobal(kon, barangId, sekarang = isoUtc()) {
  const h = await satu(kon, SQL_HARGA_GLOBAL, [barangId, sekarang]);
  if (!h) return null;
  const grosir = await pilih(kon, 'SELECT min_qty, harga FROM harga_grosir WHERE harga_jual_id = ? ORDER BY min_qty', [h.id]);
  return { id: h.id, eceran: h.harga, berlaku_mulai: h.berlaku_mulai, grosir };
}

/** Daftar barang semua toko + harga pusat terkini + HPP tertinggi dan stok total. */
export async function daftarBarang(kon, { kata = '', batas = 200 } = {}) {
  const k = `%${String(kata).trim()}%`;
  const baris = await pilih(
    kon,
    'SELECT b.id, b.barcode, b.nama, b.satuan, b.aktif, b.kategori_id, k.nama AS kategori,' +
      ' (SELECT IFNULL(SUM(m.jumlah), 0) FROM mutasi_stok m WHERE m.barang_id = b.id) AS stok_total,' +
      ' (SELECT COUNT(*) FROM barang_cabang bc WHERE bc.barang_id = b.id AND bc.aktif = 1) AS jumlah_toko' +
      ' FROM barang b LEFT JOIN kategori k ON k.id = b.kategori_id' +
      ' WHERE b.nama LIKE ? OR b.barcode LIKE ? ORDER BY b.nama LIMIT ?',
    [k, k, Math.min(Number(batas) || 200, 1000)],
  );
  const t = isoUtc();
  for (const b of baris) {
    b.harga = await hargaGlobal(kon, b.id, t);
    b.hpp_tertinggi = await hppTertinggi(kon, b.id);
  }
  return baris;
}

/** HPP terkini tertinggi di antara semua cabang (dipakai untuk mengecek harga pusat tidak rugi di toko mana pun). */
export async function hppTertinggi(kon, barangId) {
  const r = await satu(
    kon,
    'SELECT MAX(h.hpp) AS hpp FROM hpp_barang h WHERE h.barang_id = ? AND h.created_at = ' +
      '(SELECT MAX(h2.created_at) FROM hpp_barang h2 WHERE h2.barang_id = h.barang_id AND h2.cabang_id = h.cabang_id)',
    [barangId],
  );
  return r?.hpp ?? null;
}

export async function simpanKategori(kon, { nama }, olehId) {
  const n = teks(nama, 'Nama kategori', { max: 100 });
  const ada = await satu(kon, 'SELECT id FROM kategori WHERE LOWER(nama) = LOWER(?)', [n]);
  if (ada) throw new GalatPengguna(`Kategori "${n}" sudah ada`, 409);
  const id = buatId();
  await simpanBaris(kon, null, 'kategori', { id, nama: n, aktif: 1, created_at: isoUtc() });
  await catatLog(kon, { penggunaId: olehId, aksi: 'tambah_kategori', detail: { nama: n } });
  return { id };
}

export async function simpanBarang(kon, data, olehId) {
  const t = isoUtc();
  const id = data.id ?? buatId();
  wajib(adalahUuid(id), 'id barang tidak valid');
  wajib(adalahUuid(data.kategori_id), 'Kategori wajib dipilih');
  wajib(await satu(kon, 'SELECT 1 AS ada FROM kategori WHERE id = ?', [data.kategori_id]), 'Kategori tidak ditemukan');
  const barcode = data.barcode == null || String(data.barcode).trim() === '' ? null : teks(data.barcode, 'Barcode', { max: 64 });
  if (barcode) {
    const lain = await satu(kon, 'SELECT nama FROM barang WHERE barcode = ? AND id <> ? LIMIT 1', [barcode, id]);
    if (lain) throw new GalatPengguna(`Barcode ${barcode} sudah dipakai "${lain.nama}"`, 409);
  }
  const lama = await satu(kon, 'SELECT created_at, updated_at FROM barang WHERE id = ?', [id]);
  await simpanBaris(kon, null, 'barang', {
    id,
    barcode,
    nama: teks(data.nama, 'Nama barang'),
    kategori_id: data.kategori_id,
    satuan: teks(data.satuan, 'Satuan', { max: 20 }),
    aktif: data.aktif === 0 || data.aktif === false ? 0 : 1,
    created_at: lama?.created_at ?? t,
    updated_at: waktuSesudah(lama?.updated_at),
  });
  await catatLog(kon, { penggunaId: olehId, aksi: lama ? 'ubah_barang' : 'tambah_barang', detail: { barang_id: id, nama: data.nama } });
  return { id };
}

/** Atur barang dijual / tidak di sebuah toko. */
export async function aturBarangCabang(kon, { cabang_id, barang_id, aktif = 1, stok_minimum }, olehId) {
  wajib(adalahUuid(cabang_id) && adalahUuid(barang_id), 'cabang_id dan barang_id wajib');
  wajib(await satu(kon, 'SELECT 1 AS ada FROM cabang WHERE id = ?', [cabang_id]), 'Cabang tidak ditemukan', 404);
  wajib(await satu(kon, 'SELECT 1 AS ada FROM barang WHERE id = ?', [barang_id]), 'Barang tidak ditemukan', 404);
  const lama = await satu(kon, 'SELECT * FROM barang_cabang WHERE cabang_id = ? AND barang_id = ?', [cabang_id, barang_id]);
  const t = isoUtc();
  await simpanBaris(kon, null, 'barang_cabang', {
    cabang_id,
    barang_id,
    aktif: aktif ? 1 : 0,
    stok_minimum: stok_minimum == null ? (lama?.stok_minimum ?? 0) : bulat(stok_minimum, 'Stok minimum', { min: 0 }),
    created_at: lama?.created_at ?? t,
    updated_at: waktuSesudah(lama?.updated_at),
  });
  await catatLog(kon, { cabangId: cabang_id, penggunaId: olehId, aksi: 'atur_barang_toko', detail: { barang_id, aktif: !!aktif } });
}

/**
 * Harga baru dari pusat untuk SEMUA toko (cabang_id NULL). Menggantikan harga khusus toko yang lebih lama.
 * Mengembalikan peringatan (bukan galat) kalau harga eceran ≤ HPP tertinggi.
 */
export async function ubahHargaPusat(kon, { barang_id, harga, grosir = [], alasan, berlaku_mulai }, olehId) {
  wajib(adalahUuid(barang_id), 'Barang wajib dipilih');
  wajib(await satu(kon, 'SELECT 1 AS ada FROM barang WHERE id = ?', [barang_id]), 'Barang tidak ditemukan', 404);
  bulat(harga, 'Harga eceran', { min: 1 });
  wajib(Array.isArray(grosir) && grosir.length <= 10, 'Tingkat grosir maksimal 10');
  const tingkat = grosir.map((g) => ({ min_qty: g?.min_qty, harga: g?.harga }));
  const hpp = await hppTertinggi(kon, barang_id);
  const salah = periksaTingkatGrosir({ eceran: harga, hpp, tingkat });
  const pertama = Object.entries(salah)[0];
  if (pertama) throw new GalatPengguna(`Tingkat grosir ${Number(pertama[0]) + 1}: ${pertama[1]}`);
  const alasanBersih = teks(alasan, 'Alasan', { max: 300 });
  const t = isoUtc();
  const mulai = berlaku_mulai == null ? t : berlaku_mulai;
  wajib(adalahIso(mulai), 'berlaku_mulai harus waktu ISO UTC');

  const hargaId = buatId();
  await simpanBaris(kon, null, 'harga_jual', {
    id: hargaId,
    barang_id,
    cabang_id: null,
    harga,
    sumber: 'pusat',
    ref_id: null,
    alasan: alasanBersih,
    dibuat_oleh: olehId,
    disetujui_oleh: null,
    berlaku_mulai: mulai,
    created_at: t,
  });
  for (const g of tingkat) {
    await simpanBaris(kon, null, 'harga_grosir', { id: buatId(), harga_jual_id: hargaId, min_qty: g.min_qty, harga: g.harga, created_at: t });
  }
  await catatLog(kon, { penggunaId: olehId, aksi: 'ubah_harga_pusat', detail: { barang_id, harga, grosir: tingkat, alasan: alasanBersih } });
  const peringatan = hpp != null && harga <= hpp ? [`Harga eceran ≤ HPP tertinggi di toko (Rp ${hpp}).`] : [];
  return { harga_jual_id: hargaId, peringatan };
}

export function ubahHargaPusatTransaksi(pool, data, olehId) {
  return transaksi(pool, (kon) => ubahHargaPusat(kon, data, olehId));
}

// ------------------------------------------------------------------ laporan

const BUKAN_BATAL = 'NOT EXISTS (SELECT 1 FROM pembatalan x WHERE x.transaksi_id = t.id)';

/** Ringkasan per cabang + total. Definisi sama dengan laporan di Aplikasi Toko. */
export async function ringkasan(kon, q) {
  const { dari, sampai } = rentang(q);
  const fc = filterCabang(q);
  const jual = await pilih(
    kon,
    "SELECT t.cabang_id, COUNT(*) AS n, IFNULL(SUM(t.total), 0) AS total, IFNULL(SUM(CASE WHEN p.metode = 'tunai' THEN t.total ELSE 0 END), 0) AS tunai" +
      ` FROM transaksi t JOIN pembayaran p ON p.transaksi_id = t.id WHERE t.created_at >= ? AND t.created_at < ? AND ${BUKAN_BATAL}${fc.sql}` +
      ' GROUP BY t.cabang_id',
    [dari, sampai, ...fc.param],
  );
  const laba = await pilih(
    kon,
    'SELECT t.cabang_id, IFNULL(SUM((i.harga_satuan - i.hpp_satuan) * i.qty), 0) AS laba FROM transaksi_item i JOIN transaksi t ON t.id = i.transaksi_id' +
      ` WHERE t.created_at >= ? AND t.created_at < ? AND ${BUKAN_BATAL}${fc.sql} GROUP BY t.cabang_id`,
    [dari, sampai, ...fc.param],
  );
  const retur = await pilih(
    kon,
    'SELECT t.cabang_id, IFNULL(SUM(r.total_kembali), 0) AS total,' +
      ' IFNULL(SUM((SELECT SUM((i.harga_satuan - i.hpp_satuan) * ri.qty) FROM retur_item ri JOIN transaksi_item i ON i.id = ri.transaksi_item_id WHERE ri.retur_id = r.id)), 0) AS laba' +
      ` FROM retur r JOIN transaksi t ON t.id = r.transaksi_id WHERE r.created_at >= ? AND r.created_at < ?${fc.sql} GROUP BY t.cabang_id`,
    [dari, sampai, ...fc.param],
  );
  const batal = await pilih(
    kon,
    `SELECT t.cabang_id, COUNT(*) AS n FROM pembatalan x JOIN transaksi t ON t.id = x.transaksi_id WHERE x.created_at >= ? AND x.created_at < ?${fc.sql} GROUP BY t.cabang_id`,
    [dari, sampai, ...fc.param],
  );
  const cabang = await pilih(kon, 'SELECT id, kode, nama FROM cabang ORDER BY kode');
  const per = (daftar, id) => daftar.find((r) => r.cabang_id === id);
  const baris = cabang
    .filter((c) => !fc.param.length || c.id === fc.param[0])
    .map((c) => {
      const j = per(jual, c.id) ?? { n: 0, total: 0, tunai: 0 };
      const r = per(retur, c.id) ?? { total: 0, laba: 0 };
      return {
        cabang_id: c.id,
        kode: c.kode,
        nama: c.nama,
        penjualan_bersih: j.total - r.total,
        jumlah_transaksi: j.n,
        tunai: j.tunai,
        non_tunai: j.total - j.tunai,
        laba_kotor: (per(laba, c.id)?.laba ?? 0) - r.laba,
        jumlah_batal: per(batal, c.id)?.n ?? 0,
        total_retur: r.total,
      };
    });
  const total = baris.reduce(
    (a, b) => {
      for (const k of ['penjualan_bersih', 'jumlah_transaksi', 'tunai', 'non_tunai', 'laba_kotor', 'jumlah_batal', 'total_retur']) a[k] += b[k];
      return a;
    },
    { penjualan_bersih: 0, jumlah_transaksi: 0, tunai: 0, non_tunai: 0, laba_kotor: 0, jumlah_batal: 0, total_retur: 0 },
  );
  return { per_cabang: baris, total };
}

const TANGGAL_WIB = "DATE(DATE_ADD(STR_TO_DATE(t.created_at, '%Y-%m-%dT%H:%i:%sZ'), INTERVAL 7 HOUR))";

export async function penjualanHarian(kon, q) {
  const { dari, sampai } = rentang(q);
  const fc = filterCabang(q);
  return pilih(
    kon,
    `SELECT DATE_FORMAT(${TANGGAL_WIB}, '%Y-%m-%d') AS tanggal, IFNULL(SUM(t.total), 0) AS total, COUNT(*) AS transaksi` +
      ` FROM transaksi t WHERE t.created_at >= ? AND t.created_at < ? AND ${BUKAN_BATAL}${fc.sql} GROUP BY tanggal ORDER BY tanggal`,
    [dari, sampai, ...fc.param],
  );
}

export async function terlaris(kon, q) {
  const { dari, sampai } = rentang(q);
  const fc = filterCabang(q);
  return pilih(
    kon,
    'SELECT i.barang_id, MAX(i.nama_barang) AS nama, SUM(i.qty) AS qty, SUM(i.subtotal) AS total' +
      ` FROM transaksi_item i JOIN transaksi t ON t.id = i.transaksi_id WHERE t.created_at >= ? AND t.created_at < ? AND ${BUKAN_BATAL}${fc.sql}` +
      ' GROUP BY i.barang_id ORDER BY qty DESC LIMIT ?',
    [dari, sampai, ...fc.param, Math.min(Number(q.batas) || 10, 100)],
  );
}

export async function daftarTransaksi(kon, q) {
  const { dari, sampai } = rentang(q);
  const fc = filterCabang(q);
  return pilih(
    kon,
    'SELECT t.id, t.no_transaksi, t.created_at, t.total, t.jumlah_barang, p.metode, c.kode AS kode_cabang, u.nama AS kasir,' +
      ' EXISTS(SELECT 1 FROM pembatalan x WHERE x.transaksi_id = t.id) AS batal,' +
      ' EXISTS(SELECT 1 FROM retur r WHERE r.transaksi_id = t.id) AS retur' +
      ' FROM transaksi t JOIN pembayaran p ON p.transaksi_id = t.id JOIN cabang c ON c.id = t.cabang_id LEFT JOIN pengguna u ON u.id = t.kasir_id' +
      ` WHERE t.created_at >= ? AND t.created_at < ?${fc.sql} ORDER BY t.created_at DESC LIMIT ?`,
    [dari, sampai, ...fc.param, Math.min(Number(q.batas) || 500, 5000)],
  );
}

/** Stok & HPP per barang di satu cabang. */
export async function stokCabang(kon, q) {
  wajib(adalahUuid(q.cabang_id), 'Pilih cabang');
  const k = `%${String(q.kata ?? '').trim()}%`;
  return pilih(
    kon,
    'SELECT b.id, b.barcode, b.nama, b.satuan, bc.stok_minimum, bc.aktif,' +
      ' (SELECT IFNULL(SUM(m.jumlah), 0) FROM mutasi_stok m WHERE m.cabang_id = bc.cabang_id AND m.barang_id = b.id) AS stok,' +
      ' (SELECT h.hpp FROM hpp_barang h WHERE h.cabang_id = bc.cabang_id AND h.barang_id = b.id ORDER BY h.created_at DESC LIMIT 1) AS hpp' +
      ' FROM barang_cabang bc JOIN barang b ON b.id = bc.barang_id WHERE bc.cabang_id = ? AND (b.nama LIKE ? OR b.barcode LIKE ?)' +
      ' ORDER BY b.nama LIMIT 2000',
    [q.cabang_id, k, k],
  );
}

export async function daftarKaryawan(kon, q) {
  const fc = filterCabang(q, 'p');
  return pilih(
    kon,
    'SELECT p.id, p.cabang_id, c.kode AS kode_cabang, p.nama, p.nama_pengguna, p.peran, p.terkunci, p.aktif, p.updated_at' +
      ` FROM pengguna p LEFT JOIN cabang c ON c.id = p.cabang_id WHERE 1 = 1${fc.sql} ORDER BY c.kode, p.peran, p.nama`,
    fc.param,
  );
}

export async function daftarLog(kon, q) {
  const { dari, sampai } = rentang(q);
  const fc = filterCabang(q, 'l');
  return pilih(
    kon,
    'SELECT l.id, l.created_at, l.aksi, l.detail, c.kode AS kode_cabang, u.nama AS oleh, s.nama AS penyetuju' +
      ' FROM log_aktivitas l LEFT JOIN cabang c ON c.id = l.cabang_id LEFT JOIN pengguna u ON u.id = l.pengguna_id LEFT JOIN pengguna s ON s.id = l.disetujui_oleh' +
      ` WHERE l.created_at >= ? AND l.created_at < ?${fc.sql} ORDER BY l.created_at DESC LIMIT ?`,
    [dari, sampai, ...fc.param, Math.min(Number(q.batas) || 500, 5000)],
  );
}

export const barangGanda = (kon) =>
  pilih(
    kon,
    'SELECT g.barcode, g.jumlah, b.id, b.nama, b.created_at FROM barang_ganda g JOIN barang b ON b.barcode = g.barcode ORDER BY g.barcode, b.created_at',
  );
