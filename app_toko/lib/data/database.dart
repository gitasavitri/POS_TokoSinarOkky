import 'dart:convert';

import 'package:pos_core/pos_core.dart';
import 'package:sqlite3/sqlite3.dart';

import 'skema_migrasi.dart';
import 'skema_v1.dart';

/// Daftar migrasi. Index 0 = versi 1. Menambah migrasi = menambah file database/migrasi/NNN_*.sql lalu
/// menjalankan `dart run tool/salin_skema.dart`. Jangan mengubah migrasi yang sudah dipakai.
const _migrasi = <String>[skemaV1, ...skemaMigrasi];

/// Pembungkus database SQLite Aplikasi Toko.
class DatabaseToko {
  DatabaseToko._(this.db, {DateTime Function()? jam}) : _jam = jam ?? DateTime.now;

  final Database db;
  final DateTime Function() _jam;

  /// Buka (atau buat) file database, lalu jalankan migrasi yang belum.
  factory DatabaseToko.buka(String path, {DateTime Function()? jam}) =>
      DatabaseToko._(sqlite3.open(path), jam: jam).._siapkan(file: true);

  /// Database di memori, untuk test.
  factory DatabaseToko.memori({DateTime Function()? jam}) =>
      DatabaseToko._(sqlite3.openInMemory(), jam: jam).._siapkan(file: false);

  DateTime sekarang() => _jam().toUtc();
  String sekarangIso() => isoUtc(sekarang());

  void _siapkan({required bool file}) {
    db.execute('PRAGMA foreign_keys = ON');
    if (file) {
      db.execute('PRAGMA journal_mode = WAL');
      // FULL: data aman walau listrik mati tiba-tiba.
      db.execute('PRAGMA synchronous = FULL');
    }
    db.execute('PRAGMA busy_timeout = 5000');
    final versi = db.select('PRAGMA user_version').first.columnAt(0) as int;
    for (var v = versi; v < _migrasi.length; v++) {
      transaksi(() {
        db.execute(_migrasi[v]);
        db.execute('PRAGMA user_version = ${v + 1}');
      });
    }
  }

  int get versiSkema => db.select('PRAGMA user_version').first.columnAt(0) as int;

  /// Jalankan [kerja] dalam satu transaksi database: semua berhasil, atau tidak ada yang tersimpan.
  T transaksi<T>(T Function() kerja) {
    if (!db.autocommit) return kerja(); // sudah di dalam transaksi
    db.execute('BEGIN IMMEDIATE');
    try {
      final hasil = kerja();
      db.execute('COMMIT');
      return hasil;
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  ResultSet pilih(String sql, [List<Object?> param = const []]) => db.select(sql, param);

  Row? satu(String sql, [List<Object?> param = const []]) {
    final r = db.select(sql, param);
    return r.isEmpty ? null : r.first;
  }

  void jalankan(String sql, [List<Object?> param = const []]) => db.execute(sql, param);

  /// Catat baris yang harus dikirim ke Server Pusat. Isi = baris lengkap sebagai JSON.
  /// Dipanggil di dalam transaksi yang sama dengan perubahan datanya.
  void outbox(String tabel, String barisId, {String kolomKunci = 'id', Map<String, Object?>? isi}) {
    final data = isi ?? _barisSebagaiMap(tabel, kolomKunci, barisId);
    db.execute(
      'INSERT INTO outbox (id, tabel, baris_id, payload, created_at) VALUES (?,?,?,?,?)',
      [buatId(), tabel, barisId, jsonEncode(data), sekarangIso()],
    );
  }

  Map<String, Object?> _barisSebagaiMap(String tabel, String kolom, String nilai) {
    if (!RegExp(r'^[a-z_]+$').hasMatch(tabel) || !RegExp(r'^[a-z_]+$').hasMatch(kolom)) {
      throw ArgumentError('Nama tabel/kolom tidak valid');
    }
    final r = satu('SELECT * FROM $tabel WHERE $kolom = ?', [nilai]);
    if (r == null) throw StateError('Baris $tabel.$kolom=$nilai tidak ditemukan');
    return Map<String, Object?>.from(r);
  }

  /// Catat aktivitas ke log (tidak bisa diubah/dihapus). Jangan pernah memasukkan PIN/sandi ke [detail].
  void log({
    required String? cabangId,
    required String? penggunaId,
    required String aksi,
    Map<String, Object?> detail = const {},
    String? disetujuiOleh,
  }) {
    final id = buatId();
    db.execute(
      'INSERT INTO log_aktivitas (id, cabang_id, pengguna_id, disetujui_oleh, aksi, detail, created_at)'
      ' VALUES (?,?,?,?,?,?,?)',
      [id, cabangId, penggunaId, disetujuiOleh, aksi, jsonEncode(detail), sekarangIso()],
    );
    outbox('log_aktivitas', id);
  }

  void tutup() => db.close();
}
