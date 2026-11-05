/// Keranjang belanja di layar kasir.
library;

import 'harga.dart';

/// Data barang yang dibutuhkan kasir untuk satu baris belanja.
class BarangJual {
  const BarangJual({
    required this.id,
    required this.nama,
    required this.satuan,
    required this.harga,
    required this.hpp,
    this.barcode,
  });

  final String id;
  final String nama;
  final String satuan;
  final String? barcode;
  final HargaBarang harga;

  /// HPP per satuan saat ini (untuk laporan laba). 0 kalau belum ada.
  final int hpp;
}

class BarisKeranjang {
  BarisKeranjang(this.barang, this.qty);

  final BarangJual barang;
  int qty;

  HargaBaris get harga => hitungHargaBaris(barang.harga, qty);
  int get subtotal => harga.subtotal;
}

class Keranjang {
  final List<BarisKeranjang> _baris = [];

  /// Index baris yang terakhir ditambah/diubah (untuk disorot di layar). -1 kalau kosong.
  int barisTerakhir = -1;

  List<BarisKeranjang> get baris => List.unmodifiable(_baris);
  bool get kosong => _baris.isEmpty;

  int get total => _baris.fold(0, (s, b) => s + b.subtotal);
  int get jumlahBarang => _baris.fold(0, (s, b) => s + b.qty);
  int get jumlahJenis => _baris.length;

  /// Barang yang sama digabung ke baris yang sudah ada.
  void tambah(BarangJual barang, {int qty = 1}) {
    if (qty <= 0) throw ArgumentError.value(qty, 'qty', 'harus lebih dari 0');
    final i = _baris.indexWhere((b) => b.barang.id == barang.id);
    if (i >= 0) {
      _baris[i].qty += qty;
      barisTerakhir = i;
    } else {
      _baris.add(BarisKeranjang(barang, qty));
      barisTerakhir = _baris.length - 1;
    }
  }

  /// qty ≤ 0 menghapus baris.
  void ubahQty(int index, int qty) {
    RangeError.checkValidIndex(index, _baris);
    if (qty <= 0) {
      hapus(index);
      return;
    }
    _baris[index].qty = qty;
    barisTerakhir = index;
  }

  void hapus(int index) {
    RangeError.checkValidIndex(index, _baris);
    _baris.removeAt(index);
    if (_baris.isEmpty) {
      barisTerakhir = -1;
    } else if (barisTerakhir >= _baris.length) {
      barisTerakhir = _baris.length - 1;
    }
  }

  void kosongkan() {
    _baris.clear();
    barisTerakhir = -1;
  }

  /// Salinan untuk fitur "Tahan transaksi".
  Keranjang salin() {
    final k = Keranjang();
    for (final b in _baris) {
      k._baris.add(BarisKeranjang(b.barang, b.qty));
    }
    k.barisTerakhir = barisTerakhir;
    return k;
  }
}

// ---------------------------------------------------------------- isian jumlah di layar kasir

/// Hasil pemeriksaan kolom Jumlah sebelum barang dimasukkan ke daftar belanja.
enum CekJumlah {
  /// Boleh langsung ditambahkan.
  wajar,

  /// Kosong atau 0.
  kosong,

  /// Jumlah besar (≥ [batasKonfirmasiJumlah]): minta kasir memastikan dulu.
  perluKonfirmasi,

  /// Panjangnya seperti barcode: kemungkinan barcode barang berikutnya ter-scan ke kolom Jumlah
  /// karena kasir lupa menekan Enter. Ditolak.
  miripBarcode,
}

/// Jumlah sebesar ini atau lebih perlu dikonfirmasi kasir.
const batasKonfirmasiJumlah = 1000;

/// Jumlah dengan angka sebanyak ini atau lebih dianggap barcode yang salah masuk.
const panjangMiripBarcode = 6;

CekJumlah cekJumlah(String teks) {
  final angka = teks.trim();
  if (angka.isEmpty || !RegExp(r'^\d+$').hasMatch(angka)) return CekJumlah.kosong;
  if (angka.length >= panjangMiripBarcode) return CekJumlah.miripBarcode;
  final n = int.parse(angka);
  if (n <= 0) return CekJumlah.kosong;
  if (n >= batasKonfirmasiJumlah) return CekJumlah.perluKonfirmasi;
  return CekJumlah.wajar;
}
