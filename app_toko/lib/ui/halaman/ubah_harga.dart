import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pos_core/pos_core.dart';

import '../../data/model.dart';
import '../../data/repo/harga_repo.dart';
import '../../layanan/aplikasi.dart';
import '../komponen/pin.dart';
import '../komponen/umum.dart';
import '../tema.dart';
import 'transaksi.dart';

/// Ubah harga tanpa barang masuk + antrean label rak.
class IsiUbahHarga extends StatefulWidget {
  const IsiUbahHarga({super.key});
  @override
  State<IsiUbahHarga> createState() => _IsiUbahHargaState();
}

class _IsiUbahHargaState extends State<IsiUbahHarga> {
  final _scan = TextEditingController();
  final _baru = TextEditingController();
  DetailBarang? _barang;
  int _hargaBaru = 0;
  List<(TextEditingController, TextEditingController)> _grosir = [];
  String? _alasan;
  late List<AntreanLabel> _antrean;
  final _dipilihLabel = <String>{};

  Aplikasi get app => context.app;

  @override
  void initState() {
    super.initState();
    _muatAntrean();
  }

  void _muatAntrean() {
    _antrean = app.harga.antreanLabel();
    _dipilihLabel
      ..clear()
      ..addAll(_antrean.map((a) => a.barangId));
  }

  void _pilihBarang(DetailBarang b) {
    if (b.harga == null) {
      tampilkanPesan(context, '${b.nama} belum punya harga. Isi lewat barang masuk.', galat: true);
      return;
    }
    setState(() {
      _barang = b;
      _hargaBaru = b.harga!.eceran;
      _baru.text = formatAngka(_hargaBaru);
      _grosir = [for (final g in b.harga!.grosir) (TextEditingController(text: '${g.minQty}'), TextEditingController(text: formatAngka(g.harga)))];
      _alasan = null;
      _scan.clear();
    });
  }

  void _cariScan() {
    final isi = _scan.text.trim();
    if (isi.isEmpty) return;
    final c = app.cabang.id;
    final b = app.katalog.cariBarcode(isi, c) ?? app.katalog.cari(isi, c, batas: 2).firstOrNull;
    if (b == null) {
      tampilkanPesan(context, 'Barang "$isi" tidak ditemukan.', galat: true);
      return;
    }
    _pilihBarang(b);
  }

  List<TingkatGrosir> get _tingkat => [for (final (m, h) in _grosir) TingkatGrosir(minQty: bacaAngka(m.text), harga: bacaAngka(h.text))];

  Future<void> _simpan() async {
    final b = _barang;
    if (b == null) return;
    if (_alasan == null) return tampilkanPesan(context, 'Pilih alasan perubahan.', galat: true);
    final cek = cekUbahHarga(hargaLama: b.harga!.eceran, hargaBaru: _hargaBaru, hpp: b.hpp);
    Pengguna? penyetuju;
    if (cek.perluPinSpv && !bolehMenyetujui(app.penggunaAktif!.peran)) {
      penyetuju = await mintaPinSpv(context, alasan: cek.alasan!);
      if (penyetuju == null) return;
    }
    try {
      app.harga.ubahHarga(
        cabang: app.cabang,
        barangId: b.id,
        hargaBaru: _hargaBaru,
        grosir: _tingkat,
        alasan: _alasan!,
        oleh: app.penggunaAktif!,
        disetujuiOleh: penyetuju,
      );
      if (!mounted) return;
      tampilkanPesan(context, 'Harga ${b.nama} disimpan dan langsung berlaku di kasir.');
      setState(() {
        _barang = null;
        _muatAntrean();
      });
    } catch (e) {
      if (mounted) tampilkanPesan(context, pesanGalat(e), galat: true);
    }
  }

  Future<void> _cetakLabel() async {
    final dipilih = _antrean.where((a) => _dipilihLabel.contains(a.barangId)).toList();
    if (dipilih.isEmpty) return;
    final semua = BytesBuilder();
    for (final a in dipilih) {
      final d = app.katalog.detail(a.barangId, app.cabang.id);
      if (d == null || d.harga == null) continue;
      final g = d.harga!.grosir;
      semua.add(cetakBaris(
        susunLabelRak(
          namaBarang: d.nama,
          harga: d.harga!.eceran,
          satuan: d.satuan,
          grosirTeks: g.isEmpty ? null : g.map((t) => 'min ${t.minQty}: ${formatAngka(t.harga)}').join(', '),
          berlaku: DateTime.now(),
        ),
        majuAkhir: 3,
        potongKertas: app.potongKertas,
      ));
    }
    final galat = await app.kirimKePrinter(semua.takeBytes());
    if (!mounted) return;
    if (galat != null) return tampilkanPesan(context, galat, galat: true);
    app.harga.hapusDariAntrean(dipilih.map((a) => a.barangId));
    tampilkanPesan(context, '${dipilih.length} label dicetak.');
    setState(_muatAntrean);
  }

