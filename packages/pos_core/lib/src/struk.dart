/// Susunan struk 58 mm (32 karakter per baris) dan label rak.
/// Hanya menyusun teks; perintah printer dibuat di escpos.dart.
library;

import 'pembayaran.dart';
import 'uang.dart';
import 'waktu.dart';

const lebarStruk = 32;

enum Rata { kiri, tengah, kanan }

/// Satu baris struk. [besar] = tinggi ganda (lebar tetap 32 karakter).
class BarisStruk {
  const BarisStruk(this.teks, {this.rata = Rata.kiri, this.tebal = false, this.besar = false});

  final String teks;
  final Rata rata;
  final bool tebal;
  final bool besar;

  @override
  String toString() => teks;
}

class ItemStruk {
  const ItemStruk({required this.nama, required this.qty, required this.hargaSatuan, required this.isGrosir});

  final String nama;
  final int qty;
  final int hargaSatuan;
  final bool isGrosir;

  int get subtotal => qty * hargaSatuan;
}

class DataStruk {
  const DataStruk({
    required this.namaToko,
    required this.namaCabang,
    required this.alamat,
    required this.noTransaksi,
    required this.waktu,
    required this.namaKasir,
    required this.item,
    required this.metode,
    required this.diterima,
    required this.kembalian,
    this.noReferensi,
    this.pesanBawah = '',
    this.dibatalkan = false,
    this.cetakUlang = false,
  });

  final String namaToko;
  final String namaCabang;
  final String alamat;
  final String noTransaksi;
  final DateTime waktu;
  final String namaKasir;
  final List<ItemStruk> item;
  final MetodeBayar metode;
  final int diterima;
  final int kembalian;
  final String? noReferensi;
  final String pesanBawah;
  final bool dibatalkan;
  final bool cetakUlang;

  int get total => item.fold(0, (s, i) => s + i.subtotal);
  int get jumlahBarang => item.fold(0, (s, i) => s + i.qty);
}

/// Ganti karakter non-ASCII supaya printer thermal tidak mencetak simbol aneh.
String teksAman(String s) {
  const ganti = {
    '—': '-',
    '–': '-',
    '−': '-',
    '×': 'x',
    '·': '-',
    '•': '-',
    '…': '...',
    '‘': "'",
    '’': "'",
    '“': '"',
    '”': '"',
    '±': '+/-',
    '°': 'o',
    'á': 'a',
    'à': 'a',
    'â': 'a',
    'ä': 'a',
    'é': 'e',
    'è': 'e',
    'ê': 'e',
    'ë': 'e',
    'í': 'i',
    'ì': 'i',
    'î': 'i',
    'ï': 'i',
    'ó': 'o',
    'ò': 'o',
    'ô': 'o',
    'ö': 'o',
    'ú': 'u',
    'ù': 'u',
    'û': 'u',
    'ü': 'u',
    'ñ': 'n',
    'ç': 'c',
  };
  final buf = StringBuffer();
  for (final r in s.runes) {
    final c = String.fromCharCode(r);
    if (r >= 0x20 && r < 0x7f) {
      buf.write(c);
    } else if (ganti.containsKey(c)) {
      buf.write(ganti[c]);
    } else if (ganti.containsKey(c.toLowerCase())) {
      buf.write(ganti[c.toLowerCase()]!.toUpperCase());
    } else if (r == 0x09) {
      buf.write(' ');
    } else {
      buf.write('?');
    }
  }
  return buf.toString();
}

/// Potong teks panjang menjadi beberapa baris, memecah di spasi bila bisa.
List<String> bungkus(String teks, [int lebar = lebarStruk]) {
  final hasil = <String>[];
  var sisa = teksAman(teks).trim();
  if (sisa.isEmpty) return hasil;
  while (sisa.length > lebar) {
    var potong = sisa.lastIndexOf(' ', lebar);
    if (potong <= 0) potong = lebar;
    hasil.add(sisa.substring(0, potong).trimRight());
    sisa = sisa.substring(potong).trimLeft();
  }
  if (sisa.isNotEmpty) hasil.add(sisa);
  return hasil;
}

/// Kiri dan kanan dalam satu baris; kiri dipotong kalau tidak muat.
String kiriKanan(String kiri, String kanan, [int lebar = lebarStruk]) {
  final k = teksAman(kanan);
  var l = teksAman(kiri);
  final ruang = lebar - k.length - 1;
  if (ruang < 1) return k.length > lebar ? k.substring(0, lebar) : k.padLeft(lebar);
  if (l.length > ruang) l = l.substring(0, ruang);
  return l + ' ' * (lebar - l.length - k.length) + k;
}

String garis([String c = '-']) => c * lebarStruk;

