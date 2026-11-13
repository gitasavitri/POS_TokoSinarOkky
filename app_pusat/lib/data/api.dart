import 'package:pos_core/pos_core.dart';

import 'model.dart';

/// Semua yang dibutuhkan Aplikasi Pusat dari Server Pusat. Dibuat sebagai antarmuka supaya
/// layar bisa diuji dengan data contoh tanpa server.
abstract class ApiPusat {
  Future<AdminPusat> masuk(String namaPengguna, String sandi, String kode);
  Future<void> keluar();

  Future<List<CabangPusat>> cabang();
  Future<List<PerangkatPusat>> perangkat();
  Future<void> cabutPerangkat(String id);
  Future<(String kode, DateTime kedaluwarsa)> buatKodePendaftaran();

  Future<List<Kategori>> kategori();
  Future<void> tambahKategori(String nama);
  Future<List<BarangPusat>> barang({String kata = ''});
  Future<void> simpanBarang({String? id, required String? barcode, required String nama, required String kategoriId, required String satuan, bool aktif = true});
  Future<void> aturBarangToko({required String cabangId, required String barangId, required bool dijual});

  /// Salin daftar barang (rak) dari toko lain ke [keCabangId] (revisi I). [dariCabangId] null = semua barang.
  /// Stok tidak ikut. Mengembalikan jumlah barang yang ditambahkan, yang sudah ada, dan harga yang ikut disalin.
  Future<HasilSalinBarang> salinDaftarBarang({required String keCabangId, String? dariCabangId});

  /// Harga baru untuk semua toko. Mengembalikan peringatan (mis. harga ≤ HPP).
  Future<List<String>> ubahHarga({required String barangId, required int eceran, required List<TingkatGrosir> grosir, required String alasan});
  Future<List<BarangKembar>> barangKembar();

  Future<RingkasanPusat> ringkasan(DateTime dari, DateTime sampai, {String? cabangId});

  /// Kunci = awal hari WIB (dalam UTC).
  Future<Map<DateTime, int>> penjualanHarian(DateTime dari, DateTime sampai, {String? cabangId});
  Future<List<Terlaris>> terlaris(DateTime dari, DateTime sampai, {String? cabangId, int batas = 10});
  Future<List<TransaksiPusat>> transaksi(DateTime dari, DateTime sampai, {String? cabangId});
  Future<List<StokBarang>> stok(String cabangId, {String kata = ''});
  Future<List<KaryawanPusat>> karyawan({String? cabangId});
  Future<List<LogPusat>> log(DateTime dari, DateTime sampai, {String? cabangId});
}

/// Implementasi sungguhan lewat HTTPS.
class ApiHttp implements ApiPusat {
  ApiHttp(this.dasar);
  final Uri dasar;
  String? _token;

  KlienServer get _k => KlienServer(dasar, token: _token);

  Future<Map<String, Object?>> _minta(String metode, String jalur, {Object? isi, Map<String, String>? query}) async {
    final k = _k;
    try {
      return await k.minta(metode, jalur, isi: isi, query: query);
    } finally {
      k.tutup();
    }
  }

  Future<List<Map<String, Object?>>> _daftar(String jalur, [Map<String, String>? query]) async {
    final r = await _minta('GET', jalur, query: query);
    return [for (final x in r['data']! as List) Map<String, Object?>.from(x as Map)];
  }

  Map<String, String> _rentang(DateTime dari, DateTime sampai, String? cabangId, [Map<String, String> lain = const {}]) => {
        'dari': isoUtc(dari),
        'sampai': isoUtc(sampai),
        'cabang_id': ?cabangId,
        ...lain,
      };

  /// Cek alamat server sebelum disimpan.
  static Future<void> cekServer(Uri dasar) async {
    final k = KlienServer(dasar);
    try {
      final r = await k.minta('GET', '/api/sehat');
      if (r['ok'] != true) throw const GalatServer('Alamat ini bukan Server Pusat POS');
    } finally {
      k.tutup();
    }
  }

  @override
  Future<AdminPusat> masuk(String namaPengguna, String sandi, String kode) async {
    final r = await _minta('POST', '/api/pusat/masuk', isi: {'nama_pengguna': namaPengguna, 'sandi': sandi, 'kode': kode});
    _token = r['token']! as String;
    final p = r['pengguna']! as Map;
    return AdminPusat(id: p['id'] as String, nama: p['nama'] as String);
  }

  @override
  Future<void> keluar() async {
    if (_token == null) return;
    try {
      await _minta('POST', '/api/pusat/keluar');
    } on GalatServer {
      // Sesi mungkin sudah habis; tetap dianggap keluar.
    } finally {
      _token = null;
    }
  }

  @override
  Future<List<CabangPusat>> cabang() async => [for (final j in await _daftar('/api/pusat/cabang')) CabangPusat.dariJson(j)];

  @override
  Future<List<PerangkatPusat>> perangkat() async => [for (final j in await _daftar('/api/pusat/perangkat')) PerangkatPusat.dariJson(j)];

  @override
  Future<void> cabutPerangkat(String id) => _minta('POST', '/api/pusat/perangkat/$id/cabut');

