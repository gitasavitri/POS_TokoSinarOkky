/// Aturan harga eceran dan harga grosir bertingkat (AGENTS.md bagian 5).
library;

import 'uang.dart';

/// Satu tingkat harga grosir: beli minimal [minQty] → harga [harga] per satuan.
class TingkatGrosir {
  const TingkatGrosir({required this.minQty, required this.harga});

  final int minQty;
  final int harga;

  @override
  bool operator ==(Object other) => other is TingkatGrosir && other.minQty == minQty && other.harga == harga;

  @override
  int get hashCode => Object.hash(minQty, harga);

  @override
  String toString() => 'min $minQty: ${formatRupiah(harga)}';
}

/// Harga satu barang: eceran + tingkat grosir (boleh kosong).
class HargaBarang {
  HargaBarang({required this.eceran, List<TingkatGrosir> grosir = const []})
    : grosir = List<TingkatGrosir>.unmodifiable(
        List<TingkatGrosir>.of(grosir)..sort((a, b) => a.minQty.compareTo(b.minQty)),
      );

  final int eceran;

  /// Diurutkan dari `minQty` terkecil.
  final List<TingkatGrosir> grosir;
}

/// Hasil harga untuk satu baris belanja.
class HargaBaris {
  const HargaBaris({required this.hargaSatuan, required this.qty, required this.isGrosir});

  final int hargaSatuan;
  final int qty;
  final bool isGrosir;

  int get subtotal => hargaSatuan * qty;
}

/// Pilih tingkat dengan `minQty` terbesar yang ≤ [qty].
/// Harga grosir berlaku untuk **seluruh** jumlah di baris itu.
HargaBaris hitungHargaBaris(HargaBarang harga, int qty) {
  if (qty <= 0) throw ArgumentError.value(qty, 'qty', 'harus lebih dari 0');
  TingkatGrosir? terpilih;
  for (final t in harga.grosir) {
    if (t.minQty <= qty) terpilih = t;
  }
  return terpilih == null
      ? HargaBaris(hargaSatuan: harga.eceran, qty: qty, isGrosir: false)
      : HargaBaris(hargaSatuan: terpilih.harga, qty: qty, isGrosir: true);
}

/// Cek tingkat grosir yang diisi pengguna. Mengembalikan daftar pesan kesalahan
/// per tingkat (index sesuai urutan [tingkat] apa adanya). Kosong = semua benar.
///
/// Aturan: min ≥ 2, harga > 0, harga < eceran, harga > HPP (kalau HPP diketahui),
/// min_qty naik dari tingkat sebelumnya, harga tidak boleh naik untuk tingkat berikutnya.
Map<int, String> periksaTingkatGrosir({
  required int eceran,
  required int? hpp,
  required List<TingkatGrosir> tingkat,
}) {
  final salah = <int, String>{};
  for (var i = 0; i < tingkat.length; i++) {
    final t = tingkat[i];
    if (t.minQty < 2) {
      salah[i] = 'Jumlah minimal harus 2 atau lebih.';
    } else if (i > 0 && t.minQty <= tingkat[i - 1].minQty) {
      salah[i] = 'Jumlah minimal harus lebih besar dari tingkat sebelumnya.';
    } else if (t.harga <= 0) {
      salah[i] = 'Harga grosir harus diisi.';
    } else if (t.harga >= eceran) {
      salah[i] = 'Harga grosir harus lebih murah dari harga eceran.';
    } else if (hpp != null && t.harga <= hpp) {
      salah[i] = 'Rugi: harga grosir sama dengan atau di bawah HPP.';
    } else if (i > 0 && t.harga > tingkat[i - 1].harga) {
      salah[i] = 'Harga tingkat ini lebih mahal dari tingkat sebelumnya.';
    }
  }
  return salah;
}

/// Hasil pengecekan perubahan harga tanpa barang masuk.
class CekUbahHarga {
  const CekUbahHarga({required this.perluPinSpv, this.alasan});

  final bool perluPinSpv;

  /// Kenapa perlu PIN SPV (untuk ditampilkan), null kalau tidak perlu.
  final String? alasan;
}

/// Harga turun lebih dari [batasTurunPersen]% atau harga baru ≤ HPP → perlu PIN SPV.
CekUbahHarga cekUbahHarga({
  required int hargaLama,
  required int hargaBaru,
  required int? hpp,
  int batasTurunPersen = 10,
}) {
  if (hargaBaru <= 0) {
    throw ArgumentError.value(hargaBaru, 'hargaBaru', 'harus lebih dari 0');
  }
  if (hpp != null && hargaBaru <= hpp) {
    return CekUbahHarga(
      perluPinSpv: true,
      alasan: 'Harga baru sama dengan atau di bawah HPP (${formatRupiah(hpp)}).',
    );
  }
  // turun > batas%  ⇔  (lama − baru) × 100 > batas × lama   (tanpa pecahan)
  if (hargaBaru < hargaLama && (hargaLama - hargaBaru) * 100 > batasTurunPersen * hargaLama) {
    return CekUbahHarga(perluPinSpv: true, alasan: 'Harga turun lebih dari $batasTurunPersen%.');
  }
  return const CekUbahHarga(perluPinSpv: false);
}

/// Persentase perubahan harga, 1 angka desimal, untuk tampilan saja. `17500 → 18000` → `"+2,9%"`.
String teksPerubahanPersen(int lama, int baru) {
  if (lama <= 0) return '';
  final perSeribu = bagiBulat((baru - lama) * 1000, lama);
  final abs = perSeribu.abs();
  final teks = '${abs ~/ 10},${abs % 10}%';
  if (perSeribu > 0) return '+$teks';
  if (perSeribu < 0) return '-$teks';
  return '0,0%';
}
