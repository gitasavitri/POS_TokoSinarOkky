import 'dart:convert';

import 'package:pos_core/pos_core.dart';

import '../database.dart';
import '../model.dart';

class Ringkasan {
  const Ringkasan({
    required this.penjualanBersih,
    required this.jumlahTransaksi,
    required this.tunai,
    required this.nonTunai,
    required this.labaKotor,
    required this.jumlahBatal,
    required this.totalRetur,
  });

  /// Penjualan lunas dikurangi retur.
  final int penjualanBersih;
  final int jumlahTransaksi;
  final int tunai;
  final int nonTunai;
  final int labaKotor;
  final int jumlahBatal;
  final int totalRetur;

  int get rataRataStruk => jumlahTransaksi == 0 ? 0 : bagiBulat(penjualanBersih + totalRetur, jumlahTransaksi);
}

class BarisLog {
  const BarisLog({required this.waktu, required this.aksi, required this.oleh, this.penyetuju, required this.detail});
  final DateTime waktu;
  final String aksi;
  final String oleh;
  final String? penyetuju;
  final Map<String, Object?> detail;
}

/// Laporan penjualan toko ini (SPV & Admin).
class LaporanRepo {
  LaporanRepo(this._db);
  final DatabaseToko _db;

  /// [dari] inklusif, [sampai] eksklusif (UTC).
  Ringkasan ringkasan(String cabangId, DateTime dari, DateTime sampai) {
    final a = isoUtc(dari), b = isoUtc(sampai);
    final r = _db.satu(
      "SELECT COUNT(*) AS n, IFNULL(SUM(t.total), 0) AS total,"
      " IFNULL(SUM(CASE WHEN p.metode = 'tunai' THEN t.total ELSE 0 END), 0) AS tunai"
      ' FROM transaksi t JOIN pembayaran p ON p.transaksi_id = t.id'
      ' LEFT JOIN pembatalan x ON x.transaksi_id = t.id'
      ' WHERE t.cabang_id = ? AND t.created_at >= ? AND t.created_at < ? AND x.transaksi_id IS NULL',
      [cabangId, a, b],
    )!;
    final laba = _db.satu(
      'SELECT IFNULL(SUM((i.harga_satuan - i.hpp_satuan) * i.qty), 0) AS laba'
      ' FROM transaksi_item i JOIN transaksi t ON t.id = i.transaksi_id LEFT JOIN pembatalan x ON x.transaksi_id = t.id'
      ' WHERE t.cabang_id = ? AND t.created_at >= ? AND t.created_at < ? AND x.transaksi_id IS NULL',
      [cabangId, a, b],
    )!['laba']! as int;
    final retur = _db.satu(
      'SELECT IFNULL(SUM(r.total_kembali), 0) AS n,'
      ' IFNULL(SUM((SELECT SUM((i.harga_satuan - i.hpp_satuan) * ri.qty) FROM retur_item ri'
      '   JOIN transaksi_item i ON i.id = ri.transaksi_item_id WHERE ri.retur_id = r.id)), 0) AS laba'
      ' FROM retur r JOIN transaksi t ON t.id = r.transaksi_id'
      ' WHERE t.cabang_id = ? AND r.created_at >= ? AND r.created_at < ?',
      [cabangId, a, b],
    )!;
    final batal = _db.satu(
      'SELECT COUNT(*) AS n FROM pembatalan x JOIN transaksi t ON t.id = x.transaksi_id'
      ' WHERE t.cabang_id = ? AND x.created_at >= ? AND x.created_at < ?',
      [cabangId, a, b],
    )!['n']! as int;
    final total = r['total']! as int, tunai = r['tunai']! as int, totalRetur = retur['n']! as int;
    return Ringkasan(
      penjualanBersih: total - totalRetur,
      jumlahTransaksi: r['n']! as int,
      tunai: tunai,
      nonTunai: total - tunai,
      labaKotor: laba - (retur['laba']! as int),
      jumlahBatal: batal,
      totalRetur: totalRetur,
    );
  }

