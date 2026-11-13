import 'package:pos_core/pos_core.dart';
import 'package:test/test.dart';

void main() {
  group('batas 3 hari (WIB)', () {
    // Struk 1 Nov 2026 pukul 23.30 WIB = 16.30 UTC.
    final struk = DateTime.utc(2026, 11, 1, 16, 30);

    test('selisih hari memakai tanggal WIB, bukan 24 jam', () {
      expect(selisihHariWib(struk, DateTime.utc(2026, 11, 1, 16, 59)), 0);
      // 2 Nov 00.10 WIB: sudah hari berikutnya walau baru 40 menit.
      expect(selisihHariWib(struk, DateTime.utc(2026, 11, 1, 17, 10)), 1);
      expect(selisihHariWib(struk, DateTime.utc(2026, 11, 4, 16, 59)), 3); // 4 Nov 23.59 WIB
      expect(selisihHariWib(struk, DateTime.utc(2026, 11, 4, 17, 0)), 4); // 5 Nov 00.00 WIB
    });

    test('kasir: sampai hari ke-3 langsung, hari ke-4 PIN SPV', () {
      expect(aksesRetur(Peran.kasir, tanggalStruk: struk, sekarang: DateTime.utc(2026, 11, 4, 16, 59)), Akses.ya);
      expect(aksesRetur(Peran.kasir, tanggalStruk: struk, sekarang: DateTime.utc(2026, 11, 4, 17, 0)), Akses.pinSpv);
      expect(aksesRetur(Peran.kasir, tanggalStruk: struk, sekarang: DateTime.utc(2026, 12, 30)), Akses.pinSpv);
    });

    test('SPV/Admin tidak dibatasi hari', () {
      for (final p in [Peran.spv, Peran.admin]) {
        expect(aksesRetur(p, tanggalStruk: struk, sekarang: DateTime.utc(2027, 1, 1)), Akses.ya);
      }
    });

    test('izin terimaRetur untuk kasir sekarang boleh', () {
      expect(aksesUntuk(Peran.kasir, Izin.terimaRetur), Akses.ya);
    });
  });

  test('nomor retur RTR-<kode>-<YYMMDD WIB>-<urut>', () {
    // 11 Nov 2026 20.00 UTC = 12 Nov 03.00 WIB.
    final w = DateTime.utc(2026, 11, 11, 20);
    expect(nomorRetur(kodeCabang: 'A01', waktu: w, urut: 7), 'RTR-A01-261112-0007');
    expect(awalanNomorRetur('A01', w), 'RTR-A01-261112-');
    expect(() => nomorRetur(kodeCabang: 'A01', waktu: w, urut: 0), throwsRangeError);
  });

  group('hitung tukar', () {
    test('barang baru lebih mahal: pembeli bayar selisih', () {
      final h = hitungTukar(nilaiRetur: 7000, totalBelanja: 12500);
      expect(h.potongan, 7000);
      expect(h.bayar, 5500);
      expect(h.sisaDikembalikan, 0);
    });

    test('barang baru lebih murah: sisa dikembalikan tunai', () {
      final h = hitungTukar(nilaiRetur: 17500, totalBelanja: 3500);
      expect(h.potongan, 3500);
      expect(h.bayar, 0);
      expect(h.sisaDikembalikan, 14000);
    });

    test('sama persis', () {
      final h = hitungTukar(nilaiRetur: 3500, totalBelanja: 3500);
      expect((h.bayar, h.sisaDikembalikan), (0, 0));
    });

    test('nilai minus ditolak', () {
      expect(() => hitungTukar(nilaiRetur: -1, totalBelanja: 0), throwsArgumentError);
    });
  });

  group('cek isian retur', () {
    final sisa = {'a': 3, 'b': 1};
    test('wajib pilih barang dan alasan', () {
      expect(cekRetur(pilihan: {}, sisa: sisa, alasan: 'rusak'), isNotNull);
      expect(cekRetur(pilihan: {'a': 0}, sisa: sisa, alasan: 'rusak'), isNotNull);
      expect(cekRetur(pilihan: {'a': 1}, sisa: sisa, alasan: ' '), isNotNull);
      expect(cekRetur(pilihan: {'a': 1}, sisa: sisa, alasan: 'kemasan sobek'), isNull);
    });

    test('jumlah tidak boleh melebihi sisa atau barang di luar struk', () {
      expect(cekRetur(pilihan: {'b': 2}, sisa: sisa, alasan: 'salah beli'), contains('sisa 1'));
      expect(cekRetur(pilihan: {'x': 1}, sisa: sisa, alasan: 'salah beli'), isNotNull);
      expect(cekRetur(pilihan: {'a': -1}, sisa: sisa, alasan: 'salah beli'), isNotNull);
    });

    test('sisa boleh retur', () {
      expect(sisaBolehRetur(dibeli: 5, sudahDiretur: 2), 3);
      expect(sisaBolehRetur(dibeli: 2, sudahDiretur: 2), 0);
    });
  });

  test('pesan struk tidak boleh menulis aturan tukar/retur', () {
    expect(cekPesanStruk('Barang yang sudah dibeli tidak dapat dikembalikan'), isNotNull);
    expect(cekPesanStruk('Tidak bisa DITUKAR'), isNotNull);
    expect(cekPesanStruk('Buka setiap hari 07.00-21.00'), isNull);
    expect(cekPesanStruk(''), isNull);
  });

  group('struk', () {
    final waktu = DateTime.utc(2026, 11, 11, 3, 15);

    test('struk retur: nomor RTR, struk asal, tanpa aturan retur', () {
      final d = DataStrukRetur(
        namaToko: 'Toko Contoh',
        namaCabang: 'Cabang Satu',
        alamat: 'Jl. Contoh 1',
        noRetur: 'RTR-A01-261111-0001',
        noTransaksiAsal: 'TRX-A01-261110-0004',
        waktu: waktu,
        namaKasir: 'Kasir Contoh',
        item: const [
          ItemStrukRetur(nama: 'Teh Botol 350ml', qty: 2, hargaSatuan: 3500),
          ItemStrukRetur(nama: 'Mi Instan Goreng', qty: 1, hargaSatuan: 3100, rusak: true),
        ],
      );
      final teks = strukSebagaiTeks(susunStrukRetur(d));
      expect(teks, contains('STRUK RETUR'));
      expect(teks, contains('RTR-A01-261111-0001'));
      expect(teks, contains('TRX-A01-261110-0004'));
      expect(teks, contains('-7.000'));
      expect(teks, contains('(rusak)'));
      expect(teks, contains('10.100'));
      expect(teks.toLowerCase(), isNot(contains('tidak dapat')));
      for (final l in teks.split('\n')) {
        expect(l.length, lessThanOrEqualTo(lebarStruk), reason: l);
      }
    });

    test('struk tukar: satu struk, potongan, total bayar = selisih', () {
      final d = DataStruk(
        namaToko: 'Toko Contoh',
        namaCabang: 'Cabang Satu',
        alamat: '',
        noTransaksi: 'TRX-A01-261111-0002',
        waktu: waktu,
        namaKasir: 'Kasir Contoh',
        item: const [ItemStruk(nama: 'Sirup Melon 1L', qty: 1, hargaSatuan: 12500, isGrosir: false)],
        metode: MetodeBayar.tunai,
        diterima: 10000,
        kembalian: 4500,
        tukar: const TukarStruk(
          noRetur: 'RTR-A01-261111-0001',
          noTransaksiAsal: 'TRX-A01-261110-0004',
          item: [ItemStrukRetur(nama: 'Teh Botol 350ml', qty: 2, hargaSatuan: 3500)],
          potongan: 7000,
        ),
      );
      expect(d.totalBayar, 5500);
      final teks = strukSebagaiTeks(susunStruk(d));
      expect(teks, contains('TUKAR BARANG'));
      expect(teks, contains('Total belanja'));
      expect(teks, contains('RTR-A01-261111-0001'));
      expect(teks, contains('-7.000'));
      expect(RegExp(r'TOTAL BAYAR +5\.500').hasMatch(teks), isTrue, reason: teks);
      expect(teks, isNot(contains('Sisa tukar')));
      for (final l in teks.split('\n')) {
        expect(l.length, lessThanOrEqualTo(lebarStruk), reason: l);
      }
    });

    test('struk tukar: sisa nilai retur dikembalikan tunai', () {
      final d = DataStruk(
        namaToko: 'Toko Contoh',
        namaCabang: '',
        alamat: '',
        noTransaksi: 'TRX-A01-261111-0003',
        waktu: waktu,
        namaKasir: 'Kasir',
        item: const [ItemStruk(nama: 'Permen', qty: 1, hargaSatuan: 500, isGrosir: false)],
        metode: MetodeBayar.tunai,
        diterima: 0,
        kembalian: 0,
        tukar: const TukarStruk(
          noRetur: 'RTR-A01-261111-0002',
          noTransaksiAsal: 'TRX-A01-261110-0004',
          item: [ItemStrukRetur(nama: 'Teh Botol 350ml', qty: 1, hargaSatuan: 3500)],
          potongan: 500,
        ),
      );
      expect(d.totalBayar, 0);
      expect(strukSebagaiTeks(susunStruk(d)), contains('Sisa tukar (tunai)'));
      // Struk tukar tetap memakai barcode nomor transaksi baru (untuk retur berikutnya).
      expect(isiBarcodeStruk(d.noTransaksi), 'A012611110003');
    });
  });
}
