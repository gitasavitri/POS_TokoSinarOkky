/// HPP rata-rata tertimbang (asumsi, AGENTS.md bagian 5 — menunggu keputusan pemilik).
library;

import 'uang.dart';

/// `hpp_baru = (stok_lama × hpp_lama + jumlah_masuk × hpp_masuk) / (stok_lama + jumlah_masuk)`,
/// dibulatkan ke rupiah terdekat. Kalau stok lama ≤ 0 (atau belum ada HPP), HPP baru = HPP masuk.
int hppRataRata({
  required int stokLama,
  required int? hppLama,
  required int jumlahMasuk,
  required int hppMasuk,
}) {
  if (jumlahMasuk <= 0) {
    throw ArgumentError.value(jumlahMasuk, 'jumlahMasuk', 'harus lebih dari 0');
  }
  if (hppMasuk < 0) throw ArgumentError.value(hppMasuk, 'hppMasuk');
  if (stokLama <= 0 || hppLama == null) return hppMasuk;
  return bagiBulat(stokLama * hppLama + jumlahMasuk * hppMasuk, stokLama + jumlahMasuk);
}
