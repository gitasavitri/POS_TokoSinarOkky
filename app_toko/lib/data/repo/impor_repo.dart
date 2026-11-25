import 'package:pos_core/pos_core.dart';

import '../database.dart';
import '../model.dart';
import 'barang_masuk_repo.dart';
import 'katalog_repo.dart';

/// Status satu baris di pratinjau impor.
enum StatusImpor {
  baru('Barang baru'),
  sudahAda('Sudah ada'),
  salah('Salah');

  const StatusImpor(this.label);
  final String label;
}

/// Satu baris pratinjau: data dari Excel + hasil pemeriksaan.
class BarisPratinjauImpor {
  BarisPratinjauImpor(this.sumber);
  final BarisImporStok sumber;

  /// Item barang masuk yang akan disimpan (null kalau baris ini salah sebelum bisa dibuat).
  DraftItemMasuk? item;
  final List<String> salah = [];

  /// Keterangan yang bukan kesalahan (mis. nama di file berbeda dengan nama barang yang tersimpan).
  final List<String> catatan = [];

  StatusImpor get status => salah.isNotEmpty ? StatusImpor.salah : (item!.barangBaru ? StatusImpor.baru : StatusImpor.sudahAda);
}

/// Hasil pemeriksaan seluruh file.
class PratinjauImpor {
  PratinjauImpor(this.baris, this.kategoriBelumAda);
  final List<BarisPratinjauImpor> baris;

  /// Nama kategori di file yang belum ada di program (bisa ditambahkan SPV/Admin dari layar pratinjau).
  final List<String> kategoriBelumAda;

  List<BarisPratinjauImpor> get benar => baris.where((b) => b.salah.isEmpty).toList();
  int get jumlahSalah => baris.length - benar.length;
  int get jumlahBaru => baris.where((b) => b.status == StatusImpor.baru).length;
  int get jumlahSudahAda => baris.where((b) => b.status == StatusImpor.sudahAda).length;
  int get totalJumlah => benar.fold(0, (s, b) => s + b.item!.jumlah);
  int get nilaiHpp => benar.fold(0, (s, b) => s + b.item!.jumlah * b.item!.hpp);
}

/// Impor stok awal dari Excel (revisi J). Hanya SPV/Admin. Hasilnya sama seperti barang masuk biasa:
/// stok (mutasi `masuk`), HPP, harga jual, barang baru otomatis masuk daftar barang toko, log, outbox.
class ImporRepo {
  ImporRepo(this._db)
      : _katalog = KatalogRepo(_db),
        _barangMasuk = BarangMasukRepo(_db);
  final DatabaseToko _db;
  final KatalogRepo _katalog;
  final BarangMasukRepo _barangMasuk;

  /// Nomor faktur bawaan untuk impor: `STOK-AWAL-261111`.
  String noFakturBawaan() => 'STOK-AWAL-${kodeTanggal(_db.sekarang())}';

  /// Satuan yang sudah dipakai barang di program (untuk petunjuk template).
  List<String> satuanDipakai() =>
      _db.pilih('SELECT DISTINCT satuan FROM barang WHERE aktif = 1 ORDER BY satuan').map((r) => r['satuan'] as String).toList();

