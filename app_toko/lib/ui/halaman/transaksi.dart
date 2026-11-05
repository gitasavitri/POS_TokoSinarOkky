import 'package:flutter/material.dart';
import 'package:pos_core/pos_core.dart';

import '../../data/model.dart';
import '../../layanan/aplikasi.dart';
import '../komponen/pin.dart';
import '../komponen/umum.dart';
import '../tema.dart';

/// Daftar transaksi hari ini dari layar kasir (F9): cetak ulang & batalkan.
class DialogTransaksiTerakhir extends StatefulWidget {
  const DialogTransaksiTerakhir({super.key});
  @override
  State<DialogTransaksiTerakhir> createState() => _DialogTransaksiTerakhirState();
}

class _DialogTransaksiTerakhirState extends State<DialogTransaksiTerakhir> {
  List<BarisTransaksi> _daftar = [];

  @override
  void initState() {
    super.initState();
    _muat();
  }

  void _muat() {
    final app = context.app;
    final dari = awalHariWibUtc(DateTime.now());
    setState(() => _daftar = app.laporan.daftarTransaksi(app.cabang.id, dari, dari.add(const Duration(days: 1)), batas: 200));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Transaksi hari ini', style: TextStyle(fontWeight: FontWeight.w800)),
        content: SizedBox(
          width: 900,
          height: 560,
          child: _daftar.isEmpty
              ? const Center(child: Text('Belum ada transaksi hari ini.', style: TextStyle(fontSize: 18, color: Warna.teksPudar)))
              : SingleChildScrollView(
                  child: TabelSederhana(
                    kolom: const ['Jam', 'No. transaksi', 'Kasir', 'Bayar', 'Total', 'Status'],
                    lebar: const [2, 5, 3, 3, 3, 3],
                    rataKanan: const {4},
                    onTap: (i) async {
                      await bukaDetailTransaksi(context, _daftar[i].id);
                      _muat();
                    },
                    baris: [
                      for (final t in _daftar)
                        [
                          Text(formatJam(t.waktu), style: gayaSel),
                          Text(t.noTransaksi, style: gayaSelTebal),
                          Text(t.kasir, style: gayaSel),
                          Text(t.metode.label, style: gayaSel),
                          Text(formatRupiah(t.total), style: gayaSelTebal),
                          Lencana.status(t.status),
                        ],
                    ],
                  ),
                ),
        ),
        actions: [OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Tutup'))],
      );
}

Future<void> bukaDetailTransaksi(BuildContext context, String transaksiId) =>
    showDialog<void>(context: context, builder: (_) => _DialogDetail(transaksiId: transaksiId));

class _DialogDetail extends StatefulWidget {
  const _DialogDetail({required this.transaksiId});
  final String transaksiId;
  @override
  State<_DialogDetail> createState() => _DialogDetailState();
}

class _DialogDetailState extends State<_DialogDetail> {
  DataStruk? _struk;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  void _muat() {
    final app = context.app;
    setState(() => _struk = app.penjualan.struk(widget.transaksiId, app.cabang));
  }

  Future<void> _batalkan() async {
    final app = context.app;
    final alasan = await _mintaAlasan();
    if (alasan == null || !mounted) return;
    var penyetuju = app.penggunaAktif!;
    if (app.akses(Izin.batalTransaksi) == Akses.pinSpv) {
      final p = await mintaPinSpv(context, alasan: 'Membatalkan ${_struk!.noTransaksi} (${formatRupiah(_struk!.total)}).');
      if (p == null || !mounted) return;
      penyetuju = p;
    } else if (app.akses(Izin.batalTransaksi) == Akses.tidak) {
      return;
    }
    try {
      app.penjualan.batalkan(
          transaksiId: widget.transaksiId, alasan: alasan, dimintaOleh: app.penggunaAktif!.id, disetujuiOleh: penyetuju.id);
      tampilkanPesan(context, 'Transaksi dibatalkan. Stok sudah dikembalikan.');
      _muat();
    } catch (e) {
      tampilkanPesan(context, pesanGalat(e), galat: true);
    }
  }

  Future<String?> _mintaAlasan() {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Alasan pembatalan', style: TextStyle(fontWeight: FontWeight.w800)),
        content: SizedBox(
          width: 460,
          child: TextField(
            controller: c,
            autofocus: true,
            style: const TextStyle(fontSize: 19),
            decoration: const InputDecoration(hintText: 'contoh: salah input barang'),
          ),
        ),
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(d), child: const Text('Batal')),
          FilledButton(
            onPressed: () {
              if (c.text.trim().isNotEmpty) Navigator.pop(d, c.text.trim());
            },
            child: const Text('Lanjut'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _struk;
    if (s == null) return const AlertDialog(content: Text('Transaksi tidak ditemukan'));
    final app = context.app;
    return AlertDialog(
      title: Text(s.noTransaksi, style: const TextStyle(fontWeight: FontWeight.w800)),
      content: SizedBox(
        width: 520,
        height: 560,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (s.dibatalkan) ...[const KotakPesan('Transaksi ini sudah dibatalkan.', jenis: JenisPesan.galat), const SizedBox(height: 12)],
          Expanded(child: PratinjauStruk(baris: susunStruk(s))),
        ]),
      ),
      actions: [
        if (!s.dibatalkan && app.akses(Izin.batalTransaksi) != Akses.tidak)
          OutlinedButton(
            onPressed: _batalkan,
            style: OutlinedButton.styleFrom(foregroundColor: Warna.merah, side: const BorderSide(color: Warna.merahGaris, width: 2)),
            child: Text(app.akses(Izin.batalTransaksi) == Akses.pinSpv ? 'Batalkan (PIN SPV)' : 'Batalkan transaksi'),
          ),
        OutlinedButton.icon(
          onPressed: () async {
            final g = await app.cetakStrukTransaksi(s, ulang: true);
            if (context.mounted) tampilkanPesan(context, g ?? 'Struk dicetak ulang', galat: g != null);
          },
          icon: const Icon(Icons.print),
          label: const Text('Cetak ulang'),
        ),
        FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Tutup')),
      ],
    );
  }
}

/// Tampilan struk 58 mm di layar.
class PratinjauStruk extends StatelessWidget {
  const PratinjauStruk({super.key, required this.baris});
  final List<BarisStruk> baris;

  @override
  Widget build(BuildContext context) => Container(
        color: Warna.latar,
        alignment: Alignment.topCenter,
        padding: const EdgeInsets.all(14),
        child: SingleChildScrollView(
          child: Container(
            width: 380,
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final b in baris)
                Text(
                  b.teks,
                  textAlign: switch (b.rata) { Rata.kiri => TextAlign.left, Rata.tengah => TextAlign.center, Rata.kanan => TextAlign.right },
                  style: TextStyle(
                    fontFamily: fontMono,
                    fontSize: b.besar ? 16 : 13.5,
                    height: 1.45,
                    fontWeight: b.tebal ? FontWeight.w700 : FontWeight.w400,
                    color: const Color(0xFF111111),
                  ),
                ),
            ]),
          ),
        ),
      );
}
