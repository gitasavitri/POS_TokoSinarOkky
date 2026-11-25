import 'package:pos_core/pos_core.dart';
import 'package:test/test.dart';

DataStruk _struk({String telepon = '', String tambahan = ''}) => DataStruk(
      namaToko: 'TOKO CONTOH',
      namaCabang: 'Cabang Uji',
      alamat: 'Jl. Contoh No. 1',
      telepon: telepon,
      tambahan: tambahan,
      noTransaksi: 'TRX-A01-261105-0001',
      waktu: DateTime.utc(2026, 11, 5, 6, 9),
      namaKasir: 'Siti',
      item: const [ItemStruk(nama: 'Gula Pasir 1 kg', qty: 1, hargaSatuan: 17500, isGrosir: false)],
      metode: MetodeBayar.tunai,
      diterima: 20000,
      kembalian: 2500,
    );

void main() {
  group('kepala struk', () {
    test('nama cabang tidak dicetak, nama toko dan alamat tetap', () {
      final teks = strukSebagaiTeks(susunStruk(_struk()));
      expect(teks, contains('TOKO CONTOH'));
      expect(teks, contains('Jl. Contoh No. 1'));
      expect(teks, isNot(contains('Cabang')));
      expect(teks, isNot(contains('Cabang Uji')));
    });

    test('telepon kosong tidak menambah baris', () {
      final dengan = susunStruk(_struk(telepon: '   '));
      final tanpa = susunStruk(_struk());
      expect(dengan.length, tanpa.length);
      expect(strukSebagaiTeks(dengan), isNot(contains('Telp')));
    });

    test('telepon dicetak sebagai "Telp ..." di bawah alamat', () {
      final teks = strukSebagaiTeks(susunStruk(_struk(telepon: ' 0812-0000-0000 ')));
      expect(teks, contains('Telp 0812-0000-0000'));
      expect(teks.indexOf('Jl. Contoh'), lessThan(teks.indexOf('Telp')));
    });

    test('tulisan tambahan: satu baris per Enter, baris kosong dilewati', () {
      final teks = strukSebagaiTeks(susunStruk(_struk(tambahan: 'Buka 07.00 - 21.00\n\nIG @tokocontoh')));
      expect(teks, contains('Buka 07.00 - 21.00'));
      expect(teks, contains('IG @tokocontoh'));
      expect(teks.indexOf('Telp'), -1);
    });

    test('semua baris tetap ≤ 32 karakter walau teks panjang', () {
      final baris = susunStruk(_struk(
        telepon: '0812-0000-0000 / 0813-1111-1111 / 0814-2222-2222',
        tambahan: 'Melayani eceran dan grosir setiap hari kecuali hari libur nasional',
      ));
      for (final b in baris) {
        expect(b.teks.length, lessThanOrEqualTo(lebarStruk), reason: b.teks);
      }
    });

    test('struk retur: tanpa nama cabang, ada telepon', () {
      final d = DataStrukRetur(
        namaToko: 'Toko Contoh',
        namaCabang: 'Cabang Satu',
        alamat: 'Jl. Contoh 1',
        telepon: '0812-0000-0000',
        noRetur: 'RTR-A01-261111-0001',
        noTransaksiAsal: 'TRX-A01-261110-0004',
        waktu: DateTime.utc(2026, 11, 11, 3, 15),
        namaKasir: 'Kasir',
        item: const [ItemStrukRetur(nama: 'Teh Botol', qty: 1, hargaSatuan: 3500)],
      );
      final teks = strukSebagaiTeks(susunStrukRetur(d));
      expect(teks, isNot(contains('Cabang')));
      expect(teks, contains('Telp 0812-0000-0000'));
    });
  });
}
