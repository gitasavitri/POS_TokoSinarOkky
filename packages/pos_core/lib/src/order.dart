/// Order barang ke toko utama / supplier luar (revisi G, tahap 4).
///
/// - Bisa dibuat Kasir, SPV, Admin.
/// - Hasilnya PDF "Surat Pesanan Barang" + Excel. Kirim order ke pusat lewat aplikasi menyusul nanti.
library;

import 'stok.dart';
import 'waktu.dart';

/// Saran order mengisi stok sampai [kaliStokMinimum] × stok minimum.
/// ASUMSI (11 Nov 2026, belum diputuskan pemilik): 2× stok minimum.
const kaliStokMinimum = 2;

/// Saran jumlah order untuk satu barang. 0 = tidak perlu / tidak bisa disarankan.
///
/// - Stok minimum diatur: isi sampai [kaliStokMinimum] × stok minimum, hanya kalau stok ≤ stok minimum.
/// - Stok minimum belum diatur (0): kalau stok minus, saran menutup minusnya saja; selain itu 0
///   (jumlah diisi sendiri).
int saranOrder({required int stok, required int stokMinimum}) {
  if (stokMinimum > 0) {
    if (stok > stokMinimum) return 0;
    return kaliStokMinimum * stokMinimum - stok;
  }
  return stok < 0 ? -stok : 0;
}

/// Perlu diorder = habis atau hampir habis (sama dengan status di Cek stok & harga).
bool perluOrder({required int stok, required int stokMinimum}) =>
    statusStok(stok: stok, stokMinimum: stokMinimum).perluDiorder;

/// Jumlah yang ditambahkan saat tombol (+) ditekan untuk barang yang belum ada di daftar order:
/// saran kalau ada, kalau tidak 1.
int jumlahAwalOrder({required int stok, required int stokMinimum}) {
  final s = saranOrder(stok: stok, stokMinimum: stokMinimum);
  return s > 0 ? s : 1;
}

/// Batas jumlah per barang di satu order (mencegah salah ketik, mis. barcode terketik di kolom jumlah).
const maksJumlahOrder = 99999;

/// Nomor order: `ORD-A01-261111-0001`. Urut per cabang per hari (WIB).
String nomorOrder({required String kodeCabang, required DateTime waktu, required int urut}) {
  if (urut <= 0 || urut > 9999) throw RangeError.range(urut, 1, 9999, 'urut');
  return 'ORD-$kodeCabang-${kodeTanggal(waktu)}-${urut.toString().padLeft(4, '0')}';
}

/// Awalan nomor order hari itu, untuk mencari urut terakhir: `ORD-A01-261111-`.
String awalanNomorOrder(String kodeCabang, DateTime waktu) => 'ORD-$kodeCabang-${kodeTanggal(waktu)}-';

/// Satu baris di daftar order.
class BarisOrder {
  BarisOrder({
    required this.barangId,
    required this.nama,
    required this.satuan,
    this.barcode,
    required this.jumlah,
    this.stok = 0,
    this.stokMinimum = 0,
  });

  final String barangId;
  final String nama;
  final String satuan;
  final String? barcode;
  int jumlah;

  /// Stok & stok minimum saat ditambahkan (ditampilkan di surat pesanan sebagai keterangan).
  int stok;
  int stokMinimum;

  Map<String, Object?> keJson() => {
        'barangId': barangId,
        'nama': nama,
        'satuan': satuan,
        'barcode': barcode,
        'jumlah': jumlah,
        'stok': stok,
        'stokMinimum': stokMinimum,
      };

  static BarisOrder dariJson(Map<String, Object?> j) => BarisOrder(
        barangId: j['barangId']! as String,
        nama: j['nama']! as String,
        satuan: j['satuan']! as String,
        barcode: j['barcode'] as String?,
        jumlah: (j['jumlah']! as num).toInt(),
        stok: (j['stok'] as num?)?.toInt() ?? 0,
        stokMinimum: (j['stokMinimum'] as num?)?.toInt() ?? 0,
      );
}

/// Daftar order yang sedang disusun (panel kanan layar Order barang).
class DaftarOrder {
  DaftarOrder({List<BarisOrder>? baris, this.supplierId, this.catatan = ''}) : baris = baris ?? [];

  final List<BarisOrder> baris;
  String? supplierId;
  String catatan;

  bool get kosong => baris.isEmpty;
  int get jumlahJenis => baris.length;
  int get totalJumlah => baris.fold(0, (s, b) => s + b.jumlah);

  BarisOrder? cari(String barangId) {
    for (final b in baris) {
      if (b.barangId == barangId) return b;
    }
    return null;
  }

  /// Tambah barang. Kalau sudah ada, jumlahnya ditambah [jumlah].
  void tambah(BarisOrder b) {
    final ada = cari(b.barangId);
    if (ada == null) {
      b.jumlah = b.jumlah.clamp(1, maksJumlahOrder);
      baris.add(b);
    } else {
      ada.jumlah = (ada.jumlah + b.jumlah).clamp(1, maksJumlahOrder);
    }
  }

  /// Ubah jumlah. ≤ 0 = barang dihapus dari daftar.
  void aturJumlah(String barangId, int jumlah) {
    final b = cari(barangId);
    if (b == null) return;
    if (jumlah <= 0) {
      hapus(barangId);
    } else {
      b.jumlah = jumlah > maksJumlahOrder ? maksJumlahOrder : jumlah;
    }
  }

  void hapus(String barangId) => baris.removeWhere((b) => b.barangId == barangId);

  /// Pesan kesalahan sebelum disimpan, atau null kalau siap.
  String? periksa() {
    if (baris.isEmpty) return 'Daftar order masih kosong.';
    if (supplierId == null || supplierId!.isEmpty) return 'Pilih "Order ke" (toko utama atau supplier).';
    for (final b in baris) {
      if (b.jumlah <= 0 || b.jumlah > maksJumlahOrder) return 'Jumlah "${b.nama}" tidak valid.';
    }
    return null;
  }

  Map<String, Object?> keJson() => {
        'supplierId': supplierId,
        'catatan': catatan,
        'baris': [for (final b in baris) b.keJson()],
      };

  static DaftarOrder dariJson(Map<String, Object?> j) => DaftarOrder(
        supplierId: j['supplierId'] as String?,
        catatan: (j['catatan'] as String?) ?? '',
        baris: [for (final x in (j['baris'] as List<Object?>? ?? const [])) BarisOrder.dariJson(Map<String, Object?>.from(x! as Map))],
      );
}
