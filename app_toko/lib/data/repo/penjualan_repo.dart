import 'package:pos_core/pos_core.dart';

import '../database.dart';
import '../model.dart';

class HasilSimpanTransaksi {
  const HasilSimpanTransaksi({required this.transaksiId, required this.noTransaksi, required this.struk});
  final String transaksiId;
  final String noTransaksi;
  final DataStruk struk;
}

/// Shift kasir, simpan transaksi, pembatalan, retur, struk ulang.
class PenjualanRepo {
  PenjualanRepo(this._db);
  final DatabaseToko _db;

  // ---------------------------------------------------------------- shift

  Shift? shiftAktif(String kasirId) {
    final r = _db.satu(
      'SELECT s.* FROM shift s LEFT JOIN shift_tutup t ON t.shift_id = s.id'
      ' WHERE s.kasir_id = ? AND t.shift_id IS NULL ORDER BY s.dibuka_pada DESC LIMIT 1',
      [kasirId],
    );
    return r == null ? null : _shift(r);
  }

  Shift _shift(Map<String, Object?> r) => Shift(
        id: r['id']! as String,
        kasirId: r['kasir_id']! as String,
        modalAwal: r['modal_awal']! as int,
        dibukaPada: DateTime.parse(r['dibuka_pada']! as String),
      );

  Shift bukaShift({required String cabangId, required String kasirId, required int modalAwal}) {
    if (modalAwal < 0) throw ArgumentError('Modal awal tidak boleh minus');
    final ada = shiftAktif(kasirId);
    if (ada != null) return ada;
    final id = buatId();
    final t = _db.sekarangIso();
    _db.transaksi(() {
      _db.jalankan('INSERT INTO shift (id, cabang_id, kasir_id, modal_awal, dibuka_pada) VALUES (?,?,?,?,?)',
          [id, cabangId, kasirId, modalAwal, t]);
      _db.outbox('shift', id);
      _db.log(cabangId: cabangId, penggunaId: kasirId, aksi: 'buka_shift', detail: {'modal_awal': modalAwal});
    });
    return shiftAktif(kasirId)!;
  }

  RingkasanShift ringkasanShift(String shiftId) {
    final s = _shift(_db.satu('SELECT * FROM shift WHERE id = ?', [shiftId])!);
    final r = _db.satu(
      "SELECT COUNT(*) AS n,"
      " IFNULL(SUM(CASE WHEN p.metode = 'tunai' THEN t.total ELSE 0 END), 0) AS tunai,"
      " IFNULL(SUM(CASE WHEN p.metode <> 'tunai' THEN t.total ELSE 0 END), 0) AS non_tunai"
      ' FROM transaksi t JOIN pembayaran p ON p.transaksi_id = t.id'
      ' LEFT JOIN pembatalan b ON b.transaksi_id = t.id'
      ' WHERE t.shift_id = ? AND b.transaksi_id IS NULL',
      [shiftId],
    )!;
    // Retur dibayar tunai dari laci kasir, dicatat di shift yang aktif saat retur (lewat waktu & cabang).
    final cabangId = _db.satu('SELECT cabang_id FROM shift WHERE id = ?', [shiftId])!['cabang_id'];
    final ditutup = _db.satu('SELECT ditutup_pada FROM shift_tutup WHERE shift_id = ?', [shiftId])?['ditutup_pada'];
    final retur = _db.satu(
      'SELECT IFNULL(SUM(r.total_kembali), 0) AS n FROM retur r JOIN transaksi t ON t.id = r.transaksi_id'
      ' WHERE t.cabang_id = ? AND r.created_at >= ? AND r.created_at <= ?',
      [cabangId, isoUtc(s.dibukaPada), ditutup ?? '9999'],
    )!;
    return RingkasanShift(
      shift: s,
      jumlahTransaksi: r['n']! as int,
      penjualanTunai: r['tunai']! as int,
      penjualanNonTunai: r['non_tunai']! as int,
      returTunai: retur['n']! as int,
    );
  }

