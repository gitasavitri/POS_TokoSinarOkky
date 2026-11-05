import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pos_core/pos_core.dart';
import 'package:pos_ui/pos_ui.dart';

import '../../data/model.dart';
import '../komponen.dart';

/// Daftar transaksi semua toko + unduh CSV (bisa dibuka di Excel).
class IsiTransaksi extends StatefulWidget {
  const IsiTransaksi({super.key});
  @override
  State<IsiTransaksi> createState() => _IsiTransaksiState();
}

/// CSV pemisah titik koma (Excel Indonesia) dengan BOM supaya huruf terbaca benar.
String csvTransaksi(List<TransaksiPusat> daftar) {
  String sel(Object v) => '"${'$v'.replaceAll('"', '""')}"';
  final b = StringBuffer('﻿')..writeln(['Toko', 'Tanggal (WIB)', 'Jam', 'No. transaksi', 'Kasir', 'Barang', 'Cara bayar', 'Total', 'Status'].map(sel).join(';'));
  for (final t in daftar) {
    b.writeln([t.kodeCabang, formatTanggal(t.waktu), formatJam(t.waktu), t.noTransaksi, t.kasir, t.jumlahBarang, t.metode.label, t.total, t.status].map(sel).join(';'));
  }
  return b.toString();
}

class _IsiTransaksiState extends State<IsiTransaksi> {
  Periode _periode = Periode.hariIni;
  String? _cabangId;

  Future<void> _unduh(List<TransaksiPusat> daftar) async {
    try {
      final folder = await getApplicationDocumentsDirectory();
      final nama = 'transaksi-${_periode.name}-${kodeTanggal(DateTime.now())}.csv';
      final f = File('${folder.path}${Platform.pathSeparator}$nama');
      await f.writeAsString(csvTransaksi(daftar));
      if (mounted) tampilkanPesan(context, 'Tersimpan di Documents: $nama');
    } catch (e) {
      if (mounted) tampilkanPesan(context, 'Gagal menyimpan: ${pesanGalat(e)}', galat: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (dari, sampai) = _periode.rentang(DateTime.now());
    return Muat<(List<TransaksiPusat>, List<CabangPusat>)>(
      key: ValueKey('$_periode $_cabangId'),
      ambil: (s) => s.pakai((api) async => (await api.transaksi(dari, sampai, cabangId: _cabangId), await api.cabang())),
      isi: (context, d, ulang) {
        final (daftar, cabang) = d;
        return ListView(padding: const EdgeInsets.all(24), children: [
          Wrap(spacing: 16, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
            PilihPeriode(nilai: _periode, onUbah: (p) => setState(() => _periode = p)),
            PilihCabang(cabang: cabang, nilai: _cabangId, onUbah: (v) => setState(() => _cabangId = v)),
            OutlinedButton.icon(onPressed: daftar.isEmpty ? null : () => _unduh(daftar), icon: const Icon(Icons.download), label: const Text('Unduh Excel (CSV)')),
          ]),
          const SizedBox(height: 16),
          Panel(
            judul: 'Transaksi (${daftar.length}${daftar.length >= 500 ? '+, hanya 500 terbaru' : ''})',
            padding: EdgeInsets.zero,
            child: daftar.isEmpty
                ? const Padding(padding: EdgeInsets.all(20), child: Text('Belum ada transaksi di periode ini.', style: TextStyle(fontSize: 17, color: Warna.teksPudar)))
                : TabelSederhana(
                    kolom: const ['Waktu', 'Toko', 'No. transaksi', 'Kasir', 'Barang', 'Cara bayar', 'Total', 'Status'],
                    lebar: const [3, 1, 4, 2, 1, 2, 3, 2],
                    rataKanan: const {4, 6},
                    baris: [
                      for (final t in daftar)
                        [
                          Text(waktuLengkap(t.waktu), style: const TextStyle(fontSize: 15.5)),
                          Text(t.kodeCabang, style: gayaSelTebal),
                          Text(t.noTransaksi, style: const TextStyle(fontFamily: fontMono, fontSize: 15, fontWeight: FontWeight.w700)),
                          Text(t.kasir, style: gayaSel),
                          Text('${t.jumlahBarang}', style: gayaSel),
                          Text(t.metode.label, style: gayaSel),
                          Text(formatRupiah(t.total),
                              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, decoration: t.batal ? TextDecoration.lineThrough : null)),
                          Lencana.status(t.status),
                        ],
                    ],
                  ),
          ),
        ]);
      },
    );
  }
}
