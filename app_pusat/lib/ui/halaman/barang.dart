import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pos_core/pos_core.dart';
import 'package:pos_ui/pos_ui.dart';

import '../../data/model.dart';
import '../../layanan/sesi.dart';
import '../komponen.dart';

/// Barang semua toko + harga pusat (berlaku untuk semua toko).
class IsiBarang extends StatefulWidget {
  const IsiBarang({super.key});
  @override
  State<IsiBarang> createState() => _IsiBarangState();
}

class _IsiBarangState extends State<IsiBarang> {
  final _kata = TextEditingController();
  String _cari = '';
  int _versi = 0;

  void _segarkan() => setState(() => _versi++);

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _kata,
                style: const TextStyle(fontSize: 19),
                decoration: const InputDecoration(hintText: 'Cari nama atau barcode, lalu Enter', prefixIcon: Icon(Icons.search)),
                onSubmitted: (v) => setState(() => _cari = v),
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: () async {
                if (await dialogBarang(context, null)) _segarkan();
              },
              icon: const Icon(Icons.add),
              label: const Text('Barang baru'),
            ),
            const SizedBox(width: 10),
            OutlinedButton(onPressed: () => _dialogKembar(context), child: const Text('Barcode kembar')),
          ]),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: Text('Harga pusat berlaku di SEMUA toko dan menggantikan harga lama toko. Klik barang untuk mengubah harga.',
              style: TextStyle(fontSize: 15.5, color: Warna.teksPudar)),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: Muat<List<BarangPusat>>(
            key: ValueKey('$_cari $_versi'),
            ambil: (s) => s.pakai((api) => api.barang(kata: _cari)),
            isi: (context, daftar, _) => ListView(padding: const EdgeInsets.fromLTRB(24, 0, 24, 24), children: [
              Panel(
                padding: EdgeInsets.zero,
                child: daftar.isEmpty
                    ? const Padding(padding: EdgeInsets.all(20), child: Text('Tidak ada barang.', style: TextStyle(fontSize: 17, color: Warna.teksPudar)))
                    : TabelSederhana(
                        kolom: const ['Barang', 'Kategori', 'Harga pusat', 'Grosir', 'HPP tertinggi', 'Stok semua toko', ''],
                        lebar: const [6, 3, 3, 4, 3, 3, 2],
                        rataKanan: const {2, 4, 5},
                        onTap: (i) async {
                          if (await dialogHarga(context, daftar[i])) _segarkan();
                        },
                        baris: [
                          for (final b in daftar)
                            [
                              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(b.nama, style: gayaSelTebal),
                                Text('${b.barcode ?? 'tanpa barcode'} · ${b.satuan} · dijual di ${b.jumlahToko} toko',
                                    style: const TextStyle(fontSize: 14, color: Warna.teksPudar)),
                              ]),
                              Text(b.kategori, style: gayaSel),
                              Text(b.harga == null ? 'harga toko' : formatRupiah(b.harga!.eceran),
                                  style: b.harga == null ? const TextStyle(fontSize: 15, color: Warna.teksPudar) : gayaSelTebal),
                              Text(
                                b.harga == null || b.harga!.grosir.isEmpty ? '-' : b.harga!.grosir.map((t) => '≥${t.minQty}: ${formatAngka(t.harga)}').join('\n'),
                                style: const TextStyle(fontSize: 15),
                              ),
                              Text(b.hppTertinggi == null ? '-' : formatRupiah(b.hppTertinggi!), style: gayaSel),
                              Text('${formatAngka(b.stokTotal)} ${b.satuan}', style: gayaSel),
                              IconButton(
                                tooltip: 'Ubah data barang',
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () async {
                                  if (await dialogBarang(context, b)) _segarkan();
                                },
                              ),
                            ],
                        ],
                      ),
              ),
              if (daftar.length >= 200)
                const Padding(padding: EdgeInsets.only(top: 8), child: Text('Hanya 200 barang pertama. Persempit pencarian.', style: TextStyle(color: Warna.teksPudar))),
            ]),
          ),
        ),
      ]);
}

/// Ubah harga eceran + tingkat grosir untuk semua toko. Mengembalikan true kalau tersimpan.
Future<bool> dialogHarga(BuildContext context, BarangPusat b) async {
  final hasil = await showDialog<bool>(context: context, barrierDismissible: false, builder: (_) => _DialogHarga(barang: b, sesi: context.sesi));
  return hasil ?? false;
}

class _DialogHarga extends StatefulWidget {
  const _DialogHarga({required this.barang, required this.sesi});
  final BarangPusat barang;
  final Sesi sesi;
  @override
  State<_DialogHarga> createState() => _DialogHargaState();
}

class _DialogHargaState extends State<_DialogHarga> {
  late final _eceran = TextEditingController(text: widget.barang.harga == null ? '' : formatAngka(widget.barang.harga!.eceran));
  late final List<(TextEditingController, TextEditingController)> _tingkat = [
    for (final t in widget.barang.harga?.grosir ?? const <TingkatGrosir>[]) (TextEditingController(text: '${t.minQty}'), TextEditingController(text: formatAngka(t.harga))),
  ];
  final _alasan = TextEditingController();
  String? _galat;
  bool _sibuk = false;