  /// Tutup shift: kasir menghitung uang tunai, sistem mencatat selisihnya.
  RingkasanShift tutupShift({required String shiftId, required int kasDihitung, required String olehId}) {
    final ring = ringkasanShift(shiftId);
    final selisih = kasDihitung - ring.kasSistem;
    final cabangId = _db.satu('SELECT cabang_id FROM shift WHERE id = ?', [shiftId])!['cabang_id'] as String;
    _db.transaksi(() {
      _db.jalankan(
        'INSERT INTO shift_tutup (shift_id, kas_dihitung, kas_sistem, selisih, ditutup_oleh, ditutup_pada)'
        ' VALUES (?,?,?,?,?,?)',
        [shiftId, kasDihitung, ring.kasSistem, selisih, olehId, _db.sekarangIso()],
      );
      _db.outbox('shift_tutup', shiftId, kolomKunci: 'shift_id');
      _db.log(cabangId: cabangId, penggunaId: olehId, aksi: 'tutup_shift', detail: {
        'kas_dihitung': kasDihitung,
        'kas_sistem': ring.kasSistem,
        'selisih': selisih,
      });
    });
    return ring;
  }

  // ---------------------------------------------------------------- transaksi

  /// Nomor yang akan dipakai transaksi berikutnya (untuk ditampilkan di layar kasir).
  String nomorBerikutnya(InfoCabang cabang) => _nomorBerikutnya(cabang, _db.sekarang());

  String _nomorBerikutnya(InfoCabang cabang, DateTime waktu) {
    final awalan = awalanNomorTransaksi(cabang.kode, waktu);
    final r = _db.satu(
      'SELECT no_transaksi FROM transaksi WHERE cabang_id = ? AND no_transaksi LIKE ? ORDER BY no_transaksi DESC LIMIT 1',
      [cabang.id, '$awalan%'],
    );
    final urut = r == null ? 1 : int.parse((r['no_transaksi']! as String).substring(awalan.length)) + 1;
    return nomorTransaksi(kodeCabang: cabang.kode, waktu: waktu, urut: urut);
  }

  /// Simpan transaksi lengkap dalam SATU transaksi database: transaksi, item, pembayaran,
  /// mutasi stok, log, outbox. Gagal di tengah → tidak ada yang tersimpan.
  HasilSimpanTransaksi simpan({
    required InfoCabang cabang,
    required Pengguna kasir,
    required Shift shift,
    required Keranjang keranjang,
    required MetodeBayar metode,
    int uangDiterima = 0,
    String? noReferensi,
  }) {
    if (keranjang.kosong) throw ArgumentError('Keranjang kosong');
    final total = keranjang.total;
    final bayar = cekPembayaran(metode: metode, total: total, uangDiterima: uangDiterima, noReferensi: noReferensi);
    if (!bayar.boleh) throw ArgumentError(bayar.pesan);

    return _db.transaksi(() {
      final waktu = _db.sekarang();
      final t = isoUtc(waktu);
      final id = buatId();
      final no = _nomorBerikutnya(cabang, waktu);
      _db.jalankan(
        'INSERT INTO transaksi (id, cabang_id, no_transaksi, shift_id, kasir_id, total, jumlah_barang, created_at)'
        ' VALUES (?,?,?,?,?,?,?,?)',
        [id, cabang.id, no, shift.id, kasir.id, total, keranjang.jumlahBarang, t],
      );
      _db.outbox('transaksi', id);
      final itemStruk = <ItemStruk>[];
      for (final b in keranjang.baris) {
        final h = b.harga;
        final itemId = buatId();
        _db.jalankan(
          'INSERT INTO transaksi_item (id, transaksi_id, barang_id, nama_barang, qty, harga_satuan, harga_grosir,'
          ' hpp_satuan, subtotal) VALUES (?,?,?,?,?,?,?,?,?)',
          [itemId, id, b.barang.id, b.barang.nama, b.qty, h.hargaSatuan, h.isGrosir ? 1 : 0, b.barang.hpp, h.subtotal],
        );
        _db.outbox('transaksi_item', itemId);
        final mutasiId = buatId();
        _db.jalankan(
          "INSERT INTO mutasi_stok (id, cabang_id, barang_id, jumlah, jenis, ref_id, dibuat_oleh, created_at)"
          " VALUES (?,?,?,?,'jual',?,?,?)",
          [mutasiId, cabang.id, b.barang.id, -b.qty, id, kasir.id, t],
        );
        _db.outbox('mutasi_stok', mutasiId);
        itemStruk.add(ItemStruk(nama: b.barang.nama, qty: b.qty, hargaSatuan: h.hargaSatuan, isGrosir: h.isGrosir));
      }
      final bayarId = buatId();
      _db.jalankan(
        'INSERT INTO pembayaran (id, transaksi_id, metode, jumlah_diterima, kembalian, no_referensi, created_at)'
        ' VALUES (?,?,?,?,?,?,?)',
        [bayarId, id, metode.kode, bayar.diterima, bayar.kembalian, noReferensi?.trim(), t],
      );
      _db.outbox('pembayaran', bayarId);
      return HasilSimpanTransaksi(
        transaksiId: id,
        noTransaksi: no,
        struk: DataStruk(
          namaToko: cabang.namaToko,
          namaCabang: cabang.nama,
          alamat: cabang.alamat,
          noTransaksi: no,
          waktu: waktu,
          namaKasir: kasir.nama,
          item: itemStruk,
          metode: metode,
          diterima: bayar.diterima,
          kembalian: bayar.kembalian,
          noReferensi: noReferensi?.trim(),
          pesanBawah: cabang.pesanStruk,
        ),
      );
    });
  }

