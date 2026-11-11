import 'package:pos_core/pos_core.dart';
import 'package:test/test.dart';

void main() {
  group('kas keluar/masuk', () {
    test('kasir: di bawah Rp100.000 boleh sendiri, mulai Rp100.000 butuh PIN SPV', () {
      expect(aksesKas(Peran.kasir, 1), Akses.ya);
      expect(aksesKas(Peran.kasir, 99999), Akses.ya);
      expect(aksesKas(Peran.kasir, 100000), Akses.pinSpv);
      expect(aksesKas(Peran.kasir, 2500000), Akses.pinSpv);
    });

    test('SPV dan Admin boleh berapa pun', () {
      expect(aksesKas(Peran.spv, 5000000), Akses.ya);
      expect(aksesKas(Peran.admin, 5000000), Akses.ya);
    });

    test('jumlah harus > 0 dan keterangan wajib', () {
      expect(cekKas(jumlah: 0, keterangan: 'galon'), isNotNull);
      expect(cekKas(jumlah: -500, keterangan: 'galon'), isNotNull);
      expect(cekKas(jumlah: 20000, keterangan: '  '), isNotNull);
      expect(cekKas(jumlah: 20000, keterangan: 'ab'), isNotNull);
      expect(cekKas(jumlah: 20000, keterangan: 'Beli galon'), isNull);
    });

    test('kode jenis', () {
      expect(JenisKas.dariKode('keluar'), JenisKas.keluar);
      expect(JenisKas.dariKode('masuk'), JenisKas.masuk);
      expect(() => JenisKas.dariKode('lain'), throwsArgumentError);
    });
  });

  group('uang tunai seharusnya', () {
    test('modal + tunai − retur + kas masuk − kas keluar', () {
      expect(hitungKasSeharusnya(modalAwal: 200000, penjualanTunai: 450000, returTunai: 17500), 632500);
      expect(
        hitungKasSeharusnya(modalAwal: 200000, penjualanTunai: 450000, returTunai: 17500, kasMasuk: 50000, kasKeluar: 120000),
        562500,
      );
    });
  });

  group('hitung buta', () {
    test('kasir: hitungan pertama + 2 hitung ulang boleh sendiri, ke-4 butuh PIN SPV', () {
      expect(aksesHitungUang(Peran.kasir, 0), Akses.ya); // hitungan pertama
      expect(aksesHitungUang(Peran.kasir, 1), Akses.ya); // hitung ulang 1
      expect(aksesHitungUang(Peran.kasir, 2), Akses.ya); // hitung ulang 2
      expect(aksesHitungUang(Peran.kasir, 3), Akses.pinSpv);
      expect(aksesHitungUang(Peran.kasir, 7), Akses.pinSpv);
    });

    test('SPV/Admin tidak dibatasi', () {
      expect(aksesHitungUang(Peran.spv, 5), Akses.ya);
      expect(aksesHitungUang(Peran.admin, 5), Akses.ya);
    });

    test('sisa hitung ulang', () {
      expect(sisaHitungUlang(0), 2);
      expect(sisaHitungUlang(1), 2);
      expect(sisaHitungUlang(2), 1);
      expect(sisaHitungUlang(3), 0);
      expect(sisaHitungUlang(9), 0);
    });
  });
}