  List<TingkatGrosir> get _grosir => [for (final (q, h) in _tingkat) TingkatGrosir(minQty: bacaAngka(q.text), harga: bacaAngka(h.text))];

  Future<void> _simpan() async {
    final eceran = bacaAngka(_eceran.text);
    final salah = periksaTingkatGrosir(eceran: eceran, hpp: widget.barang.hppTertinggi, tingkat: _grosir);
    if (eceran <= 0) return setState(() => _galat = 'Isi harga eceran.');
    if (salah.isNotEmpty) return setState(() => _galat = 'Tingkat ${salah.keys.first + 1}: ${salah.values.first}');
    if (_alasan.text.trim().isEmpty) return setState(() => _galat = 'Isi alasan perubahan harga.');
    setState(() {
      _sibuk = true;
      _galat = null;
    });
    try {
      final peringatan = await widget.sesi.pakai((api) => api.ubahHarga(barangId: widget.barang.id, eceran: eceran, grosir: _grosir, alasan: _alasan.text.trim()));
      if (!mounted) return;
      Navigator.pop(context, true);
      tampilkanPesan(context, peringatan.isEmpty ? 'Harga baru dikirim ke semua toko (± 1–2 menit).' : 'Tersimpan. ${peringatan.join(' ')}');
    } on GalatServer catch (e) {
      setState(() => _galat = e.pesan);
    } finally {
      if (mounted) setState(() => _sibuk = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.barang;
    final eceran = bacaAngka(_eceran.text);
    final hpp = b.hppTertinggi;
    return AlertDialog(
      title: Text('Harga ${b.nama}', style: const TextStyle(fontWeight: FontWeight.w800)),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(
              'HPP tertinggi di toko: ${hpp == null ? 'belum ada' : formatRupiah(hpp)}'
              '${b.harga == null ? '' : ' · Harga pusat sekarang: ${formatRupiah(b.harga!.eceran)}'}',
              style: const TextStyle(fontSize: 16, color: Warna.teksPudar),
            ),
            const SizedBox(height: 16),
            InputRupiah(controller: _eceran, label: 'Harga eceran per ${b.satuan}', onChanged: (_) => setState(() {})),
            if (hpp != null && eceran > 0 && eceran <= hpp)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: KotakPesan('Harga eceran sama dengan atau di bawah HPP: toko akan rugi.', jenis: JenisPesan.perhatian),
              ),
            const SizedBox(height: 18),
            const Text('Harga grosir (opsional) — berlaku untuk seluruh jumlah di baris belanja', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            for (final (i, (q, h)) in _tingkat.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(children: [
                  SizedBox(
                    width: 150,
                    child: TextField(
                      controller: q,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: const TextStyle(fontSize: 18),
                      decoration: InputDecoration(labelText: 'Min. jumlah', suffixText: b.satuan),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: InputRupiah(controller: h, label: 'Harga per ${b.satuan}')),
                  IconButton(onPressed: () => setState(() => _tingkat.removeAt(i)), icon: const Icon(Icons.delete_outline, color: Warna.merah)),
                ]),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _tingkat.length >= 5 ? null : () => setState(() => _tingkat.add((TextEditingController(), TextEditingController()))),
                icon: const Icon(Icons.add),
                label: const Text('Tambah tingkat grosir'),
              ),
            ),
            const SizedBox(height: 10),
            TextField(controller: _alasan, style: const TextStyle(fontSize: 18), decoration: const InputDecoration(labelText: 'Alasan (wajib), mis. harga supplier naik')),
            if (_galat != null) ...[const SizedBox(height: 12), KotakPesan(_galat!, jenis: JenisPesan.galat)],
          ]),
        ),
      ),
      actions: [
        OutlinedButton(onPressed: _sibuk ? null : () => Navigator.pop(context, false), child: const Text('Batal')),
        FilledButton(onPressed: _sibuk ? null : _simpan, child: Text(_sibuk ? 'Menyimpan…' : 'Simpan untuk semua toko')),
      ],
    );
  }
}

/// Tambah barang baru (null) atau ubah data barang. Mengembalikan true kalau tersimpan.
Future<bool> dialogBarang(BuildContext context, BarangPusat? b) async {
  final sesi = context.sesi;
  final List<Kategori> kategori;
  try {
    kategori = await sesi.pakai((api) => api.kategori());
  } on GalatServer catch (e) {
    if (context.mounted) tampilkanPesan(context, e.pesan, galat: true);
    return false;
  }
  if (!context.mounted) return false;
  final hasil = await showDialog<bool>(context: context, builder: (_) => _DialogBarang(barang: b, kategori: kategori, sesi: sesi));
  return hasil ?? false;
}

