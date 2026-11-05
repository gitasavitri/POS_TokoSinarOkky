import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pos_core/pos_core.dart';

import '../layanan/aplikasi.dart';
import 'halaman/barang_masuk.dart';
import 'halaman/beranda.dart';
import 'halaman/karyawan.dart';
import 'halaman/kasir.dart';
import 'halaman/koreksi.dart';
import 'halaman/laporan.dart';
import 'halaman/masuk.dart';
import 'halaman/pengaturan.dart';
import 'halaman/produk.dart';
import 'halaman/retur.dart';
import 'halaman/setup_awal.dart';
import 'halaman/ubah_harga.dart';
import 'komponen/kerangka.dart';
import 'tema.dart';

class AplikasiToko extends StatefulWidget {
  const AplikasiToko({super.key, required this.app});
  final Aplikasi app;
  @override
  State<AplikasiToko> createState() => _AplikasiTokoState();
}

class _AplikasiTokoState extends State<AplikasiToko> {
  bool _tombol(KeyEvent _) {
    widget.app.adaAktivitas();
    return false;
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_tombol);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_tombol);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AplikasiScope(
        aplikasi: widget.app,
        child: MaterialApp(
          title: 'POS Toko',
          debugShowCheckedModeBanner: false,
          theme: buatTema(),
          builder: (context, child) => Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => widget.app.adaAktivitas(),
            child: child,
          ),
          home: const _Akar(),
        ),
      );
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

/// Kasir: layar penjualan, bisa membuka barang masuk / ubah harga / pengaturan printer sebagai layar penuh.
class _AlurKasir extends StatelessWidget {
  const _AlurKasir({super.key});

  @override
  Widget build(BuildContext context) {
    void buka(String judul, Widget isi) => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => HalamanPenuh(judul: judul, child: isi),
        ));
    return HalamanKasir(
      onBukaBarangMasuk: () => buka('Barang masuk', const IsiBarangMasuk()),
      onBukaUbahHarga: () => buka('Ubah harga', const IsiUbahHarga()),
      onBukaPengaturan: () => buka('Pengaturan printer', const IsiPengaturan(hanyaPrinter: true)),
    );
  }
}

/// Layar penuh dengan kepala hijau dan tombol kembali ke penjualan (untuk kasir).
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
          color: Warna.hijauTua,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(children: [
            Text(judul, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(width: 20),
            Expanded(
              child: Text('${app.cabang.namaToko} · ${app.cabang.nama} · ${app.penggunaAktif?.nama ?? ''}',
                  style: const TextStyle(color: Color(0xFFCFE3DA), fontSize: 17)),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Warna.hijauTua, minimumSize: const Size(48, 48)),
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

  void _buka(MenuAdmin m) => setState(() => _menu = m);

  @override
  Widget build(BuildContext context) {
    if (_menu == MenuAdmin.penjualan) {
      return HalamanKasir(
        onKembaliKeMenu: () => _buka(MenuAdmin.beranda),
        onBukaBarangMasuk: () => _buka(MenuAdmin.barangMasuk),
        onBukaUbahHarga: () => _buka(MenuAdmin.ubahHarga),
        onBukaPengaturan: () => _buka(MenuAdmin.pengaturan),
      );
    }
    final isi = switch (_menu) {
      MenuAdmin.beranda => IsiBeranda(onMenu: _buka),
      MenuAdmin.barangMasuk => const IsiBarangMasuk(),
      MenuAdmin.ubahHarga => const IsiUbahHarga(),
      MenuAdmin.koreksi => const IsiKoreksi(),
      MenuAdmin.produk => const IsiProduk(),
      MenuAdmin.retur => const IsiRetur(),
      MenuAdmin.laporan => const IsiLaporan(),
      MenuAdmin.log => const IsiLog(),
      MenuAdmin.karyawan => const IsiKaryawan(),
      MenuAdmin.pengaturan => const IsiPengaturan(),
      MenuAdmin.penjualan => const SizedBox(),
    };
    return KerangkaAdmin(aktif: _menu, onMenu: _buka, judul: _menu.label, child: KeyedSubtree(key: ValueKey(_menu), child: isi));
  }
}
