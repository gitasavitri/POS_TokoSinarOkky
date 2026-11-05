import 'package:pos_core/pos_core.dart';
import 'package:test/test.dart';

BarangJual barang(String id, int eceran, [List<TingkatGrosir> grosir = const []]) => BarangJual(
  id: id,
  nama: 'Barang $id',
  satuan: 'pcs',
  harga: HargaBarang(eceran: eceran, grosir: grosir),
  hpp: eceran - 1000,
);

void main() {
  group('keranjang', () {
    test('barang sama digabung, total dan jumlah benar', () {
      final k = Keranjang()
        ..tambah(barang('a', 17500, const [TingkatGrosir(minQty: 10, harga: 17000)]), qty: 4)
        ..tambah(barang('b', 36000), qty: 3)
        ..tambah(barang('a', 17500, const [TingkatGrosir(minQty: 10, harga: 17000)]), qty: 6);
      expect(k.jumlahJenis, 2);
      expect(k.jumlahBarang, 13);
      expect(k.barisTerakhir, 0);
      // a: 10 × 17.000 (grosir aktif setelah digabung), b: 3 × 36.000
      expect(k.total, 170000 + 108000);
      expect(k.baris.first.harga.isGrosir, isTrue);
    });

    test('ubahQty ke 0 menghapus baris', () {
      final k = Keranjang()
        ..tambah(barang('a', 1000))
        ..tambah(barang('b', 2000));
      k.ubahQty(1, 0);
      expect(k.jumlahJenis, 1);
      expect(k.barisTerakhir, 0);
      k.hapus(0);
      expect(k.kosong, isTrue);
      expect(k.barisTerakhir, -1);
    });

    test('salin untuk tahan transaksi tidak ikut berubah', () {
      final k = Keranjang()..tambah(barang('a', 1000), qty: 2);
      final ditahan = k.salin();
      k.kosongkan();
      expect(ditahan.total, 2000);
      expect(k.total, 0);
    });
  });

  group('pembayaran', () {
    test('tunai cukup → kembalian', () {
      final h = cekPembayaran(metode: MetodeBayar.tunai, total: 636000, uangDiterima: 700000);
      expect(h.boleh, isTrue);
      expect(h.kembalian, 64000);
      expect(h.diterima, 700000);
    });

    test('tunai pas → kembalian 0', () {
      final h = cekPembayaran(metode: MetodeBayar.tunai, total: 636000, uangDiterima: 636000);
      expect(h.boleh, isTrue);
      expect(h.kembalian, 0);
    });

    test('tunai kurang ditolak', () {
      final h = cekPembayaran(metode: MetodeBayar.tunai, total: 636000, uangDiterima: 600000);
      expect(h.boleh, isFalse);
      expect(h.kurang, 36000);
      expect(h.pesan, 'Uang kurang Rp 36.000');
    });

    test('kartu/transfer wajib referensi, QRIS tidak', () {
      expect(cekPembayaran(metode: MetodeBayar.kartu, total: 1000).boleh, isFalse);
      expect(cekPembayaran(metode: MetodeBayar.transfer, total: 1000, noReferensi: '  ').boleh, isFalse);
      final k = cekPembayaran(metode: MetodeBayar.kartu, total: 1000, noReferensi: '004521');
      expect(k.boleh, isTrue);
      expect(k.diterima, 1000);
      expect(cekPembayaran(metode: MetodeBayar.qris, total: 1000).boleh, isTrue);
    });

    test('kode metode cocok dengan database', () {
      expect(MetodeBayar.values.map((m) => m.kode), ['tunai', 'qris', 'kartu', 'transfer']);
      expect(MetodeBayar.dariKode('qris'), MetodeBayar.qris);
    });
  });

  group('hak akses (AGENTS.md bagian 4)', () {
    test('kasir', () {
      expect(aksesUntuk(Peran.kasir, Izin.jual), Akses.ya);
      expect(aksesUntuk(Peran.kasir, Izin.catatBarangMasuk), Akses.ya);
      expect(aksesUntuk(Peran.kasir, Izin.ubahHargaNaik), Akses.ya);
      expect(aksesUntuk(Peran.kasir, Izin.batalTransaksi), Akses.pinSpv);
      expect(aksesUntuk(Peran.kasir, Izin.ubahHargaTurunBesar), Akses.pinSpv);
      expect(aksesUntuk(Peran.kasir, Izin.setujuiKoreksiBarangMasuk), Akses.tidak);
      expect(aksesUntuk(Peran.kasir, Izin.lihatLaporan), Akses.tidak);
      expect(aksesUntuk(Peran.kasir, Izin.aturPrinter), Akses.tidak);
    });

    test('spv semua kecuali kelola karyawan; admin semua', () {
      for (final i in Izin.values) {
        expect(aksesUntuk(Peran.spv, i), i == Izin.kelolaKaryawan ? Akses.tidak : Akses.ya);
        expect(aksesUntuk(Peran.admin, i), Akses.ya);
      }
      expect(bolehMenyetujui(Peran.kasir), isFalse);
      expect(bolehMenyetujui(Peran.spv), isTrue);
    });
  });

  group('waktu & nomor', () {
    final t = DateTime.utc(2026, 11, 5, 6, 9, 30); // 13:09 WIB

    test('ISO UTC tanpa milidetik', () {
      expect(isoUtc(DateTime.utc(2026, 11, 5, 6, 9, 30, 999)), '2026-11-05T06:09:30Z');
    });

    test('tampilan WIB', () {
      expect(formatStruk(t), '05/11/26 13:09');
      expect(formatLayar(t), 'Kamis, 5 Nov 2026 · 13:09');
      expect(formatJam(t), '13.09');
    });

    test('pergantian hari mengikuti WIB, bukan UTC', () {
      final malam = DateTime.utc(2026, 11, 5, 17, 30); // 00:30 WIB tanggal 6
      expect(kodeTanggal(malam), '261106');
      expect(awalHariWibUtc(malam), DateTime.utc(2026, 11, 5, 17));
    });

    test('nomor transaksi', () {
      expect(nomorTransaksi(kodeCabang: 'A01', waktu: t, urut: 1), 'TRX-A01-261105-0001');
      expect(awalanNomorTransaksi('A01', t), 'TRX-A01-261105-');
      expect(() => nomorTransaksi(kodeCabang: 'A01', waktu: t, urut: 10000), throwsRangeError);
    });
  });
}
