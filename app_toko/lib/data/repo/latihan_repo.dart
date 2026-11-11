import 'package:pos_core/pos_core.dart';

import '../database.dart';
import 'pengaturan_repo.dart';

/// Isi database mode latihan dari data asli.
///
/// Mode latihan memakai FILE DATABASE TERPISAH (pos_toko_latihan.db). Yang disalin dari data asli:
/// info toko, akun (supaya kasir masuk dengan PIN-nya sendiri), kategori, supplier, barang, daftar barang toko,
/// harga jual & grosir yang berlaku, HPP terkini, dan stok sekarang (sebagai satu baris stok awal per barang).
/// Pengaturan printer ikut; alamat server / token kantor pusat TIDAK ikut, jadi data latihan tidak pernah
/// terkirim ke pusat. Transaksi, shift, dan riwayat lain tidak disalin.
class LatihanRepo {
  LatihanRepo._();

  /// Pengaturan PC yang ikut ke data latihan. Sengaja tanpa kunci server/token, cadangan, dan draft.
  static const pengaturanDisalin = [
    PengaturanRepo.kCabangId,
    PengaturanRepo.kNamaToko,
    PengaturanRepo.kPrinter,
    PengaturanRepo.kCetakOtomatis,
    PengaturanRepo.kPotongKertas,
    PengaturanRepo.kSalinanStruk,
    PengaturanRepo.kModalTetap,
  ];

  /// Penanda di database latihan (supaya database latihan tidak pernah dianggap data asli).
  static const kPenanda = 'mode_latihan';
  static const kDisalinPada = 'latihan_disalin_pada';

  static bool adalahLatihan(DatabaseToko db) => PengaturanRepo(db).ambil(kPenanda) == '1';

  /// Salin data dari [asli] ke [latihan] yang masih kosong (baru dibuat). [olehId] = SPV/Admin yang menyalakan.
  static void isiDariAsli({required DatabaseToko asli, required DatabaseToko latihan, required String olehId}) {
    if (adalahLatihan(asli)) throw StateError('Database asli tidak boleh database latihan');
    final cabangId = PengaturanRepo(asli).ambil(PengaturanRepo.kCabangId);
    if (cabangId == null) throw StateError('Toko belum disiapkan');
    if (latihan.satu('SELECT 1 FROM cabang LIMIT 1') != null) throw StateError('Database latihan tidak kosong');

    void salin(String tabel, String sql, [List<Object?> param = const []]) {
      for (final r in asli.pilih(sql, param)) {
        final kolom = r.keys.toList();
        latihan.jalankan(
          'INSERT INTO $tabel (${kolom.join(', ')}) VALUES (${List.filled(kolom.length, '?').join(', ')})',
          [for (final k in kolom) r[k]],
        );
      }
    }

    latihan.transaksi(() {
      salin('cabang', 'SELECT * FROM cabang');
      salin('pengguna', 'SELECT * FROM pengguna');
      salin('kategori', 'SELECT * FROM kategori');
      salin('supplier', 'SELECT * FROM supplier');
      salin('barang', 'SELECT * FROM barang');
      salin('barang_cabang', 'SELECT * FROM barang_cabang WHERE cabang_id = ?', [cabangId]);
      // Hanya versi harga yang berlaku sekarang (+ harga terjadwal yang belum berlaku) dan tingkat grosirnya.
      const hargaDipakai = 'SELECT id FROM harga_jual_terkini UNION SELECT id FROM harga_jual WHERE berlaku_mulai > ?';
      final t = asli.sekarangIso();
      salin('harga_jual', 'SELECT * FROM harga_jual WHERE (cabang_id IS NULL OR cabang_id = ?) AND id IN ($hargaDipakai)', [cabangId, t]);
      salin('harga_grosir', 'SELECT g.* FROM harga_grosir g JOIN harga_jual h ON h.id = g.harga_jual_id'
          ' WHERE (h.cabang_id IS NULL OR h.cabang_id = ?) AND h.id IN ($hargaDipakai)', [cabangId, t]);
      for (final r in asli.pilih('SELECT barang_id, hpp FROM hpp_terkini WHERE cabang_id = ?', [cabangId])) {
        latihan.jalankan('INSERT INTO hpp_barang (id, cabang_id, barang_id, hpp, ref_id, created_at) VALUES (?,?,?,?,NULL,?)',
            [buatId(), cabangId, r['barang_id'], r['hpp'], t]);
      }
      for (final r in asli.pilih('SELECT barang_id, stok FROM stok_sekarang WHERE cabang_id = ? AND stok <> 0', [cabangId])) {
        latihan.jalankan(
          "INSERT INTO mutasi_stok (id, cabang_id, barang_id, jumlah, jenis, ref_id, dibuat_oleh, created_at) VALUES (?,?,?,?,'opname',NULL,?,?)",
          [buatId(), cabangId, r['barang_id'], r['stok'], olehId, t],
        );
      }
      final p = PengaturanRepo(latihan);
      for (final k in pengaturanDisalin) {
        final v = PengaturanRepo(asli).ambil(k);
        if (v != null) p.simpan(k, v);
      }
      p.simpan(kPenanda, '1');
      p.simpan(kDisalinPada, t);
      // Data salinan tidak perlu dikirim ke mana pun; pastikan antrean kosong.
      latihan.jalankan('DELETE FROM outbox');
    });
  }
}
