import 'package:flutter/material.dart';
import 'package:pos_core/pos_core.dart';

import '../../data/model.dart';
import '../../layanan/aplikasi.dart';
import '../komponen/umum.dart';
import '../tema.dart';

/// Cek stok & harga (revisi C). Kasir hanya melihat: tanpa harga beli/HPP, tanpa stok opname.
class IsiCekStok extends StatefulWidget {
  const IsiCekStok({super.key});
  @override
  State<IsiCekStok> createState() => _IsiCekStokState();
}

class _IsiCekStokState extends State<IsiCekStok> {
  final _kata = TextEditingController();
  List<DetailBarang> _semua = [];
  bool _hanyaMenipis = false;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  @override
  void dispose() {
    _kata.dispose();
    super.dispose();
  }

  void _muat() {
    final app = context.app;
    setState(() => _semua = app.katalog.daftarToko(app.cabang.id, kata: _kata.text));
  }

  StatusStok _status(DetailBarang b) => statusStok(stok: b.stok, stokMinimum: b.stokMinimum);

  @override
  Widget build(BuildContext context) {
    final daftar = _hanyaMenipis ? _semua.where((b) => _status(b).perluDiorder).toList() : _semua;
    final menipis = _semua.where((b) => _status(b).perluDiorder).length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
        child: Row(children: [
          Expanded(
            child: TextField(
              key: const ValueKey('cari-stok'),
              controller: _kata,
              autofocus: true,
              style: const TextStyle(fontSize: 19),
              decoration: const InputDecoration(hintText: 'Scan barcode atau ketik nama barang', prefixIcon: Icon(Icons.search)),
              onChanged: (_) => _muat(),
              onSubmitted: (_) => _muat(),
            ),
          ),
          const SizedBox(width: 14),
          FilterChip(
            key: const ValueKey('filter-menipis'),
            label: Text('Hampir habis / habis ($menipis)', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            selected: _hanyaMenipis,
            padding: const EdgeInsets.all(10),
            onSelected: (v) => setState(() => _hanyaMenipis = v),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Text('${daftar.length} barang · hanya untuk melihat. Stok opname dilakukan SPV/Admin.',
            style: const TextStyle(fontSize: 15.5, color: Warna.teksPudar)),
      ),
      const SizedBox(height: 10),
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(24, 0, 24, 24), children: [
          Panel(
            padding: EdgeInsets.zero,
            child: daftar.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Tidak ada barang yang cocok.', style: TextStyle(fontSize: 17, color: Warna.teksPudar)),
                  )
                : TabelSederhana(
                    kolom: const ['Barang', 'Barcode', 'Stok', 'Harga jual', 'Grosir', 'Status'],
                    lebar: const [6, 4, 3, 3, 4, 3],
                    rataKanan: const {2, 3},
                    baris: [
                      for (final b in daftar)
                        [
                          Text(b.nama, style: gayaSelTebal),
                          Text(b.barcode ?? 'tanpa barcode', style: const TextStyle(fontSize: 15.5, fontFamily: fontMono, color: Warna.teks2)),
                          Text('${formatAngka(b.stok)} ${b.satuan}',
                              style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  color: switch (_status(b)) {
                                    StatusStok.habis => Warna.merah,
                                    StatusStok.hampirHabis => Warna.oranye,
                                    StatusStok.aman => Warna.teks,
                                  })),
                          Text(b.harga == null ? '-' : formatRupiah(b.harga!.eceran), style: gayaSelTebal),
                          Text(
                              b.harga == null || b.harga!.grosir.isEmpty
                                  ? '-'
                                  : b.harga!.grosir.map((t) => '≥${formatAngka(t.minQty)}: ${formatRupiah(t.harga)}').join('\n'),
                              style: const TextStyle(fontSize: 15)),
                          Lencana.status(_status(b).label),
                        ],
                    ],
                  ),
          ),
        ]),
      ),
    ]);
  }
}
