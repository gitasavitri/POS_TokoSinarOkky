// Aturan per tabel untuk sinkronisasi.
//
// mode:
//   tambah  – tabel riwayat: baris hanya ditambah; kiriman ulang dengan id sama diabaikan.
//   ubah    – data master dengan kolom updated_at: versi yang lebih baru menang.
//   status  – koreksi_barang_masuk: hanya boleh berubah dari 'menunggu' ke keputusan.
//   draft   – barang_masuk: boleh berubah selama status 'draft', terkunci setelah 'terkirim'.
//
// cabang: dari mana server tahu baris ini milik cabang mana (untuk mencegah toko A menulis data toko B).
//   { jenis: 'diri' }    – baris cabang itu sendiri (id = cabang)
//   { jenis: 'kolom' }   – kolom cabang_id di baris
//   { jenis: 'global' }  – berlaku semua toko (barang, kategori, supplier)
//   { jenis: 'induk', sql, kolom } – dicari lewat baris induk

const induk = (sql, kolom) => ({ jenis: 'induk', sql, kolom });
const lewatTransaksi = (kolom) => induk('SELECT cabang_id FROM transaksi WHERE id = ?', kolom);

export const TABEL = {
  cabang: { kunci: ['id'], mode: 'ubah', cabang: { jenis: 'diri' } },
  pengguna: { kunci: ['id'], mode: 'ubah', cabang: { jenis: 'kolom' }, buang: ['totp_secret'] },
  kategori: { kunci: ['id'], mode: 'tambah', cabang: { jenis: 'global' } },
  supplier: { kunci: ['id'], mode: 'tambah', cabang: { jenis: 'global' } },
  barang: { kunci: ['id'], mode: 'ubah', cabang: { jenis: 'global' } },
  barang_cabang: { kunci: ['cabang_id', 'barang_id'], mode: 'ubah', cabang: { jenis: 'kolom' } },
  harga_jual: { kunci: ['id'], mode: 'tambah', cabang: { jenis: 'kolom' } },
  harga_grosir: { kunci: ['id'], mode: 'tambah', cabang: induk('SELECT cabang_id FROM harga_jual WHERE id = ?', 'harga_jual_id') },
  hpp_barang: { kunci: ['id'], mode: 'tambah', cabang: { jenis: 'kolom' } },
  mutasi_stok: { kunci: ['id'], mode: 'tambah', cabang: { jenis: 'kolom' } },
  barang_masuk: { kunci: ['id'], mode: 'draft', cabang: { jenis: 'kolom' } },
  barang_masuk_item: { kunci: ['id'], mode: 'tambah', cabang: induk('SELECT cabang_id FROM barang_masuk WHERE id = ?', 'barang_masuk_id') },
  koreksi_barang_masuk: {
    kunci: ['id'],
    mode: 'status',
    cabang: induk(
      'SELECT bm.cabang_id FROM barang_masuk_item i JOIN barang_masuk bm ON bm.id = i.barang_masuk_id WHERE i.id = ?',
      'barang_masuk_item_id',
    ),
  },
  shift: { kunci: ['id'], mode: 'tambah', cabang: { jenis: 'kolom' } },
  shift_tutup: { kunci: ['shift_id'], mode: 'tambah', cabang: induk('SELECT cabang_id FROM shift WHERE id = ?', 'shift_id') },
  kas_shift: { kunci: ['id'], mode: 'tambah', cabang: { jenis: 'kolom' } },
  shift_hitung: { kunci: ['id'], mode: 'tambah', cabang: { jenis: 'kolom' } },
  shift_belum_dihitung: { kunci: ['shift_id'], mode: 'tambah', cabang: { jenis: 'kolom' } },
  transaksi: { kunci: ['id'], mode: 'tambah', cabang: { jenis: 'kolom' } },
  transaksi_item: { kunci: ['id'], mode: 'tambah', cabang: lewatTransaksi('transaksi_id') },
  pembayaran: { kunci: ['id'], mode: 'tambah', cabang: lewatTransaksi('transaksi_id') },
  pembatalan: { kunci: ['transaksi_id'], mode: 'tambah', cabang: lewatTransaksi('transaksi_id') },
  retur: { kunci: ['id'], mode: 'tambah', cabang: lewatTransaksi('transaksi_id') },
  retur_item: {
    kunci: ['id'],
    mode: 'tambah',
    cabang: induk('SELECT t.cabang_id FROM retur r JOIN transaksi t ON t.id = r.transaksi_id WHERE r.id = ?', 'retur_id'),
  },
  log_aktivitas: { kunci: ['id'], mode: 'tambah', cabang: { jenis: 'kolom' } },
};

/** Tabel yang dikirim dari server ke toko (data barang & harga, akun, info cabang). Urutan tidak penting:
 *  toko menerapkannya menurut urutan perubahan (seq). */
export const TABEL_TARIK = new Set(['cabang', 'pengguna', 'kategori', 'barang', 'barang_cabang', 'harga_jual', 'harga_grosir']);

/** baris_id untuk kunci gabungan memakai '|' (sama seperti outbox di Aplikasi Toko). */
export const barisIdDari = (def, baris) => def.kunci.map((k) => baris[k]).join('|');

export function kunciDariBarisId(def, barisId) {
  const bagian = String(barisId).split('|');
  return Object.fromEntries(def.kunci.map((k, i) => [k, bagian[i]]));
}
