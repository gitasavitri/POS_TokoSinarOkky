import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pos_core/pos_core.dart';

import '../../data/model.dart';
import '../../data/repo/impor_repo.dart';
import '../../layanan/aplikasi.dart';
import '../../layanan/dokumen.dart';
import '../komponen/umum.dart';
import '../tema.dart';

/// Pilih file Excel. Mengembalikan (nama file, isi) atau null kalau dibatalkan.
typedef PilihFileExcel = Future<(String, Uint8List)?> Function();

/// Simpan template. Mengembalikan path, atau null kalau dibatalkan.
typedef SimpanTemplate = Future<String?> Function(String namaBawaan, Uint8List isi);

const _grupExcel = XTypeGroup(label: 'Excel', extensions: ['xlsx']);

Future<(String, Uint8List)?> pilihFileExcelBawaan() async {
  final f = await openFile(acceptedTypeGroups: const [_grupExcel], confirmButtonText: 'Pilih');
  if (f == null) return null;
  return (f.name, await f.readAsBytes());
}

Future<String?> simpanTemplateBawaan(String namaBawaan, Uint8List isi) async {
  final lokasi = await getSaveLocation(suggestedName: namaBawaan, acceptedTypeGroups: const [_grupExcel], confirmButtonText: 'Simpan');
  if (lokasi == null) return null;
  final path = lokasi.path.toLowerCase().endsWith('.xlsx') ? lokasi.path : '${lokasi.path}.xlsx';
  await File(path).writeAsBytes(isi, flush: true);
  return path;
}

/// Cara memilih file & menyimpan template. Diganti di uji tampilan (tanpa jendela Windows).
@visibleForTesting
PilihFileExcel pilihFileExcel = pilihFileExcelBawaan;
@visibleForTesting
SimpanTemplate simpanTemplateExcel = simpanTemplateBawaan;

/// Buka layar Impor stok awal (SPV/Admin). Mengembalikan true kalau ada yang disimpan.
Future<bool?> bukaImporStok(BuildContext context) => Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => HalamanImporStok(pilihFile: pilihFileExcel, simpanTemplate: simpanTemplateExcel),
    ));

/// Impor stok awal dari Excel (revisi J): template → pilih file → pratinjau (baris salah ditandai) → simpan.
/// Hasilnya sama seperti barang masuk biasa.
class HalamanImporStok extends StatefulWidget {
  const HalamanImporStok({super.key, required this.pilihFile, required this.simpanTemplate});
  final PilihFileExcel pilihFile;
  final SimpanTemplate simpanTemplate;

  @override
  State<HalamanImporStok> createState() => _HalamanImporStokState();
}

class _HalamanImporStokState extends State<HalamanImporStok> {
  String? _namaFile;
  List<BarisImporStok>? _data;
  PratinjauImpor? _pratinjau;
  late List<Supplier> _supplier;
  String? _supplierId;
  final _faktur = TextEditingController();
  bool _hanyaSalah = false;
  bool _sibuk = false;

  Aplikasi get app => context.app;

  @override
  void initState() {
    super.initState();
    _supplier = app.katalog.supplier();
    _supplierId = _supplier.where((s) => s.jenis == 'toko_utama').firstOrNull?.id ?? _supplier.firstOrNull?.id;
    _faktur.text = app.impor.noFakturBawaan();
  }

  @override
  void dispose() {
    _faktur.dispose();
    super.dispose();
  }

  Future<void> _simpanTemplate() async {
    try {
      final isi = templateImporStok(kategori: [for (final k in app.katalog.kategori()) k.nama], satuan: app.impor.satuanDipakai());
      final path = await widget.simpanTemplate('Template-stok-awal-${app.cabang.kode}.xlsx', isi);
      if (path != null && mounted) tampilkanPesan(context, 'Template disimpan: $path');
    } catch (e) {
      if (mounted) tampilkanPesan(context, 'Gagal menyimpan template: ${pesanGalat(e)}', galat: true);
    }
  }

