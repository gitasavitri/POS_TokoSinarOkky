import 'package:pos_core/pos_core.dart';
import 'package:test/test.dart';

void main() {
  final waktu = DateTime.utc(2026, 11, 21, 7, 20); // 14.20 WIB
  ItemUsulanWa item({int? lama = 16000, int baru = 13500, int? hpp = 12800, String nama = 'Gula Pasir 1 kg'}) =>
      ItemUsulanWa(namaBarang: nama, hargaLama: lama, hargaBaru: baru, hpp: hpp, diubahOleh: 'Kasir Siti', waktu: waktu);

  test('satu barang: sama dengan desain yang disetujui (turun 15,6%, waktu WIB)', () {
    expect(
      pesanWaUsulanHarga(namaToko: 'Toko Contoh', kodeCabang: 'A01', item: [item()]),
      'Usulan harga perlu disetujui\n'
      '\n'
      'Toko: Toko Contoh (A01)\n'
      'Barang: Gula Pasir 1 kg\n'
      'Harga sekarang: Rp 16.000\n'
      'Harga usulan: Rp 13.500 (turun 15,6%)\n'
      'HPP: Rp 12.800\n'
      'Diubah oleh: Kasir Siti, 21 Nov 14.20\n'
      '\n'
      'Setujui atau tolak di Aplikasi Pusat atau Aplikasi Toko.',
    );
  });

  test('harga naik, tetap, dan harga pertama; HPP kosong dilewati', () {
    String pesan(ItemUsulanWa i) => pesanWaUsulanHarga(namaToko: 'T', kodeCabang: 'A01', item: [i]);
    expect(pesan(item(baru: 17000)), contains('Rp 17.000 (naik 6,2%)'));
    expect(pesan(item(baru: 16000)), contains('Rp 16.000 (tetap)'));
    final pertama = pesan(item(lama: null, hpp: null));
    expect(pertama, contains('Harga usulan: Rp 13.500 (harga pertama)'));
    expect(pertama, isNot(contains('Harga sekarang')));
    expect(pertama, isNot(contains('HPP')));
  });

  test('beberapa barang: satu pesan, dibatasi $maksItemPesanWa barang', () {
    final banyak = [for (var i = 1; i <= 10; i++) item(nama: 'Barang $i')];
    final p = pesanWaUsulanHarga(namaToko: 'T', kodeCabang: 'A01', item: banyak);
    expect(p, startsWith('Usulan harga perlu disetujui (10 barang)'));
    expect(p, contains('Barang: Barang $maksItemPesanWa'));
    expect(p, isNot(contains('Barang: Barang ${maksItemPesanWa + 1}')));
    expect(p, contains('…dan 2 barang lainnya.'));
    expect(() => pesanWaUsulanHarga(namaToko: 'T', kodeCabang: 'A01', item: const []), throwsArgumentError);
  });

  test('tautan WhatsApp: pesan di-encode dan bisa dibaca kembali', () {
    final p = pesanWaUsulanHarga(namaToko: 'Toko & Co', kodeCabang: 'A01', item: [item()]);
    final u = tautanWa(p);
    expect(u.host, 'wa.me');
    expect(u.queryParameters['text'], p);
    expect(u.toString(), isNot(contains(' ')));
    expect(u.toString(), isNot(contains('&Co')), reason: '& di dalam pesan tidak boleh memecah tautan');
  });
}
