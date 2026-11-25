import 'uang.dart';
import 'usulan_harga.dart';
import 'waktu.dart';

/// Satu usulan harga di pesan WhatsApp. [waktu] boleh UTC; ditampilkan dalam WIB.
class ItemUsulanWa {
  const ItemUsulanWa({
    required this.namaBarang,
    required this.hargaLama,
    required this.hargaBaru,
    required this.hpp,
    required this.diubahOleh,
    required this.waktu,
  });
  final String namaBarang;
  final int? hargaLama;
  final int hargaBaru;
  final int? hpp;
  final String diubahOleh;
  final DateTime waktu;
}

/// Batas barang per pesan supaya tautan WhatsApp tidak kepanjangan.
const maksItemPesanWa = 8;

/// Pesan pemberitahuan usulan harga untuk dikirim lewat WhatsApp (tombol manual "Kirim ke WA").
String pesanWaUsulanHarga({required String namaToko, required String kodeCabang, required List<ItemUsulanWa> item}) {
  if (item.isEmpty) throw ArgumentError('Tidak ada usulan untuk dikirim');
  final b = StringBuffer(item.length == 1 ? 'Usulan harga perlu disetujui' : 'Usulan harga perlu disetujui (${item.length} barang)');
  for (final u in item.take(maksItemPesanWa)) {
    final String hargaUsulan;
    if (u.hargaLama == null) {
      hargaUsulan = '${formatRupiah(u.hargaBaru)} (harga pertama)';
    } else {
      final pm = turunPerMil(u.hargaLama!, u.hargaBaru);
      final selisih = pm > 0 ? ' (turun ${formatPerMil(pm)})' : (pm < 0 ? ' (naik ${formatPerMil(-pm)})' : ' (tetap)');
      hargaUsulan = '${formatRupiah(u.hargaBaru)}$selisih';
    }
    b
      ..write('\n\nToko: $namaToko ($kodeCabang)')
      ..write('\nBarang: ${u.namaBarang}')
      ..write(u.hargaLama == null ? '' : '\nHarga sekarang: ${formatRupiah(u.hargaLama!)}')
      ..write('\nHarga usulan: $hargaUsulan')
      ..write(u.hpp == null ? '' : '\nHPP: ${formatRupiah(u.hpp!)}')
      ..write('\nDiubah oleh: ${u.diubahOleh}, ${formatTanggal(u.waktu).replaceFirst(RegExp(r' \d{4}$'), '')} ${formatJam(u.waktu)}');
  }
  if (item.length > maksItemPesanWa) b.write('\n\n…dan ${item.length - maksItemPesanWa} barang lainnya.');
  b.write('\n\nSetujui atau tolak di Aplikasi Pusat atau Aplikasi Toko.');
  return b.toString();
}

/// Tautan yang membuka WhatsApp dengan pesan sudah terisi. Tanpa nomor: pengirim memilih penerima sendiri.
Uri tautanWa(String pesan) => Uri.parse('https://wa.me/?text=${Uri.encodeComponent(pesan)}');
