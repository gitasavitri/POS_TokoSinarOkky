import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'data/database.dart';
import 'layanan/aplikasi.dart';
import 'layanan/printer.dart';
import 'ui/akar.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Database disimpan di folder data aplikasi (AppData), bukan di folder program.
  final folder = await getApplicationSupportDirectory();
  await folder.create(recursive: true);
  final lokasi = '${folder.path}${Platform.pathSeparator}pos_toko.db';
  final db = DatabaseToko.buka(lokasi);
  final app = Aplikasi(db: db, printer: LayananPrinter.untukSistemIni(), lokasiDatabase: lokasi);
  app.sinkron.mulai(); // tidak melakukan apa-apa sebelum PC ini didaftarkan ke Server Pusat
  runApp(AplikasiToko(app: app));
}
