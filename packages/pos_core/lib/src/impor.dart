/// Impor stok awal dari Excel (revisi J, tahap 4). Hanya SPV/Admin, lewat Barang masuk.
///
/// Di sini hanya pembacaan sel & pemeriksaan per baris yang tidak butuh database
/// (angka, barcode, kolom wajib). Pencocokan dengan barang/kategori yang sudah ada dilakukan Aplikasi Toko.
library;

/// Kolom template, urut dari kiri (A–G).
const kolomImporStok = ['Barcode', 'Nama barang', 'Kategori', 'Satuan', 'Jumlah', 'HPP (harga beli)', 'Harga jual'];

/// Maksimal baris data dalam satu file impor.
const maksBarisImpor = 5000;

/// Hasil membaca satu sel angka.
class AngkaSel {
  const AngkaSel._(this.nilai, this.salah);
  const AngkaSel.kosong() : this._(null, null);
  const AngkaSel.ok(int n) : this._(n, null);
  const AngkaSel.salah(String pesan) : this._(null, pesan);

  final int? nilai;
  final String? salah;
  bool get kosong => nilai == null && salah == null;
}

/// Baca bilangan bulat rupiah/jumlah dari sel Excel.
///
/// Diterima: angka (17500 atau 17500.0), teks `17500`, `17.500`, `Rp 17.500`, `Rp17.500,00`.
/// Titik = pemisah ribuan, koma = desimal (format Indonesia). Pecahan selain ,0/,00 ditolak.
AngkaSel bacaBilanganBulat(Object? sel) {
  if (sel == null) return const AngkaSel.kosong();
  if (sel is int) return AngkaSel.ok(sel);
  if (sel is double) {
    if (sel.isNaN || sel.isInfinite) return const AngkaSel.salah('bukan angka');
    if (sel != sel.roundToDouble()) return const AngkaSel.salah('harus bilangan bulat (tanpa koma)');
    if (sel.abs() > 9e15) return const AngkaSel.salah('angka terlalu besar');
    return AngkaSel.ok(sel.round());
  }
  var t = '$sel'.trim();
  if (t.isEmpty || t == '-') return const AngkaSel.kosong();
  t = t.replaceFirst(RegExp(r'^rp\.?', caseSensitive: false), '').replaceAll(RegExp(r'\s'), '');
  var minus = false;
  if (t.startsWith('-')) {
    minus = true;
    t = t.substring(1);
  }
  // ",00" / ",0" di belakang boleh (format rupiah), pecahan lain tidak.
  final koma = RegExp(r',(\d+)$').firstMatch(t);
  if (koma != null) {
    if (RegExp(r'^0+$').hasMatch(koma[1]!)) {
      t = t.substring(0, koma.start);
    } else {
      return const AngkaSel.salah('harus bilangan bulat (tanpa koma)');
    }
  }
  final ribuan = RegExp(r'^\d{1,3}(\.\d{3})+$');
  if (ribuan.hasMatch(t)) {
    t = t.replaceAll('.', '');
  } else if (!RegExp(r'^\d+$').hasMatch(t)) {
    return AngkaSel.salah('"$sel" bukan angka');
  }
  if (t.length > 15) return const AngkaSel.salah('angka terlalu besar');
  final n = int.parse(t);
  return AngkaSel.ok(minus ? -n : n);
}

/// Baca barcode dari sel. Barcode yang terbaca Excel sebagai angka (mis. 8991234567890.0) diubah jadi teks.
/// Mengembalikan (barcode, pesan salah).
(String, String?) bacaBarcode(Object? sel) {
  if (sel == null) return ('', null);
  if (sel is int) return ('$sel', null);
  if (sel is double) {
    if (sel != sel.roundToDouble() || sel.abs() >= 1e15) {
      return ('', 'barcode terbaca sebagai angka pecahan; ubah format kolom Barcode menjadi Teks lalu ketik ulang');
    }
    return ('${sel.round()}', null);
  }
  final t = '$sel'.trim();
  if (RegExp(r'^\d+(\.\d+)?[eE]\+?\d+$').hasMatch(t)) {
    return ('', 'barcode terbaca seperti "$t"; ubah format kolom Barcode menjadi Teks lalu ketik ulang');
  }
  if (t.length > 64) return ('', 'barcode terlalu panjang');
  return (t, null);
}

