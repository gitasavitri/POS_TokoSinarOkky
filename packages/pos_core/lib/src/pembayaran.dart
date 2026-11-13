/// Aturan pembayaran.
library;

import 'uang.dart';

enum MetodeBayar {
  tunai('tunai', 'Tunai'),
  qris('qris', 'QRIS'),
  kartu('kartu', 'Kartu debit / kredit'),
  transfer('transfer', 'Transfer bank');

  const MetodeBayar(this.kode, this.label);

  /// Nilai yang disimpan di database (kolom `pembayaran.metode`).
  final String kode;
  final String label;

  bool get perluReferensi => this == kartu || this == transfer;

  static MetodeBayar dariKode(String kode) =>
      values.firstWhere((m) => m.kode == kode, orElse: () => throw ArgumentError.value(kode, 'kode'));
}

class HasilPembayaran {
  const HasilPembayaran._({
    required this.boleh,
    required this.diterima,
    required this.kembalian,
    this.kurang = 0,
    this.pesan,
  });

  final bool boleh;

  /// Uang yang dicatat sebagai diterima. Non-tunai = total.
  final int diterima;
  final int kembalian;
  final int kurang;
  final String? pesan;
}

/// Cek pembayaran sebelum transaksi disimpan.
/// Tunai: uang diterima ≥ total. Kartu/transfer: wajib nomor referensi.
HasilPembayaran cekPembayaran({
  required MetodeBayar metode,
  required int total,
  int uangDiterima = 0,
  String? noReferensi,
}) {
  if (total < 0) throw ArgumentError.value(total, 'total');
  if (metode == MetodeBayar.tunai) {
    if (uangDiterima < total) {
      final kurang = total - uangDiterima;
      return HasilPembayaran._(
        boleh: false,
        diterima: uangDiterima,
        kembalian: 0,
        kurang: kurang,
        pesan: 'Uang kurang ${formatRupiah(kurang)}',
      );
    }
    return HasilPembayaran._(boleh: true, diterima: uangDiterima, kembalian: uangDiterima - total);
  }
  if (metode.perluReferensi && (noReferensi == null || noReferensi.trim().isEmpty)) {
    return HasilPembayaran._(
      boleh: false,
      diterima: total,
      kembalian: 0,
      pesan: 'Isi nomor referensi dari struk EDC / bukti transfer',
    );
  }
  return HasilPembayaran._(boleh: true, diterima: total, kembalian: 0);
}
