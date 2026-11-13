import 'package:pos_core/pos_core.dart';

import '../database.dart';
import '../model.dart';

/// Barang, harga berlaku, HPP, stok, kategori, supplier.
class KatalogRepo {
  KatalogRepo(this._db);
  final DatabaseToko _db;

  // ---------------------------------------------------------------- kategori & supplier

  List<Kategori> kategori() => _db
      .pilih('SELECT id, nama FROM kategori WHERE aktif = 1 ORDER BY nama')
      .map((r) => Kategori(r['id'] as String, r['nama'] as String))
      .toList();

  /// Kategori baru. Nama yang sama (beda huruf besar/kecil) ditolak oleh database.
  String tambahKategori(String nama, {required String cabangId, required String olehId}) {
    final n = nama.trim();
    if (n.isEmpty) throw ArgumentError('Nama kategori wajib diisi');
    final ada = _db.satu('SELECT id FROM kategori WHERE nama = ? COLLATE NOCASE', [n]);
    if (ada != null) throw ArgumentError('Kategori "$n" sudah ada');
    final id = buatId();
    _db.transaksi(() {
      _db.jalankan('INSERT INTO kategori (id, nama, created_at) VALUES (?,?,?)', [id, n, _db.sekarangIso()]);
      _db.outbox('kategori', id);
      _db.log(cabangId: cabangId, penggunaId: olehId, aksi: 'tambah_kategori', detail: {'nama': n});
    });
    return id;
  }

  List<Supplier> supplier() => _db
      .pilih("SELECT id, nama, jenis FROM supplier WHERE aktif = 1 ORDER BY jenis = 'toko_utama' DESC, nama")
      .map((r) => Supplier(r['id'] as String, r['nama'] as String, r['jenis'] as String))
      .toList();

  String tambahSupplier(String nama, {String telepon = '', required String cabangId, required String olehId}) {
    final n = nama.trim();
    if (n.isEmpty) throw ArgumentError('Nama supplier wajib diisi');
    final id = buatId();
    _db.transaksi(() {
      _db.jalankan('INSERT INTO supplier (id, nama, jenis, telepon, created_at) VALUES (?,?,?,?,?)',
          [id, n, 'luar', telepon.trim(), _db.sekarangIso()]);
      _db.outbox('supplier', id);
      _db.log(cabangId: cabangId, penggunaId: olehId, aksi: 'tambah_supplier', detail: {'nama': n});
    });
    return id;
  }

  // ---------------------------------------------------------------- harga

  /// Harga berlaku untuk toko ini: versi terbaru di antara harga khusus toko dan harga semua toko.
  (String, HargaBarang)? hargaBerlaku(String barangId, String cabangId) {
    final r = _db.satu(
      'SELECT id, harga FROM harga_jual_terkini WHERE barang_id = ? AND (cabang_id = ? OR cabang_id IS NULL)'
      ' ORDER BY berlaku_mulai DESC, cabang_id IS NULL LIMIT 1',
      [barangId, cabangId],
    );
    if (r == null) return null;
    final id = r['id'] as String;
    final tingkat = _db
        .pilih('SELECT min_qty, harga FROM harga_grosir WHERE harga_jual_id = ? ORDER BY min_qty', [id])
        .map((g) => TingkatGrosir(minQty: g['min_qty'] as int, harga: g['harga'] as int))
        .toList();
    return (id, HargaBarang(eceran: r['harga'] as int, grosir: tingkat));
  }

  int? hpp(String barangId, String cabangId) =>
      _db.satu('SELECT hpp FROM hpp_terkini WHERE barang_id = ? AND cabang_id = ?', [barangId, cabangId])?['hpp']
          as int?;

  int stok(String barangId, String cabangId) =>
      (_db.satu('SELECT stok FROM stok_sekarang WHERE barang_id = ? AND cabang_id = ?', [barangId, cabangId])?['stok']
          as int?) ??
      0;

  // ---------------------------------------------------------------- barang

  DetailBarang? detail(String barangId, String cabangId) {
    final r = _db.satu(
      'SELECT b.*, k.nama AS kategori_nama, bc.aktif AS di_toko, bc.stok_minimum'
      ' FROM barang b JOIN kategori k ON k.id = b.kategori_id'
      ' LEFT JOIN barang_cabang bc ON bc.barang_id = b.id AND bc.cabang_id = ?'
      ' WHERE b.id = ?',
      [cabangId, barangId],
    );
    if (r == null) return null;
    final h = hargaBerlaku(barangId, cabangId);
    return DetailBarang(
      id: barangId,
      barcode: r['barcode'] as String?,
      nama: r['nama'] as String,
      kategoriId: r['kategori_id'] as String,
      kategoriNama: r['kategori_nama'] as String,
      satuan: r['satuan'] as String,
      hargaJualId: h?.$1,
      harga: h?.$2,
      hpp: hpp(barangId, cabangId),
      stok: stok(barangId, cabangId),
      stokMinimum: (r['stok_minimum'] as int?) ?? 0,
      dijualDiToko: r['di_toko'] == 1 && r['aktif'] == 1,
    );
  }