  Future<void> _pilihFile() async {
    final f = await widget.pilihFile();
    if (f == null || !mounted) return;
    try {
      final data = bacaExcelImporStok(f.$2);
      if (data.isEmpty) throw const FormatException('Tidak ada baris barang di file ini. Isi mulai baris 2 di sheet "Stok awal".');
      setState(() {
        _namaFile = f.$1;
        _data = data;
        _hanyaSalah = false;
      });
      _periksa();
    } on FormatException catch (e) {
      tampilkanPesan(context, e.message, galat: true);
    } catch (e) {
      tampilkanPesan(context, 'File tidak bisa dibaca: ${pesanGalat(e)}', galat: true);
    }
  }

  void _periksa() => setState(() => _pratinjau = app.impor.periksa(_data!, app.cabang.id));

  Future<void> _tambahKategori() async {
    final k = _pratinjau!.kategoriBelumAda;
    final ok = await konfirmasi(context,
        judul: 'Tambah ${k.length} kategori baru?', isi: k.join(', '), ya: 'Tambah kategori');
    if (!ok || !mounted) return;
    try {
      app.impor.tambahKategori(k, cabangId: app.cabang.id, oleh: app.penggunaAktif!);
      _periksa();
    } catch (e) {
      tampilkanPesan(context, pesanGalat(e), galat: true);
    }
  }

