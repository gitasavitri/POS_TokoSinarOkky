import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:pos_core/pos_core.dart';

import '../data/database.dart';
import '../data/model.dart';
import '../data/repo/barang_masuk_repo.dart';
import '../data/repo/harga_repo.dart';
import '../data/repo/katalog_repo.dart';
import '../data/repo/laporan_repo.dart';
import '../data/repo/pengaturan_repo.dart';
import '../data/repo/pengguna_repo.dart';
import '../data/repo/penjualan_repo.dart';
import '../data/repo/setup_repo.dart';
import 'printer.dart';
import 'sinkron.dart';

/// Lama tidak dipakai sebelum keluar otomatis.
const batasDiam = Duration(minutes: 10);

/// Semua layanan aplikasi + sesi pengguna yang sedang masuk.
class Aplikasi extends ChangeNotifier {
  Aplikasi({required this.db, required this.printer, this.lokasiDatabase})
      : pengaturan = PengaturanRepo(db),
        pengguna = PenggunaRepo(db),
        katalog = KatalogRepo(db),
        penjualan = PenjualanRepo(db),
        barangMasuk = BarangMasukRepo(db),
        harga = HargaRepo(db),
        laporan = LaporanRepo(db),
        setup = SetupRepo(db),
        sinkron = LayananSinkron(db);

  final DatabaseToko db;
  final LayananPrinter printer;
  final String? lokasiDatabase;

  final PengaturanRepo pengaturan;
  final PenggunaRepo pengguna;
  final KatalogRepo katalog;
  final PenjualanRepo penjualan;
  final BarangMasukRepo barangMasuk;
  final HargaRepo harga;
  final LaporanRepo laporan;
  final SetupRepo setup;

  /// Kirim data ke Server Pusat & ambil harga/barang dari pusat (otomatis tiap menit kalau sudah didaftarkan).
  final LayananSinkron sinkron;

  Pengguna? _pengguna;
  Shift? _shift;
  Timer? _timerDiam;

  Pengguna? get penggunaAktif => _pengguna;
  Shift? get shiftAktif => _shift;
  bool get sudahDisiapkan => pengaturan.sudahDisiapkan;
  InfoCabang get cabang => pengaturan.infoCabang()!;

  Akses akses(Izin izin) => _pengguna == null ? Akses.tidak : aksesUntuk(_pengguna!.peran, izin);
  bool boleh(Izin izin) => akses(izin) == Akses.ya;

  void masuk(Pengguna p) {
    _pengguna = p;
    _shift = penjualan.shiftAktif(p.id);
    adaAktivitas();
    notifyListeners();
  }

  void keluar({String alasan = 'keluar'}) {
    final p = _pengguna;
    if (p != null) {
      db.transaksi(() => db.log(cabangId: p.cabangId, penggunaId: p.id, aksi: alasan));
    }
    _pengguna = null;
    _shift = null;
    _timerDiam?.cancel();
    notifyListeners();
  }

  void aturShift(Shift? s) {
    _shift = s;
    notifyListeners();
  }

  /// Dipanggil setiap ada sentuhan/ketikan. Setelah 10 menit diam → keluar otomatis.
  void adaAktivitas() {
    if (_pengguna == null) return;
    _timerDiam?.cancel();
    _timerDiam = Timer(batasDiam, () => keluar(alasan: 'keluar_otomatis'));
  }

  void segarkan() => notifyListeners();

  // ---------------------------------------------------------------- cetak

  String? get namaPrinter => pengaturan.ambil(PengaturanRepo.kPrinter) ?? _printerBawaanAman();

  String? _printerBawaanAman() {
    try {
      return printer.printerBawaan();
    } catch (_) {
      return null;
    }
  }

  bool get potongKertas => pengaturan.ambilBool(PengaturanRepo.kPotongKertas);
  bool get cetakOtomatis => pengaturan.ambilBool(PengaturanRepo.kCetakOtomatis, bawaan: true);
  int get salinanStruk => pengaturan.ambilInt(PengaturanRepo.kSalinanStruk, bawaan: 1).clamp(1, 3);

  /// Cetak byte ke printer yang dipilih. Mengembalikan pesan galat atau null kalau berhasil.
  Future<String?> kirimKePrinter(List<int> data, {int salinan = 1}) async {
    final nama = namaPrinter;
    if (nama == null) return 'Belum ada printer yang dipilih. Atur di Pengaturan.';
    try {
      for (var i = 0; i < salinan; i++) {
        await printer.cetak(nama, data is Uint8List ? data : Uint8List.fromList(data));
      }
      return null;
    } on PrinterGagal catch (e) {
      return e.pesan;
    } catch (e) {
      return 'Gagal mencetak: $e';
    }
  }

  Future<String?> cetakStrukTransaksi(DataStruk d, {bool ulang = false}) =>
      kirimKePrinter(cetakStruk(d, potongKertas: potongKertas), salinan: ulang ? 1 : salinanStruk);

  // ---------------------------------------------------------------- cadangan

  /// Salin database utuh ke [folder] memakai `VACUUM INTO` (aman walau aplikasi sedang jalan).
  String cadangkan(String folder) {
    final dir = Directory(folder)..createSync(recursive: true);
    final w = keWib(db.sekarang());
    String d2(int n) => n.toString().padLeft(2, '0');
    final nama = 'pos-${cabang.kode}-${w.year}${d2(w.month)}${d2(w.day)}-${d2(w.hour)}${d2(w.minute)}${d2(w.second)}.db';
    final tujuan = '${dir.path}${Platform.pathSeparator}$nama';
    db.jalankan('VACUUM INTO ?', [tujuan]);
    return tujuan;
  }
}

/// Akses [Aplikasi] dari widget mana pun: `Aplikasi.of(context)`.
class AplikasiScope extends InheritedNotifier<Aplikasi> {
  const AplikasiScope({super.key, required Aplikasi aplikasi, required super.child}) : super(notifier: aplikasi);

  static Aplikasi of(BuildContext context, {bool dengar = false}) {
    final s = dengar
        ? context.dependOnInheritedWidgetOfExactType<AplikasiScope>()
        : context.getInheritedWidgetOfExactType<AplikasiScope>();
    return s!.notifier!;
  }
}

extension AplikasiContext on BuildContext {
  Aplikasi get app => AplikasiScope.of(this);
}
