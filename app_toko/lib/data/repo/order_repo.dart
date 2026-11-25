import 'dart:convert';

import 'package:pos_core/pos_core.dart';

import '../database.dart';
import '../model.dart';
import 'pengaturan_repo.dart';

/// Satu barang di daftar kiri layar Order barang.
class BarangOrder {
  const BarangOrder({
    required this.id,
    required this.barcode,
    required this.nama,
    required this.satuan,
    required this.stok,
    required this.stokMinimum,
  });
  final String id;
  final String? barcode;
  final String nama;
  final String satuan;
  final int stok;
  final int stokMinimum;

  int get saran => saranOrder(stok: stok, stokMinimum: stokMinimum);
  bool get perlu => perluOrder(stok: stok, stokMinimum: stokMinimum);
  StatusStok get status => statusStok(stok: stok, stokMinimum: stokMinimum);

  BarisOrder keBaris() => BarisOrder(
        barangId: id,
        nama: nama,
        satuan: satuan,
        barcode: barcode,
        jumlah: jumlahAwalOrder(stok: stok, stokMinimum: stokMinimum),
        stok: stok,
        stokMinimum: stokMinimum,
      );
}

/// Order yang sudah disimpan (untuk surat pesanan PDF / Excel dan riwayat).
class OrderTersimpan {
  const OrderTersimpan({
    required this.id,
    required this.noOrder,
    required this.waktu,
    required this.tujuan,
    required this.tujuanTokoUtama,
    required this.catatan,
    required this.dibuatOleh,
    required this.peranPembuat,
    required this.baris,
  });
  final String id;
  final String noOrder;
  final DateTime waktu;

  /// Nama toko utama / supplier.
  final String tujuan;
  final bool tujuanTokoUtama;
  final String catatan;
  final String dibuatOleh;
  final String peranPembuat;
  final List<BarisOrder> baris;

  int get jumlahJenis => baris.length;
  int get totalJumlah => baris.fold(0, (s, b) => s + b.jumlah);
}

/// Order barang (revisi G): daftar barang + saran, draft per PC, simpan dengan nomor ORD-…, riwayat.
/// Belum dikirim ke Server Pusat (hanya log aktivitasnya).
class OrderRepo {
  OrderRepo(this._db) : _pengaturan = PengaturanRepo(_db);
  final DatabaseToko _db;
  final PengaturanRepo _pengaturan;

  static const kDraftOrder = 'draft_order';

  // ---------------------------------------------------------------- daftar barang

  /// Barang yang dijual di toko ini + stok + stok minimum. [hanyaPerlu] = filter "Perlu order saja".
  List<BarangOrder> daftarBarang(String cabangId, {String kata = '', bool hanyaPerlu = false}) {
    final k = kata.trim().replaceAll('%', '').replaceAll('_', '');
    final hasil = _db
        .pilih(
          'SELECT bt.barang_id, bt.barcode, bt.nama, bt.satuan, bt.stok_minimum, IFNULL(s.stok, 0) AS stok'
          ' FROM barang_toko bt LEFT JOIN stok_sekarang s ON s.barang_id = bt.barang_id AND s.cabang_id = bt.cabang_id'
          ' WHERE bt.cabang_id = ? AND (bt.nama LIKE ? OR bt.barcode LIKE ?)'
          ' ORDER BY bt.nama COLLATE NOCASE',
          [cabangId, '%$k%', '$k%'],
        )
        .map((r) => BarangOrder(
              id: r['barang_id'] as String,
              barcode: r['barcode'] as String?,
              nama: r['nama'] as String,
              satuan: r['satuan'] as String,
              stok: r['stok'] as int,
              stokMinimum: r['stok_minimum'] as int,
            ));
    return hanyaPerlu ? hasil.where((b) => b.perlu).toList() : hasil.toList();
  }

  /// Barang toko ini dengan barcode persis (scan di layar Order barang).
  BarangOrder? cariBarcode(String cabangId, String barcode) {
    final b = barcode.trim();
    if (b.isEmpty) return null;
    for (final x in daftarBarang(cabangId, kata: b)) {
      if (x.barcode == b) return x;
    }
    return null;
  }

  // ---------------------------------------------------------------- draft (disimpan per PC)

  void simpanDraft(DaftarOrder d) =>
      _pengaturan.simpan(kDraftOrder, d.kosong && d.catatan.isEmpty ? null : jsonEncode(d.keJson()));

  DaftarOrder? muatDraft() {
    final s = _pengaturan.ambil(kDraftOrder);
    if (s == null) return null;
    try {
      return DaftarOrder.dariJson(Map<String, Object?>.from(jsonDecode(s) as Map));
    } catch (_) {
      return null;
    }
  }

  void hapusDraft() => _pengaturan.simpan(kDraftOrder, null);

  // ---------------------------------------------------------------- simpan

  String _nomorBerikutnya(InfoCabang cabang, DateTime waktu) {
    final awalan = awalanNomorOrder(cabang.kode, waktu);
    final r = _db.satu(
      'SELECT no_order FROM order_barang WHERE cabang_id = ? AND no_order LIKE ? ORDER BY no_order DESC LIMIT 1',
      [cabang.id, '$awalan%'],
    );
    final urut = r == null ? 1 : int.parse((r['no_order']! as String).substring(awalan.length)) + 1;
    return nomorOrder(kodeCabang: cabang.kode, waktu: waktu, urut: urut);
  }

