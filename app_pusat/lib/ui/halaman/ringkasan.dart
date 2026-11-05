import 'package:flutter/material.dart';
import 'package:pos_core/pos_core.dart';
import 'package:pos_ui/pos_ui.dart';

import '../../data/model.dart';
import '../komponen.dart';

/// Dashboard: penjualan semua toko per periode, per toko, grafik harian, barang terlaris.
class IsiRingkasan extends StatefulWidget {
  const IsiRingkasan({super.key});
  @override
  State<IsiRingkasan> createState() => _IsiRingkasanState();
}

typedef _Data = ({RingkasanPusat ringkasan, Map<DateTime, int> harian, List<Terlaris> terlaris, List<CabangPusat> cabang});

class _IsiRingkasanState extends State<IsiRingkasan> {
  Periode _periode = Periode.hariIni;
  String? _cabangId;

  @override
  Widget build(BuildContext context) {
    final (dari, sampai) = _periode.rentang(DateTime.now());
    return Muat<_Data>(
      key: ValueKey('$_periode $_cabangId'),
      ambil: (s) => s.pakai((api) async => (
            ringkasan: await api.ringkasan(dari, sampai, cabangId: _cabangId),
            harian: await api.penjualanHarian(dari, sampai, cabangId: _cabangId),
            terlaris: await api.terlaris(dari, sampai, cabangId: _cabangId),
            cabang: await api.cabang(),
          )),
      isi: (context, d, ulang) {
        final t = d.ringkasan.total;
        final sekarang = DateTime.now();
        return ListView(padding: const EdgeInsets.all(24), children: [
          Wrap(spacing: 16, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
            PilihPeriode(nilai: _periode, onUbah: (p) => setState(() => _periode = p)),
            PilihCabang(cabang: d.cabang, nilai: _cabangId, onUbah: (v) => setState(() => _cabangId = v)),
            IconButton(onPressed: ulang, tooltip: 'Muat ulang', icon: const Icon(Icons.refresh)),
          ]),
          const SizedBox(height: 18),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: KartuAngka(label: 'Penjualan bersih', nilai: formatRupiah(t.penjualanBersih), catatan: 'setelah dikurangi retur', aksen: Warna.sukses, ikon: Icons.payments)),
            const SizedBox(width: 14),
            Expanded(child: KartuAngka(label: 'Jumlah transaksi', nilai: formatAngka(t.jumlahTransaksi), catatan: 'rata-rata ${formatRupiah(t.rataRataStruk)}', aksen: Warna.utama, ikon: Icons.receipt_long)),
            const SizedBox(width: 14),
            Expanded(child: KartuAngka(label: 'Laba kotor', nilai: formatRupiah(t.labaKotor), catatan: 'harga jual − HPP', aksen: Warna.ungu, ikon: Icons.trending_up)),
            const SizedBox(width: 14),
            Expanded(
              child: KartuAngka(
                label: 'Batal / retur',
                nilai: '${t.jumlahBatal} batal',
                catatan: 'retur ${formatRupiah(t.totalRetur)}',
                latar: t.jumlahBatal > 0 ? Warna.oranyeMuda : Colors.white,
                aksen: Warna.merahIkon,
                ikon: Icons.assignment_return,
              ),
            ),
          ]),
          const SizedBox(height: 18),
          Panel(
            judul: 'Per toko',
            padding: EdgeInsets.zero,
            child: TabelSederhana(
              kolom: const ['Toko', 'Penjualan', 'Transaksi', 'Tunai', 'Non-tunai', 'Laba kotor', 'Data terakhir'],
              lebar: const [4, 3, 2, 3, 3, 3, 3],
              rataKanan: const {1, 2, 3, 4, 5},
              baris: [
                for (final c in d.ringkasan.perCabang)
                  () {
                    final info = d.cabang.where((x) => x.id == c.cabangId).firstOrNull;
                    final (teks, warna) = statusSinkron(info?.terakhirSinkron, sekarang);
                    return [
                      Text(c.label, style: gayaSelTebal),
                      Text(formatRupiah(c.penjualanBersih), style: gayaSelTebal),
                      Text(formatAngka(c.jumlahTransaksi), style: gayaSel),
                      Text(formatRupiah(c.tunai), style: gayaSel),
                      Text(formatRupiah(c.nonTunai), style: gayaSel),
                      Text(formatRupiah(c.labaKotor), style: gayaSel),
                      Text(teks, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: warna)),
                    ];
                  }(),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('"Data terakhir" = kapan PC toko terakhir mengirim data. Toko yang offline belum terhitung penuh.',
                style: TextStyle(fontSize: 15, color: Warna.teksPudar)),
          ),
          const SizedBox(height: 18),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              flex: 3,
              child: Panel(
                judul: 'Penjualan per hari (WIB)',
                child: d.harian.length <= 1
                    ? Text('Total hari ini: ${formatRupiah(d.harian.values.fold(0, (a, b) => a + b))}', style: const TextStyle(fontSize: 18))
                    : GrafikBatang(data: d.harian),
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              flex: 2,
              child: Panel(
                judul: 'Barang terlaris',
                child: d.terlaris.isEmpty
                    ? const Text('Belum ada penjualan.', style: TextStyle(fontSize: 17, color: Warna.teksPudar))
                    : Column(children: [
                        for (final (i, b) in d.terlaris.indexed)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(children: [
                              CircleAvatar(radius: 15, backgroundColor: Warna.utamaMuda, child: Text('${i + 1}', style: const TextStyle(fontWeight: FontWeight.w800, color: Warna.utamaGelap))),
                              const SizedBox(width: 12),
                              Expanded(child: Text(b.nama, style: const TextStyle(fontSize: 17))),
                              Text('${formatAngka(b.qty)} terjual', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                            ]),
                          ),
                      ]),
              ),
            ),
          ]),
        ]);
      },
    );
  }
}
