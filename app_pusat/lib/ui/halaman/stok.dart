import 'package:flutter/material.dart';
import 'package:pos_core/pos_core.dart';
import 'package:pos_ui/pos_ui.dart';

import '../../data/model.dart';
import '../komponen.dart';

/// Stok & HPP per barang di satu toko (sesuai data terakhir yang dikirim PC toko).
class IsiStok extends StatefulWidget {
  const IsiStok({super.key});
  @override
  State<IsiStok> createState() => _IsiStokState();
}

class _IsiStokState extends State<IsiStok> {
  String? _cabangId;
  String _cari = '';
  bool _hanyaMenipis = false;

  @override
  Widget build(BuildContext context) => Muat<List<CabangPusat>>(
        ambil: (s) => s.pakai((api) => api.cabang()),
        isi: (context, cabang, _) {
          if (cabang.isEmpty) {
            return const Padding(padding: EdgeInsets.all(24), child: KotakPesan('Belum ada toko yang terdaftar.', jenis: JenisPesan.info));
          }
          final id = _cabangId ?? cabang.first.id;
          final info = cabang.firstWhere((c) => c.id == id);
          final (teks, warna) = statusSinkron(info.terakhirSinkron, DateTime.now());
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
              child: Wrap(spacing: 14, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
                PilihCabang(cabang: cabang, nilai: id, bolehSemua: false, onUbah: (v) => setState(() => _cabangId = v)),
                SizedBox(
                  width: 360,
                  child: TextField(
                    style: const TextStyle(fontSize: 18),
                    decoration: const InputDecoration(hintText: 'Cari barang, lalu Enter', prefixIcon: Icon(Icons.search), isDense: true),
                    onSubmitted: (v) => setState(() => _cari = v),
                  ),
                ),
                FilterChip(
                  label: const Text('Hanya stok hampir habis', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  selected: _hanyaMenipis,
                  onSelected: (v) => setState(() => _hanyaMenipis = v),
                ),
                Text('Data dari toko: $teks', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: warna)),
              ]),
            ),
            Expanded(
              child: Muat<List<StokBarang>>(
                key: ValueKey('$id $_cari'),
                ambil: (s) => s.pakai((api) => api.stok(id, kata: _cari)),
                isi: (context, semua, _) {
                  final daftar = _hanyaMenipis ? semua.where((b) => b.menipis || b.stok <= 0).toList() : semua;
                  return ListView(padding: const EdgeInsets.fromLTRB(24, 8, 24, 24), children: [
                    Panel(
                      padding: EdgeInsets.zero,
                      child: daftar.isEmpty
                          ? const Padding(padding: EdgeInsets.all(20), child: Text('Tidak ada barang.', style: TextStyle(fontSize: 17, color: Warna.teksPudar)))
                          : TabelSederhana(
                              kolom: const ['Barang', 'Stok', 'Stok minimum', 'HPP', 'Status'],
                              lebar: const [6, 2, 2, 2, 2],
                              rataKanan: const {1, 2, 3},
                              baris: [
                                for (final b in daftar)
                                  [
                                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text(b.nama, style: gayaSelTebal),
                                      Text(b.barcode ?? 'tanpa barcode', style: const TextStyle(fontSize: 14, color: Warna.teksPudar)),
                                    ]),
                                    Text('${formatAngka(b.stok)} ${b.satuan}',
                                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: b.stok <= 0 ? Warna.merah : (b.menipis ? Warna.oranye : Warna.teks))),
                                    Text(b.stokMinimum == 0 ? '-' : '${b.stokMinimum}', style: gayaSel),
                                    Text(b.hpp == null ? '-' : formatRupiah(b.hpp!), style: gayaSel),
                                    Lencana.status(!b.aktif ? 'Nonaktif' : (b.stok <= 0 ? 'Habis' : (b.menipis ? 'Menipis' : 'Aman'))),
                                  ],
                              ],
                            ),
                    ),
                  ]);
                },
              ),
            ),
          ]);
        },
      );
}