  /// Cocokkan baris Excel dengan barang & kategori yang ada, lalu periksa seperti Barang masuk.
  PratinjauImpor periksa(List<BarisImporStok> data, String cabangId) {
    final kategori = {for (final k in _katalog.kategori()) k.nama.toLowerCase(): k.id};
    final belumAda = <String, String>{}; // huruf kecil → nama seperti di file
    final hasil = <BarisPratinjauImpor>[];
    for (final s in data) {
      final b = BarisPratinjauImpor(s)..salah.addAll(s.salah);
      hasil.add(b);
      DetailBarang? ada;
      if (s.barcode.isNotEmpty) {
        ada = _katalog.cariBarcode(s.barcode, cabangId);
      } else if (s.nama.isNotEmpty) {
        // Tanpa barcode: cocokkan nama persis (huruf besar/kecil diabaikan), hanya kalau tepat satu barang.
        final r = _db.pilih('SELECT id FROM barang WHERE barcode IS NULL AND nama = ? COLLATE NOCASE LIMIT 2', [s.nama]);
        if (r.length == 1) ada = _katalog.detail(r.first['id'] as String, cabangId);
      }
      if (ada != null) {
        final it = _barangMasuk.itemDariBarang(ada);
        if (s.nama.isNotEmpty && s.nama.toLowerCase() != ada.nama.toLowerCase()) {
          b.catatan.add('Barcode sudah dipakai "${ada.nama}". Nama di file tidak dipakai.');
        }
        it.jumlah = s.jumlah ?? 0;
        it.hpp = s.hpp ?? 0;
        it.hargaJual = s.hargaJual ?? 0;
        b.item = it;
      } else {
        if (s.nama.isEmpty) b.salah.add('Nama barang wajib diisi untuk barang baru.');
        if (s.satuan.isEmpty) b.salah.add('Satuan wajib diisi untuk barang baru.');
        var kategoriId = '';
        if (s.kategori.isEmpty) {
          b.salah.add('Kategori wajib diisi untuk barang baru.');
        } else {
          kategoriId = kategori[s.kategori.toLowerCase()] ?? '';
          if (kategoriId.isEmpty) {
            belumAda.putIfAbsent(s.kategori.toLowerCase(), () => s.kategori);
            b.salah.add('Kategori "${s.kategori}" belum ada.');
          }
        }
        b.item = DraftItemMasuk(
          barcode: s.barcode,
          nama: s.nama,
          kategoriId: kategoriId,
          satuan: s.satuan,
          jumlah: s.jumlah ?? 0,
          hpp: s.hpp ?? 0,
          hargaJual: s.hargaJual ?? 0,
        );
      }
    }

    // Pemeriksaan yang sama dengan Barang masuk (barcode kembar, harga grosir, dst.) untuk baris yang belum salah.
    final cek = hasil.where((b) => b.salah.isEmpty).toList();
    final salahBm = _barangMasuk.periksa(DraftBarangMasuk(item: [for (final b in cek) b.item!]));
    for (final e in salahBm.entries) {
      final b = cek[e.key];
      for (final p in e.value) {
        // "no. N" dari Barang masuk = urutan di daftar; ganti dengan nomor baris Excel.
        b.salah.add(p.replaceAllMapped(RegExp(r'no\. (\d+)'), (m) => 'baris Excel ${cek[int.parse(m[1]!) - 1].sumber.nomorBaris}'));
      }
    }
    return PratinjauImpor(hasil, belumAda.values.toList());
  }

  /// Tambahkan kategori yang belum ada (dari layar pratinjau). Hanya SPV/Admin.
  void tambahKategori(List<String> nama, {required String cabangId, required Pengguna oleh}) {
    if (aksesUntuk(oleh.peran, Izin.imporStokAwal) != Akses.ya) throw StateError('Hanya SPV atau Admin');
    _db.transaksi(() {
      for (final n in nama) {
        if (_db.satu('SELECT 1 FROM kategori WHERE nama = ? COLLATE NOCASE', [n.trim()]) == null) {
          _katalog.tambahKategori(n, cabangId: cabangId, olehId: oleh.id);
        }
      }
    });
  }

  /// Simpan baris yang benar sebagai satu barang masuk (terkirim & terkunci). Baris salah dilewati.
  /// Mengembalikan id barang_masuk.
  String simpan({
    required InfoCabang cabang,
    required Pengguna oleh,
    required PratinjauImpor pratinjau,
    required String supplierId,
    required String noFaktur,
  }) {
    if (aksesUntuk(oleh.peran, Izin.imporStokAwal) != Akses.ya) throw StateError('Impor stok awal hanya untuk SPV atau Admin');
    final benar = pratinjau.benar;
    if (benar.isEmpty) throw ArgumentError('Tidak ada baris yang bisa disimpan');
    return _db.transaksi(() {
      final id = _barangMasuk.kirim(
        cabang: cabang,
        oleh: oleh,
        draft: DraftBarangMasuk(supplierId: supplierId, noFaktur: noFaktur, item: [for (final b in benar) b.item!]),
      );
      _db.log(cabangId: cabang.id, penggunaId: oleh.id, aksi: 'impor_stok_awal', detail: {
        'barang_masuk_id': id,
        'no_faktur': noFaktur.trim(),
        'baris_disimpan': benar.length,
        'baris_dilewati': pratinjau.jumlahSalah,
        'barang_baru': pratinjau.jumlahBaru,
      });
      return id;
    });
  }
}
