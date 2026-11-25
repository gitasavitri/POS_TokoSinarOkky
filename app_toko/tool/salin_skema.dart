// Salin skema database ke kode Dart supaya ikut terbawa di aplikasi:
//   database/schema_toko.sql        -> lib/data/skema_v1.dart     (versi 1)
//   database/migrasi/NNN_*.sql      -> lib/data/skema_migrasi.dart (versi 2, 3, ...)
// Jalankan dari folder app_toko:  dart run tool/salin_skema.dart
import 'dart:io';

void main() {
  final sql = File('../database/schema_toko.sql').readAsStringSync();
  _cekKutip(sql, 'schema_toko.sql');
  File('lib/data/skema_v1.dart').writeAsStringSync(
    '// FILE INI DIBUAT OTOMATIS dari database/schema_toko.sql.\n'
    '// Jangan diedit langsung. Ubah skema lewat file migrasi baru, lalu jalankan:\n'
    '//   dart run tool/salin_skema.dart\n'
    '// ignore_for_file: unnecessary_raw_strings\n\n'
    "const skemaV1 = r'''\n$sql''';\n",
  );

  final file = Directory('../database/migrasi')
      .listSync()
      .whereType<File>()
      .where((f) => RegExp(r'[/\\]\d{3}_[^/\\]+\.sql$').hasMatch(f.path))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  final isi = StringBuffer()
    ..write('// FILE INI DIBUAT OTOMATIS dari database/migrasi/*.sql.\n'
        '// Jangan diedit langsung. Tambah file migrasi baru, lalu jalankan:\n'
        '//   dart run tool/salin_skema.dart\n'
        '// ignore_for_file: unnecessary_raw_strings\n\n'
        '/// Migrasi setelah versi 1, berurutan. Elemen ke-0 = versi 2.\n'
        'const skemaMigrasi = <String>[\n');
  var nomor = 2;
  for (final f in file) {
    final nama = f.uri.pathSegments.last;
    if (int.parse(nama.substring(0, 3)) != nomor) throw StateError('Nomor migrasi harus berurutan mulai 002: $nama');
    final m = f.readAsStringSync();
    _cekKutip(m, nama);
    isi.write("  // $nama\n  r'''\n$m''',\n");
    nomor++;
  }
  isi.write('];\n');
  File('lib/data/skema_migrasi.dart').writeAsStringSync(isi.toString());
  stdout.writeln('Skema v1 + ${file.length} migrasi disalin (versi terbaru: ${nomor - 1}).');
}

void _cekKutip(String sql, String nama) {
  if (sql.contains("'''")) throw StateError('$nama tidak boleh berisi tiga tanda kutip berurutan');
}
