import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pos_core/pos_core.dart';

import '../../layanan/aplikasi.dart';
import '../tema.dart';
import 'umum.dart';


/// Kelompok ikon di menu SPV/Admin.
enum GrupAdmin { penjualan, barang, laporan }

/// Menu SPV/Admin (ditampilkan sebagai ikon-ikon di layar menu).
enum MenuAdmin {
  beranda('Menu', Icons.apps, GrupAdmin.penjualan, Warna.utama, Warna.utamaMuda),
  penjualan('Transaksi', Icons.point_of_sale, GrupAdmin.penjualan, Warna.utama, Color(0xFFDCEBFC)),
  retur('Retur', Icons.assignment_return, GrupAdmin.penjualan, Warna.merahIkon, Warna.merahIkonMuda),
  barangMasuk('Barang masuk', Icons.local_shipping, GrupAdmin.barang, Warna.toska, Warna.toskaMuda),
  ubahHarga('Ubah harga', Icons.sell, GrupAdmin.barang, Warna.coklat, Warna.coklatMuda),
  koreksi('Koreksi barang masuk', Icons.fact_check, GrupAdmin.barang, Warna.ungu, Warna.unguMuda),
  produk('Produk & stok', Icons.inventory_2, GrupAdmin.barang, Warna.hijauIkon, Warna.hijauIkonMuda),
  laporan('Laporan penjualan', Icons.bar_chart, GrupAdmin.laporan, Warna.utama, Color(0xFFDCEBFC)),
  log('Log aktivitas', Icons.history, GrupAdmin.laporan, Warna.abuIkon, Warna.abuIkonMuda),
  karyawan('Karyawan', Icons.badge, GrupAdmin.laporan, Warna.toska, Warna.toskaMuda),
  pengaturan('Pengaturan & printer', Icons.print, GrupAdmin.laporan, Warna.abuIkon, Warna.abuIkonMuda);

  const MenuAdmin(this.label, this.ikon, this.grup, this.warna, this.latar);
  final String label;
  final IconData ikon;
  final GrupAdmin grup;
  final Color warna;
  final Color latar;

  bool bolehUntuk(Peran p) => switch (this) {
        MenuAdmin.karyawan => p == Peran.admin,
        _ => true,
      };
}

typedef BukaMenu = void Function(MenuAdmin menu);

/// Kerangka halaman SPV/Admin: kepala biru dengan tombol "← Menu" (atau Esc) + isi selebar layar.
class KerangkaAdmin extends StatelessWidget {
  const KerangkaAdmin({super.key, required this.aktif, required this.onMenu, required this.judul, this.aksi = const [], required this.child});

  final MenuAdmin aktif;
  final BukaMenu onMenu;
  final String judul;
  final List<Widget> aksi;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final app = AplikasiScope.of(context, dengar: true);
    final p = app.penggunaAktif;
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => onMenu(MenuAdmin.beranda)},
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            BarKepala(
              judul: judul,
              onMenu: () => onMenu(MenuAdmin.beranda),
              nama: p == null ? '' : '${p.nama} (${p.peran.label})',
              keterangan: '${app.cabang.namaToko} · ${app.cabang.kode}',
              onKeluar: app.keluar,
              aksi: aksi,
            ),
            Expanded(child: child),
          ]),
        ),
      ),
    );
  }
}