  /// Cari barang dengan barcode (semua barang, termasuk yang belum dijual di toko ini — untuk barang masuk).
  DetailBarang? cariBarcode(String barcode, String cabangId) {
    final b = barcode.trim();
    if (b.isEmpty) return null;
    final r = _db.satu('SELECT id FROM barang WHERE barcode = ?', [b]);
    return r == null ? null : detail(r['id'] as String, cabangId);
  }

  /// Barang yang bisa dijual di kasir toko ini, dicari dengan barcode.
  BarangJual? untukKasirBarcode(String barcode, String cabangId) {
    final r = _db.satu('SELECT barang_id FROM barang_toko WHERE cabang_id = ? AND barcode = ?', [cabangId, barcode.trim()]);
    if (r == null) return null;
    return detail(r['barang_id'] as String, cabangId)?.untukDijual;
  }

  /// Barang yang bisa dijual di kasir toko ini, dicari dengan id (memuat ulang belanjaan tersimpan).
  BarangJual? untukKasir(String barangId, String cabangId) {
    if (_db.satu('SELECT 1 FROM barang_toko WHERE cabang_id = ? AND barang_id = ?', [cabangId, barangId]) == null) return null;
    return detail(barangId, cabangId)?.untukDijual;
  }

  /// Cari dengan nama (berisi kata) atau awal barcode. [hanyaDiToko] = hanya barang yang dijual di toko ini.
  List<DetailBarang> cari(String kata, String cabangId, {bool hanyaDiToko = true, int batas = 30}) {
    final k = kata.trim();
    final pola = '%${k.replaceAll('%', '').replaceAll('_', '')}%';
    final sql = hanyaDiToko
        ? 'SELECT barang_id AS id FROM barang_toko WHERE cabang_id = ? AND (nama LIKE ? OR barcode LIKE ?)'
            ' ORDER BY nama LIMIT ?'
        : 'SELECT id FROM barang WHERE aktif = 1 AND (nama LIKE ? OR barcode LIKE ?) ORDER BY nama LIMIT ?';
    final param = hanyaDiToko ? [cabangId, pola, '$k%', batas] : [pola, '$k%', batas];
    return _db.pilih(sql, param).map((r) => detail(r['id'] as String, cabangId)).whereType<DetailBarang>().toList();
  }

  /// Semua barang yang dijual di toko ini dengan stok (halaman Produk & stok).
  List<DetailBarang> daftarToko(String cabangId, {String kata = ''}) => cari(kata, cabangId, batas: 5000);

  /// Barang dengan stok ≤ stok minimum.
  List<DetailBarang> stokMenipis(String cabangId) => _db
      .pilih(
        'SELECT bt.barang_id AS id FROM barang_toko bt'
        ' LEFT JOIN stok_sekarang s ON s.barang_id = bt.barang_id AND s.cabang_id = bt.cabang_id'
        ' WHERE bt.cabang_id = ? AND bt.stok_minimum > 0 AND IFNULL(s.stok, 0) <= bt.stok_minimum'
        ' ORDER BY IFNULL(s.stok, 0)',
        [cabangId],
      )
      .map((r) => detail(r['id'] as String, cabangId))
      .whereType<DetailBarang>()
      .toList();

  void aturStokMinimum(String barangId, String cabangId, int minimum, {required String olehId}) => _db.transaksi(() {
        _db.jalankan('UPDATE barang_cabang SET stok_minimum = ?, updated_at = ? WHERE barang_id = ? AND cabang_id = ?',
            [minimum < 0 ? 0 : minimum, _db.sekarangIso(), barangId, cabangId]);
        _db.outbox('barang_cabang', '$cabangId|$barangId',
            isi: Map<String, Object?>.from(_db.satu(
                'SELECT * FROM barang_cabang WHERE barang_id = ? AND cabang_id = ?', [barangId, cabangId])!));
        _db.log(cabangId: cabangId, penggunaId: olehId, aksi: 'atur_stok_minimum', detail: {'barang_id': barangId, 'minimum': minimum});
      });
}
