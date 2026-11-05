import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pos_core/pos_core.dart';

import '../../data/repo/pengaturan_repo.dart';
import '../../layanan/aplikasi.dart';
import '../komponen/umum.dart';
import '../tema.dart';
import 'shift.dart';
import 'transaksi.dart';

/// Pengaturan printer (per PC), info toko, kategori & supplier, cadangan data.
class IsiPengaturan extends StatefulWidget {
  const IsiPengaturan({super.key, this.hanyaPrinter = false});
  final bool hanyaPrinter;
  @override
  State<IsiPengaturan> createState() => _IsiPengaturanState();
}

class _IsiPengaturanState extends State<IsiPengaturan> {
  List<String> _printer = [];
  String? _pilih;
  String? _galatDaftar;

  Aplikasi get app => context.app;

  @override
  void initState() {
    super.initState();
    _cariPrinter();
  }

  void _cariPrinter() {
    try {
      _printer = app.printer.daftarPrinter();
      _galatDaftar = null;
    } catch (e) {
      _printer = [];
      _galatDaftar = 'Gagal membaca daftar printer: ${pesanGalat(e)}';
    }
    _pilih = app.namaPrinter;
    if (_pilih != null && !_printer.contains(_pilih)) _printer = [_pilih!, ..._printer];
    setState(() {});
  }

  Future<void> _tesCetak() async {
    final galat = await app.kirimKePrinter(cetakTes(namaToko: app.cabang.namaToko, namaCabang: app.cabang.nama, potongKertas: app.potongKertas));
    if (mounted) tampilkanPesan(context, galat ?? 'Tes cetak terkirim. Cek baris angka 1–32 muat satu baris.', galat: galat != null);
  }

  @override
  Widget build(BuildContext context) {
    final p = app.pengaturan;
    final admin = app.penggunaAktif?.peran == Peran.admin;
    return ListView(padding: const EdgeInsets.all(24), children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          flex: 3,
          child: Panel(
            judul: 'Printer struk (khusus PC ini)',
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (_galatDaftar != null) ...[KotakPesan(_galatDaftar!, jenis: JenisPesan.galat), const SizedBox(height: 12)],
              DropdownButtonFormField<String>(
                initialValue: _pilih,
                decoration: const InputDecoration(labelText: 'Printer yang dipakai'),
                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: Warna.teks, fontFamily: fontUtama),
                items: [for (final n in _printer) DropdownMenuItem(value: n, child: Text(n))],
                onChanged: (v) => setState(() {
                  _pilih = v;
                  p.simpan(PengaturanRepo.kPrinter, v);
                }),
              ),
              const SizedBox(height: 6),
              const Text('Daftar ini diambil dari printer yang sudah terpasang di Windows. Printer baru: pasang drivernya dulu, lalu tekan Cari ulang.',
                  style: TextStyle(fontSize: 15, color: Warna.teksPudar)),
              const SizedBox(height: 14),
              SwitchListTile(
                value: app.cetakOtomatis,
                onChanged: (v) => setState(() => p.simpanBool(PengaturanRepo.kCetakOtomatis, v)),
                title: const Text('Cetak struk otomatis setelah bayar', style: TextStyle(fontSize: 17.5, fontWeight: FontWeight.w700)),
                subtitle: const Text('Kalau mati, kasir menekan tombol Cetak sendiri'),
              ),
              SwitchListTile(
                value: app.potongKertas,
                onChanged: (v) => setState(() => p.simpanBool(PengaturanRepo.kPotongKertas, v)),
                title: const Text('Potong kertas otomatis', style: TextStyle(fontSize: 17.5, fontWeight: FontWeight.w700)),
                subtitle: const Text('Hanya untuk printer yang punya pisau pemotong'),
              ),
              ListTile(
                title: const Text('Jumlah salinan struk', style: TextStyle(fontSize: 17.5, fontWeight: FontWeight.w700)),
                trailing: PengaturJumlah(
                  nilai: app.salinanStruk,
                  onUbah: (v) => setState(() => p.simpan(PengaturanRepo.kSalinanStruk, '${v.clamp(1, 3)}')),
                ),
              ),
              const SizedBox(height: 10),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                OutlinedButton(onPressed: _cariPrinter, child: const Text('Cari ulang printer')),
                const SizedBox(width: 10),
                FilledButton.icon(onPressed: _pilih == null ? null : _tesCetak, icon: const Icon(Icons.print), label: const Text('Tes cetak')),
              ]),
            ]),
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          flex: 2,
          child: Panel(
            judul: 'Contoh tes cetak',
            child: SizedBox(
              height: 330,
              child: PratinjauStruk(baris: [
                BarisStruk(app.cabang.namaToko, rata: Rata.tengah, tebal: true, besar: true),
                BarisStruk('Cabang ${app.cabang.nama}', rata: Rata.tengah),
                BarisStruk(garis()),
                const BarisStruk('TES CETAK', rata: Rata.tengah, tebal: true),
                BarisStruk(kiriKanan('Lebar kertas', '58 mm')),
                BarisStruk(kiriKanan('Huruf per baris', '32')),
                const BarisStruk('12345678901234567890123456789012'),
                BarisStruk(garis()),
              ]),
            ),
          ),
        ),
      ]),
      const SizedBox(height: 16),
      const KotakPesan(
        'Printer harus printer thermal 58 mm yang mendukung ESC/POS, tersambung USB, dan drivernya sudah terpasang di Windows. '
        'Scanner barcode USB langsung terbaca seperti keyboard, tidak perlu disetel.',
        jenis: JenisPesan.info,
      ),
      if (!widget.hanyaPrinter) ...[
        const SizedBox(height: 20),
        if (admin) _InfoToko(onSimpan: () => setState(() {})),
        if (admin) const SizedBox(height: 20),
        if (admin) const _KategoriSupplier(),
        if (admin) const SizedBox(height: 20),
        Panel(
          judul: 'Data & cadangan',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _Baris('Data penjualan tersimpan di', 'Komputer ini (tetap jalan tanpa internet)'),
            _Baris('Lokasi file database', app.lokasiDatabase ?? '-'),
            const _Baris('Cadangan otomatis', 'Setiap tutup shift → Documents\\POS-Cadangan'),
            const _Baris('Kirim ke kantor pusat', 'Belum aktif (menunggu Server Pusat)'),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: () async {
                  try {
                    final f = app.cadangkan(await folderCadangan());
                    if (context.mounted) tampilkanPesan(context, 'Tersimpan: $f');
                  } catch (e) {
                    if (context.mounted) tampilkanPesan(context, 'Gagal: ${pesanGalat(e)}', galat: true);
                  }
                },
                icon: const Icon(Icons.save_alt),
                label: const Text('Cadangkan sekarang'),
              ),
            ),
            const SizedBox(height: 8),
            Text('Salin folder cadangan ke flashdisk secara rutin. Sistem operasi: ${Platform.operatingSystem}.',
                style: const TextStyle(fontSize: 15, color: Warna.teksPudar)),
          ]),
        ),
      ],
    ]);
  }
}