  String? idDariNomor(String cabangId, String noAtauBarcode) {
    final no = noAtauBarcode.toUpperCase().startsWith('TRX-') ? noAtauBarcode.trim().toUpperCase() : noTransaksiDariBarcode(noAtauBarcode);
    if (no == null) return null;
    return _db.satu('SELECT id FROM transaksi WHERE cabang_id = ? AND no_transaksi = ?', [cabangId, no])?['id'] as String?;
  }

  bool sudahDibatalkan(String transaksiId) =>
      _db.satu('SELECT 1 FROM pembatalan WHERE transaksi_id = ?', [transaksiId]) != null;

  /// Batalkan transaksi yang sudah dibayar. Transaksi asli tidak diubah; stok dikembalikan.
  void batalkan({
    required String transaksiId,
    required String alasan,
    required String dimintaOleh,
    required String disetujuiOleh,
  }) {
    if (alasan.trim().isEmpty) throw ArgumentError('Alasan wajib diisi');
    _db.transaksi(() {
      if (sudahDibatalkan(transaksiId)) throw StateError('Transaksi sudah dibatalkan');
      if (_db.satu('SELECT 1 FROM retur WHERE transaksi_id = ?', [transaksiId]) != null) {
        throw StateError('Transaksi sudah ada returnya, tidak bisa dibatalkan');
      }
      final tr = _db.satu('SELECT cabang_id, no_transaksi, total FROM transaksi WHERE id = ?', [transaksiId]);
      if (tr == null) throw StateError('Transaksi tidak ditemukan');
      final t = _db.sekarangIso();
      _db.jalankan(
        'INSERT INTO pembatalan (transaksi_id, alasan, diminta_oleh, disetujui_oleh, created_at) VALUES (?,?,?,?,?)',
        [transaksiId, alasan.trim(), dimintaOleh, disetujuiOleh, t],
      );
      _db.outbox('pembatalan', transaksiId, kolomKunci: 'transaksi_id');
      for (final i in _db.pilih('SELECT barang_id, qty FROM transaksi_item WHERE transaksi_id = ?', [transaksiId])) {
        final mid = buatId();
        _db.jalankan(
          "INSERT INTO mutasi_stok (id, cabang_id, barang_id, jumlah, jenis, ref_id, dibuat_oleh, created_at)"
          " VALUES (?,?,?,?,'batal_jual',?,?,?)",
          [mid, tr['cabang_id'], i['barang_id'], i['qty'], transaksiId, disetujuiOleh, t],
        );
        _db.outbox('mutasi_stok', mid);
      }
      _db.log(
        cabangId: tr['cabang_id'] as String,
        penggunaId: dimintaOleh,
        disetujuiOleh: disetujuiOleh,
        aksi: 'batal_transaksi',
        detail: {'no_transaksi': tr['no_transaksi'], 'total': tr['total'], 'alasan': alasan.trim()},
      );
    });
  }

  /// Data struk untuk cetak ulang.
  DataStruk? struk(String transaksiId, InfoCabang cabang) {
    final t = _db.satu(
      'SELECT t.*, p.metode, p.jumlah_diterima, p.kembalian, p.no_referensi, u.nama AS kasir'
      ' FROM transaksi t JOIN pembayaran p ON p.transaksi_id = t.id JOIN pengguna u ON u.id = t.kasir_id'
      ' WHERE t.id = ?',
      [transaksiId],
    );
    if (t == null) return null;
    final item = _db
        .pilih('SELECT nama_barang, qty, harga_satuan, harga_grosir FROM transaksi_item WHERE transaksi_id = ? ORDER BY rowid',
            [transaksiId])
        .map((r) => ItemStruk(
              nama: r['nama_barang'] as String,
              qty: r['qty'] as int,
              hargaSatuan: r['harga_satuan'] as int,
              isGrosir: r['harga_grosir'] == 1,
            ))
        .toList();
    return DataStruk(
      namaToko: cabang.namaToko,
      namaCabang: cabang.nama,
      alamat: cabang.alamat,
      noTransaksi: t['no_transaksi'] as String,
      waktu: DateTime.parse(t['created_at'] as String),
      namaKasir: t['kasir'] as String,
      item: item,
      metode: MetodeBayar.dariKode(t['metode'] as String),
      diterima: t['jumlah_diterima'] as int,
      kembalian: t['kembalian'] as int,
      noReferensi: t['no_referensi'] as String?,
      pesanBawah: cabang.pesanStruk,
      dibatalkan: sudahDibatalkan(transaksiId),
      cetakUlang: true,
    );
  }