  /// Simpan order dengan nomor ORD-… baru. Stok tidak berubah (stok baru bertambah lewat Barang masuk).
  OrderTersimpan simpan({required InfoCabang cabang, required Pengguna oleh, required DaftarOrder order}) {
    if (aksesUntuk(oleh.peran, Izin.buatOrder) != Akses.ya) throw StateError('Tidak boleh membuat order');
    final salah = order.periksa();
    if (salah != null) throw ArgumentError(salah);
    final sup = _db.satu('SELECT id FROM supplier WHERE id = ? AND aktif = 1', [order.supplierId]);
    if (sup == null) throw ArgumentError('Tujuan order tidak ditemukan. Pilih ulang "Order ke".');
    final id = _db.transaksi(() {
      final waktu = _db.sekarang();
      final t = isoUtc(waktu);
      final no = _nomorBerikutnya(cabang, waktu);
      final id = buatId();
      _db.jalankan(
        'INSERT INTO order_barang (id, cabang_id, no_order, supplier_id, catatan, dibuat_oleh, created_at) VALUES (?,?,?,?,?,?,?)',
        [id, cabang.id, no, order.supplierId, order.catatan.trim(), oleh.id, t],
      );
      var urut = 1;
      for (final b in order.baris) {
        final barang = _db.satu('SELECT nama, satuan FROM barang WHERE id = ?', [b.barangId]);
        if (barang == null) throw ArgumentError('Barang "${b.nama}" tidak ditemukan');
        final stok = (_db.satu('SELECT stok FROM stok_sekarang WHERE cabang_id = ? AND barang_id = ?', [cabang.id, b.barangId])?['stok']
                as int?) ??
            0;
        _db.jalankan(
          'INSERT INTO order_barang_item (id, order_id, barang_id, nama_barang, satuan, jumlah, stok_saat_order, urut)'
          ' VALUES (?,?,?,?,?,?,?,?)',
          [buatId(), id, b.barangId, barang['nama'], barang['satuan'], b.jumlah, stok, urut++],
        );
      }
      _db.log(cabangId: cabang.id, penggunaId: oleh.id, aksi: 'buat_order', detail: {
        'order_id': id,
        'no_order': no,
        'supplier_id': order.supplierId,
        'jumlah_jenis': order.jumlahJenis,
        'total_jumlah': order.totalJumlah,
      });
      return id;
    });
    hapusDraft();
    return muat(id)!;
  }

  // ---------------------------------------------------------------- riwayat

  OrderTersimpan? muat(String id) {
    final r = _db.satu(
      'SELECT o.*, s.nama AS tujuan, s.jenis, u.nama AS oleh, u.peran FROM order_barang o'
      ' JOIN supplier s ON s.id = o.supplier_id JOIN pengguna u ON u.id = o.dibuat_oleh WHERE o.id = ?',
      [id],
    );
    if (r == null) return null;
    return OrderTersimpan(
      id: id,
      noOrder: r['no_order'] as String,
      waktu: DateTime.parse(r['created_at'] as String),
      tujuan: r['tujuan'] as String,
      tujuanTokoUtama: r['jenis'] == 'toko_utama',
      catatan: r['catatan'] as String,
      dibuatOleh: r['oleh'] as String,
      peranPembuat: Peran.dariKode(r['peran'] as String).label,
      baris: _db
          .pilih(
            'SELECT i.*, b.barcode, IFNULL(bc.stok_minimum, 0) AS stok_minimum FROM order_barang_item i'
            ' JOIN barang b ON b.id = i.barang_id'
            ' LEFT JOIN barang_cabang bc ON bc.barang_id = i.barang_id AND bc.cabang_id = ?'
            ' WHERE i.order_id = ? ORDER BY i.urut',
            [r['cabang_id'], id],
          )
          .map((i) => BarisOrder(
                barangId: i['barang_id'] as String,
                nama: i['nama_barang'] as String,
                satuan: i['satuan'] as String,
                barcode: i['barcode'] as String?,
                jumlah: i['jumlah'] as int,
                stok: i['stok_saat_order'] as int,
                stokMinimum: i['stok_minimum'] as int,
              ))
          .toList(),
    );
  }

  /// Order terbaru di toko ini.
  List<({String id, String noOrder, DateTime waktu, String tujuan, String oleh, int jumlahJenis, int totalJumlah})> riwayat(
    String cabangId, {
    int batas = 50,
  }) =>
      _db
          .pilih(
            'SELECT o.id, o.no_order, o.created_at, s.nama AS tujuan, u.nama AS oleh,'
            ' (SELECT COUNT(*) FROM order_barang_item i WHERE i.order_id = o.id) AS jenis,'
            ' (SELECT IFNULL(SUM(jumlah), 0) FROM order_barang_item i WHERE i.order_id = o.id) AS total'
            ' FROM order_barang o JOIN supplier s ON s.id = o.supplier_id JOIN pengguna u ON u.id = o.dibuat_oleh'
            ' WHERE o.cabang_id = ? ORDER BY o.created_at DESC, o.no_order DESC LIMIT ?',
            [cabangId, batas],
          )
          .map((r) => (
                id: r['id'] as String,
                noOrder: r['no_order'] as String,
                waktu: DateTime.parse(r['created_at'] as String),
                tujuan: r['tujuan'] as String,
                oleh: r['oleh'] as String,
                jumlahJenis: r['jenis'] as int,
                totalJumlah: r['total'] as int,
              ))
          .toList();
}
