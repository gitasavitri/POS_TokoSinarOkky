import 'package:app_pusat/data/api.dart';
import 'package:app_pusat/data/model.dart';
import 'package:pos_core/pos_core.dart';

/// Server palsu dengan data contoh (bukan data asli toko), untuk menguji layar tanpa server.
class ApiPalsu implements ApiPusat {
  final sekarang = DateTime.now().toUtc();
  bool sesiHabis = false;
  final hargaTerkirim = <({String barangId, int eceran, List<TingkatGrosir> grosir, String alasan})>[];
  final perangkatDicabut = <String>[];

  late final cabangContoh = [
    CabangPusat(id: 'c1', kode: 'A01', nama: 'Contoh Satu', alamat: 'Jl. Contoh No. 1', terakhirSinkron: sekarang.subtract(const Duration(minutes: 2)), jumlahPerangkat: 1),
    CabangPusat(id: 'c2', kode: 'B02', nama: 'Contoh Dua', alamat: 'Jl. Contoh No. 2', terakhirSinkron: sekarang.subtract(const Duration(hours: 5)), jumlahPerangkat: 1),
    const CabangPusat(id: 'c3', kode: 'C03', nama: 'Contoh Tiga', alamat: 'Jl. Contoh No. 3', terakhirSinkron: null, jumlahPerangkat: 0),
  ];

  Future<T> _jawab<T>(T nilai) async {
    if (sesiHabis) throw const GalatServer('Sesi berakhir, silakan masuk lagi', status: 401);
    return nilai;
  }

  @override
  Future<AdminPusat> masuk(String namaPengguna, String sandi, String kode) async {
    if (sandi != 'sandi-contoh-1' || kode != '123456') throw const GalatServer('Nama pengguna, kata sandi, atau kode tidak cocok', status: 401);
    return const AdminPusat(id: 'a1', nama: 'Admin Contoh');
  }

  @override
  Future<void> keluar() async {}

  @override
  Future<List<CabangPusat>> cabang() => _jawab(cabangContoh);

  @override
  Future<List<PerangkatPusat>> perangkat() => _jawab([
        PerangkatPusat(id: 'p1', nama: 'PC kasir 1', aktif: true, terdaftar: sekarang.subtract(const Duration(days: 3)), terakhirSinkron: sekarang, cabang: 'A01 · Contoh Satu'),
        PerangkatPusat(id: 'p0', nama: 'PC lama', aktif: false, terdaftar: sekarang.subtract(const Duration(days: 30)), terakhirSinkron: null, cabang: 'A01 · Contoh Satu'),
      ]);

  @override
  Future<void> cabutPerangkat(String id) async => perangkatDicabut.add(id);

  @override
  Future<(String, DateTime)> buatKodePendaftaran() => _jawab(('ABCDE-FGHJK', sekarang.add(const Duration(hours: 24))));

  @override
  Future<List<Kategori>> kategori() => _jawab(const [Kategori('k1', 'Sembako'), Kategori('k2', 'Minuman')]);

  @override
  Future<void> tambahKategori(String nama) async {}

  @override
  Future<List<BarangPusat>> barang({String kata = ''}) => _jawab([
        BarangPusat(
          id: 'b1', barcode: '8990001', nama: 'Gula Pasir 1 kg', satuan: 'pak', aktif: true, kategoriId: 'k1', kategori: 'Sembako',
          stokTotal: 120, jumlahToko: 2, hppTertinggi: 16200,
          harga: HargaPusat(eceran: 17500, grosir: const [TingkatGrosir(minQty: 10, harga: 17000)], berlakuMulai: sekarang),
        ),
        const BarangPusat(
          id: 'b2', barcode: '8990002', nama: 'Air Mineral 600 ml', satuan: 'botol', aktif: true, kategoriId: 'k2', kategori: 'Minuman',
          stokTotal: 300, jumlahToko: 3, hppTertinggi: 2600, harga: null,
        ),
      ]);

  @override
  Future<void> simpanBarang({String? id, required String? barcode, required String nama, required String kategoriId, required String satuan, bool aktif = true}) async {}

  @override
  Future<void> aturBarangToko({required String cabangId, required String barangId, required bool dijual}) async {}

  @override
  Future<List<String>> ubahHarga({required String barangId, required int eceran, required List<TingkatGrosir> grosir, required String alasan}) async {
    hargaTerkirim.add((barangId: barangId, eceran: eceran, grosir: grosir, alasan: alasan));
    return const [];
  }

