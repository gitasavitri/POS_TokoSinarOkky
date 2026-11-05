import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pos_core/pos_core.dart';

import '../../data/model.dart';
import '../../layanan/aplikasi.dart';
import '../komponen/kerangka.dart';
import '../komponen/umum.dart';
import '../tema.dart';

/// Daftar barang toko ini: harga, HPP, stok, stok minimum, stok opname.
class IsiProduk extends StatefulWidget {
  const IsiProduk({super.key});
  @override
  State<IsiProduk> createState() => _IsiProdukState();
}

class _IsiProdukState extends State<IsiProduk> {
  final _kata = TextEditingController();
  List<DetailBarang> _daftar = [];
  bool _hanyaMenipis = false;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  void _muat() {
    final app = context.app;
    setState(() => _daftar = _hanyaMenipis ? app.katalog.stokMenipis(app.cabang.id) : app.katalog.daftarToko(app.cabang.id, kata: _kata.text));
  }

  Future<void> _opname(DetailBarang b) async {
    final fisik = TextEditingController();
    final alasan = TextEditingController(text: 'Stok opname');
    final minimum = TextEditingController(text: '${b.stokMinimum}');
    final ok = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(b.nama, style: const TextStyle(fontWeight: FontWeight.w800)),
        content: SizedBox(
          width: 480,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Stok di sistem: ${b.stok} ${b.satuan}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            TextField(
              controller: fisik,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              decoration: InputDecoration(labelText: 'Stok hasil hitung fisik (${b.satuan})', hintText: 'kosongkan kalau hanya mengubah stok minimum'),
            ),
            const SizedBox(height: 14),
            TextField(controller: alasan, style: const TextStyle(fontSize: 18), decoration: const InputDecoration(labelText: 'Catatan')),
            const SizedBox(height: 14),
            TextField(
              controller: minimum,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(fontSize: 19),
              decoration: const InputDecoration(labelText: 'Stok minimum (peringatan stok hampir habis)'),
            ),
          ]),
        ),
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(d), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(d, 'ok'), child: const Text('Simpan')),
        ],
      ),
    );
    if (ok == null || !mounted) return;
    final app = context.app;
    try {
      final p = app.penggunaAktif!;
      final m = bacaAngka(minimum.text);
      if (m != b.stokMinimum) app.katalog.aturStokMinimum(b.id, app.cabang.id, m, olehId: p.id);
      if (fisik.text.isNotEmpty) {
        final s = app.barangMasuk.stokOpname(cabangId: app.cabang.id, barangId: b.id, stokFisik: bacaAngka(fisik.text), alasan: alasan.text, oleh: p);
        tampilkanPesan(context, s == 0 ? 'Stok cocok, tidak ada selisih.' : 'Selisih ${s > 0 ? '+' : ''}$s ${b.satuan} tercatat.');
      } else {
        tampilkanPesan(context, 'Tersimpan.');
      }
      _muat();
    } catch (e) {
      tampilkanPesan(context, pesanGalat(e), galat: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bolehOpname = context.app.boleh(Izin.stokOpname);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _kata,
              style: const TextStyle(fontSize: 19),
              decoration: const InputDecoration(hintText: 'Cari nama atau barcode', prefixIcon: Icon(Icons.search)),
              onChanged: (_) => _muat(),
            ),
          ),
          const SizedBox(width: 14),
          FilterChip(
            label: const Text('Hanya stok hampir habis', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            selected: _hanyaMenipis,
            padding: const EdgeInsets.all(10),
            onSelected: (v) {
              _hanyaMenipis = v;
              _muat();
            },
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Text('${_daftar.length} barang · Barang baru ditambahkan lewat Barang masuk.', style: const TextStyle(fontSize: 15.5, color: Warna.teksPudar)),
      ),
      const SizedBox(height: 10),
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(24, 0, 24, 24), children: [
          Panel(
            padding: EdgeInsets.zero,
            child: TabelSederhana(
              kolom: const ['Barang', 'Kategori', 'Harga', 'Grosir', 'HPP', 'Stok'],
              lebar: const [6, 3, 3, 4, 3, 3],
              rataKanan: const {2, 4, 5},
              onTap: bolehOpname ? (i) => _opname(_daftar[i]) : null,
              baris: [
                for (final b in _daftar)
                  [
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(b.nama, style: gayaSelTebal),
                      Text(b.barcode ?? 'tanpa barcode', style: const TextStyle(fontSize: 14, color: Warna.teksPudar)),
                    ]),
                    Text(b.kategoriNama, style: gayaSel),
                    Text(b.harga == null ? '-' : formatRupiah(b.harga!.eceran), style: gayaSelTebal),
                    Text(b.harga == null || b.harga!.grosir.isEmpty ? '-' : b.harga!.grosir.map((t) => '≥${t.minQty}: ${formatAngka(t.harga)}').join('\n'),
                        style: const TextStyle(fontSize: 15)),
                    Text(b.hpp == null ? '-' : formatRupiah(b.hpp!), style: gayaSel),
                    Text('${b.stok} ${b.satuan}',
                        style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: b.stok <= 0 ? Warna.merah : (b.stokMinimum > 0 && b.stok <= b.stokMinimum ? Warna.oranye : Warna.teks))),
                  ],
              ],
            ),
          ),
          if (bolehOpname)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text('Klik barang untuk stok opname atau mengatur stok minimum.', style: TextStyle(fontSize: 15.5, color: Warna.teksPudar)),
            ),
        ]),
      ),
    ]);
  }
}
