import 'package:pos_core/pos_core.dart';
import 'package:test/test.dart';

void main() {
  group('usulan harga: siapa perlu persetujuan', () {
    test('kasir perlu persetujuan, SPV dan Admin langsung berlaku', () {
      expect(hargaPerluPersetujuan(Peran.kasir), isTrue);
      expect(hargaPerluPersetujuan(Peran.spv), isFalse);
      expect(hargaPerluPersetujuan(Peran.admin), isFalse);
    });
  });

  group('turunPerMil', () {
    test('16.000 → 13.500 = 15,6%', () {
      expect(turunPerMil(16000, 13500), 156);
      expect(formatPerMil(156), '15,6%');
    });
    test('harga naik menghasilkan negatif', () {
      expect(turunPerMil(10000, 11000), -100);
      expect(formatPerMil(-100), '-10,0%');
    });
    test('harga sama = 0, harga lama tidak valid = 0', () {
      expect(turunPerMil(5000, 5000), 0);
      expect(turunPerMil(0, 5000), 0);
      expect(turunPerMil(-1, 5000), 0);
    });
    test('dibulatkan ke bawah, tidak memakai pecahan', () {
      expect(turunPerMil(3, 2), 333);
      expect(formatPerMil(333), '33,3%');
      expect(formatPerMil(5), '0,5%');
    });
  });

  group('alasanTidakBolehMemutuskan', () {
    test('kasir ditolak', () {
      expect(alasanTidakBolehMemutuskan(peran: Peran.kasir, statusUsulan: statusUsulanMenunggu), isNotNull);
    });
    test('SPV dan Admin boleh saat masih menunggu', () {
      expect(alasanTidakBolehMemutuskan(peran: Peran.spv, statusUsulan: statusUsulanMenunggu), isNull);
      expect(alasanTidakBolehMemutuskan(peran: Peran.admin, statusUsulan: statusUsulanMenunggu), isNull);
    });
    test('usulan yang sudah diputuskan tidak bisa diputuskan lagi', () {
      expect(alasanTidakBolehMemutuskan(peran: Peran.spv, statusUsulan: statusUsulanDisetujui), contains('sudah diputuskan'));
      expect(alasanTidakBolehMemutuskan(peran: Peran.admin, statusUsulan: statusUsulanDitolak), contains('sudah diputuskan'));
    });
  });
}