class _Baris extends StatelessWidget {
  const _Baris(this.a, this.b);
  final String a;
  final String b;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 280, child: Text(a, style: const TextStyle(fontSize: 17))),
          Expanded(child: SelectableText(b, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
        ]),
      );
}

class _InfoToko extends StatefulWidget {
  const _InfoToko({required this.onSimpan});
  final VoidCallback onSimpan;
  @override
  State<_InfoToko> createState() => _InfoTokoState();
}

class _InfoTokoState extends State<_InfoToko> {
  late final c = context.app.cabang;
  late final _toko = TextEditingController(text: c.namaToko);
  late final _nama = TextEditingController(text: c.nama);
  late final _alamat = TextEditingController(text: c.alamat);
  late final _pesan = TextEditingController(text: c.pesanStruk);

  @override
  Widget build(BuildContext context) => Panel(
        judul: 'Info toko di struk (Admin)',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: TextField(controller: _toko, style: const TextStyle(fontSize: 18), decoration: const InputDecoration(labelText: 'Nama toko'))),
            const SizedBox(width: 14),
            Expanded(child: TextField(controller: _nama, style: const TextStyle(fontSize: 18), decoration: const InputDecoration(labelText: 'Nama cabang'))),
            const SizedBox(width: 14),
            SizedBox(width: 140, child: InputDecorator(decoration: const InputDecoration(labelText: 'Kode cabang'), child: Text(c.kode, style: const TextStyle(fontSize: 18)))),
          ]),
          const SizedBox(height: 14),
          TextField(controller: _alamat, style: const TextStyle(fontSize: 18), decoration: const InputDecoration(labelText: 'Alamat')),
          const SizedBox(height: 14),
          TextField(controller: _pesan, style: const TextStyle(fontSize: 18), decoration: const InputDecoration(labelText: 'Pesan di bawah struk')),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: () {
                final app = context.app;
                app.pengaturan.ubahInfoCabang(
                  cabangId: c.id,
                  nama: _nama.text,
                  alamat: _alamat.text,
                  pesanStruk: _pesan.text,
                  namaToko: _toko.text,
                  olehId: app.penggunaAktif!.id,
                );
                tampilkanPesan(context, 'Info toko disimpan.');
                app.segarkan();
                widget.onSimpan();
              },
              child: const Text('Simpan info toko'),
            ),
          ),
        ]),
      );
}

class _KategoriSupplier extends StatefulWidget {
  const _KategoriSupplier();
  @override
  State<_KategoriSupplier> createState() => _KategoriSupplierState();
}

class _KategoriSupplierState extends State<_KategoriSupplier> {
  final _kat = TextEditingController();
  final _sup = TextEditingController();

  void _tambah(bool kategori) {
    final app = context.app;
    final c = kategori ? _kat : _sup;
    try {
      if (kategori) {
        app.katalog.tambahKategori(c.text, cabangId: app.cabang.id, olehId: app.penggunaAktif!.id);
      } else {
        app.katalog.tambahSupplier(c.text, cabangId: app.cabang.id, olehId: app.penggunaAktif!.id);
      }
      c.clear();
      setState(() {});
    } catch (e) {
      tampilkanPesan(context, pesanGalat(e), galat: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    Widget kolom(String judul, List<String> isi, TextEditingController c, bool kategori) => Expanded(
          child: Panel(
            judul: judul,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Wrap(spacing: 8, runSpacing: 8, children: [for (final n in isi) Chip(label: Text(n, style: const TextStyle(fontSize: 16)))]),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: c,
                    style: const TextStyle(fontSize: 18),
                    decoration: InputDecoration(hintText: kategori ? 'Nama kategori baru' : 'Nama supplier baru'),
                    onSubmitted: (_) => _tambah(kategori),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(height: 56, child: OutlinedButton(onPressed: () => _tambah(kategori), child: const Text('Tambah'))),
              ]),
            ]),
          ),
        );
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      kolom('Kategori barang', [for (final k in app.katalog.kategori()) k.nama], _kat, true),
      const SizedBox(width: 18),
      kolom('Supplier', [for (final s in app.katalog.supplier()) s.nama], _sup, false),
    ]);
  }
}
