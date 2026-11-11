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
  retur('Tukar / retur barang', Icons.assignment_return, GrupAdmin.penjualan, Warna.merahIkon, Warna.merahIkonMuda),
  shiftMenunggu('Shift menunggu dihitung', Icons.mark_email_unread, GrupAdmin.penjualan, Warna.oranyeTua, Warna.oranyeMuda),
  barangMasuk('Barang masuk', Icons.local_shipping, GrupAdmin.barang, Warna.toska, Warna.toskaMuda),
  ubahHarga('Ubah harga', Icons.sell, GrupAdmin.barang, Warna.coklat, Warna.coklatMuda),
  koreksi('Koreksi barang masuk', Icons.fact_check, GrupAdmin.barang, Warna.ungu, Warna.unguMuda),
  produk('Produk & stok', Icons.inventory_2, GrupAdmin.barang, Warna.hijauIkon, Warna.hijauIkonMuda),
  order('Order barang', Icons.shopping_cart, GrupAdmin.barang, Warna.oranyeTua, Warna.oranyeMuda),
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

/// Kelompok ikon di menu Kasir.
enum GrupKasir { penjualan, barang, shift }

/// Menu ikon Kasir (revisi B, + tukar/kembalikan barang revisi F). Stok opname, laporan lengkap, log, karyawan, dan pengaturan printer tetap tidak ada.
enum MenuKasir {
  beranda('Menu', Icons.apps, GrupKasir.penjualan, Warna.utama, Warna.utamaMuda),
  transaksi('Transaksi', Icons.point_of_sale, GrupKasir.penjualan, Warna.utama, Color(0xFFDCEBFC)),
  penjualanShift('Penjualan shift saya', Icons.receipt_long, GrupKasir.penjualan, Warna.hijauIkon, Warna.hijauIkonMuda),
  cetakUlang('Cetak ulang struk', Icons.print, GrupKasir.penjualan, Warna.abuIkon, Warna.abuIkonMuda),
  retur('Tukar / kembalikan barang', Icons.assignment_return, GrupKasir.penjualan, Warna.merahIkon, Warna.merahIkonMuda),
  cekStok('Cek stok & harga', Icons.inventory_2, GrupKasir.barang, Warna.hijauIkon, Warna.hijauIkonMuda),
  barangMasuk('Barang masuk', Icons.local_shipping, GrupKasir.barang, Warna.toska, Warna.toskaMuda),
  ubahHarga('Ubah harga', Icons.sell, GrupKasir.barang, Warna.coklat, Warna.coklatMuda),
  mintaKoreksi('Minta koreksi barang masuk', Icons.fact_check, GrupKasir.barang, Warna.ungu, Warna.unguMuda),
  orderBarang('Order barang', Icons.shopping_cart, GrupKasir.barang, Warna.oranyeTua, Warna.oranyeMuda),
  tutupShift('Tutup shift', Icons.lock_clock, GrupKasir.shift, Warna.merahIkon, Warna.merahIkonMuda);

  const MenuKasir(this.label, this.ikon, this.grup, this.warna, this.latar);
  final String label;
  final IconData ikon;
  final GrupKasir grup;
  final Color warna;
  final Color latar;

  /// Menu yang dibuka sebagai halaman (bukan dialog / pesan).
  bool get halaman => switch (this) {
        MenuKasir.mintaKoreksi || MenuKasir.tutupShift => false,
        _ => true,
      };
}

/// Kerangka halaman SPV/Admin: kepala biru dengan tombol "← Menu" (atau Esc) + isi selebar layar.
class KerangkaAdmin extends StatelessWidget {
  const KerangkaAdmin({super.key, required this.aktif, required this.onMenu, required this.judul, this.aksi = const [], required this.child});

  final MenuAdmin aktif;
  final BukaMenu onMenu;
  final String judul;
  final List<Widget> aksi;
  final Widget child;

  @override
  Widget build(BuildContext context) => KerangkaMenu(judul: judul, onKembali: () => onMenu(MenuAdmin.beranda), aksi: aksi, child: child);
}

/// Kerangka halaman di dalam menu ikon (Kasir, SPV, Admin): kepala biru dengan tombol "← Menu" (atau Esc).
class KerangkaMenu extends StatelessWidget {
  const KerangkaMenu({super.key, required this.judul, required this.onKembali, this.aksi = const [], required this.child});

  final String judul;
  final VoidCallback onKembali;
  final List<Widget> aksi;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final app = AplikasiScope.of(context, dengar: true);
    final p = app.penggunaAktif;
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): onKembali},
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            BarKepala(
              judul: judul,
              onMenu: onKembali,
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