  @override
  Future<List<BarangKembar>> barangKembar() => _jawab(const []);

  RingkasanCabang _r(String? id, String label, int jual, int n) => RingkasanCabang(
        cabangId: id, label: label, penjualanBersih: jual, jumlahTransaksi: n, tunai: jual - 36000, nonTunai: 36000,
        labaKotor: jual ~/ 12, jumlahBatal: id == 'c2' ? 1 : 0, totalRetur: 0,
      );

  @override
  Future<RingkasanPusat> ringkasan(DateTime dari, DateTime sampai, {String? cabangId}) => _jawab(RingkasanPusat(
        [_r('c1', 'A01 · Contoh Satu', 2480000, 61), _r('c2', 'B02 · Contoh Dua', 1325000, 38), _r('c3', 'C03 · Contoh Tiga', 0, 0)],
        _r(null, 'Semua toko', 3805000, 99),
      ));

  @override
  Future<Map<DateTime, int>> penjualanHarian(DateTime dari, DateTime sampai, {String? cabangId}) async {
    final hasil = <DateTime, int>{};
    var i = 0;
    for (var h = awalHariWibUtc(dari); h.isBefore(sampai); h = h.add(const Duration(days: 1))) {
      hasil[h] = 1500000 + (i++ % 5) * 450000;
    }
    return _jawab(hasil);
  }

  @override
  Future<List<Terlaris>> terlaris(DateTime dari, DateTime sampai, {String? cabangId, int batas = 10}) =>
      _jawab(const [Terlaris('Gula Pasir 1 kg', 42, 714000), Terlaris('Air Mineral 600 ml', 37, 129500), Terlaris('Mi Instan Goreng', 30, 105000)]);

  @override
  Future<List<TransaksiPusat>> transaksi(DateTime dari, DateTime sampai, {String? cabangId}) => _jawab([
        for (var i = 1; i <= 6; i++)
          TransaksiPusat(
            noTransaksi: 'TRX-A01-261105-${i.toString().padLeft(4, '0')}', waktu: sekarang.subtract(Duration(minutes: 7 * i)), total: 25000 * i,
            jumlahBarang: i, metode: i.isEven ? MetodeBayar.qris : MetodeBayar.tunai, kodeCabang: i > 4 ? 'B02' : 'A01', kasir: 'Kasir Contoh',
            batal: i == 3, retur: i == 5,
          ),
      ]);

  @override
  Future<List<StokBarang>> stok(String cabangId, {String kata = ''}) => _jawab(const [
        StokBarang(nama: 'Gula Pasir 1 kg', barcode: '8990001', satuan: 'pak', stok: 38, stokMinimum: 10, hpp: 16200, aktif: true),
        StokBarang(nama: 'Minyak Goreng 2 L', barcode: '8990002', satuan: 'pcs', stok: 2, stokMinimum: 5, hpp: 33000, aktif: true),
        StokBarang(nama: 'Sabun Mandi 85 g', barcode: '8990003', satuan: 'pcs', stok: 0, stokMinimum: 0, hpp: 3100, aktif: true),
      ]);

  @override
  Future<List<KaryawanPusat>> karyawan({String? cabangId}) => _jawab(const [
        KaryawanPusat(nama: 'Admin Contoh', namaPengguna: 'admin.contoh', peran: Peran.admin, kodeCabang: null, terkunci: false, aktif: true),
        KaryawanPusat(nama: 'Kasir Satu', namaPengguna: null, peran: Peran.kasir, kodeCabang: 'A01', terkunci: true, aktif: true),
        KaryawanPusat(nama: 'SPV Satu', namaPengguna: null, peran: Peran.spv, kodeCabang: 'A01', terkunci: false, aktif: true),
      ]);

  @override
  Future<List<LogPusat>> log(DateTime dari, DateTime sampai, {String? cabangId}) => _jawab([
        LogPusat(waktu: sekarang, aksi: 'batal_transaksi', detail: '{"no_transaksi":"TRX-A01-261105-0003","alasan":"Salah input"}', kodeCabang: 'A01', oleh: 'Kasir Satu', penyetuju: 'SPV Satu'),
        LogPusat(waktu: sekarang.subtract(const Duration(minutes: 5)), aksi: 'ubah_harga_pusat', detail: '{"harga":17500}', kodeCabang: null, oleh: 'Admin Contoh', penyetuju: null),
      ]);
}
