// Usulan harga dari kasir: Admin pusat melihat dan memutuskan. Aturan sama dengan Aplikasi Toko
// (packages/pos_core/lib/src/usulan_harga.dart): yang memutuskan lebih dulu yang berlaku; keputusan kedua ditolak.
import { catatLog } from './akun.js';
import { pilih, satu } from './db.js';
import { simpanBaris } from './sinkron.js';
import { GalatPengguna, adalahUuid, buatId, isoUtc, wajib } from './umum.js';

const STATUS = ['menunggu', 'disetujui', 'ditolak'];

/** per-mil turun (156 = 15,6%); sama dengan turunPerMil di pos_core. */
export function turunPerMil(lama, baru) {
  if (!(lama > 0)) return 0;
  return Math.trunc(((lama - baru) * 1000) / lama);
}

export async function daftarUsulan(kon, { status, cabang_id, batas = 200 } = {}) {
  const kondisi = [];
  const nilai = [];
  if (status) {
    wajib(STATUS.includes(status), 'status tidak dikenal');
    kondisi.push('u.status = ?');
    nilai.push(status);
  }
  if (cabang_id) {
    wajib(adalahUuid(cabang_id), 'cabang_id tidak valid');
    kondisi.push('u.cabang_id = ?');
    nilai.push(cabang_id);
  }
  const lim = Math.min(Math.max(Number.parseInt(batas, 10) || 200, 1), 500);
  const baris = await pilih(
    kon,
    'SELECT u.*, b.nama AS barang_nama, b.satuan, c.kode AS cabang_kode, c.nama AS cabang_nama,' +
      ' p.nama AS peminta_nama, m.nama AS pemutus_nama' +
      ' FROM usulan_harga u JOIN barang b ON b.id = u.barang_id JOIN cabang c ON c.id = u.cabang_id' +
      ' LEFT JOIN pengguna p ON p.id = u.diminta_oleh LEFT JOIN pengguna m ON m.id = u.diputuskan_oleh' +
      (kondisi.length ? ` WHERE ${kondisi.join(' AND ')}` : '') +
      ' ORDER BY u.created_at DESC LIMIT ?',
    [...nilai, lim],
  );
  return baris.map((u) => ({
    ...u,
    grosir: JSON.parse(u.grosir_json || '[]').map(([min_qty, harga]) => ({ min_qty, harga })),
    turun_per_mil: u.harga_lama == null ? null : turunPerMil(u.harga_lama, u.harga_baru),
  }));
}

/**
 * Admin pusat menyetujui/menolak. Harus dipanggil di dalam transaksi.
 * Disetujui → harga_jual (+ grosir) khusus toko itu; sampai ke PC toko lewat sinkron (tabel `perubahan`).
 * Sudah diputuskan (di toko atau pusat) → galat 409.
 */
export async function putuskanUsulan(kon, { id, setuju }, adminId) {
  wajib(adalahUuid(id), 'id usulan tidak valid');
  wajib(typeof setuju === 'boolean', 'setuju harus true atau false');
  const u = await satu(kon, 'SELECT * FROM usulan_harga WHERE id = ? FOR UPDATE', [id]);
  wajib(u, 'Usulan tidak ditemukan', 404);
  if (u.status !== 'menunggu') {
    throw new GalatPengguna(`Usulan sudah ${u.status === 'disetujui' ? 'disetujui' : 'ditolak'} (${u.diputuskan_di === 'pusat' ? 'dari pusat' : 'di toko'}).`, 409);
  }
  const t = isoUtc();
  let hargaJualId = null;
  if (setuju) {
    hargaJualId = buatId();
    await simpanBaris(kon, null, 'harga_jual', {
      id: hargaJualId,
      barang_id: u.barang_id,
      cabang_id: u.cabang_id,
      harga: u.harga_baru,
      sumber: u.sumber,
      ref_id: u.ref_id,
      alasan: u.alasan,
      dibuat_oleh: u.diminta_oleh,
      disetujui_oleh: adminId,
      berlaku_mulai: t,
      created_at: t,
    });
    for (const [min_qty, harga] of JSON.parse(u.grosir_json || '[]')) {
      await simpanBaris(kon, null, 'harga_grosir', { id: buatId(), harga_jual_id: hargaJualId, min_qty, harga, created_at: t });
    }
  }
  await simpanBaris(kon, null, 'usulan_harga', {
    id,
    cabang_id: u.cabang_id,
    status: setuju ? 'disetujui' : 'ditolak',
    diputuskan_oleh: adminId,
    diputuskan_di: 'pusat',
    diputuskan_pada: t,
    harga_jual_id: hargaJualId,
  });
  await catatLog(kon, {
    cabangId: u.cabang_id,
    penggunaId: adminId,
    aksi: setuju ? 'usulan_harga_disetujui' : 'usulan_harga_ditolak',
    detail: { usulan_id: id, barang_id: u.barang_id, harga_lama: u.harga_lama, harga_baru: u.harga_baru, dari: 'pusat' },
  });
  return { status: setuju ? 'disetujui' : 'ditolak', harga_jual_id: hargaJualId };
}
