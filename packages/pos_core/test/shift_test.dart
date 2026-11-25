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

  group('tutup shift "Belum dihitung" (revisi P)', () {
    test('modal tetap ditinggal di kasir, sisanya amplop', () {
      expect(hitungModalDitinggal(modalTetap: 200000, kasSistem: 845000), 200000);
      expect(hitungIsiAmplopSeharusnya(kasSistem: 845000, modalDitinggal: 200000), 645000);
    });

    test('tanpa modal tetap: semua uang masuk amplop', () {
      expect(hitungModalDitinggal(modalTetap: 0, kasSistem: 845000), 0);
      expect(hitungIsiAmplopSeharusnya(kasSistem: 845000, modalDitinggal: 0), 845000);
    });

    test('uang seharusnya kurang dari modal tetap: semua tetap di kasir, amplop kosong', () {
      expect(hitungModalDitinggal(modalTetap: 200000, kasSistem: 150000), 150000);
      expect(hitungIsiAmplopSeharusnya(kasSistem: 150000, modalDitinggal: 150000), 0);
      expect(hitungModalDitinggal(modalTetap: 200000, kasSistem: -5000), 0);
    });

    test('selisih = isi amplop + modal ditinggal − uang seharusnya', () {
      expect(hitungSelisihAmplop(amplopDihitung: 645000, modalDitinggal: 200000, kasSistem: 845000), 0);
      expect(hitungSelisihAmplop(amplopDihitung: 630000, modalDitinggal: 200000, kasSistem: 845000), -15000);
      expect(hitungSelisihAmplop(amplopDihitung: 650000, modalDitinggal: 200000, kasSistem: 845000), 5000);
      expect(hitungKasDariAmplop(amplopDihitung: 630000, modalDitinggal: 200000), 830000);
      expect(() => hitungKasDariAmplop(amplopDihitung: -1, modalDitinggal: 0), throwsArgumentError);
    });

    test('label amplop', () {
      expect(labelAmplop(namaKasir: ' Siti ', dibuka: '08.00', ditutup: '16.05'), 'Siti · 08.00–16.05');
    });
  });

  group('status stok (revisi C)', () {
    test('habis, hampir habis, aman', () {
      expect(statusStok(stok: 0, stokMinimum: 5), StatusStok.habis);
      expect(statusStok(stok: -2, stokMinimum: 0), StatusStok.habis);
      expect(statusStok(stok: 5, stokMinimum: 5), StatusStok.hampirHabis);
      expect(statusStok(stok: 3, stokMinimum: 5), StatusStok.hampirHabis);
      expect(statusStok(stok: 6, stokMinimum: 5), StatusStok.aman);
      expect(statusStok(stok: 1, stokMinimum: 0), StatusStok.aman, reason: 'stok minimum belum diatur');
      expect(StatusStok.habis.perluDiorder, isTrue);
      expect(StatusStok.hampirHabis.perluDiorder, isTrue);
      expect(StatusStok.aman.perluDiorder, isFalse);
    });
  });
}
