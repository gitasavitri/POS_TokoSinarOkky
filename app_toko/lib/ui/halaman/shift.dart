import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pos_core/pos_core.dart';

import '../../data/model.dart';
import '../../layanan/aplikasi.dart';
import '../komponen/umum.dart';
import '../tema.dart';

/// Folder cadangan otomatis: Documents\POS-Cadangan.
Future<String> folderCadangan() async {
  final d = await getApplicationDocumentsDirectory();
  return '${d.path}${Platform.pathSeparator}POS-Cadangan';
}

/// Buka shift: kasir mengisi uang modal di laci/dompet kasir.
Future<Shift?> bukaShiftDialog(BuildContext context) => showDialog<Shift>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _DialogBukaShift(),
    );

class _DialogBukaShift extends StatefulWidget {
  const _DialogBukaShift();
  @override
  State<_DialogBukaShift> createState() => _DialogBukaShiftState();
}

class _DialogBukaShiftState extends State<_DialogBukaShift> {
  final _modal = TextEditingController();
  int _nilai = 0;

  void _buka() {
    final app = context.app;
    final s = app.penjualan.bukaShift(cabangId: app.cabang.id, kasirId: app.penggunaAktif!.id, modalAwal: _nilai);
    Navigator.pop(context, s);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Buka shift', style: TextStyle(fontWeight: FontWeight.w800)),
        content: SizedBox(
          width: 480,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Halo, ${context.app.penggunaAktif!.nama}. Hitung uang modal (uang kembalian) sebelum mulai berjualan.',
                style: const TextStyle(fontSize: 17, height: 1.5)),
            const SizedBox(height: 18),
            InputRupiah(
              controller: _modal,
              autofocus: true,
              besar: true,
              label: 'Uang modal awal',
              onChanged: (n) => setState(() => _nilai = n),
              onSubmitted: (_) => _buka(),
            ),
          ]),
        ),
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          FilledButton(onPressed: _buka, child: const Text('Mulai shift')),
        ],
      );
}

/// Tutup shift: hitung uang tunai, catat selisih, lalu cadangkan data otomatis.
Future<bool?> tutupShiftDialog(BuildContext context) =>
    showDialog<bool>(context: context, barrierDismissible: false, builder: (_) => const _DialogTutupShift());

class _DialogTutupShift extends StatefulWidget {
  const _DialogTutupShift();
  @override
  State<_DialogTutupShift> createState() => _DialogTutupShiftState();
}

class _DialogTutupShiftState extends State<_DialogTutupShift> {
  final _kas = TextEditingController();
  int? _dihitung;
  late RingkasanShift _r;
  bool _sibuk = false;

  @override
  void initState() {
    super.initState();
    _r = context.app.penjualan.ringkasanShift(context.app.shiftAktif!.id);
  }

  Future<void> _tutup() async {
    if (_dihitung == null || _sibuk) return;
    setState(() => _sibuk = true);
    final app = context.app;
    final p = app.penggunaAktif!;
    app.penjualan.tutupShift(shiftId: _r.shift.id, kasDihitung: _dihitung!, olehId: p.id);
    String pesan = 'Shift ditutup.';
    try {
      final f = app.cadangkan(await folderCadangan());
      pesan += ' Data dicadangkan ke $f';
    } catch (e) {
      pesan += ' Cadangan otomatis gagal: ${pesanGalat(e)}';
    }
    final baris = <BarisStruk>[
      BarisStruk(app.cabang.namaToko, rata: Rata.tengah, tebal: true),
      BarisStruk('TUTUP SHIFT', rata: Rata.tengah, tebal: true),
      BarisStruk(garis()),
      BarisStruk(kiriKanan('Kasir', p.nama)),
      BarisStruk(kiriKanan('Dibuka', formatStruk(_r.shift.dibukaPada))),
      BarisStruk(kiriKanan('Ditutup', formatStruk(DateTime.now()))),
      BarisStruk(kiriKanan('Transaksi', '${_r.jumlahTransaksi}')),
      BarisStruk(kiriKanan('Modal awal', formatAngka(_r.shift.modalAwal))),
      BarisStruk(kiriKanan('Penjualan tunai', formatAngka(_r.penjualanTunai))),
      BarisStruk(kiriKanan('Non-tunai', formatAngka(_r.penjualanNonTunai))),
      BarisStruk(kiriKanan('Retur tunai', formatAngka(_r.returTunai))),
      BarisStruk(kiriKanan('Kas seharusnya', formatAngka(_r.kasSistem)), tebal: true),
      BarisStruk(kiriKanan('Kas dihitung', formatAngka(_dihitung!)), tebal: true),
      BarisStruk(kiriKanan('Selisih', formatAngka(_dihitung! - _r.kasSistem)), tebal: true),
    ];
    await app.kirimKePrinter(cetakBaris(baris, potongKertas: app.potongKertas));
    if (!mounted) return;
    tampilkanPesan(context, pesan);
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final selisih = _dihitung == null ? null : _dihitung! - _r.kasSistem;
    Widget baris(String a, int b, {bool tebal = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(children: [
            Expanded(child: Text(a, style: TextStyle(fontSize: 18, fontWeight: tebal ? FontWeight.w800 : FontWeight.w500))),
            Text(formatRupiah(b), style: TextStyle(fontSize: 18, fontWeight: tebal ? FontWeight.w800 : FontWeight.w600)),
          ]),
        );
    return AlertDialog(
      title: const Text('Tutup shift', style: TextStyle(fontWeight: FontWeight.w800)),
      content: SizedBox(
        width: 520,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Dibuka ${formatLayar(_r.shift.dibukaPada)} · ${_r.jumlahTransaksi} transaksi',
              style: const TextStyle(fontSize: 16, color: Warna.teksPudar)),
          const SizedBox(height: 12),
          baris('Uang modal awal', _r.shift.modalAwal),
          baris('Penjualan tunai', _r.penjualanTunai),
          baris('Retur dibayar tunai', -_r.returTunai),
          const Divider(height: 18),
          baris('Uang tunai seharusnya', _r.kasSistem, tebal: true),
          baris('Non-tunai (tidak di laci)', _r.penjualanNonTunai),
          const SizedBox(height: 16),
          InputRupiah(
            controller: _kas,
            autofocus: true,
            besar: true,
            label: 'Uang tunai yang dihitung',
            onChanged: (n) => setState(() => _dihitung = _kas.text.isEmpty ? null : n),
          ),
          if (selisih != null) ...[
            const SizedBox(height: 14),
            KotakPesan(
              selisih == 0 ? 'Uang pas, tidak ada selisih.' : 'Selisih ${formatRupiah(selisih)}. Akan tercatat dan dilihat Admin.',
              jenis: selisih == 0 ? JenisPesan.berhasil : JenisPesan.perhatian,
            ),
          ],
        ]),
      ),
      actions: [
        OutlinedButton(onPressed: _sibuk ? null : () => Navigator.pop(context, false), child: const Text('Batal')),
        FilledButton(onPressed: _dihitung == null || _sibuk ? null : _tutup, child: Text(_sibuk ? 'Menutup…' : 'Tutup shift & keluar')),
      ],
    );
  }
}