/// Isi barcode di struk: nomor transaksi tanpa `TRX-` dan tanda hubung,
/// mis. `TRX-A01-261105-0001` → `A012611050001`. Dipakai untuk retur (scan struk).
String isiBarcodeStruk(String noTransaksi) => noTransaksi.replaceFirst('TRX-', '').replaceAll('-', '');

/// Kebalikan [isiBarcodeStruk]: 10 digit terakhir = YYMMDD + urut 4 digit, sisanya kode cabang.
String? noTransaksiDariBarcode(String isi) {
  final s = isi.trim().toUpperCase();
  final m = RegExp(r'^([A-Z0-9]+?)(\d{6})(\d{4})$').firstMatch(s);
  if (m == null) return null;
  return 'TRX-${m[1]}-${m[2]}-${m[3]}';
}

/// Susun semua baris struk penjualan.
List<BarisStruk> susunStruk(DataStruk d) {
  final b = <BarisStruk>[];
  void tengah(String s, {bool tebal = false, bool besar = false}) {
    for (final l in bungkus(s)) {
      b.add(BarisStruk(l, rata: Rata.tengah, tebal: tebal, besar: besar));
    }
  }

  tengah(d.namaToko, tebal: true, besar: true);
  if (d.namaCabang.isNotEmpty) tengah('Cabang ${d.namaCabang}');
  if (d.alamat.isNotEmpty) tengah(d.alamat);
  if (d.cetakUlang) tengah('*** CETAK ULANG ***', tebal: true);
  if (d.dibatalkan) tengah('*** DIBATALKAN ***', tebal: true);
  b.add(BarisStruk(garis()));
  b.add(BarisStruk(kiriKanan('No', d.noTransaksi)));
  b.add(BarisStruk(kiriKanan('Tgl', formatStruk(d.waktu))));
  b.add(BarisStruk(kiriKanan('Kasir', d.namaKasir)));
  b.add(BarisStruk(garis()));

  var adaGrosir = false;
  for (final i in d.item) {
    for (final l in bungkus(i.nama)) {
      b.add(BarisStruk(l));
    }
    final tanda = i.isGrosir ? ' *G' : '';
    adaGrosir |= i.isGrosir;
    b.add(BarisStruk(kiriKanan('  ${i.qty} x ${formatAngka(i.hargaSatuan)}$tanda', formatAngka(i.subtotal))));
  }

  b.add(BarisStruk(garis()));
  b.add(BarisStruk(kiriKanan('Jumlah barang', '${d.jumlahBarang}')));
  b.add(BarisStruk(kiriKanan('TOTAL', formatAngka(d.total)), tebal: true, besar: true));
  b.add(
    BarisStruk(kiriKanan(d.metode == MetodeBayar.tunai ? 'Tunai' : d.metode.label, formatAngka(d.diterima))),
  );
  if (d.metode == MetodeBayar.tunai) {
    b.add(BarisStruk(kiriKanan('Kembali', formatAngka(d.kembalian))));
  }
  if (d.noReferensi != null && d.noReferensi!.isNotEmpty) {
    b.add(BarisStruk(kiriKanan('Ref', d.noReferensi!)));
  }
  b.add(BarisStruk(garis()));
  if (adaGrosir) tengah('*G = harga grosir');
  tengah('Terima kasih');
  if (d.pesanBawah.isNotEmpty) tengah(d.pesanBawah);
  return b;
}

/// Teks polos struk (untuk pratinjau di layar dan untuk test).
String strukSebagaiTeks(List<BarisStruk> baris) => baris
    .map((l) {
      switch (l.rata) {
        case Rata.kiri:
          return l.teks;
        case Rata.kanan:
          return l.teks.padLeft(lebarStruk);
        case Rata.tengah:
          final kiri = (lebarStruk - l.teks.length) ~/ 2;
          return (' ' * (kiri < 0 ? 0 : kiri)) + l.teks;
      }
    })
    .join('\n');

/// Label rak (dicetak di printer struk lalu ditempel).
List<BarisStruk> susunLabelRak({
  required String namaBarang,
  required int harga,
  required String satuan,
  String? grosirTeks,
  required DateTime berlaku,
}) {
  final b = <BarisStruk>[];
  for (final l in bungkus(namaBarang)) {
    b.add(BarisStruk(l, tebal: true));
  }
  b.add(BarisStruk(formatRupiah(harga), tebal: true, besar: true));
  b.add(BarisStruk('per $satuan'));
  if (grosirTeks != null && grosirTeks.isNotEmpty) {
    for (final l in bungkus(grosirTeks)) {
      b.add(BarisStruk(l));
    }
  }
  b.add(BarisStruk('Berlaku ${formatTanggal(berlaku)}'));
  return b;
}