  List<BarisTransaksi> daftarTransaksi(
    String cabangId,
    DateTime dari,
    DateTime sampai, {
    String? kasirId,
    MetodeBayar? metode,
    int batas = 500,
  }) {
    final param = <Object?>[cabangId, isoUtc(dari), isoUtc(sampai)];
    var filter = '';
    if (kasirId != null) {
      filter += ' AND t.kasir_id = ?';
      param.add(kasirId);
    }
    if (metode != null) {
      filter += ' AND p.metode = ?';
      param.add(metode.kode);
    }
    param.add(batas);
    return _db
        .pilih(
          'SELECT t.id, t.no_transaksi, t.created_at, t.jumlah_barang, t.total, p.metode, u.nama AS kasir,'
          ' (x.transaksi_id IS NOT NULL) AS batal, EXISTS(SELECT 1 FROM retur r WHERE r.transaksi_id = t.id) AS retur'
          ' FROM transaksi t JOIN pembayaran p ON p.transaksi_id = t.id JOIN pengguna u ON u.id = t.kasir_id'
          ' LEFT JOIN pembatalan x ON x.transaksi_id = t.id'
          ' WHERE t.cabang_id = ? AND t.created_at >= ? AND t.created_at < ?$filter'
          ' ORDER BY t.created_at DESC LIMIT ?',
          param,
        )
        .map((r) => BarisTransaksi(
              id: r['id'] as String,
              noTransaksi: r['no_transaksi'] as String,
              waktu: DateTime.parse(r['created_at'] as String),
              kasir: r['kasir'] as String,
              jumlahBarang: r['jumlah_barang'] as int,
              total: r['total'] as int,
              metode: MetodeBayar.dariKode(r['metode'] as String),
              dibatalkan: r['batal'] == 1,
              adaRetur: r['retur'] == 1,
            ))
        .toList();
  }

  /// Penjualan per hari WIB dalam rentang (untuk grafik). Kunci = awal hari WIB (UTC).
  Map<DateTime, int> penjualanPerHari(String cabangId, DateTime dari, DateTime sampai) {
    final hasil = <DateTime, int>{};
    for (var h = awalHariWibUtc(dari); h.isBefore(sampai); h = h.add(const Duration(days: 1))) {
      hasil[h] = 0;
    }
    for (final r in _db.pilih(
      'SELECT t.created_at, t.total FROM transaksi t LEFT JOIN pembatalan x ON x.transaksi_id = t.id'
      ' WHERE t.cabang_id = ? AND t.created_at >= ? AND t.created_at < ? AND x.transaksi_id IS NULL',
      [cabangId, isoUtc(dari), isoUtc(sampai)],
    )) {
      final k = awalHariWibUtc(DateTime.parse(r['created_at'] as String));
      hasil[k] = (hasil[k] ?? 0) + (r['total'] as int);
    }
    return hasil;
  }

  List<({String nama, String satuan, int qty, int omzet})> terlaris(String cabangId, DateTime dari, DateTime sampai,
          {int batas = 10}) =>
      _db
          .pilih(
            'SELECT i.nama_barang, b.satuan, SUM(i.qty) AS qty, SUM(i.subtotal) AS omzet'
            ' FROM transaksi_item i JOIN transaksi t ON t.id = i.transaksi_id JOIN barang b ON b.id = i.barang_id'
            ' LEFT JOIN pembatalan x ON x.transaksi_id = t.id'
            ' WHERE t.cabang_id = ? AND t.created_at >= ? AND t.created_at < ? AND x.transaksi_id IS NULL'
            ' GROUP BY i.barang_id ORDER BY qty DESC LIMIT ?',
            [cabangId, isoUtc(dari), isoUtc(sampai), batas],
          )
          .map((r) => (
                nama: r['nama_barang'] as String,
                satuan: r['satuan'] as String,
                qty: r['qty'] as int,
                omzet: r['omzet'] as int,
              ))
          .toList();

