import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'layanan/sesi.dart';
import 'ui/akar.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Aplikasi Pusat tidak menyimpan data toko di PC; hanya alamat server.
  final folder = await getApplicationSupportDirectory();
  final lokal = PengaturanLokal(File('${folder.path}${Platform.pathSeparator}pengaturan.json'));
  await lokal.muat();
  runApp(AplikasiPusat(sesi: Sesi(lokal: lokal)));
}
