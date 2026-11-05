// Salin database/schema_toko.sql ke lib/data/skema_v1.dart supaya ikut terbawa di aplikasi.
// Jalankan dari folder app_toko:  dart run tool/salin_skema.dart
import 'dart:io';

void main() {
  final sql = File('../database/schema_toko.sql').readAsStringSync();
  if (sql.contains("'''")) throw StateError('Skema tidak boleh berisi tiga tanda kutip berurutan');
  File('lib/data/skema_v1.dart').writeAsStringSync(
    '// FILE INI DIBUAT OTOMATIS dari database/schema_toko.sql.\n'
    '// Jangan diedit langsung. Ubah skema lewat file migrasi baru, lalu jalankan:\n'
    '//   dart run tool/salin_skema.dart\n'
    '// ignore_for_file: unnecessary_raw_strings\n\n'
    "const skemaV1 = r'''\n$sql''';\n",
  );
  stdout.writeln('lib/data/skema_v1.dart diperbarui (${sql.length} karakter).');
}
