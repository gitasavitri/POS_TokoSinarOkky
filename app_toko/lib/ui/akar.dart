import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pos_core/pos_core.dart';

import '../layanan/aplikasi.dart';
import 'halaman/barang_masuk.dart';
import 'halaman/beranda.dart';
import 'halaman/cek_stok.dart';
import 'halaman/karyawan.dart';
import 'halaman/kasir.dart';
import 'halaman/koreksi.dart';
import 'halaman/laporan.dart';
import 'halaman/masuk.dart';
import 'halaman/order.dart';
import 'halaman/pengaturan.dart';
import 'halaman/penjualan_shift.dart';
import 'halaman/produk.dart';
import 'halaman/retur.dart';
import 'halaman/setup_awal.dart';
import 'halaman/shift.dart';
import 'halaman/transaksi.dart';
import 'halaman/ubah_harga.dart';
import 'komponen/kerangka.dart';
import 'komponen/umum.dart';
import 'tema.dart';

class AplikasiToko extends StatefulWidget {
  const AplikasiToko({super.key, required this.app});
  final Aplikasi app;
  @override
  State<AplikasiToko> createState() => _AplikasiTokoState();
}

class _AplikasiTokoState extends State<AplikasiToko> {
  /// Aplikasi yang sedang dipakai: data asli, atau data latihan kalau mode latihan menyala.
  Aplikasi get _aktif => widget.app.pengaturMode?.aktif ?? widget.app;

  bool _tombol(KeyEvent _) {
    _aktif.adaAktivitas();
    return false;
  }

  void _gantiMode() => setState(() {});

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_tombol);
    widget.app.pengaturMode?.addListener(_gantiMode);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_tombol);
    widget.app.pengaturMode?.removeListener(_gantiMode);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = _aktif;
    return AplikasiScope(
      // Kunci berbeda per mode: semua layar dibuat ulang saat pindah ke / dari mode latihan.
      key: ValueKey(app.latihan),
      aplikasi: app,
      child: MaterialApp(
        title: app.latihan ? 'POS Toko · MODE LATIHAN' : 'POS Toko',
        debugShowCheckedModeBanner: false,
        theme: buatTema(),
        builder: (context, child) => Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => app.adaAktivitas(),
          child: app.latihan ? PitaLatihan(child: child!) : child,
        ),
        home: const _Akar(),
      ),
    );
  }
}

/// Pita oranye "MODE LATIHAN" di atas seluruh layar (termasuk dialog).
class PitaLatihan extends StatelessWidget {
  const PitaLatihan({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Material(
          key: const ValueKey('pita-latihan'),
          color: Warna.pitaLatihan,
          child: const SizedBox(
            height: 34,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.school, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text('MODE LATIHAN', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
              SizedBox(width: 14),
              Text('Transaksi tidak mengubah stok asli, tidak masuk laporan, dan tidak terkirim ke pusat',
                  style: TextStyle(color: Colors.white, fontSize: 15)),
            ]),
          ),
        ),
        Expanded(child: child),
      ]);
}

class _Akar extends StatelessWidget {
  const _Akar();
  @override
  Widget build(BuildContext context) {
    final app = AplikasiScope.of(context, dengar: true);
    if (!app.sudahDisiapkan) return const HalamanSetupAwal();
    final p = app.penggunaAktif;
    if (p == null) return const HalamanMasuk(key: ValueKey('masuk'));
    if (p.peran == Peran.kasir) return _AlurKasir(key: ValueKey('kasir-${p.id}'));
    return HalamanAdmin(key: ValueKey('admin-${p.id}'));
  }
}

/// Kasir: menu ikon (revisi B). Transaksi, penjualan shift sendiri, cetak ulang struk, cek stok & harga,
/// barang masuk, ubah harga, minta koreksi, order barang (revisi G), tutup shift.
/// Kembali ke menu atau keluar tidak menutup shift.
class _AlurKasir extends StatefulWidget {
  const _AlurKasir({super.key});
  @override
  State<_AlurKasir> createState() => _AlurKasirState();
}

class _AlurKasirState extends State<_AlurKasir> {
  MenuKasir _menu = MenuKasir.beranda;

  /// Barang dari "Ubah transaksi" / tukar barang yang dibawa ke layar Transaksi.
  KeTransaksi? _isi;
  int _kunciTransaksi = 0;

  @override
  void initState() {
    super.initState();
    // Setelah listrik padam: ada belanjaan belum dibayar / struk belum tercetak → langsung ke layar Transaksi.
    final app = context.app;
    final t = app.pemulihan.muatKeranjang(app.cabang.id);
    if (app.pemulihan.strukBelumCetak() != null || (t != null && !t.kosong)) _menu = MenuKasir.transaksi;
  }

  Future<void> _buka(MenuKasir m) async {
    final app = context.app;
    switch (m) {
      case MenuKasir.mintaKoreksi:
        return bukaRiwayatBarangMasuk(context);
      case MenuKasir.tutupShift:
        if (app.shiftAktif == null) return tampilkanPesan(context, 'Belum ada shift yang dibuka.', galat: true);
        final selesai = await tutupShiftDialog(context);
        if (selesai == true && mounted) app.keluar();
        return;
      default:
        setState(() {
          _menu = m;
          if (m != MenuKasir.transaksi) _isi = null;
        });
    }
  }

  void _keTransaksi(KeTransaksi isi) => setState(() {
        _isi = isi;
        _kunciTransaksi++;
        _menu = MenuKasir.transaksi;
      });

