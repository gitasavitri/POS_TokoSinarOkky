import 'package:flutter/material.dart';
import 'package:pos_core/pos_core.dart';

import '../../layanan/aplikasi.dart';
import '../komponen/umum.dart';
import '../tema.dart';
import 'transaksi.dart';

/// Retur (SPV/Admin): scan barcode struk → pilih barang → uang dikembalikan tunai.
class IsiRetur extends StatefulWidget {
  const IsiRetur({super.key});
  @override
  State<IsiRetur> createState() => _IsiReturState();
}

typedef _Item = ({String itemId, String barangId, String nama, int qty, int harga, int sudahRetur});

class _IsiReturState extends State<IsiRetur> {
  final _scan = TextEditingController();
  final _alasan = TextEditingController();
  String? _transaksiId;
  DataStruk? _struk;
  List<_Item> _item = [];
  final _qty = <String, int>{};
  bool _kembaliKeStok = true;

  Aplikasi get app => context.app;

  void _cari() {
    final id = app.penjualan.idDariNomor(app.cabang.id, _scan.text);
    if (id == null) {
      tampilkanPesan(context, 'Struk tidak ditemukan di toko ini.', galat: true);
      return;
    }
    final s = app.penjualan.struk(id, app.cabang);
    if (s!.dibatalkan) {
      tampilkanPesan(context, 'Transaksi ini sudah dibatalkan, tidak bisa diretur.', galat: true);
      return;
    }
    setState(() {
      _transaksiId = id;
      _struk = s;
      _item = app.penjualan.itemUntukRetur(id);
      _qty.clear();
      _alasan.clear();
    });
  }

  int get _total => _item.fold(0, (s, i) => s + (_qty[i.itemId] ?? 0) * i.harga);

  Future<void> _proses() async {
    if (_alasan.text.trim().isEmpty) return tampilkanPesan(context, 'Isi alasan retur.', galat: true);
    final ok = await konfirmasi(context,
        judul: 'Proses retur?', isi: 'Kembalikan uang tunai ${formatRupiah(_total)} ke pembeli.', ya: 'Proses retur');
    if (!ok || !mounted) return;
    try {
      final t = app.penjualan.retur(
        transaksiId: _transaksiId!,
        qtyPerItem: _qty,
        kembaliKeStok: _kembaliKeStok,
        alasan: _alasan.text,
        olehId: app.penggunaAktif!.id,
      );
      tampilkanPesan(context, 'Retur tersimpan. Kembalikan ${formatRupiah(t)} ke pembeli.');
      setState(() {
        _transaksiId = null;
        _struk = null;
        _scan.clear();
      });
    } catch (e) {
      tampilkanPesan(context, pesanGalat(e), galat: true);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(24), children: [
        Panel(
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _scan,
                autofocus: true,
                style: const TextStyle(fontSize: 21),
                decoration: const InputDecoration(
                  labelText: 'Scan barcode di struk atau ketik nomor transaksi',
                  hintText: 'contoh: TRX-A01-261105-0001',
                  prefixIcon: Icon(Icons.qr_code_scanner, color: Warna.hijau),
                ),
                onSubmitted: (_) => _cari(),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(height: 58, child: FilledButton(onPressed: _cari, child: const Text('Cari'))),
          ]),
        ),
        const SizedBox(height: 16),
        if (_struk != null)
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              flex: 3,
              child: Panel(
                judul: 'Pilih barang yang diretur · ${_struk!.noTransaksi}',
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (final i in _item)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(i.nama, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                            Text('Dibeli ${i.qty} × ${formatRupiah(i.harga)}${i.sudahRetur > 0 ? ' · sudah diretur ${i.sudahRetur}' : ''}',
                                style: const TextStyle(fontSize: 15.5, color: Warna.teksPudar)),
                          ]),
                        ),
                        if (i.qty - i.sudahRetur > 0)
                          PengaturJumlah(
                            nilai: _qty[i.itemId] ?? 0,
                            min: 0,
                            onUbah: (v) => setState(() => _qty[i.itemId] = v.clamp(0, i.qty - i.sudahRetur)),
                          )
                        else
                          const Lencana('Sudah diretur semua', latar: Warna.abuMuda, warna: Warna.teks2),
                      ]),
                    ),
                  const Divider(height: 28),
                  CheckboxListTile(
                    value: _kembaliKeStok,
                    onChanged: (v) => setState(() => _kembaliKeStok = v ?? true),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text('Barang masih bagus, kembalikan ke stok', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                    subtitle: const Text('Matikan kalau barang rusak/kedaluwarsa (tidak dijual lagi).'),
                  ),
                  const SizedBox(height: 8),
                  TextField(controller: _alasan, style: const TextStyle(fontSize: 18), decoration: const InputDecoration(labelText: 'Alasan retur')),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(child: Text('Uang dikembalikan: ${formatRupiah(_total)}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800))),
                    FilledButton(onPressed: _total > 0 ? _proses : null, child: const Text('Proses retur')),
                  ]),
                ]),
              ),
            ),
            const SizedBox(width: 16),
            SizedBox(width: 420, height: 620, child: PratinjauStruk(baris: susunStruk(_struk!))),
          ])
        else
          const KotakPesan('Retur hanya untuk SPV/Admin. Uang dikembalikan tunai dan tercatat di laporan serta tutup shift.', jenis: JenisPesan.info),
      ]);
}
