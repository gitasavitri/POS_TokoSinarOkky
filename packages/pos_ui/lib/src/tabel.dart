import 'package:flutter/material.dart';

import 'tema.dart';

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
