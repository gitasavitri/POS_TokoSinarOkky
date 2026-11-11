import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'data/database.dart';
import 'layanan/aplikasi.dart';
import 'layanan/mode_latihan.dart';
import 'layanan/printer.dart';
import 'layanan/sistem.dart';
import 'ui/akar.dart';
import 'ui/halaman/pemulihan.dart';
import 'ui/halaman/shift.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Database disimpan di folder data aplikasi (AppData), bukan di folder program.
  final folder = await getApplicationSupportDirectory();
  await folder.create(recursive: true);
  final s = Platform.pathSeparator;
  final lokasi = '${folder.path}${s}pos_toko.db';
  final cadangan = await folderCadangan();

  // Semua galat yang tidak tertangani dicatat ke file, supaya penyebab masalah bisa dilacak.
  final catatan = CatatanGalat('${folder.path}${s}log');
  FlutterError.onError = (d) {
    FlutterError.presentError(d);
    catatan.tulis(d.exception, d.stack, konteks: 'tampilan');
  };
  PlatformDispatcher.instance.onError = (e, st) {
    catatan.tulis(e, st, konteks: 'tidak tertangani');
    return true;
  };

  void mulai() {
    // Buka database (sisa tulisan saat listrik padam diselesaikan otomatis oleh SQLite), lalu cek keutuhannya.
    DatabaseToko? db;
    String? masalah;
    try {
      db = DatabaseToko.buka(lokasi);
      final hasil = db.pilih('PRAGMA quick_check').map((r) => '${r.values.first}').toList();
      if (hasil.length != 1 || hasil.first != 'ok') masalah = hasil.take(5).join('; ');
    } catch (e, st) {
      masalah = '$e';
      catatan.tulis(e, st, konteks: 'buka database');
    }
    if (masalah != null) {
      db?.tutup();
      catatan.tulis(masalah, null, konteks: 'database rusak');
      runApp(AplikasiPemulihan(lokasiDatabase: lokasi, folderCadangan: [cadangan, ..._cadanganDiFlashdisk()], masalah: masalah, onSelesai: mulai));
      return;
    }
    final app = Aplikasi(db: db!, printer: LayananPrinter.untukSistemIni(), lokasiDatabase: lokasi, folderCadangan: cadangan, catatan: catatan);
    // Mode latihan: database terpisah di folder yang sama. Selalu mulai dari data asli saat aplikasi dibuka.
    final lokasiLatihan = '${folder.path}${s}pos_toko_latihan.db';
    PengaturMode(
      asli: app,
      bukaDatabaseLatihan: () => DatabaseToko.buka(lokasiLatihan),
      hapusDatabaseLatihan: () {
        for (final akhiran in const ['', '-wal', '-shm']) {
          final f = File('$lokasiLatihan$akhiran');
          if (f.existsSync()) f.deleteSync();
        }
      },
    );
    app.sinkron.mulai(); // tidak melakukan apa-apa sebelum PC ini didaftarkan ke Server Pusat
    app.mulaiTugasLatar(); // cadangan tiap jam + cek ruang disk
    runApp(AplikasiToko(app: app));
  }

  mulai();
}

/// Folder POS-Cadangan di flashdisk/drive lain (D: sampai Z:), untuk pemulihan saat database tidak bisa dibaca.
List<String> _cadanganDiFlashdisk() => [
      if (Platform.isWindows)
        for (final huruf in 'DEFGHIJKLMNOPQRSTUVWXYZ'.split(''))
          if (Directory('$huruf:\\POS-Cadangan').existsSync()) '$huruf:\\POS-Cadangan',
    ];
