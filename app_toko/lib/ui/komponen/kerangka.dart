import 'package:flutter/material.dart';
import 'package:pos_core/pos_core.dart';

import '../../layanan/aplikasi.dart';
import '../tema.dart';

/// Menu samping untuk halaman SPV/Admin.
enum MenuAdmin {
  beranda('Beranda', Icons.space_dashboard_outlined),
  penjualan('Buka layar kasir', Icons.point_of_sale),
  barangMasuk('Barang masuk', Icons.inventory_2_outlined),
  ubahHarga('Ubah harga', Icons.sell_outlined),
  koreksi('Koreksi barang masuk', Icons.fact_check_outlined),
  produk('Produk & stok', Icons.list_alt),
  retur('Retur', Icons.assignment_return_outlined),
  laporan('Laporan penjualan', Icons.bar_chart),
  log('Log aktivitas', Icons.history),
  karyawan('Karyawan', Icons.badge_outlined),
  pengaturan('Pengaturan & printer', Icons.settings_outlined);

  const MenuAdmin(this.label, this.ikon);
  final String label;
  final IconData ikon;

  bool bolehUntuk(Peran p) => switch (this) {
        MenuAdmin.karyawan => p == Peran.admin,
        _ => true,
      };
}

typedef BukaMenu = void Function(MenuAdmin menu);

/// Kerangka halaman SPV/Admin: menu kiri hijau tua + isi.
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
    final cabang = app.cabang;
    return Scaffold(
      body: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          width: 270,
          color: Warna.hijauTua,
          child: ListView(padding: const EdgeInsets.fromLTRB(14, 22, 14, 14), children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(cabang.namaToko, style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w800)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 2, 10, 18),
              child: Text('Cabang ${cabang.nama}\n${p?.peran.label ?? ''} · ${p?.nama ?? ''}',
                  style: const TextStyle(color: Warna.hijauTeksTerang, fontSize: 15, height: 1.45)),
            ),
            for (final m in MenuAdmin.values)
              if (p != null && m.bolehUntuk(p.peran))
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Material(
                    color: m == aktif ? const Color(0xFF1E5A45) : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => onMenu(m),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 50),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(children: [
                            Icon(m.ikon, color: Colors.white, size: 22),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(m.label,
                                  style: TextStyle(
                                      color: Colors.white, fontSize: 16.5, fontWeight: m == aktif ? FontWeight.w800 : FontWeight.w500)),
                            ),
                          ]),
                        ),
                      ),
                    ),
                  ),
                ),
          ]),
        ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(28, 18, 20, 18),
              child: Row(children: [
                Expanded(child: Text(judul, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800))),
                ...aksi.expand((w) => [const SizedBox(width: 10), w]),
                const SizedBox(width: 10),
                // Tombol keluar selalu terlihat di kanan atas, tidak tertutup menu yang panjang.
                OutlinedButton.icon(onPressed: () => app.keluar(), icon: const Icon(Icons.logout), label: const Text('Keluar')),
              ]),
            ),
            const Divider(height: 2, thickness: 2, color: Warna.garisTipis),
            Expanded(child: child),
          ]),
        ),
      ]),
    );
  }
}

/// Tabel sederhana bergaris (dipakai di banyak halaman).
class TabelSederhana extends StatelessWidget {
  const TabelSederhana({super.key, required this.kolom, required this.baris, this.lebar, this.rataKanan = const {}, this.onTap, this.sorot});

  final List<String> kolom;
  final List<List<Widget>> baris;

  /// Lebar relatif tiap kolom (flex). null = sama rata.
  final List<int>? lebar;
  final Set<int> rataKanan;
  final ValueChanged<int>? onTap;
  final int? sorot;

  @override
  Widget build(BuildContext context) {
    Widget sel(Widget w, int i) => Expanded(
          flex: lebar?[i] ?? 1,
          child: Padding(
            // Jarak antarkolom supaya kolom rata kanan tidak menempel ke kolom berikutnya.
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Align(alignment: rataKanan.contains(i) ? Alignment.centerRight : Alignment.centerLeft, child: w),
          ),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        color: Warna.kepalaTabel,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          for (var i = 0; i < kolom.length; i++)
            sel(Text(kolom[i].toUpperCase(), style: const TextStyle(fontSize: 13.5, letterSpacing: 0.5, fontWeight: FontWeight.w800, color: Warna.teks2)), i),
        ]),
      ),
      for (var r = 0; r < baris.length; r++)
        Material(
          color: r == sorot ? Warna.hijauSorot : (r.isOdd ? Warna.baris2 : Colors.white),
          child: InkWell(
            onTap: onTap == null ? null : () => onTap!(r),
            child: Container(
              constraints: const BoxConstraints(minHeight: 56),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: Warna.garisTipis))),
              child: Row(children: [for (var i = 0; i < baris[r].length; i++) sel(baris[r][i], i)]),
            ),
          ),
        ),
    ]);
  }
}

const gayaSel = TextStyle(fontSize: 17);
const gayaSelTebal = TextStyle(fontSize: 17, fontWeight: FontWeight.w800);
