import 'package:flutter/material.dart';
import 'package:pos_core/pos_core.dart';

import '../../data/model.dart';
import '../../layanan/aplikasi.dart';
import '../komponen/umum.dart';
import '../tema.dart';
import 'transaksi.dart';

/// Penjualan shift saya (revisi D): hanya transaksi kasir ini di shift yang sedang aktif.
/// Total, tunai, non-tunai, jumlah transaksi + daftar (klik untuk cetak ulang). Tanpa laba/HPP.
class IsiPenjualanShift extends StatefulWidget {
  const IsiPenjualanShift({super.key, this.onIsiUlang});

  /// "Ubah transaksi" dari detail: barangnya dibawa ke layar Transaksi.
  final ValueChanged<KeTransaksi>? onIsiUlang;
  @override
  State<IsiPenjualanShift> createState() => _IsiPenjualanShiftState();
}

class _IsiPenjualanShiftState extends State<IsiPenjualanShift> {
  List<BarisTransaksi> _daftar = [];
  RingkasanShift? _r;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  void _muat() {
    final app = context.app;
    final s = app.shiftAktif;
    setState(() {
      _r = s == null ? null : app.penjualan.ringkasanShift(s.id);
      _daftar = s == null ? [] : app.penjualan.transaksiShift(s.id);
    });
  }

  Future<void> _buka(BarisTransaksi t) async {
    final isi = await bukaDetailTransaksi(context, t.id, bisaIsiUlang: widget.onIsiUlang != null);
    if (!mounted) return;
    if (isi != null) return widget.onIsiUlang?.call(isi);
    _muat();
  }

  @override
  Widget build(BuildContext context) {
    final r = _r;
    if (r == null) {
      return const Center(
        child: Text('Belum ada shift yang dibuka. Buka shift lewat menu Transaksi.', style: TextStyle(fontSize: 19, color: Warna.teksPudar)),
      );
    }
    final batal = _daftar.where((t) => t.dibatalkan).length;
    return ListView(padding: const EdgeInsets.all(24), children: [
      Text('Shift dibuka ${formatLayar(r.shift.dibukaPada)}', style: const TextStyle(fontSize: 16, color: Warna.teksPudar)),
      const SizedBox(height: 12),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: KartuAngka(
            label: 'Total penjualan',
            nilai: formatRupiah(r.penjualan),
            catatan: r.potonganTukar == 0 ? null : 'termasuk tukar barang ${formatRupiah(r.potonganTukar)}',
            aksen: Warna.sukses,
            ikon: Icons.payments,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(child: KartuAngka(label: 'Tunai', nilai: formatRupiah(r.penjualanTunai), aksen: Warna.hijauIkon, ikon: Icons.money)),
        const SizedBox(width: 14),
        Expanded(child: KartuAngka(label: 'Non-tunai', nilai: formatRupiah(r.penjualanNonTunai), aksen: Warna.biru, ikon: Icons.qr_code_2)),
        const SizedBox(width: 14),
        Expanded(
          child: KartuAngka(
            label: 'Jumlah transaksi',
            nilai: '${r.jumlahTransaksi}',
            catatan: batal == 0 ? null : '$batal dibatalkan (tidak dihitung)',
            aksen: Warna.utama,
            ikon: Icons.receipt_long,
          ),
        ),
      ]),
      const SizedBox(height: 18),
      Panel(
        judul: 'Transaksi saya di shift ini (${_daftar.length})',
        padding: EdgeInsets.zero,
        child: _daftar.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Belum ada transaksi di shift ini.', style: TextStyle(fontSize: 17, color: Warna.teksPudar)),
              )
            : TabelSederhana(
                kolom: const ['Jam', 'No. transaksi', 'Barang', 'Bayar', 'Total', 'Status'],
                lebar: const [2, 5, 2, 3, 3, 3],
                rataKanan: const {2, 4},
                onTap: (i) => _buka(_daftar[i]),
                baris: [
                  for (final t in _daftar)
                    [
                      Text(formatJam(t.waktu), style: gayaSel),
                      Text(t.noTransaksi, style: gayaSelTebal),
                      Text(formatAngka(t.jumlahBarang), style: gayaSel),
                      Text(t.metode.label, style: gayaSel),
                      Text(formatRupiah(t.total), style: gayaSelTebal),
                      Lencana.status(t.status),
                    ],
                ],
              ),
      ),
      const Padding(
        padding: EdgeInsets.only(top: 10),
        child: Text('Klik transaksi untuk melihat isinya dan mencetak ulang struk.', style: TextStyle(fontSize: 15.5, color: Warna.teksPudar)),
      ),
    ]);
  }
}
