// Pembantu test: database MySQL sementara + data contoh (bukan data asli toko).
import mysql from 'mysql2/promise';

import { buatPool } from '../src/db.js';
import { buatHashSandi, buatRahasiaTotp } from '../src/keamanan.js';
import { jalankanMigrasi } from '../src/migrasi.js';
import { buatId, isoUtc } from '../src/umum.js';

/** Alamat MySQL untuk test, TANPA nama database. Database sementara dibuat dan dihapus otomatis. */
export const URL_UJI = process.env.DB_UJI_URL ?? 'mysql://pos:pos-uji@127.0.0.1:3306';

export async function databaseUji() {
  let admin;
  try {
    admin = await mysql.createConnection(URL_UJI);
  } catch (e) {
    return { lewati: `MySQL untuk test tidak tersedia (${e.code ?? e.message}). Atur DB_UJI_URL.` };
  }
  const nama = `pos_uji_${Date.now()}_${Math.floor(Math.random() * 1e6)}`;
  await admin.query(`CREATE DATABASE ${nama} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci`);
  const pool = buatPool(`${URL_UJI}/${nama}`);
  await jalankanMigrasi(pool);
  return {
    pool,
    async tutup() {
      await pool.end();
      await admin.query(`DROP DATABASE ${nama}`);
      await admin.end();
    },
  };
}

export async function buatAdminPusat(pool, { namaPengguna = 'admin.pusat', sandi = 'sandi-pusat-123' } = {}) {
  const id = buatId();
  const rahasia = buatRahasiaTotp();
  const t = isoUtc();
  await pool.query(
    "INSERT INTO pengguna (id, cabang_id, nama, nama_pengguna, peran, sandi_hash, totp_secret, created_at, updated_at) VALUES (?, NULL, 'Admin Pusat', ?, 'admin', ?, ?, ?, ?)",
    [id, namaPengguna, await buatHashSandi(sandi), rahasia, t, t],
  );
  await pool.query("INSERT INTO perubahan (tabel, baris_id, created_at) VALUES ('pengguna', ?, ?)", [id, t]);
  return { id, namaPengguna, sandi, rahasia };
}

let urutOutbox = 0;
/** Satu item outbox seperti yang dikirim Aplikasi Toko. */
export const item = (tabel, payload, barisId = payload.id) => ({
  id: buatId(),
  tabel,
  baris_id: barisId,
  payload: JSON.stringify(payload),
  created_at: isoUtc(new Date(Date.UTC(2026, 10, 5, 2, 0, urutOutbox++))),
});

/** Data contoh satu toko: cabang, kategori, supplier, admin & kasir, barang gula dengan harga + grosir. */
export function tokoContoh(kode = 'A01') {
  const t = '2026-11-05T02:00:00Z';
  const cabang = { id: buatId(), kode, nama: `Contoh ${kode}`, alamat: 'Jl. Contoh 1', pesan_struk: 'Terima kasih', aktif: 1, created_at: t, updated_at: t };
  const kategori = { id: buatId(), nama: 'Sembako', aktif: 1, created_at: t };
  const supplier = { id: buatId(), nama: 'Toko Utama', jenis: 'toko_utama', telepon: '', aktif: 1, created_at: t };
  const admin = {
    id: buatId(), cabang_id: cabang.id, nama: 'Admin Toko', nama_pengguna: 'admin.toko', peran: 'admin', pin_hash: null,
    sandi_hash: '$argon2id$v=19$m=8192,t=3,p=1$c2FsdA$aGFzaA', totp_secret: 'RAHASIATOKO', gagal_login: 0, terkunci: 0, aktif: 1, created_at: t, updated_at: t,
  };
  const kasir = { ...admin, id: buatId(), nama: 'Kasir Contoh', nama_pengguna: null, peran: 'kasir', pin_hash: '$argon2id$pin', sandi_hash: null, totp_secret: null };
  const barang = { id: buatId(), barcode: `899${kode}01`, nama: 'Gula Pasir 1 kg', kategori_id: kategori.id, satuan: 'pak', aktif: 1, created_at: t, updated_at: t };
  const barangCabang = { cabang_id: cabang.id, barang_id: barang.id, aktif: 1, stok_minimum: 5, created_at: t, updated_at: t };
  const harga = {
    id: buatId(), barang_id: barang.id, cabang_id: cabang.id, harga: 17500, sumber: 'barang_masuk', ref_id: null, alasan: '',
    dibuat_oleh: kasir.id, disetujui_oleh: null, berlaku_mulai: t, created_at: t,
  };
  const grosir = { id: buatId(), harga_jual_id: harga.id, min_qty: 10, harga: 17000, created_at: t };
  const hpp = { id: buatId(), cabang_id: cabang.id, barang_id: barang.id, hpp: 16200, ref_id: null, created_at: t };
  return { cabang, kategori, supplier, admin, kasir, barang, barangCabang, harga, grosir, hpp };
}

/** Item outbox untuk menyiapkan toko contoh di server (urutan sama seperti di aplikasi). */
export function itemSetup(d) {
  return [
    item('cabang', d.cabang),
    item('kategori', d.kategori),
    item('supplier', d.supplier),
    item('pengguna', d.admin),
    item('pengguna', d.kasir),
    item('barang', d.barang),
    item('barang_cabang', d.barangCabang, `${d.cabang.id}|${d.barang.id}`),
    item('harga_jual', d.harga),
    item('harga_grosir', d.grosir),
    item('hpp_barang', d.hpp),
  ];
}

/** Satu penjualan: shift + transaksi + item + pembayaran + mutasi stok. */
export function penjualanContoh(d, { qty = 15, harga = 17000, hpp = 16200, waktu = '2026-11-05T03:00:00Z', no = 1 } = {}) {
  const shift = { id: buatId(), cabang_id: d.cabang.id, kasir_id: d.kasir.id, modal_awal: 200000, dibuka_pada: waktu };
  const trx = {
    id: buatId(), cabang_id: d.cabang.id, no_transaksi: `TRX-${d.cabang.kode}-261105-${String(no).padStart(4, '0')}`, shift_id: shift.id,
    kasir_id: d.kasir.id, total: qty * harga, jumlah_barang: qty, created_at: waktu,
  };
  const ti = {
    id: buatId(), transaksi_id: trx.id, barang_id: d.barang.id, nama_barang: d.barang.nama, qty, harga_satuan: harga,
    harga_grosir: 1, hpp_satuan: hpp, subtotal: qty * harga,
  };
  const bayar = { id: buatId(), transaksi_id: trx.id, metode: 'tunai', jumlah_diterima: 300000, kembalian: 300000 - qty * harga, no_referensi: null, created_at: waktu };
  const mutasi = { id: buatId(), cabang_id: d.cabang.id, barang_id: d.barang.id, jumlah: -qty, jenis: 'jual', ref_id: trx.id, dibuat_oleh: d.kasir.id, created_at: waktu };
  return { shift, trx, ti, bayar, mutasi, item: [item('shift', shift), item('transaksi', trx), item('transaksi_item', ti), item('pembayaran', bayar), item('mutasi_stok', mutasi)] };
}
