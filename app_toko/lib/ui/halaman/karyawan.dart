import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pos_core/pos_core.dart';

import '../../data/model.dart';
import '../../layanan/aplikasi.dart';
import '../komponen/umum.dart';
import '../tema.dart';

/// Admin: kelola kasir & SPV, ganti PIN, buka kunci, nonaktifkan. Plus tabel hak akses.
class IsiKaryawan extends StatefulWidget {
  const IsiKaryawan({super.key});
  @override
  State<IsiKaryawan> createState() => _IsiKaryawanState();
}

class _IsiKaryawanState extends State<IsiKaryawan> {
  late List<Pengguna> _daftar;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  void _muat() => setState(() => _daftar = context.app.pengguna.semua(context.app.cabang.id));

  Future<void> _tambah() async {
    final nama = TextEditingController();
    final pin = TextEditingController();
    var peran = Peran.kasir;
    final hasil = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, ss) => AlertDialog(
          title: const Text('Tambah karyawan', style: TextStyle(fontWeight: FontWeight.w800)),
          content: SizedBox(
            width: 460,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(controller: nama, autofocus: true, style: const TextStyle(fontSize: 19), decoration: const InputDecoration(labelText: 'Nama')),
              const SizedBox(height: 16),
              SegmentedButton<Peran>(
                segments: const [
                  ButtonSegment(value: Peran.kasir, label: Text('Kasir')),
                  ButtonSegment(value: Peran.spv, label: Text('SPV')),
                ],
                selected: {peran},
                onSelectionChanged: (s) => ss(() => peran = s.first),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: pin,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(fontSize: 22, letterSpacing: 6),
                decoration: const InputDecoration(labelText: 'PIN awal (6 angka)', counterText: ''),
              ),
              const SizedBox(height: 8),
              const Text('Beri tahu PIN ini langsung ke karyawan. PIN tidak bisa dilihat lagi setelah disimpan.',
                  style: TextStyle(fontSize: 15, color: Warna.teksPudar)),
            ]),
          ),
          actions: [
            OutlinedButton(onPressed: () => Navigator.pop(d), child: const Text('Batal')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Simpan')),
          ],
        ),
      ),
    );
    if (hasil != true || !mounted) return;
    try {
      final app = context.app;
      await app.pengguna.tambah(cabangId: app.cabang.id, nama: nama.text, peran: peran, pin: pin.text, olehId: app.penggunaAktif!.id);
      if (mounted) tampilkanPesan(context, '${nama.text} ditambahkan.');
      _muat();
    } catch (e) {
      if (mounted) tampilkanPesan(context, pesanGalat(e), galat: true);
    }
  }

  Future<void> _gantiPin(Pengguna p) async {
    final pin = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('PIN baru untuk ${p.nama}', style: const TextStyle(fontWeight: FontWeight.w800)),
        content: SizedBox(
          width: 400,
          child: TextField(
            controller: pin,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(fontSize: 22, letterSpacing: 6),
            decoration: const InputDecoration(labelText: 'PIN baru (6 angka)', counterText: ''),
          ),
        ),
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(d), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Simpan')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await context.app.pengguna.gantiPin(p.id, pin.text, olehId: context.app.penggunaAktif!.id);
      if (mounted) tampilkanPesan(context, 'PIN ${p.nama} diganti. Akun juga dibuka kuncinya.');
      _muat();
    } catch (e) {
      if (mounted) tampilkanPesan(context, pesanGalat(e), galat: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final saya = app.penggunaAktif!;
    const y = Text('Ya', style: TextStyle(fontWeight: FontWeight.w800, color: Warna.utamaGelap, fontSize: 16));
    const n = Text('—', style: TextStyle(color: Warna.teksPudar, fontSize: 16));
    const pin = Text('PIN SPV', style: TextStyle(fontWeight: FontWeight.w800, color: Warna.oranye, fontSize: 16));
    Widget sel(Akses a) => switch (a) { Akses.ya => y, Akses.pinSpv => pin, Akses.tidak => n };
    const izin = {
      Izin.jual: 'Jual & cetak struk',
      Izin.batalTransaksi: 'Batalkan transaksi',
      Izin.terimaRetur: 'Terima retur',
      Izin.catatBarangMasuk: 'Barang masuk (termasuk ubah harga)',
      Izin.ubahHargaNaik: 'Ubah harga naik',
      Izin.ubahHargaTurunBesar: 'Turunkan harga >10% / di bawah HPP',
      Izin.setujuiKoreksiBarangMasuk: 'Setujui koreksi barang masuk',
      Izin.stokOpname: 'Stok opname',
      Izin.lihatLaporan: 'Lihat laporan',
      Izin.aturPrinter: 'Atur printer',
      Izin.kelolaKaryawan: 'Kelola karyawan',
    };

    return ListView(padding: const EdgeInsets.all(24), children: [
      Row(children: [
        const Expanded(child: Text('Kasir dan SPV masuk dengan nama + PIN 6 angka.', style: TextStyle(fontSize: 17, color: Warna.teksPudar))),
        FilledButton.icon(onPressed: _tambah, icon: const Icon(Icons.person_add), label: const Text('Tambah karyawan')),
      ]),
      const SizedBox(height: 16),
      Panel(
        padding: EdgeInsets.zero,
        child: TabelSederhana(
          kolom: const ['Nama', 'Peran', 'Status', 'Aksi'],
          lebar: const [4, 2, 2, 6],
          baris: [
            for (final p in _daftar)
              [
                Text(p.nama + (p.namaPengguna != null ? '\n${p.namaPengguna}' : ''), style: gayaSelTebal),
                Text(p.cabangId == null ? '${p.peran.label} pusat' : p.peran.label, style: gayaSel),
                Lencana.status(!p.aktif ? 'Nonaktif' : (p.terkunci ? 'Terkunci' : 'Aktif')),
                if (p.id == saya.id || (p.peran == Peran.admin))
                  const Text('—', style: gayaSel)
                else
                  Wrap(spacing: 8, runSpacing: 6, children: [
                    if (p.terkunci)
                      FilledButton(
                        onPressed: () {
                          app.pengguna.bukaKunci(p.id, olehId: saya.id);
                          tampilkanPesan(context, 'Kunci akun ${p.nama} dibuka.');
                          _muat();
                        },
                        style: FilledButton.styleFrom(minimumSize: const Size(48, 46)),
                        child: const Text('Buka kunci'),
                      ),
                    OutlinedButton(
                        onPressed: () => _gantiPin(p), style: OutlinedButton.styleFrom(minimumSize: const Size(48, 46)), child: const Text('Ganti PIN')),
                    OutlinedButton(
                      onPressed: () async {
                        final ok = await konfirmasi(context,
                            judul: p.aktif ? 'Nonaktifkan ${p.nama}?' : 'Aktifkan ${p.nama}?',
                            isi: p.aktif ? 'Akun tidak bisa dipakai masuk lagi. Riwayat transaksinya tetap tersimpan.' : 'Akun bisa dipakai masuk lagi.',
                            ya: p.aktif ? 'Nonaktifkan' : 'Aktifkan',
                            bahaya: p.aktif);
                        if (!ok) return;
                        app.pengguna.aturAktif(p.id, !p.aktif, olehId: saya.id);
                        _muat();
                      },
                      style: OutlinedButton.styleFrom(minimumSize: const Size(48, 46)),
                      child: Text(p.aktif ? 'Nonaktifkan' : 'Aktifkan'),
                    ),
                  ]),
              ],
          ],
        ),
      ),
      const SizedBox(height: 20),
      Panel(
        judul: 'Hak akses per peran',
        padding: EdgeInsets.zero,
        child: TabelSederhana(
          kolom: const ['Boleh…', 'Kasir', 'SPV', 'Admin'],
          lebar: const [6, 2, 2, 2],
          baris: [
            for (final e in izin.entries) [Text(e.value, style: gayaSel), sel(aksesUntuk(Peran.kasir, e.key)), sel(aksesUntuk(Peran.spv, e.key)), sel(aksesUntuk(Peran.admin, e.key))],
          ],
        ),
      ),
    ]);
  }
}