  @override
  Future<(String, DateTime)> buatKodePendaftaran() async {
    final r = await _minta('POST', '/api/pusat/kode-pendaftaran');
    return (r['kode']! as String, DateTime.parse(r['kedaluwarsa']! as String));
  }

  @override
  Future<List<Kategori>> kategori() async => [for (final j in await _daftar('/api/pusat/kategori')) Kategori(j['id']! as String, j['nama']! as String)];

  @override
  Future<void> tambahKategori(String nama) => _minta('POST', '/api/pusat/kategori', isi: {'nama': nama});

  @override
  Future<List<BarangPusat>> barang({String kata = ''}) async =>
      [for (final j in await _daftar('/api/pusat/barang', {'kata': kata})) BarangPusat.dariJson(j)];

  @override
  Future<void> simpanBarang({String? id, required String? barcode, required String nama, required String kategoriId, required String satuan, bool aktif = true}) =>
      _minta('POST', '/api/pusat/barang', isi: {
        'id': ?id,
        'barcode': barcode,
        'nama': nama,
        'kategori_id': kategoriId,
        'satuan': satuan,
        'aktif': aktif ? 1 : 0,
      });

  @override
  Future<void> aturBarangToko({required String cabangId, required String barangId, required bool dijual}) =>
      _minta('POST', '/api/pusat/barang-cabang', isi: {'cabang_id': cabangId, 'barang_id': barangId, 'aktif': dijual ? 1 : 0});

  @override
  Future<HasilSalinBarang> salinDaftarBarang({required String keCabangId, String? dariCabangId}) async {
    final r = await _minta('POST', '/api/pusat/salin-daftar-barang', isi: {'ke_cabang_id': keCabangId, 'dari_cabang_id': dariCabangId});
    return HasilSalinBarang.dariJson(r);
  }

  @override
  Future<List<String>> ubahHarga({required String barangId, required int eceran, required List<TingkatGrosir> grosir, required String alasan}) async {
    final r = await _minta('POST', '/api/pusat/harga', isi: {
      'barang_id': barangId,
      'harga': eceran,
      'grosir': [for (final g in grosir) {'min_qty': g.minQty, 'harga': g.harga}],
      'alasan': alasan,
    });
    return [for (final p in (r['peringatan'] as List? ?? const [])) '$p'];
  }

  @override
  Future<List<BarangKembar>> barangKembar() async => [
        for (final j in await _daftar('/api/pusat/barang-ganda'))
          BarangKembar(j['barcode']! as String, j['id']! as String, j['nama']! as String, DateTime.parse(j['created_at']! as String)),
      ];

  @override
  Future<RingkasanPusat> ringkasan(DateTime dari, DateTime sampai, {String? cabangId}) async {
    final r = await _minta('GET', '/api/pusat/ringkasan', query: _rentang(dari, sampai, cabangId));
    return RingkasanPusat(
      [for (final j in r['per_cabang']! as List) RingkasanCabang.dariJson(Map<String, Object?>.from(j as Map))],
      RingkasanCabang.dariJson(Map<String, Object?>.from(r['total']! as Map)),
    );
  }

  @override
  Future<Map<DateTime, int>> penjualanHarian(DateTime dari, DateTime sampai, {String? cabangId}) async {
    final hasil = <DateTime, int>{};
    for (var h = awalHariWibUtc(dari); h.isBefore(sampai); h = h.add(const Duration(days: 1))) {
      hasil[h] = 0;
    }
    for (final j in await _daftar('/api/pusat/penjualan-harian', _rentang(dari, sampai, cabangId))) {
      final t = DateTime.parse('${j['tanggal']}T00:00:00Z').subtract(const Duration(hours: 7));
      hasil[t] = (j['total'] as num).toInt();
    }
    return hasil;
  }

  @override
  Future<List<Terlaris>> terlaris(DateTime dari, DateTime sampai, {String? cabangId, int batas = 10}) async => [
        for (final j in await _daftar('/api/pusat/terlaris', _rentang(dari, sampai, cabangId, {'batas': '$batas'})))
          Terlaris(j['nama']! as String, (j['qty'] as num).toInt(), (j['total'] as num).toInt()),
      ];

  @override
  Future<List<TransaksiPusat>> transaksi(DateTime dari, DateTime sampai, {String? cabangId}) async =>
      [for (final j in await _daftar('/api/pusat/transaksi', _rentang(dari, sampai, cabangId))) TransaksiPusat.dariJson(j)];

  @override
  Future<List<StokBarang>> stok(String cabangId, {String kata = ''}) async =>
      [for (final j in await _daftar('/api/pusat/stok', {'cabang_id': cabangId, 'kata': kata})) StokBarang.dariJson(j)];

  @override
  Future<List<KaryawanPusat>> karyawan({String? cabangId}) async =>
      [for (final j in await _daftar('/api/pusat/karyawan', {'cabang_id': ?cabangId})) KaryawanPusat.dariJson(j)];

  @override
  Future<List<LogPusat>> log(DateTime dari, DateTime sampai, {String? cabangId}) async =>
      [for (final j in await _daftar('/api/pusat/log', _rentang(dari, sampai, cabangId))) LogPusat.dariJson(j)];
}
