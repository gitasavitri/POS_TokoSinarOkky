// Memuat huruf asli aplikasi di test, supaya ukuran teks sama seperti di layar sungguhan.
import 'dart:io';

import 'package:flutter/services.dart';

Future<void> muatHuruf() async {
  Future<void> muat(String keluarga, List<String> berkas) async {
    final l = FontLoader(keluarga);
    for (final b in berkas) {
      final data = File(b).readAsBytesSync();
      l.addFont(Future.value(ByteData.sublistView(data)));
    }
    await l.load();
  }

  await muat('PlusJakartaSans', [
    for (final w in ['400Regular', '500Medium', '600SemiBold', '700Bold', '800ExtraBold']) 'assets/fonts/PlusJakartaSans_$w.ttf',
  ]);
  await muat('JetBrainsMono', ['assets/fonts/JetBrainsMono_400Regular.ttf', 'assets/fonts/JetBrainsMono_700Bold.ttf']);
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  final ikon = File('$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (flutterRoot != null && ikon.existsSync()) await muat('MaterialIcons', [ikon.path]);
}
