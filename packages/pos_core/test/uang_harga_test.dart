import 'package:pos_core/pos_core.dart';
import 'package:test/test.dart';

void main() {
  group('uang', () {
    test('formatAngka dan formatRupiah', () {
      expect(formatAngka(0), '0');
      expect(formatAngka(500), '500');
      expect(formatAngka(17500), '17.500');
      expect(formatAngka(1250000), '1.250.000');
      expect(formatAngka(-6000), '-6.000');
      expect(formatRupiah(636000), 'Rp 636.000');
      expect(formatRupiah(-700), '-Rp 700');
    });

    test('bacaAngka mengabaikan selain digit', () {
      expect(bacaAngka('Rp 1.250.000'), 1250000);
      expect(bacaAngka(''), 0);
      expect(bacaAngka('abc'), 0);
      expect(bacaAngka('99999999999999999'), 9999999999999);
    });

    test('bagiBulat setengah ke atas', () {
      expect(bagiBulat(10, 4), 3); // 2.5 → 3
      expect(bagiBulat(9, 4), 2); // 2.25 → 2
      expect(bagiBulat(-10, 4), -3);
      expect(() => bagiBulat(1, 0), throwsArgumentError);
    });
  });

  group('harga grosir', () {
    final gula = HargaBarang(
      eceran: 17500,
      grosir: const [
        TingkatGrosir(minQty: 50, harga: 16800), // sengaja tidak urut
        TingkatGrosir(minQty: 10, harga: 17000),
      ],
    );

    test('tingkat diurutkan', () {
      expect(gula.grosir.map((t) => t.minQty), [10, 50]);
    });

    test('beli di bawah tingkat pertama memakai eceran', () {
      final h = hitungHargaBaris(gula, 9);
      expect(h.hargaSatuan, 17500);
      expect(h.isGrosir, isFalse);
      expect(h.subtotal, 157500);
    });

    test('tepat di batas tingkat', () {
      expect(hitungHargaBaris(gula, 10).hargaSatuan, 17000);
      expect(hitungHargaBaris(gula, 50).hargaSatuan, 16800);
    });

    test('harga grosir berlaku untuk seluruh jumlah di baris', () {
      final h = hitungHargaBaris(gula, 15);
      expect(h.hargaSatuan, 17000);
      expect(h.isGrosir, isTrue);
      expect(h.subtotal, 15 * 17000);
    });

    test('beli 60 memakai tingkat tertinggi yang terpenuhi', () {
      expect(hitungHargaBaris(gula, 60).subtotal, 60 * 16800);
    });

    test('tanpa grosir selalu eceran', () {
      final h = hitungHargaBaris(HargaBarang(eceran: 3000), 100);
      expect(h.hargaSatuan, 3000);
      expect(h.isGrosir, isFalse);
    });

    test('qty 0 ditolak', () {
      expect(() => hitungHargaBaris(gula, 0), throwsArgumentError);
    });

    test('periksaTingkatGrosir', () {
      expect(
        periksaTingkatGrosir(
          eceran: 17500,
          hpp: 16200,
          tingkat: const [TingkatGrosir(minQty: 10, harga: 17000), TingkatGrosir(minQty: 50, harga: 16800)],
        ),
        isEmpty,
      );
      final salah = periksaTingkatGrosir(
        eceran: 17500,
        hpp: 16200,
        tingkat: const [
          TingkatGrosir(minQty: 1, harga: 17000), // min < 2
          TingkatGrosir(minQty: 10, harga: 18000), // lebih mahal dari eceran
          TingkatGrosir(minQty: 10, harga: 16900), // min tidak naik
          TingkatGrosir(minQty: 20, harga: 16000), // di bawah HPP
          TingkatGrosir(minQty: 30, harga: 0), // kosong
        ],
      );
      expect(salah.keys, [0, 1, 2, 3, 4]);
      expect(salah[1], contains('lebih murah'));
      expect(salah[3], contains('HPP'));
    });

    test('tingkat berikutnya tidak boleh lebih mahal', () {
      final salah = periksaTingkatGrosir(
        eceran: 17500,
        hpp: null,
        tingkat: const [TingkatGrosir(minQty: 10, harga: 16800), TingkatGrosir(minQty: 50, harga: 17000)],
      );
      expect(salah.keys, [1]);
    });
  });

  group('ubah harga', () {
    test('naik tidak perlu PIN', () {
      expect(cekUbahHarga(hargaLama: 17500, hargaBaru: 18000, hpp: 16200).perluPinSpv, isFalse);
    });

    test('turun tepat 10% tidak perlu PIN, lebih dari 10% perlu', () {
      expect(cekUbahHarga(hargaLama: 20000, hargaBaru: 18000, hpp: 10000).perluPinSpv, isFalse);
      final c = cekUbahHarga(hargaLama: 20000, hargaBaru: 17999, hpp: 10000);
      expect(c.perluPinSpv, isTrue);
      expect(c.alasan, contains('10%'));
    });

    test('sama dengan atau di bawah HPP perlu PIN', () {
      final c = cekUbahHarga(hargaLama: 17500, hargaBaru: 16200, hpp: 16200);
      expect(c.perluPinSpv, isTrue);
      expect(c.alasan, contains('HPP'));
    });

    test('teksPerubahanPersen', () {
      expect(teksPerubahanPersen(17500, 18000), '+2,9%');
      expect(teksPerubahanPersen(17500, 15500), '-11,4%');
      expect(teksPerubahanPersen(17500, 17500), '0,0%');
    });
  });

  group('HPP rata-rata tertimbang', () {
    test('stok kosong memakai HPP masuk', () {
      expect(hppRataRata(stokLama: 0, hppLama: 15000, jumlahMasuk: 10, hppMasuk: 16200), 16200);
      expect(hppRataRata(stokLama: 5, hppLama: null, jumlahMasuk: 10, hppMasuk: 16200), 16200);
      expect(hppRataRata(stokLama: -3, hppLama: 15000, jumlahMasuk: 10, hppMasuk: 16200), 16200);
    });

    test('rata-rata dibulatkan', () {
      // (12 × 16.000 + 50 × 16.200) / 62 = 16.161,29 → 16.161
      expect(hppRataRata(stokLama: 12, hppLama: 16000, jumlahMasuk: 50, hppMasuk: 16200), 16161);
      // (1 × 100 + 1 × 101) / 2 = 100,5 → 101
      expect(hppRataRata(stokLama: 1, hppLama: 100, jumlahMasuk: 1, hppMasuk: 101), 101);
    });

    test('jumlah masuk harus positif', () {
      expect(() => hppRataRata(stokLama: 1, hppLama: 1, jumlahMasuk: 0, hppMasuk: 1), throwsArgumentError);
    });
  });
}