  Future<void> _simpan() async {
    final p = _pratinjau!;
    if (_supplierId == null) return tampilkanPesan(context, 'Pilih supplier.', galat: true);
    if (_faktur.text.trim().isEmpty) return tampilkanPesan(context, 'Isi nomor faktur / keterangan.', galat: true);
    final ok = await konfirmasi(
      context,
      judul: 'Simpan stok awal ${p.benar.length} barang?',
      isi: '${p.jumlahBaru} barang baru, ${p.jumlahSudahAda} barang yang sudah ada. Total ${formatAngka(p.totalJumlah)} barang, '
          'nilai HPP ${formatRupiah(p.nilaiHpp)}.'
          '${p.jumlahSalah > 0 ? '\n\n${p.jumlahSalah} baris salah DILEWATI (tidak disimpan).' : ''}'
          '\n\nSetelah disimpan, data terkunci seperti barang masuk biasa. Kesalahan jumlah diperbaiki lewat koreksi barang masuk.',
      ya: 'Simpan',
    );
    if (!ok || !mounted) return;
    setState(() => _sibuk = true);
    try {
      app.impor.simpan(cabang: app.cabang, oleh: app.penggunaAktif!, pratinjau: p, supplierId: _supplierId!, noFaktur: _faktur.text);
      if (!mounted) return;
      tampilkanPesan(context, 'Stok awal ${p.benar.length} barang tersimpan.');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _sibuk = false);
      tampilkanPesan(context, pesanGalat(e), galat: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _pratinjau;
    return Scaffold(
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          color: Warna.utamaTua,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(children: [
            const Text('Impor stok awal dari Excel', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(width: 20),
            Expanded(
              child: Text('${app.cabang.namaToko} · ${app.cabang.nama} · ${app.penggunaAktif?.nama ?? ''}',
                  style: const TextStyle(color: Warna.utamaTeksTerang, fontSize: 17)),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Warna.utamaTua, minimumSize: const Size(48, 48)),
              child: const Text('Kembali', style: TextStyle(fontSize: 16)),
            ),
          ]),
        ),
        Expanded(child: p == null ? _langkahAwal() : _isiPratinjau(p)),
      ]),
    );
  }

  Widget _langkahAwal() => Center(
        child: SizedBox(
          width: 760,
          child: Panel(
            judul: 'Untuk toko baru: masukkan semua stok sekaligus',
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final (n, t) in const [
                ('1', 'Simpan template Excel, lalu isi: barcode, nama barang, kategori, satuan, jumlah, HPP, harga jual.'),
                ('2', 'Pilih file yang sudah diisi. Program memeriksa setiap baris dan menandai yang salah.'),
                ('3', 'Periksa pratinjau, lalu simpan. Hasilnya sama seperti barang masuk biasa: stok, HPP, harga, dan daftar barang toko.'),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    CircleAvatar(radius: 16, backgroundColor: Warna.utamaMuda, child: Text(n, style: const TextStyle(fontWeight: FontWeight.w800, color: Warna.utamaTua))),
                    const SizedBox(width: 12),
                    Expanded(child: Text(t, style: const TextStyle(fontSize: 17.5, height: 1.4))),
                  ]),
                ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: SizedBox(
                    height: 60,
                    child: OutlinedButton.icon(
                      key: const ValueKey('simpan-template'),
                      onPressed: _simpanTemplate,
                      icon: const Icon(Icons.download),
                      label: const Text('Simpan template Excel', style: TextStyle(fontSize: 18)),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: SizedBox(
                    height: 60,
                    child: FilledButton.icon(
                      key: const ValueKey('pilih-file-impor'),
                      onPressed: _pilihFile,
                      icon: const Icon(Icons.upload_file),
                      label: const Text('Pilih file Excel…', style: TextStyle(fontSize: 18)),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 14),
              const KotakPesan('Hanya SPV/Admin. Barang yang barcodenya sudah ada di program hanya ditambah stoknya '
                  '(nama, kategori, satuan tidak diubah); HPP dan harga jual mengikuti file.'),
            ]),
          ),
        ),
      );

  Widget _isiPratinjau(PratinjauImpor p) {
    final tampil = _hanyaSalah ? p.baris.where((b) => b.status == StatusImpor.salah).toList() : p.baris;
    Widget angka(String label, String nilai, Color warna) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Warna.garis, width: 1.5)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 14, color: Warna.teksPudar, fontWeight: FontWeight.w700)),
            Text(nilai, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: warna)),
          ]),
        );
    const lebar = [2, 4, 7, 3, 2, 2, 3, 3, 7];
    const kolom = ['Baris', 'Barcode', 'Nama barang', 'Kategori', 'Satuan', 'Jumlah', 'HPP', 'Harga jual', 'Status'];
    Widget sel(int i, Widget w) => Expanded(
          flex: lebar[i],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: Align(alignment: i >= 5 && i <= 7 ? Alignment.centerRight : Alignment.centerLeft, child: w),
          ),
        );
    const gs = TextStyle(fontSize: 15.5);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Wrap(spacing: 12, runSpacing: 10, children: [
              angka('File', _namaFile ?? '-', Warna.teks),
              angka('Baris', '${p.baris.length}', Warna.teks),
              angka('Barang baru', '${p.jumlahBaru}', Warna.utama),
              angka('Sudah ada', '${p.jumlahSudahAda}', Warna.suksesTua),
              angka('Salah', '${p.jumlahSalah}', p.jumlahSalah > 0 ? Warna.merah : Warna.teks),
              angka('Total stok', formatAngka(p.totalJumlah), Warna.teks),
            ]),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(onPressed: _pilihFile, icon: const Icon(Icons.upload_file), label: const Text('Pilih file lain')),
        ]),
        if (p.kategoriBelumAda.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Warna.oranyeMuda, borderRadius: BorderRadius.circular(10), border: Border.all(color: Warna.oranyeGaris)),
            child: Row(children: [
              const Icon(Icons.category, color: Warna.oranyeTua),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Kategori belum ada: ${p.kategoriBelumAda.join(', ')}. Tambahkan, atau samakan nama kategori di Excel dengan yang sudah ada.',
                    style: const TextStyle(fontSize: 16, color: Warna.oranyeTua)),
              ),
              const SizedBox(width: 10),
              FilledButton(
                key: const ValueKey('tambah-kategori-impor'),
                onPressed: _tambahKategori,
                child: Text('Tambah ${p.kategoriBelumAda.length} kategori'),
              ),
            ]),
          ),
        ],
        const SizedBox(height: 12),
        Row(children: [
          FilterChip(
            label: Text('Baris salah saja (${p.jumlahSalah})', style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
            selected: _hanyaSalah,
            onSelected: p.jumlahSalah == 0 ? null : (v) => setState(() => _hanyaSalah = v),
          ),
          const Spacer(),
          const Text('Perbaiki di Excel, simpan, lalu "Pilih file lain" untuk memeriksa ulang.', style: TextStyle(fontSize: 15, color: Warna.teksPudar)),
        ]),
        const SizedBox(height: 8),
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Warna.garis, width: 1.5)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                color: Warna.utamaMuda,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                child: Row(children: [
                  for (var i = 0; i < kolom.length; i++)
                    sel(i, Text(kolom[i].toUpperCase(), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: Warna.utamaTua))),
                ]),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: tampil.length,
                  itemBuilder: (context, r) {
                    final b = tampil[r];
                    final s = b.sumber;
                    final it = b.item;
                    final salah = b.status == StatusImpor.salah;
                    return Container(
                      key: ValueKey('impor-baris-${s.nomorBaris}'),
                      color: salah ? Warna.merahMuda : (r.isOdd ? Warna.baris2 : Colors.white),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                        sel(0, Text('${s.nomorBaris}', style: const TextStyle(fontSize: 15, fontFamily: fontMono))),
                        sel(1, Text(s.barcode.isEmpty ? '-' : s.barcode, style: const TextStyle(fontSize: 14.5, fontFamily: fontMono))),
                        sel(2, Text(it != null && !it.barangBaru ? it.nama : (s.nama.isEmpty ? '-' : s.nama), style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700))),
                        sel(3, Text(s.kategori.isEmpty ? '-' : s.kategori, style: gs)),
                        sel(4, Text(s.satuan.isEmpty ? '-' : s.satuan, style: gs)),
                        sel(5, Text(s.jumlah == null ? '-' : formatAngka(s.jumlah!), style: gs)),
                        sel(6, Text(s.hpp == null ? '-' : formatAngka(s.hpp!), style: gs)),
                        sel(7, Text(s.hargaJual == null ? '-' : formatAngka(s.hargaJual!), style: gs)),
                        sel(
                          8,
                          Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                            Text(b.status.label,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: switch (b.status) {
                                    StatusImpor.salah => Warna.merah,
                                    StatusImpor.baru => Warna.utama,
                                    StatusImpor.sudahAda => Warna.suksesTua,
                                  },
                                )),
                            for (final e in b.salah) Text(e, style: const TextStyle(fontSize: 14, color: Warna.merah)),
                            for (final c in b.catatan) Text(c, style: const TextStyle(fontSize: 14, color: Warna.teksPudar)),
                          ]),
                        ),
                      ]),
                    );
                  },
                ),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          SizedBox(
            width: 360,
            child: DropdownButtonFormField<String>(
              initialValue: _supplierId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Supplier / asal barang'),
              style: const TextStyle(fontSize: 17, color: Warna.teks, fontFamily: fontUtama),
              items: [for (final s in _supplier) DropdownMenuItem(value: s.id, child: Text(s.jenis == 'toko_utama' ? '${s.nama} (toko utama)' : s.nama))],
              onChanged: (v) => setState(() => _supplierId = v),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 300,
            child: TextField(
              controller: _faktur,
              style: const TextStyle(fontSize: 17),
              inputFormatters: [LengthLimitingTextInputFormatter(60)],
              decoration: const InputDecoration(labelText: 'No. faktur / keterangan'),
            ),
          ),
          const Spacer(),
          SizedBox(
            height: 60,
            child: FilledButton.icon(
              key: const ValueKey('simpan-impor'),
              onPressed: p.benar.isEmpty || _sibuk ? null : _simpan,
              icon: const Icon(Icons.save),
              label: Text(
                _sibuk
                    ? 'Menyimpan…'
                    : p.jumlahSalah == 0
                        ? 'Simpan ${p.benar.length} barang'
                        : 'Simpan ${p.benar.length} baris benar (lewati ${p.jumlahSalah})',
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ),
        ]),
      ]),
    );
  }
}