  List<BarisLog> log(String cabangId, DateTime dari, DateTime sampai, {int batas = 300}) => _db
      .pilih(
        'SELECT l.*, u.nama AS oleh, s.nama AS penyetuju FROM log_aktivitas l'
        ' LEFT JOIN pengguna u ON u.id = l.pengguna_id LEFT JOIN pengguna s ON s.id = l.disetujui_oleh'
        ' WHERE (l.cabang_id = ? OR l.cabang_id IS NULL) AND l.created_at >= ? AND l.created_at < ?'
        ' ORDER BY l.created_at DESC LIMIT ?',
        [cabangId, isoUtc(dari), isoUtc(sampai), batas],
      )
      .map((r) => BarisLog(
            waktu: DateTime.parse(r['created_at'] as String),
            aksi: r['aksi'] as String,
            oleh: (r['oleh'] as String?) ?? '-',
            penyetuju: r['penyetuju'] as String?,
            detail: Map<String, Object?>.from(jsonDecode(r['detail'] as String) as Map),
          ))
      .toList();

  /// Hal yang perlu dicek SPV/Admin: pembatalan, akun terkunci, koreksi menunggu, perubahan harga, selisih kas.
  ({int batal, int terkunci, int koreksiMenunggu, int ubahHarga, int selisihKas, int shiftMenunggu}) perluDicek(
      String cabangId, DateTime dari, DateTime sampai) {
    int n(String sql, List<Object?> p) => _db.satu(sql, p)!['n']! as int;
    final a = isoUtc(dari), b = isoUtc(sampai);
    return (
      batal: n(
          'SELECT COUNT(*) AS n FROM pembatalan x JOIN transaksi t ON t.id = x.transaksi_id'
          ' WHERE t.cabang_id = ? AND x.created_at >= ? AND x.created_at < ?',
          [cabangId, a, b]),
      terkunci: n('SELECT COUNT(*) AS n FROM pengguna WHERE cabang_id = ? AND terkunci = 1 AND aktif = 1', [cabangId]),
      koreksiMenunggu: n(
          "SELECT COUNT(*) AS n FROM koreksi_barang_masuk k JOIN barang_masuk_item i ON i.id = k.barang_masuk_item_id"
          " JOIN barang_masuk bm ON bm.id = i.barang_masuk_id WHERE bm.cabang_id = ? AND k.status = 'menunggu'",
          [cabangId]),
      ubahHarga: n(
          "SELECT COUNT(*) AS n FROM harga_jual WHERE cabang_id = ? AND sumber = 'ubah_harga' AND created_at >= ? AND created_at < ?",
          [cabangId, a, b]),
      selisihKas: n(
          'SELECT COUNT(*) AS n FROM shift_tutup st JOIN shift s ON s.id = st.shift_id'
          ' WHERE s.cabang_id = ? AND st.selisih <> 0 AND st.ditutup_pada >= ? AND st.ditutup_pada < ?',
          [cabangId, a, b]),
      // Tidak dibatasi tanggal: amplop dari kemarin yang belum dihitung tetap harus terlihat.
      shiftMenunggu: n(
          'SELECT COUNT(*) AS n FROM shift_belum_dihitung b LEFT JOIN shift_tutup t ON t.shift_id = b.shift_id'
          ' WHERE b.cabang_id = ? AND t.shift_id IS NULL',
          [cabangId]),
    );
  }

  /// Ekspor CSV (dibuka di Excel). Pemisah titik koma supaya cocok dengan Excel berbahasa Indonesia.
  String csvTransaksi(List<BarisTransaksi> daftar) {
    String sel(Object? v) {
      final s = '$v';
      return s.contains(';') || s.contains('"') ? '"${s.replaceAll('"', '""')}"' : s;
    }

    final b = StringBuffer('Tanggal;Jam;No transaksi;Kasir;Jumlah barang;Cara bayar;Total;Status\n');
    for (final t in daftar) {
      b.writeln([
        formatTanggal(t.waktu),
        formatJam(t.waktu),
        t.noTransaksi,
        t.kasir,
        t.jumlahBarang,
        t.metode.label,
        t.total,
        t.status,
      ].map(sel).join(';'));
    }
    return b.toString();
  }
}
