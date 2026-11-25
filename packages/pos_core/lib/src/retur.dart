/// Aturan tukar / kembalikan barang (revisi F, 11 Nov 2026).
///
/// - Kasir boleh memproses sendiri tanpa SPV, tanpa batas nominal, maksimal [batasHariReturKasir] hari
///   dari tanggal struk. Lewat dari itu → PIN SPV.
/// - Uang retur selalu dikembalikan tunai (juga untuk transaksi QRIS/kartu/transfer).
/// - Tukar barang: nilai retur menjadi potongan di transaksi baru, pembeli membayar selisihnya.
///   Kalau nilai retur lebih besar dari belanja baru, sisanya dikembalikan tunai.
library;

import 'akses.dart';
import 'waktu.dart';

/// Kasir boleh menerima retur sendiri sampai sekian hari kalender (WIB) setelah tanggal struk.
/// Contoh: struk tanggal 1 → boleh sampai tanggal 4 (jam berapa pun). Tanggal 5 → PIN SPV.
const batasHariReturKasir = 3;

/// Selisih hari kalender WIB antara tanggal struk dan [sekarang]. Hari yang sama = 0.
int selisihHariWib(DateTime tanggalStruk, DateTime sekarang) {
  final a = keWib(tanggalStruk), b = keWib(sekarang);
  return DateTime.utc(b.year, b.month, b.day).difference(DateTime.utc(a.year, a.month, a.day)).inDays;
}

/// Siapa boleh memproses tukar/retur untuk struk bertanggal [tanggalStruk].
/// Kasir: ≤ [batasHariReturKasir] hari langsung, lebih dari itu PIN SPV. SPV/Admin: selalu boleh.
Akses aksesRetur(Peran peran, {required DateTime tanggalStruk, required DateTime sekarang}) {
  if (peran != Peran.kasir) return Akses.ya;
  return selisihHariWib(tanggalStruk, sekarang) <= batasHariReturKasir ? Akses.ya : Akses.pinSpv;
}

/// Nomor struk retur: `RTR-A01-261111-0001`. Urut per cabang per hari (WIB).
String nomorRetur({required String kodeCabang, required DateTime waktu, required int urut}) {
  if (urut <= 0 || urut > 9999) throw RangeError.range(urut, 1, 9999, 'urut');
  return 'RTR-$kodeCabang-${kodeTanggal(waktu)}-${urut.toString().padLeft(4, '0')}';
}

/// Awalan nomor retur hari itu, untuk mencari urut terakhir: `RTR-A01-261111-`.
String awalanNomorRetur(String kodeCabang, DateTime waktu) => 'RTR-$kodeCabang-${kodeTanggal(waktu)}-';

/// Pembagian uang saat tukar barang.
class HitungTukar {
  const HitungTukar._({required this.nilaiRetur, required this.totalBelanja, required this.potongan});

  /// Nilai barang yang dikembalikan pembeli.
  final int nilaiRetur;

  /// Total belanja baru (harga sekarang).
  final int totalBelanja;

  /// Bagian nilai retur yang dipakai memotong belanja baru.
  final int potongan;

  /// Yang harus dibayar pembeli (≥ 0).
  int get bayar => totalBelanja - potongan;

  /// Sisa nilai retur yang dikembalikan tunai (kalau barang yang dikembalikan lebih mahal).
  int get sisaDikembalikan => nilaiRetur - potongan;
}

HitungTukar hitungTukar({required int nilaiRetur, required int totalBelanja}) {
  if (nilaiRetur < 0) throw ArgumentError.value(nilaiRetur, 'nilaiRetur');
  if (totalBelanja < 0) throw ArgumentError.value(totalBelanja, 'totalBelanja');
  return HitungTukar._(
    nilaiRetur: nilaiRetur,
    totalBelanja: totalBelanja,
    potongan: nilaiRetur < totalBelanja ? nilaiRetur : totalBelanja,
  );
}

/// Jumlah yang masih boleh diretur untuk satu barang di struk.
int sisaBolehRetur({required int dibeli, required int sudahDiretur}) {
  final n = dibeli - sudahDiretur;
  return n < 0 ? 0 : n;
}

/// Cek isian retur. [pilihan]: jumlah diretur per baris; [sisa]: jumlah yang masih boleh per baris.
/// Mengembalikan pesan galat, atau null kalau boleh disimpan.
String? cekRetur({required Map<String, int> pilihan, required Map<String, int> sisa, required String alasan}) {
  final dipilih = {for (final e in pilihan.entries) if (e.value != 0) e.key: e.value};
  if (dipilih.isEmpty) return 'Pilih barang yang dikembalikan.';
  for (final e in dipilih.entries) {
    if (e.value < 0) return 'Jumlah tidak boleh minus.';
    final s = sisa[e.key];
    if (s == null) return 'Barang tidak ada di struk ini.';
    if (e.value > s) return 'Jumlah melebihi yang dibeli (sisa $s).';
  }
  if (alasan.trim().length < 3) return 'Isi alasan (mis. kemasan rusak, salah beli).';
  return null;
}

/// Pesan bawah struk tidak boleh menulis aturan tukar/retur (revisi F: supaya pembeli tidak terbiasa retur).
/// Mengembalikan pesan galat, atau null kalau boleh.
String? cekPesanStruk(String pesan) {
  final p = pesan.toLowerCase();
  const kata = ['tukar', 'retur', 'dikembalikan', 'kembalikan', 'pengembalian', 'garansi', 'refund'];
  for (final k in kata) {
    if (p.contains(k)) return 'Pesan struk tidak boleh menulis aturan tukar/retur (kata "$k").';
  }
  return null;
}
