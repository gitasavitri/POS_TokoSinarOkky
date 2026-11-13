/// Status stok untuk layar Cek stok & harga (revisi C) dan Produk & stok.
library;

enum StatusStok {
  aman('Aman'),
  hampirHabis('Hampir habis'),
  habis('Habis');

  const StatusStok(this.label);
  final String label;

  /// Perlu diperhatikan (filter "Hampir habis" di Cek stok menampilkan hampir habis dan habis).
  bool get perluDiorder => this != StatusStok.aman;
}

/// Habis kalau stok ≤ 0. Hampir habis kalau stok minimum diatur (> 0) dan stok ≤ stok minimum.
StatusStok statusStok({required int stok, required int stokMinimum}) {
  if (stok <= 0) return StatusStok.habis;
  if (stokMinimum > 0 && stok <= stokMinimum) return StatusStok.hampirHabis;
  return StatusStok.aman;
}
