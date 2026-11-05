import 'package:flutter/material.dart';

import 'tema.dart';

/// Kepala layar biru bergradasi (menu ikon & halaman SPV/Admin).
class BarKepala extends StatelessWidget {
  const BarKepala({super.key, required this.judul, this.sub, this.onMenu, required this.nama, required this.keterangan, required this.onKeluar, this.aksi = const []});

  final String judul;
  final String? sub;

  /// Ada = tampilkan tombol "← Menu" (halaman di dalam menu).
  final VoidCallback? onMenu;
  final String nama;
  final String keterangan;
  final VoidCallback onKeluar;
  final List<Widget> aksi;

  @override
  Widget build(BuildContext context) => Container(
        height: 76,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: const BoxDecoration(
          gradient: Warna.gradasiKepala,
          boxShadow: [BoxShadow(color: Color(0x590D47A1), blurRadius: 10, offset: Offset(0, 3))],
        ),
        child: Row(children: [
          if (onMenu != null) ...[
            OutlinedButton.icon(
              onPressed: onMenu,
              style: OutlinedButton.styleFrom(
                backgroundColor: Warna.utamaPanel,
                foregroundColor: Colors.white,
                side: const BorderSide(color: Warna.utamaGaris, width: 1.5),
                minimumSize: const Size(48, 46),
              ),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Menu'),
            ),
            const SizedBox(width: 16),
          ],
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(judul,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white, fontSize: onMenu == null ? 22 : 25, fontWeight: FontWeight.w800)),
              if (sub != null) Text(sub!, style: const TextStyle(color: Warna.utamaTeksTerang, fontSize: 14.5)),
            ]),
          ),
          ...aksi.expand((w) => [w, const SizedBox(width: 10)]),
          Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(nama, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
            Text(keterangan, style: const TextStyle(color: Warna.utamaTeksTerang, fontSize: 14.5)),
          ]),
          const SizedBox(width: 14),
          FilledButton.icon(
            onPressed: onKeluar,
            style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Warna.utamaTua, minimumSize: const Size(48, 46)),
            icon: const Icon(Icons.logout),
            label: const Text('Keluar'),
          ),
        ]),
      );
}

/// Satu ikon menu (seperti ikon folder): kotak ikon berwarna + nama di bawahnya.
class UbinMenu extends StatelessWidget {
  const UbinMenu({super.key, required this.ikon, required this.label, required this.warna, required this.latar, this.lencana, this.utama = false, required this.onTap});

  final IconData ikon;
  final String label;
  final Color warna;
  final Color latar;

  /// Angka/teks kecil di pojok, mis. "1" atau "3 menipis".
  final String? lencana;

  /// Menu yang paling sering dipakai diberi garis biru.
  final bool utama;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 146,
        height: 140,
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned.fill(
            child: Material(
              color: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: utama ? Warna.utama : Warna.garisTipis, width: utama ? 2 : 1.5),
              ),
              shadowColor: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: onTap,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: utama ? const [BoxShadow(color: Color(0x261E88E5), blurRadius: 0, spreadRadius: 4)] : null,
                  ),
                  padding: const EdgeInsets.only(top: 14),
                  child: Column(children: [
                    Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(color: latar, borderRadius: BorderRadius.circular(18)),
                      child: Icon(ikon, color: warna, size: 40),
                    ),
                    const SizedBox(height: 9),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Text(label,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, height: 1.2)),
                    ),
                  ]),
                ),
              ),
            ),
          ),
          if (lencana != null)
            Positioned(
              top: 6,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Warna.lencanaOranye,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 3, offset: Offset(0, 1))],
                ),
                child: Text(lencana!, style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w800)),
              ),
            ),
        ]),
      );
}

/// Kelompok ikon menu dengan judul berwarna, mis. PENJUALAN / BARANG & HARGA.
class GrupMenu extends StatelessWidget {
  const GrupMenu({super.key, required this.judul, required this.warna, required this.latar, required this.ubin});
  final String judul;
  final Color warna;
  final Color latar;
  final List<Widget> ubin;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        decoration: BoxDecoration(
          color: latar,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: warna.withValues(alpha: 0.35), width: 1.5),
          boxShadow: Warna.bayangan,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: warna, borderRadius: BorderRadius.circular(3))),
              const SizedBox(width: 8),
              Text(judul, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: warna)),
            ]),
          ),
          Wrap(spacing: 10, runSpacing: 10, children: ubin),
        ]),
      );
}
