/// Perintah ESC/POS untuk printer thermal 58 mm.
/// Dibuat sendiri (tanpa library) supaya byte yang dikirim ke printer jelas dan bisa diuji.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'struk.dart';

const _esc = 0x1B;
const _gs = 0x1D;
const _lf = 0x0A;

class EscPos {
  final BytesBuilder _b = BytesBuilder(copy: false);

  Uint8List get bytes => _b.toBytes();

  EscPos mulai() => _tulis([_esc, 0x40]); // ESC @ : reset printer

  EscPos rata(Rata r) => _tulis([_esc, 0x61, r == Rata.kiri ? 0 : (r == Rata.tengah ? 1 : 2)]);

  EscPos tebal(bool aktif) => _tulis([_esc, 0x45, aktif ? 1 : 0]);

  /// Tinggi ganda saja (lebar tetap), supaya 32 karakter per baris tetap berlaku.
  EscPos besar(bool aktif) => _tulis([_gs, 0x21, aktif ? 0x01 : 0x00]);

  EscPos teks(String s) => _tulis(ascii.encode(teksAman(s)));

  EscPos baris([String s = '']) {
    if (s.isNotEmpty) teks(s);
    return _tulis([_lf]);
  }

  EscPos majukan(int n) => _tulis([_esc, 0x64, n.clamp(0, 255)]); // ESC d n

  /// Potong kertas (hanya printer yang punya pisau). GS V 66 0.
  EscPos potong() => _tulis([_gs, 0x56, 0x42, 0x00]);

  /// Barcode CODE128. Huruf memakai set B, deretan angka genap memakai set C supaya barcode pendek
  /// dan muat di kertas 58 mm.
  EscPos barcode128(String isi, {int tinggi = 60, int lebarModul = 2}) {
    _tulis([_gs, 0x68, tinggi.clamp(1, 255)]); // GS h: tinggi
    _tulis([_gs, 0x77, lebarModul.clamp(1, 6)]); // GS w: lebar modul
    _tulis([_gs, 0x48, 0x02]); // GS H: teks di bawah barcode
    final data = dataCode128(isi);
    if (data.length > 255) throw ArgumentError('Isi barcode terlalu panjang');
    _tulis([_gs, 0x6B, 73, data.length]); // GS k m=73 (CODE128) n
    return _tulis(data);
  }

  EscPos _tulis(List<int> data) {
    _b.add(data);
    return this;
  }
}

/// Data GS k CODE128 dengan pemilih set `{B` / `{C` (format ESC/POS).
List<int> dataCode128(String isi) {
  final s = teksAman(isi);
  final out = <int>[];
  var i = 0;
  String? setSekarang;
  while (i < s.length) {
    // panjang deretan angka mulai i
    var j = i;
    while (j < s.length && _angka(s.codeUnitAt(j))) {
      j++;
    }
    final panjangAngka = j - i;
    if (panjangAngka >= 4) {
      final genap = panjangAngka - panjangAngka % 2;
      if (setSekarang != 'C') {
        out.addAll(ascii.encode('{C'));
        setSekarang = 'C';
      }
      for (var k = i; k < i + genap; k += 2) {
        out.add(int.parse(s.substring(k, k + 2)));
      }
      i += genap;
    } else {
      if (setSekarang != 'B') {
        out.addAll(ascii.encode('{B'));
        setSekarang = 'B';
      }
      final c = s.codeUnitAt(i);
      if (c == 0x7B) {
        out.addAll([0x7B, 0x7B]); // '{' harus ditulis '{{'
      } else {
        out.add(c);
      }
      i++;
    }
  }
  return out;
}

bool _angka(int c) => c >= 0x30 && c <= 0x39;

/// Ubah baris struk menjadi byte siap kirim ke printer.
Uint8List cetakBaris(
  List<BarisStruk> baris, {
  String? barcode,
  bool potongKertas = false,
  int majuAkhir = 4,
}) {
  final p = EscPos().mulai();
  for (final l in baris) {
    p.rata(l.rata).tebal(l.tebal).besar(l.besar).baris(l.teks);
  }
  p.rata(Rata.kiri).tebal(false).besar(false);
  if (barcode != null && barcode.isNotEmpty) {
    p.rata(Rata.tengah).baris().barcode128(barcode).baris().rata(Rata.kiri);
  }
  p.majukan(majuAkhir);
  if (potongKertas) p.potong();
  return p.bytes;
}

/// Struk lengkap → byte printer.
Uint8List cetakStruk(DataStruk d, {bool potongKertas = false}) =>
    cetakBaris(susunStruk(d), barcode: isiBarcodeStruk(d.noTransaksi), potongKertas: potongKertas);

/// Struk tes dari halaman Pengaturan printer.
Uint8List cetakTes({required String namaToko, required String namaCabang, bool potongKertas = false}) {
  final baris = <BarisStruk>[
    BarisStruk(namaToko, rata: Rata.tengah, tebal: true, besar: true),
    if (namaCabang.isNotEmpty) BarisStruk('Cabang $namaCabang', rata: Rata.tengah),
    BarisStruk(garis()),
    const BarisStruk('TES CETAK', rata: Rata.tengah, tebal: true),
    BarisStruk(kiriKanan('Lebar kertas', '58 mm')),
    BarisStruk(kiriKanan('Huruf per baris', '$lebarStruk')),
    const BarisStruk('12345678901234567890123456789012'),
    BarisStruk(garis()),
    const BarisStruk('Baris angka di atas harus muat', rata: Rata.tengah),
    const BarisStruk('dalam satu baris.', rata: Rata.tengah),
  ];
  return cetakBaris(baris, barcode: 'A012611050001', potongKertas: potongKertas);
}
