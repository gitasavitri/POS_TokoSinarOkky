/// Aturan uang tunai per shift: kas keluar/masuk (revisi K) dan tutup shift hitung buta (revisi H).
library;

import 'akses.dart';

// ------------------------------------------------------------------ kas keluar / masuk

enum JenisKas {
  /// Uang diambil dari uang kasir (bayar titipan, beli barang dari sales eceran, dll.).
  keluar('keluar', 'Kas keluar'),

  /// Uang ditambahkan ke uang kasir (tambah uang kecil, dll.).
  masuk('masuk', 'Kas masuk');

  const JenisKas(this.kode, this.label);
  final String kode;
  final String label;

  static JenisKas dariKode(String kode) =>
      values.firstWhere((j) => j.kode == kode, orElse: () => throw ArgumentError.value(kode, 'kode'));
}

/// Kas keluar/masuk mulai jumlah ini butuh PIN SPV kalau dilakukan kasir (keputusan 11 Nov 2026).
const batasKasTanpaPin = 100000;

/// Siapa boleh mencatat kas keluar/masuk sebesar [jumlah].
Akses aksesKas(Peran peran, int jumlah) {
  if (peran != Peran.kasir) return Akses.ya;
  return jumlah >= batasKasTanpaPin ? Akses.pinSpv : Akses.ya;
}

/// Cek isian kas keluar/masuk. Mengembalikan pesan galat, atau null kalau boleh disimpan.
String? cekKas({required int jumlah, required String keterangan}) {
  if (jumlah <= 0) return 'Isi jumlah uang (lebih dari Rp 0).';
  if (keterangan.trim().length < 3) return 'Isi keterangan (untuk apa uangnya).';
  return null;
}

// ------------------------------------------------------------------ uang tunai seharusnya

/// Uang tunai yang seharusnya ada di kasir saat tutup shift.
int hitungKasSeharusnya({
  required int modalAwal,
  required int penjualanTunai,
  required int returTunai,
  int kasMasuk = 0,
  int kasKeluar = 0,
}) =>
    modalAwal + penjualanTunai - returTunai + kasMasuk - kasKeluar;

// ------------------------------------------------------------------ hitung buta

/// Kasir boleh menghitung ulang sendiri sebanyak ini (setelah hitungan pertama). Lebih dari itu butuh PIN SPV.
const maksHitungUlangKasir = 2;

/// Akses untuk menyimpan hitungan uang berikutnya, kalau sudah ada [sudahDihitung] hitungan di shift ini.
/// Hitungan ke-1 (pertama) dan 2 hitung ulang boleh langsung; berikutnya kasir butuh PIN SPV.
Akses aksesHitungUang(Peran peran, int sudahDihitung) {
  if (peran != Peran.kasir) return Akses.ya;
  return sudahDihitung <= maksHitungUlangKasir ? Akses.ya : Akses.pinSpv;
}

/// Sisa hitung ulang yang boleh dilakukan kasir tanpa PIN SPV.
int sisaHitungUlang(int sudahDihitung) {
  final sisa = maksHitungUlangKasir - (sudahDihitung - 1);
  if (sudahDihitung <= 0) return maksHitungUlangKasir;
  return sisa < 0 ? 0 : sisa;
}