  Future<void> _bukaShift() async {
    final app = context.app;
    final s = await bukaShiftDialog(context);
    if (s != null && mounted) app.aturShift(s);
  }

  @override
  Widget build(BuildContext context) {
    void dorong(String judul, Widget isi) => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => HalamanPenuh(judul: judul, child: isi),
        ));
    if (_menu == MenuKasir.transaksi) {
      return HalamanKasir(
        key: ValueKey('transaksi-$_kunciTransaksi'),
        isiAwal: _isi,
        onKembaliKeMenu: () => setState(() {
          _isi = null;
          _menu = MenuKasir.beranda;
        }),
        // Dari layar Transaksi dibuka di atasnya, supaya belanjaan di layar tidak hilang.
        onBukaBarangMasuk: () => dorong('Barang masuk', const IsiBarangMasuk()),
        onBukaUbahHarga: () => dorong('Ubah harga', const IsiUbahHarga()),
        onBukaPengaturan: () => dorong('Pengaturan printer', const IsiPengaturan(hanyaPrinter: true)),
      );
    }
    if (_menu == MenuKasir.beranda) return MenuBerandaKasir(onMenu: _buka, onBukaShift: _bukaShift);
    final isi = switch (_menu) {
      MenuKasir.penjualanShift => IsiPenjualanShift(onIsiUlang: _keTransaksi),
      MenuKasir.cetakUlang => IsiCetakUlang(onIsiUlang: _keTransaksi),
      MenuKasir.retur => IsiRetur(onTukar: (d) => _keTransaksi(KeTransaksi.tukar(d))),
      MenuKasir.cekStok => const IsiCekStok(),
      MenuKasir.barangMasuk => const IsiBarangMasuk(),
      MenuKasir.ubahHarga => const IsiUbahHarga(),
      MenuKasir.orderBarang => const IsiOrderBarang(),
      _ => const SizedBox(),
    };
    return KerangkaMenu(
      judul: _menu.label,
      onKembali: () => setState(() => _menu = MenuKasir.beranda),
      child: KeyedSubtree(key: ValueKey(_menu), child: isi),
    );
  }
}

/// Layar penuh dengan kepala biru dan tombol kembali ke penjualan (dibuka dari layar Transaksi kasir).
class HalamanPenuh extends StatelessWidget {
  const HalamanPenuh({super.key, required this.judul, required this.child});
  final String judul;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    return Scaffold(
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          color: Warna.utamaTua,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(children: [
            Text(judul, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(width: 20),
            Expanded(
              child: Text('${app.cabang.namaToko} · ${app.cabang.nama} · ${app.penggunaAktif?.nama ?? ''}',
                  style: const TextStyle(color: Warna.utamaTeksTerang, fontSize: 17)),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Warna.utamaTua, minimumSize: const Size(48, 48)),
              child: const Text('Kembali ke penjualan', style: TextStyle(fontSize: 16)),
            ),
          ]),
        ),
        Expanded(child: child),
      ]),
    );
  }
}

/// SPV & Admin: menu samping + isi halaman.
class HalamanAdmin extends StatefulWidget {
  const HalamanAdmin({super.key});
  @override
  State<HalamanAdmin> createState() => _HalamanAdminState();
}

class _HalamanAdminState extends State<HalamanAdmin> {
  MenuAdmin _menu = MenuAdmin.beranda;

  /// Tukar barang dari menu Tukar / retur: dibawa ke layar Transaksi.
  KeTransaksi? _isi;
  int _kunci = 0;

  void _buka(MenuAdmin m) => setState(() {
        _menu = m;
        _isi = null;
      });

  @override
  Widget build(BuildContext context) {
    if (_menu == MenuAdmin.penjualan) {
      return HalamanKasir(
        key: ValueKey('penjualan-$_kunci'),
        isiAwal: _isi,
        onKembaliKeMenu: () => _buka(MenuAdmin.beranda),
        onBukaBarangMasuk: () => _buka(MenuAdmin.barangMasuk),
        onBukaUbahHarga: () => _buka(MenuAdmin.ubahHarga),
        onBukaPengaturan: () => _buka(MenuAdmin.pengaturan),
      );
    }
    if (_menu == MenuAdmin.beranda) return MenuBeranda(onMenu: _buka);
    final isi = switch (_menu) {
      MenuAdmin.beranda => const SizedBox(),
      MenuAdmin.barangMasuk => const IsiBarangMasuk(),
      MenuAdmin.ubahHarga => const IsiUbahHarga(),
      MenuAdmin.koreksi => const IsiKoreksi(),
      MenuAdmin.produk => const IsiProduk(),
      MenuAdmin.order => const IsiOrderBarang(),
      MenuAdmin.retur => IsiRetur(
          onTukar: (d) => setState(() {
            _isi = KeTransaksi.tukar(d);
            _kunci++;
            _menu = MenuAdmin.penjualan;
          }),
        ),
      MenuAdmin.shiftMenunggu => const IsiShiftMenunggu(),
      MenuAdmin.laporan => const IsiLaporan(),
      MenuAdmin.log => const IsiLog(),
      MenuAdmin.karyawan => const IsiKaryawan(),
      MenuAdmin.pengaturan => const IsiPengaturan(),
      MenuAdmin.penjualan => const SizedBox(),
    };
    return KerangkaAdmin(aktif: _menu, onMenu: _buka, judul: _menu.label, child: KeyedSubtree(key: ValueKey(_menu), child: isi));
  }
}