  @override
  Widget build(BuildContext context) {
    final b = _barang;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          flex: 3,
          child: ListView(children: [
            Panel(
              child: TextField(
                controller: _scan,
                autofocus: true,
                style: const TextStyle(fontSize: 21),
                decoration: const InputDecoration(
                  labelText: 'Scan / cari barang yang harganya berubah',
                  hintText: 'Scan barcode atau ketik nama barang, lalu Enter',
                  prefixIcon: Icon(Icons.qr_code_scanner, color: Warna.utama),
                ),
                onSubmitted: (_) => _cariScan(),
              ),
            ),
            const SizedBox(height: 16),
            if (b == null)
              const KotakPesan(
                'Untuk harga yang berubah tanpa ada barang datang. Harga naik bisa langsung disimpan. '
                'Harga turun lebih dari 10% atau sampai di bawah HPP perlu PIN SPV.',
                jenis: JenisPesan.info,
              )
            else
              _formHarga(b),
          ]),
        ),
        const SizedBox(width: 18),
        SizedBox(
          width: 400,
          child: ListView(children: [
            Panel(
              judul: 'Label rak perlu dicetak ulang',
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (_antrean.isEmpty)
                  const Text('Tidak ada. Label masuk ke sini otomatis setiap harga jual berubah.', style: TextStyle(fontSize: 16, color: Warna.teksPudar)),
                for (final a in _antrean)
                  CheckboxListTile(
                    value: _dipilihLabel.contains(a.barangId),
                    onChanged: (v) => setState(() => v == true ? _dipilihLabel.add(a.barangId) : _dipilihLabel.remove(a.barangId)),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(app.katalog.detail(a.barangId, app.cabang.id)?.nama ?? '-', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                    subtitle: Text('${formatAngka(a.hargaLama)} → ${formatAngka(a.hargaBaru)} · ${formatJam(a.waktu)} · ${a.oleh}'),
                  ),
                if (_antrean.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  FilledButton(
                    onPressed: _dipilihLabel.isEmpty ? null : _cetakLabel,
                    style: FilledButton.styleFrom(backgroundColor: Warna.utamaTua),
                    child: Text('Cetak label rak (${_dipilihLabel.length})'),
                  ),
                ],
              ]),
            ),
            if (b != null) ...[
              const SizedBox(height: 16),
              Panel(
                judul: 'Contoh label rak',
                child: SizedBox(
                  height: 220,
                  child: PratinjauStruk(
                    baris: susunLabelRak(
                      namaBarang: b.nama,
                      harga: _hargaBaru > 0 ? _hargaBaru : b.harga!.eceran,
                      satuan: b.satuan,
                      grosirTeks: _tingkat.isEmpty ? null : _tingkat.map((t) => 'min ${t.minQty}: ${formatAngka(t.harga)}').join(', '),
                      berlaku: DateTime.now(),
                    ),
                  ),
                ),
              ),
            ],
          ]),
        ),
      ]),
    );
  }

  Widget _formHarga(DetailBarang b) {
    final lama = b.harga!.eceran;
    final cek = _hargaBaru > 0 ? cekUbahHarga(hargaLama: lama, hargaBaru: _hargaBaru, hpp: b.hpp) : null;
    final perluPin = cek?.perluPinSpv == true && !bolehMenyetujui(app.penggunaAktif!.peran);
    final (latar, warna) = _hargaBaru == lama || _hargaBaru == 0
        ? (Warna.abuMuda, Warna.teks2)
        : (cek!.perluPinSpv ? (Warna.merahMuda, Warna.merahTua) : (_hargaBaru > lama ? (Warna.utamaMuda, Warna.utamaGelap) : (Warna.oranyeMuda, Warna.oranyeTua)));
    final salahGrosir = periksaTingkatGrosir(eceran: _hargaBaru, hpp: b.hpp, tingkat: _tingkat);
    final untung = _hargaBaru - (b.hpp ?? 0);

    return Panel(
      judul: b.nama,
      aksi: Text('${b.barcode ?? '-'} · ${b.kategoriNama} · per ${b.satuan} · stok ${b.stok}', style: const TextStyle(fontSize: 15.5, color: Warna.teks2)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: _Kotak('HARGA SEKARANG', formatRupiah(lama), Warna.abuMuda, Warna.teks)),
            const SizedBox(width: 14),
            Expanded(
              child: InputRupiah(
                controller: _baru,
                besar: true,
                label: 'HARGA BARU',
                onChanged: (n) => setState(() => _hargaBaru = n),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _Kotak(
                'PERUBAHAN',
                _hargaBaru == 0 ? '—' : (_hargaBaru == lama ? 'Tidak berubah' : '${_hargaBaru > lama ? 'Naik' : 'Turun'} ${teksPerubahanPersen(lama, _hargaBaru).replaceAll(RegExp('[+-]'), '')}'),
                latar,
                warna,
              ),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: Warna.garisTipis, width: 2)),
          child: Wrap(spacing: 24, children: [
            Text.rich(TextSpan(style: const TextStyle(fontSize: 17), children: [
              const TextSpan(text: 'HPP: '),
              TextSpan(text: b.hpp == null ? '-' : formatRupiah(b.hpp!), style: const TextStyle(fontWeight: FontWeight.w800)),
              const TextSpan(text: '  (hanya berubah lewat barang masuk)', style: TextStyle(fontSize: 15, color: Warna.teksPudar)),
            ])),
            if (_hargaBaru > 0 && b.hpp != null)
              Text(untung > 0 ? 'Untung per ${b.satuan}: ${formatRupiah(untung)}' : 'Rugi per ${b.satuan}: ${formatRupiah(-untung)}',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: untung > 0 ? Warna.suksesTua : Warna.merah)),
          ]),
        ),
        const SizedBox(height: 16),
        const LabelKecil('Harga grosir', warna: Warna.utamaGelap),
        const SizedBox(height: 10),
        for (var i = 0; i < _grosir.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Text('Min  ', style: TextStyle(fontSize: 17)),
                SizedBox(
                  width: 90,
                  child: TextField(
                    controller: _grosir[i].$1,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                Text('  ${b.satuan}  →  ', style: const TextStyle(fontSize: 17)),
                SizedBox(width: 200, child: InputRupiah(controller: _grosir[i].$2, onChanged: (_) => setState(() {}))),
                const SizedBox(width: 10),
                IconButton(
                  onPressed: () => setState(() => _grosir.removeAt(i)),
                  icon: const Icon(Icons.delete_outline, color: Warna.merah),
                  tooltip: 'Hapus tingkat',
                ),
              ]),
              if (salahGrosir[i] != null)
                Text(salahGrosir[i]!, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Warna.merah)),
            ]),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
            onPressed: () => setState(() => _grosir.add((TextEditingController(), TextEditingController()))),
            child: const Text('+ Tambah tingkat harga'),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: 420,
          child: DropdownButtonFormField<String>(
            initialValue: _alasan,
            decoration: const InputDecoration(labelText: 'Alasan perubahan'),
            style: const TextStyle(fontSize: 19, color: Warna.teks, fontFamily: fontUtama),
            items: [for (final a in alasanUbahHarga) DropdownMenuItem(value: a, child: Text(a))],
            onChanged: (v) => setState(() => _alasan = v),
          ),
        ),
        const SizedBox(height: 16),
        if (perluPin)
          KotakPesan('Perlu persetujuan SPV: ${cek!.alasan} PIN SPV diminta saat menyimpan.')
        else if (_hargaBaru > 0 && _hargaBaru != lama)
          const KotakPesan('Langsung berlaku di kasir setelah disimpan. Tercatat di log dan dilaporkan ke Admin.', jenis: JenisPesan.berhasil),
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          OutlinedButton(onPressed: () => setState(() => _barang = null), child: const Text('Batal')),
          const SizedBox(width: 10),
          FilledButton(
            onPressed: _hargaBaru > 0 && salahGrosir.isEmpty ? _simpan : null,
            child: Text(perluPin ? 'Simpan (PIN SPV)' : 'Simpan harga baru'),
          ),
        ]),
      ]),
    );
  }
}

class _Kotak extends StatelessWidget {
  const _Kotak(this.label, this.nilai, this.latar, this.warna);
  final String label;
  final String nilai;
  final Color latar;
  final Color warna;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: latar, borderRadius: BorderRadius.circular(8)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: warna)),
          FittedBox(fit: BoxFit.scaleDown, child: Text(nilai, style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: warna))),
        ]),
      );
}