  /// Item transaksi untuk retur: (id item, nama, qty dibeli, harga, qty sudah diretur).
  List<({String itemId, String barangId, String nama, int qty, int harga, int sudahRetur})> itemUntukRetur(
          String transaksiId) =>
      _db
          .pilih(
            'SELECT i.id, i.barang_id, i.nama_barang, i.qty, i.harga_satuan,'
            ' IFNULL((SELECT SUM(ri.qty) FROM retur_item ri WHERE ri.transaksi_item_id = i.id), 0) AS sudah'
            ' FROM transaksi_item i WHERE i.transaksi_id = ? ORDER BY i.rowid',
            [transaksiId],
          )
          .map((r) => (
                itemId: r['id'] as String,
                barangId: r['barang_id'] as String,
                nama: r['nama_barang'] as String,
                qty: r['qty'] as int,
                harga: r['harga_satuan'] as int,
                sudahRetur: r['sudah'] as int,
              ))
          .toList();

  /// Retur (SPV/Admin). [qtyPerItem]: id item → jumlah diretur. Uang dikembalikan tunai.
  int retur({
    required String transaksiId,
    required Map<String, int> qtyPerItem,
    required bool kembaliKeStok,
    required String alasan,
    required String olehId,
  }) {
    if (alasan.trim().isEmpty) throw ArgumentError('Alasan wajib diisi');
    final dipilih = {for (final e in qtyPerItem.entries) if (e.value > 0) e.key: e.value};
    if (dipilih.isEmpty) throw ArgumentError('Pilih barang yang diretur');
    return _db.transaksi(() {
      if (sudahDibatalkan(transaksiId)) throw StateError('Transaksi sudah dibatalkan');
      final item = {for (final i in itemUntukRetur(transaksiId)) i.itemId: i};
      final cabangId = _db.satu('SELECT cabang_id FROM transaksi WHERE id = ?', [transaksiId])!['cabang_id'] as String;
      var total = 0;
      for (final e in dipilih.entries) {
        final i = item[e.key];
        if (i == null) throw ArgumentError('Barang tidak ada di transaksi ini');
        if (e.value > i.qty - i.sudahRetur) throw ArgumentError('Jumlah retur ${i.nama} melebihi yang dibeli');
        total += e.value * i.harga;
      }
      final id = buatId();
      final t = _db.sekarangIso();
      _db.jalankan(
        'INSERT INTO retur (id, transaksi_id, alasan, total_kembali, diproses_oleh, created_at) VALUES (?,?,?,?,?,?)',
        [id, transaksiId, alasan.trim(), total, olehId, t],
      );
      _db.outbox('retur', id);
      for (final e in dipilih.entries) {
        final rid = buatId();
        _db.jalankan(
          'INSERT INTO retur_item (id, retur_id, transaksi_item_id, qty, kembali_ke_stok) VALUES (?,?,?,?,?)',
          [rid, id, e.key, e.value, kembaliKeStok ? 1 : 0],
        );
        _db.outbox('retur_item', rid);
        if (kembaliKeStok) {
          final mid = buatId();
          _db.jalankan(
            "INSERT INTO mutasi_stok (id, cabang_id, barang_id, jumlah, jenis, ref_id, dibuat_oleh, created_at)"
            " VALUES (?,?,?,?,'retur',?,?,?)",
            [mid, cabangId, item[e.key]!.barangId, e.value, id, olehId, t],
          );
          _db.outbox('mutasi_stok', mid);
        }
      }
      _db.log(cabangId: cabangId, penggunaId: olehId, aksi: 'retur', detail: {
        'transaksi_id': transaksiId,
        'total_kembali': total,
        'kembali_ke_stok': kembaliKeStok,
        'alasan': alasan.trim(),
      });
      return total;
    });
  }
}