class _DialogBarang extends StatefulWidget {
  const _DialogBarang({required this.barang, required this.kategori, required this.sesi});
  final BarangPusat? barang;
  final List<Kategori> kategori;
  final Sesi sesi;
  @override
  State<_DialogBarang> createState() => _DialogBarangState();
}

class _DialogBarangState extends State<_DialogBarang> {
  late final _nama = TextEditingController(text: widget.barang?.nama);
  late final _barcode = TextEditingController(text: widget.barang?.barcode);
  late final _satuan = TextEditingController(text: widget.barang?.satuan ?? 'pcs');
  late String? _kategori = widget.barang?.kategoriId;
  late bool _aktif = widget.barang?.aktif ?? true;
  late final List<Kategori> _daftarKategori = [...widget.kategori];
  String? _galat;

  Future<void> _tambahKategori() async {
    final c = TextEditingController();
    final nama = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Kategori baru'),
        content: TextField(controller: c, autofocus: true, decoration: const InputDecoration(labelText: 'Nama kategori')),
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(d), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(d, c.text.trim()), child: const Text('Tambah')),
        ],
      ),
    );
    if (nama == null || nama.isEmpty) return;
    try {
      await widget.sesi.pakai((api) => api.tambahKategori(nama));
      final baru = await widget.sesi.pakai((api) => api.kategori());
      setState(() {
        _daftarKategori
          ..clear()
          ..addAll(baru);
        _kategori = baru.where((k) => k.nama.toLowerCase() == nama.toLowerCase()).firstOrNull?.id ?? _kategori;
      });
    } on GalatServer catch (e) {
      setState(() => _galat = e.pesan);
    }
  }

  Future<void> _simpan() async {
    if (_kategori == null) return setState(() => _galat = 'Pilih kategori.');
    try {
      await widget.sesi.pakai((api) => api.simpanBarang(
            id: widget.barang?.id,
            barcode: _barcode.text.trim().isEmpty ? null : _barcode.text.trim(),
            nama: _nama.text,
            kategoriId: _kategori!,
            satuan: _satuan.text,
            aktif: _aktif,
          ));
      if (mounted) Navigator.pop(context, true);
    } on GalatServer catch (e) {
      setState(() => _galat = e.pesan);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.barang == null ? 'Barang baru' : 'Ubah data barang', style: const TextStyle(fontWeight: FontWeight.w800)),
        content: SizedBox(
          width: 560,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(controller: _nama, style: const TextStyle(fontSize: 18), decoration: const InputDecoration(labelText: 'Nama barang')),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: TextField(controller: _barcode, style: const TextStyle(fontSize: 18), decoration: const InputDecoration(labelText: 'Barcode (boleh kosong)'))),
              const SizedBox(width: 12),
              SizedBox(width: 150, child: TextField(controller: _satuan, style: const TextStyle(fontSize: 18), decoration: const InputDecoration(labelText: 'Satuan'))),
            ]),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _kategori,
                  decoration: const InputDecoration(labelText: 'Kategori'),
                  items: [for (final k in _daftarKategori) DropdownMenuItem(value: k.id, child: Text(k.nama))],
                  onChanged: (v) => setState(() => _kategori = v),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton(onPressed: _tambahKategori, child: const Text('+ Kategori')),
            ]),
            if (widget.barang != null)
              SwitchListTile(
                value: _aktif,
                onChanged: (v) => setState(() => _aktif = v),
                contentPadding: EdgeInsets.zero,
                title: const Text('Masih dijual', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                subtitle: const Text('Matikan untuk menyembunyikan barang dari kasir di semua toko'),
              ),
            const SizedBox(height: 6),
            const Text('Barang baru muncul di kasir toko setelah toko mencatat barang masuk untuk barang ini.',
                style: TextStyle(fontSize: 14.5, color: Warna.teksPudar)),
            if (_galat != null) ...[const SizedBox(height: 12), KotakPesan(_galat!, jenis: JenisPesan.galat)],
          ]),
        ),
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          FilledButton(onPressed: _simpan, child: const Text('Simpan')),
        ],
      );
}

Future<void> _dialogKembar(BuildContext context) => showDialog<void>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Barcode kembar', style: TextStyle(fontWeight: FontWeight.w800)),
        content: SizedBox(
          width: 640,
          child: Muat<List<BarangKembar>>(
            ambil: (s) => s.pakai((api) => api.barangKembar()),
            isi: (context, daftar, _) => daftar.isEmpty
                ? const Text('Tidak ada barcode kembar.', style: TextStyle(fontSize: 17))
                : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const Text(
                      'Terjadi kalau dua toko membuat barang baru dengan barcode sama saat offline. '
                      'Ubah barcode salah satunya (atau nonaktifkan) lewat tombol ubah di daftar barang.',
                      style: TextStyle(fontSize: 15, color: Warna.teksPudar),
                    ),
                    const SizedBox(height: 12),
                    for (final k in daftar) Text('${k.barcode} · ${k.nama} · dibuat ${formatTanggal(k.dibuat)}', style: const TextStyle(fontSize: 16)),
                  ]),
          ),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(d), child: const Text('Tutup'))],
      ),
    );