String _teks(Object? sel) {
  if (sel == null) return '';
  if (sel is double && sel == sel.roundToDouble()) return '${sel.round()}';
  return '$sel'.trim().replaceAll(RegExp(r'\s+'), ' ');
}

/// Satu baris data dari file impor.
class BarisImporStok {
  BarisImporStok({
    required this.nomorBaris,
    required this.barcode,
    required this.nama,
    required this.kategori,
    required this.satuan,
    required this.jumlah,
    required this.hpp,
    required this.hargaJual,
    List<String>? salah,
  }) : salah = salah ?? [];

  /// Nomor baris di Excel (baris 1 = paling atas), untuk ditunjukkan ke pengguna.
  final int nomorBaris;
  final String barcode;
  final String nama;
  final String kategori;
  final String satuan;
  final int? jumlah;
  final int? hpp;
  final int? hargaJual;

  /// Kesalahan yang sudah ketahuan dari isi sel saja.
  final List<String> salah;
}

/// Baca satu baris (sel A–G). null = baris kosong (dilewati).
BarisImporStok? bacaBarisImporStok(int nomorBaris, List<Object?> sel) {
  Object? ambil(int i) => i < sel.length ? sel[i] : null;
  if (List.generate(kolomImporStok.length, ambil).every((s) => _teks(s).isEmpty)) return null;
  final salah = <String>[];
  final (barcode, salahBarcode) = bacaBarcode(ambil(0));
  if (salahBarcode != null) salah.add('Barcode: $salahBarcode.');
  final nama = _teks(ambil(1));
  if (nama.length > 200) salah.add('Nama barang terlalu panjang (maks. 200 huruf).');
  int? angka(int i, String label, {required bool lebihDariNol}) {
    final a = bacaBilanganBulat(ambil(i));
    if (a.salah != null) {
      salah.add('$label: ${a.salah}.');
      return null;
    }
    if (a.kosong) {
      salah.add('$label wajib diisi.');
      return null;
    }
    final n = a.nilai!;
    if (lebihDariNol ? n <= 0 : n < 0) {
      salah.add('$label harus ${lebihDariNol ? 'lebih dari 0' : '0 atau lebih'}.');
      return null;
    }
    return n;
  }

  final jumlah = angka(4, 'Jumlah', lebihDariNol: true);
  final hpp = angka(5, 'HPP', lebihDariNol: false);
  final harga = angka(6, 'Harga jual', lebihDariNol: true);
  if (hpp != null && harga != null && harga <= hpp) salah.add('Harga jual harus lebih besar dari HPP.');
  return BarisImporStok(
    nomorBaris: nomorBaris,
    barcode: barcode,
    nama: nama,
    kategori: _teks(ambil(2)),
    satuan: _teks(ambil(3)).toLowerCase(),
    jumlah: jumlah,
    hpp: hpp,
    hargaJual: harga,
    salah: salah,
  );
}

/// Cari baris judul kolom (sel A = "Barcode") di 10 baris pertama. Mengembalikan index (0 = baris 1),
/// atau -1 kalau tidak ada (dianggap tidak ada baris judul).
int cariBarisJudul(List<List<Object?>> baris) {
  for (var i = 0; i < baris.length && i < 10; i++) {
    final a = baris[i].isEmpty ? '' : _teks(baris[i].first).toLowerCase();
    if (a == 'barcode') return i;
  }
  return -1;
}

/// Baca semua baris data dari isi sheet. Baris judul dan baris kosong dilewati.
List<BarisImporStok> bacaSheetImporStok(List<List<Object?>> baris) {
  final judul = cariBarisJudul(baris);
  final hasil = <BarisImporStok>[];
  for (var i = judul + 1; i < baris.length; i++) {
    final b = bacaBarisImporStok(i + 1, baris[i]);
    if (b != null) hasil.add(b);
    if (hasil.length > maksBarisImpor) {
      throw const FormatException('File berisi lebih dari $maksBarisImpor baris barang. Pecah menjadi beberapa file.');
    }
  }
  return hasil;
}
