import 'package:flutter/material.dart';
import 'package:pos_core/pos_core.dart';

import '../../layanan/aplikasi.dart';
import '../komponen/kerangka.dart';
import '../komponen/umum.dart';
import '../tema.dart';
import 'laporan.dart';

/// Beranda SPV/Admin: ringkasan hari ini, hal yang perlu dicek, stok menipis, terlaris.
class IsiBeranda extends StatelessWidget {
  const IsiBeranda({super.key, required this.onMenu});
  final BukaMenu onMenu;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final c = app.cabang.id;
    final (dari, sampai) = Periode.hariIni.rentang(DateTime.now());
    final r = app.laporan.ringkasan(c, dari, sampai);
    final cek = app.laporan.perluDicek(c, dari, sampai);
    final menipis = app.katalog.stokMenipis(c);
    final laris = app.laporan.terlaris(c, dari, sampai, batas: 6);
    final antreanLabel = app.harga.antreanLabel().length;

    Widget itemCek(String judul, String isi, {required bool penting, MenuAdmin? ke}) => InkWell(
          onTap: ke == null ? null : () => onMenu(ke),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: Warna.garisTipis, width: 2))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(judul, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: penting ? Warna.merah : Warna.oranye)),
              Text(isi, style: const TextStyle(fontSize: 15.5, color: Warna.teksPudar)),
            ]),
          ),
        );

    final daftarCek = <Widget>[
      if (cek.batal > 0) itemCek('${cek.batal} transaksi dibatalkan', 'Lihat di Log aktivitas', penting: true, ke: MenuAdmin.log),
      if (cek.terkunci > 0) itemCek('${cek.terkunci} akun terkunci', 'Salah PIN 5 kali · buka di Karyawan', penting: true, ke: MenuAdmin.karyawan),
      if (cek.koreksiMenunggu > 0)
        itemCek('${cek.koreksiMenunggu} permintaan koreksi barang masuk', 'Menunggu persetujuan', penting: false, ke: MenuAdmin.koreksi),
      if (cek.ubahHarga > 0) itemCek('${cek.ubahHarga} harga diubah hari ini', 'Cek harga lama → baru di Log', penting: false, ke: MenuAdmin.log),
      if (cek.selisihKas > 0) itemCek('${cek.selisihKas} shift dengan selisih kas', 'Lihat di Log aktivitas', penting: false, ke: MenuAdmin.log),
      if (antreanLabel > 0) itemCek('$antreanLabel label rak perlu dicetak ulang', 'Buka Ubah harga', penting: false, ke: MenuAdmin.ubahHarga),
    ];

    return ListView(padding: const EdgeInsets.all(24), children: [
      Row(children: [
        Expanded(child: Text('Hari ini · ${formatTanggal(DateTime.now())}', style: const TextStyle(fontSize: 18, color: Warna.teksPudar))),
        FilledButton.icon(onPressed: () => onMenu(MenuAdmin.penjualan), icon: const Icon(Icons.point_of_sale), label: const Text('Buka layar kasir')),
      ]),
      const SizedBox(height: 16),
      LayoutBuilder(builder: (context, c) {
        final lebar = (c.maxWidth - 14 * 3) / 4;
        return Wrap(spacing: 14, runSpacing: 14, children: [
          for (final k in [
            KartuAngka(label: 'Penjualan bersih', nilai: formatRupiah(r.penjualanBersih)),
            KartuAngka(label: 'Jumlah transaksi', nilai: '${r.jumlahTransaksi}'),
            KartuAngka(label: 'Rata-rata per struk', nilai: formatRupiah(r.rataRataStruk)),
            KartuAngka(label: 'Laba kotor', nilai: formatRupiah(r.labaKotor), catatan: 'harga jual − HPP'),
          ])
            SizedBox(width: lebar, child: k),
        ]);
      }),
      const SizedBox(height: 20),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Panel(
            judul: 'Perlu dicek',
            child: daftarCek.isEmpty
                ? const Text('Tidak ada yang perlu dicek.', style: TextStyle(fontSize: 17, color: Warna.teksPudar))
                : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: daftarCek),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Panel(
            judul: 'Stok hampir habis (${menipis.length})',
            child: menipis.isEmpty
                ? const Text('Aman. Atur stok minimum per barang di Produk & stok.', style: TextStyle(fontSize: 17, color: Warna.teksPudar))
                : Column(children: [
                    for (final b in menipis.take(8))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(children: [
                          Expanded(child: Text(b.nama, style: const TextStyle(fontSize: 17))),
                          Text('sisa ${b.stok} ${b.satuan}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Warna.oranye)),
                        ]),
                      ),
                  ]),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Panel(
            judul: 'Barang terlaris hari ini',
            child: laris.isEmpty
                ? const Text('Belum ada penjualan.', style: TextStyle(fontSize: 17, color: Warna.teksPudar))
                : Column(children: [
                    for (var i = 0; i < laris.length; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(children: [
                          CircleAvatar(
                              radius: 15,
                              backgroundColor: Warna.hijauMuda,
                              child: Text('${i + 1}', style: const TextStyle(fontWeight: FontWeight.w800, color: Warna.hijauGelap))),
                          const SizedBox(width: 12),
                          Expanded(child: Text(laris[i].nama, style: const TextStyle(fontSize: 17))),
                          Text('${laris[i].qty} ${laris[i].satuan}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                        ]),
                      ),
                  ]),
          ),
        ),
      ]),
    ]);
  }
}
