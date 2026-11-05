import 'package:flutter/material.dart';
import 'package:pos_core/pos_core.dart';

import 'tema.dart';

/// Grafik batang sederhana penjualan per hari.
class GrafikBatang extends StatelessWidget {
  const GrafikBatang({super.key, required this.data});
  final Map<DateTime, int> data;

  @override
  Widget build(BuildContext context) {
    final maks = data.values.fold<int>(0, (a, b) => b > a ? b : a);
    String singkat(int v) => v >= 1000000 ? '${(v / 1000000).toStringAsFixed(1).replaceAll('.', ',')} jt' : formatAngka(v);
    return SizedBox(
      height: 240,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (final e in data.entries)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                if (data.length <= 14) Text(singkat(e.value), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Container(
                  height: maks == 0 ? 2 : 4 + 170 * e.value / maks,
                  decoration: const BoxDecoration(color: Warna.hijau, borderRadius: BorderRadius.vertical(top: Radius.circular(6))),
                ),
                const SizedBox(height: 6),
                Text('${keWib(e.key).day}', style: const TextStyle(fontSize: 13, color: Warna.teks2, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
      ]),
    );
  }
}
