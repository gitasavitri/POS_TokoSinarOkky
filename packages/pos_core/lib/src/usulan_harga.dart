import 'akses.dart';

/// Status satu usulan perubahan harga.
const statusUsulanMenunggu = 'menunggu';
const statusUsulanDisetujui = 'disetujui';
const statusUsulanDitolak = 'ditolak';

/// Perubahan harga oleh kasir (lewat barang masuk atau ubah harga) tidak langsung berlaku.
/// Ia menjadi usulan yang menunggu SPV/Admin. Perubahan oleh SPV/Admin langsung berlaku.
bool hargaPerluPersetujuan(Peran peran) => !bolehMenyetujui(peran);

/// Persentase turun dalam per-mil (permil), bilangan bulat: 156 = 15,6%.
/// Negatif kalau harga naik. 0 kalau harga lama tidak valid. Dibulatkan ke bawah (menuju nol).
int turunPerMil(int hargaLama, int hargaBaru) {
  if (hargaLama <= 0) return 0;
  return ((hargaLama - hargaBaru) * 1000) ~/ hargaLama;
}

/// "15,6%" dari per-mil. Selalu satu angka desimal.
String formatPerMil(int perMil) {
  final negatif = perMil < 0;
  final a = perMil.abs();
  return '${negatif ? '-' : ''}${a ~/ 10},${a % 10}%';
}

/// Boleh memutuskan usulan? Hanya SPV/Admin, dan hanya kalau masih menunggu.
/// Kalau sudah diputuskan (misalnya oleh SPV di toko), keputusan kedua ditolak.
String? alasanTidakBolehMemutuskan({required Peran peran, required String statusUsulan}) {
  if (!bolehMenyetujui(peran)) return 'Hanya SPV atau Admin yang boleh memutuskan usulan harga';
  if (statusUsulan != statusUsulanMenunggu) return 'Usulan ini sudah diputuskan';
  return null;
}
