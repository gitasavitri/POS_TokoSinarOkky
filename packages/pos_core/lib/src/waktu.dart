/// Waktu: disimpan UTC (ISO 8601), ditampilkan WIB (UTC+7, tanpa musim panas).
library;

const _wib = Duration(hours: 7);

const namaBulanPendek = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];
const namaBulan = [
  'Januari',
  'Februari',
  'Maret',
  'April',
  'Mei',
  'Juni',
  'Juli',
  'Agustus',
  'September',
  'Oktober',
  'November',
  'Desember',
];
const namaHari = ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'];

/// `2026-11-05T06:09:00Z` (detik penuh, tanpa milidetik) — format yang disimpan di database.
String isoUtc(DateTime waktu) {
  final u = waktu.toUtc();
  String d2(int n) => n.toString().padLeft(2, '0');
  return '${u.year.toString().padLeft(4, '0')}-${d2(u.month)}-${d2(u.day)}'
      'T${d2(u.hour)}:${d2(u.minute)}:${d2(u.second)}Z';
}

String sekarangIso([DateTime Function() jam = DateTime.now]) => isoUtc(jam());

/// Jam dinding WIB dari waktu apa pun. Hasilnya DateTime "UTC" berisi angka jam WIB,
/// supaya tidak terpengaruh zona waktu komputer.
DateTime keWib(DateTime waktu) => waktu.toUtc().add(_wib);

/// Awal hari WIB (00:00 WIB) dalam UTC, untuk filter laporan per hari.
DateTime awalHariWibUtc(DateTime waktu) {
  final w = keWib(waktu);
  return DateTime.utc(w.year, w.month, w.day).subtract(_wib);
}

String _d2(int n) => n.toString().padLeft(2, '0');

/// `05/11/26 13:09` (WIB) — untuk struk.
String formatStruk(DateTime waktu) {
  final w = keWib(waktu);
  return '${_d2(w.day)}/${_d2(w.month)}/${_d2(w.year % 100)} ${_d2(w.hour)}:${_d2(w.minute)}';
}

/// `Kamis, 5 Nov 2026 · 13:09` (WIB) — untuk layar.
String formatLayar(DateTime waktu) {
  final w = keWib(waktu);
  return '${namaHari[w.weekday - 1]}, ${w.day} ${namaBulanPendek[w.month - 1]} ${w.year}'
      ' · ${_d2(w.hour)}:${_d2(w.minute)}';
}

/// `13.09` (WIB)
String formatJam(DateTime waktu) {
  final w = keWib(waktu);
  return '${_d2(w.hour)}.${_d2(w.minute)}';
}

/// `5 Nov 2026` (WIB)
String formatTanggal(DateTime waktu) {
  final w = keWib(waktu);
  return '${w.day} ${namaBulanPendek[w.month - 1]} ${w.year}';
}

/// `261105` (WIB) — bagian tanggal di nomor transaksi.
String kodeTanggal(DateTime waktu) {
  final w = keWib(waktu);
  return '${_d2(w.year % 100)}${_d2(w.month)}${_d2(w.day)}';
}

/// Nomor transaksi untuk struk: `TRX-A01-261105-0001`. Urut per cabang per hari (WIB).
String nomorTransaksi({required String kodeCabang, required DateTime waktu, required int urut}) {
  if (urut <= 0 || urut > 9999) throw RangeError.range(urut, 1, 9999, 'urut');
  return 'TRX-$kodeCabang-${kodeTanggal(waktu)}-${urut.toString().padLeft(4, '0')}';
}

/// Awalan nomor transaksi hari itu, untuk mencari urut terakhir: `TRX-A01-261105-`.
String awalanNomorTransaksi(String kodeCabang, DateTime waktu) => 'TRX-$kodeCabang-${kodeTanggal(waktu)}-';

/// Nomor dokumen barang masuk: `BM-A01-261105-001`.
String nomorBarangMasuk({required String kodeCabang, required DateTime waktu, required int urut}) =>
    'BM-$kodeCabang-${kodeTanggal(waktu)}-${urut.toString().padLeft(3, '0')}';
