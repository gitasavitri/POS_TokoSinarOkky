import 'dart:io';

import 'package:pos_core/pos_core.dart';
import 'package:sqlite3/sqlite3.dart';

import '../data/database.dart';

/// Cocokkan PIN SPV/Admin dengan akun di file database [path] (dibaca saja). Dipakai di layar pemulihan,
/// sebelum database utama bisa dibuka.
Future<bool> pinPenyetujuCocok(String path, String pin) async {
  Database? db;
  try {
    db = sqlite3.open(path, mode: OpenMode.readOnly);
    final hash = db
        .select("SELECT pin_hash FROM pengguna WHERE peran IN ('spv','admin') AND aktif = 1 AND terkunci = 0 AND pin_hash IS NOT NULL")
        .map((r) => r['pin_hash'] as String)
        .toList();
    db.close();
    db = null;
    for (final h in hash) {
      if (await cocokkanHash(pin, h)) return true;
    }
    return false;
  } catch (_) {
    return false;
  } finally {
    db?.close();
  }
}

/// Hasil pemeriksaan sebuah file database.
class HasilPeriksa {
  const HasilPeriksa(this.utuh, this.pesan);
  final bool utuh;
  final String pesan;
}

/// Cadangan database: dibuat tiap jam & saat tutup shift, disimpan [simpanTerakhir] file terbaru,
/// dan (kalau diatur) disalin juga ke folder kedua, mis. flashdisk.
class LayananCadangan {
  LayananCadangan(this._db, {required this.folder, this.folderKedua, this.simpanTerakhir = 14});

  final DatabaseToko _db;
  final String folder;
  final String? Function()? folderKedua;
  final int simpanTerakhir;

  static final _pola = RegExp(r'^pos-[A-Z0-9]+-\d{8}-\d{6}\.db$');

  /// Buat cadangan sekarang. Cadangan yang ternyata rusak langsung dihapus dan dilaporkan sebagai galat.
  String buat(String kodeCabang) {
    final dir = Directory(folder)..createSync(recursive: true);
    final w = keWib(_db.sekarang());
    String d2(int n) => n.toString().padLeft(2, '0');
    final nama = 'pos-$kodeCabang-${w.year}${d2(w.month)}${d2(w.day)}-${d2(w.hour)}${d2(w.minute)}${d2(w.second)}.db';
    final tujuan = '${dir.path}${Platform.pathSeparator}$nama';
    if (File(tujuan).existsSync()) return tujuan;
    _db.jalankan('VACUUM INTO ?', [tujuan]);
    final cek = periksa(tujuan);
    if (!cek.utuh) {
      File(tujuan).deleteSync();
      throw StateError('Cadangan gagal diperiksa: ${cek.pesan}');
    }
    _rotasi(dir);
    final kedua = folderKedua?.call();
    if (kedua != null && kedua.trim().isNotEmpty && Directory(kedua).existsSync()) {
      try {
        final d2dir = Directory('$kedua${Platform.pathSeparator}POS-Cadangan')..createSync(recursive: true);
        File(tujuan).copySync('${d2dir.path}${Platform.pathSeparator}$nama');
        _rotasi(d2dir);
      } on FileSystemException {
        // Flashdisk dicabut / penuh: cadangan utama tetap ada.
      }
    }
    return tujuan;
  }

  void _rotasi(Directory dir) {
    final semua = daftar(dir.path);
    for (final f in semua.skip(simpanTerakhir)) {
      try {
        f.deleteSync();
      } on FileSystemException {
        // dibiarkan
      }
    }
  }

  /// Cadangan di [folder], terbaru dulu (nama file memuat tanggal & jam).
  static List<File> daftar(String folder) {
    final d = Directory(folder);
    if (!d.existsSync()) return [];
    final f = d.listSync().whereType<File>().where((f) => _pola.hasMatch(f.uri.pathSegments.last)).toList()
      ..sort((a, b) => b.uri.pathSegments.last.substring(8).compareTo(a.uri.pathSegments.last.substring(8)));
    return f;
  }

  /// Periksa keutuhan file database. [bacaSaja] = jangan mengubah file (untuk file cadangan).
  /// Database yang sedang dipakai diperiksa dengan bacaSaja: false, supaya sisa tulisan terakhir (file -wal)
  /// sempat diselesaikan dulu seperti saat aplikasi dibuka biasa.
  static HasilPeriksa periksa(String path, {bool bacaSaja = true}) {
    if (!File(path).existsSync()) return const HasilPeriksa(false, 'File tidak ada');
    Database? db;
    try {
      db = sqlite3.open(path, mode: bacaSaja ? OpenMode.readOnly : OpenMode.readWrite);
      final hasil = db.select('PRAGMA quick_check').map((r) => r.values.first.toString()).toList();
      if (hasil.length != 1 || hasil.first != 'ok') return HasilPeriksa(false, hasil.take(3).join('; '));
      final tabel = db.select("SELECT COUNT(*) AS n FROM sqlite_master WHERE type = 'table' AND name IN ('transaksi','barang','cabang')");
      if ((tabel.first['n'] as int) != 3) return const HasilPeriksa(false, 'Bukan database POS');
      return const HasilPeriksa(true, 'ok');
    } on SqliteException catch (e) {
      return HasilPeriksa(false, e.message);
    } catch (e) {
      return HasilPeriksa(false, '$e');
    } finally {
      db?.close();
    }
  }

  /// Ganti database [tujuan] dengan [cadangan]. File lama (beserta -wal/-shm) TIDAK dihapus,
  /// tapi diganti nama menjadi `*.rusak-<waktu>` supaya masih bisa diperiksa/diselamatkan.
  static String pulihkan({required String cadangan, required String tujuan, DateTime? waktu}) {
    final cek = periksa(cadangan);
    if (!cek.utuh) throw StateError('File cadangan juga rusak: ${cek.pesan}');
    final w = (waktu ?? DateTime.now()).toUtc();
    final akhiran = '.rusak-${w.millisecondsSinceEpoch}';
    for (final ext in ['', '-wal', '-shm']) {
      final f = File('$tujuan$ext');
      if (f.existsSync()) f.renameSync('$tujuan$ext$akhiran');
    }
    File(cadangan).copySync(tujuan);
    return '$tujuan$akhiran';
  }
}
