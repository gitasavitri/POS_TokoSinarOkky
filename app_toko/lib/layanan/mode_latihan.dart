import 'package:flutter/foundation.dart';
import 'package:pos_core/pos_core.dart';

import '../data/database.dart';
import '../data/model.dart';
import '../data/repo/latihan_repo.dart';
import 'aplikasi.dart';

/// Pindah antara data asli dan MODE LATIHAN.
///
/// - Dinyalakan SPV/Admin dari layar masuk (PIN). Kasir lalu masuk seperti biasa dengan PIN-nya sendiri.
/// - Data latihan ada di file database terpisah; barang, harga, akun, dan stok disalin dari data asli saat
///   pertama kali dinyalakan (atau setelah "Hapus data latihan"). Data latihan tetap tersimpan sampai dihapus.
/// - Transaksi latihan tidak mengubah stok asli, tidak masuk laporan asli, dan tidak terkirim ke pusat
///   (database latihan tidak punya alamat server/token, sinkron & cadangan tidak dijalankan).
/// - Sementara mode latihan menyala, aplikasi asli tetap mengirim data ke pusat & mencadangkan di belakang.
/// - Aplikasi ditutup / listrik padam → saat dibuka lagi selalu kembali ke data asli.
class PengaturMode extends ChangeNotifier {
  PengaturMode({required this.asli, required this.bukaDatabaseLatihan, required this.hapusDatabaseLatihan}) {
    asli.pengaturMode = this;
  }

  final Aplikasi asli;

  /// Buka (atau buat) database latihan. File: pos_toko_latihan.db di folder data aplikasi.
  final DatabaseToko Function() bukaDatabaseLatihan;

  /// Hapus file database latihan (dipanggil saat database latihan sudah ditutup).
  final void Function() hapusDatabaseLatihan;

  Aplikasi? _latihan;

  /// Aplikasi yang sedang dipakai layar.
  Aplikasi get aktif => _latihan ?? asli;
  bool get latihanAktif => _latihan != null;

  /// Nyalakan mode latihan. [oleh] = SPV/Admin yang memasukkan PIN.
  void nyalakan(Pengguna oleh) {
    if (_latihan != null) return;
    if (!bolehMenyalakan(oleh)) throw StateError('Mode latihan hanya bisa dinyalakan SPV atau Admin');
    final db = bukaDatabaseLatihan();
    try {
      if (!LatihanRepo.adalahLatihan(db)) LatihanRepo.isiDariAsli(asli: asli.db, latihan: db, olehId: oleh.id);
    } catch (_) {
      db.tutup();
      rethrow;
    }
    asli.keluar(alasan: 'keluar');
    asli.db.transaksi(() => asli.db.log(cabangId: asli.cabang.id, penggunaId: oleh.id, aksi: 'mode_latihan_nyala'));
    _latihan = Aplikasi(
      db: db,
      printer: asli.printer,
      folderCadangan: asli.folderCadangan,
      catatan: asli.catatan,
      latihan: true,
    )..pengaturMode = this;
    notifyListeners();
  }

  /// Kembali ke data asli. Data latihan tetap tersimpan.
  void matikan() {
    final l = _latihan;
    if (l == null) return;
    l.keluar();
    _latihan = null;
    notifyListeners();
    // Tutup setelah layar berganti ke data asli.
    l.dispose();
    l.db.tutup();
    asli.db.transaksi(() => asli.db.log(cabangId: asli.cabang.id, penggunaId: null, aksi: 'mode_latihan_mati'));
  }

  /// Hapus semua data latihan. Kalau mode latihan sedang menyala, langsung diisi ulang dari data asli
  /// (transaksi, shift, dll. latihan hilang; barang, harga, stok disalin lagi).
  void hapusDataLatihan(Pengguna oleh) {
    final menyala = _latihan != null;
    if (menyala) matikan();
    hapusDatabaseLatihan();
    asli.db.transaksi(() => asli.db.log(cabangId: asli.cabang.id, penggunaId: oleh.id, aksi: 'hapus_data_latihan'));
    if (menyala) nyalakan(oleh);
  }

  static bool bolehMenyalakan(Pengguna p) => aksesUntuk(p.peran, Izin.nyalakanLatihan) == Akses.ya;
}
