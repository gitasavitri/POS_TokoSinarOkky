import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Ruang kosong di disk tempat [path] berada, dalam byte. null kalau tidak bisa dibaca (atau bukan Windows).
int? ruangKosong(String path) {
  if (!Platform.isWindows) return null;
  try {
    final k32 = DynamicLibrary.open('kernel32.dll');
    final f = k32.lookupFunction<Int32 Function(Pointer<Utf16>, Pointer<Uint64>, Pointer<Uint64>, Pointer<Uint64>),
        int Function(Pointer<Utf16>, Pointer<Uint64>, Pointer<Uint64>, Pointer<Uint64>)>('GetDiskFreeSpaceExW');
    final p = path.toNativeUtf16();
    final bebas = calloc<Uint64>();
    try {
      return f(p, bebas, nullptr, nullptr) == 0 ? null : bebas.value;
    } finally {
      calloc.free(p);
      calloc.free(bebas);
    }
  } catch (_) {
    return null;
  }
}

/// Batas peringatan disk hampir penuh.
const batasRuangKosong = 1024 * 1024 * 1024; // 1 GB

/// Catatan galat ke file teks (satu file per bulan) supaya penyebab masalah bisa dilacak.
/// Jangan pernah menulis PIN/kata sandi ke sini.
class CatatanGalat {
  CatatanGalat(this.folder);
  final String folder;

  String get _berkas {
    final n = DateTime.now();
    return '$folder${Platform.pathSeparator}galat-${n.year}${n.month.toString().padLeft(2, '0')}.txt';
  }

  void tulis(Object galat, StackTrace? jejak, {String konteks = ''}) {
    try {
      Directory(folder).createSync(recursive: true);
      final waktu = DateTime.now().toUtc().toIso8601String();
      File(_berkas).writeAsStringSync('[$waktu] $konteks\n$galat\n${jejak ?? ''}\n\n', mode: FileMode.append, flush: true);
    } catch (_) {
      // Mencatat galat tidak boleh membuat aplikasi ikut galat.
    }
  }
}
