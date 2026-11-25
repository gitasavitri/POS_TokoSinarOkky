import 'package:pos_core/pos_core.dart';

/// Pilihan periode laporan.
enum Periode {
  hariIni('Hari ini'),
  kemarin('Kemarin'),
  tujuhHari('7 hari'),
  bulanIni('Bulan ini'),
  bulanLalu('Bulan lalu'),
  tahunIni('Tahun ini');

  const Periode(this.label);
  final String label;

  /// (dari, sampai) dalam UTC, batas hari mengikuti WIB.
  (DateTime, DateTime) rentang(DateTime sekarang) {
    final hari = awalHariWibUtc(sekarang);
    final w = keWib(sekarang);
    DateTime awalBulanWib(int tahun, int bulan) => DateTime.utc(tahun, bulan).subtract(const Duration(hours: 7));
    return switch (this) {
      Periode.hariIni => (hari, hari.add(const Duration(days: 1))),
      Periode.kemarin => (hari.subtract(const Duration(days: 1)), hari),
      Periode.tujuhHari => (hari.subtract(const Duration(days: 6)), hari.add(const Duration(days: 1))),
      Periode.bulanIni => (awalBulanWib(w.year, w.month), awalBulanWib(w.year, w.month + 1)),
      Periode.bulanLalu => (awalBulanWib(w.year, w.month - 1), awalBulanWib(w.year, w.month)),
      Periode.tahunIni => (awalBulanWib(w.year, 1), awalBulanWib(w.year + 1, 1)),
    };
  }
}
