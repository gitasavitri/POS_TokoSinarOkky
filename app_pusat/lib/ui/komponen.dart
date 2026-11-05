import 'package:flutter/material.dart';
import 'package:pos_core/pos_core.dart';
import 'package:pos_ui/pos_ui.dart';

import '../data/model.dart';
import '../layanan/sesi.dart';

/// Memuat data dari server lalu menampilkannya; menampilkan galat + tombol "Coba lagi" kalau gagal.
/// Ganti [key] untuk memuat ulang (mis. saat filter berubah).
class Muat<T> extends StatefulWidget {
  const Muat({super.key, required this.ambil, required this.isi});
  final Future<T> Function(Sesi sesi) ambil;
  final Widget Function(BuildContext context, T data, VoidCallback muatUlang) isi;

  @override
  State<Muat<T>> createState() => _MuatState<T>();
}

class _MuatState<T> extends State<Muat<T>> {
  late Future<T> _f;

  @override
  void initState() {
    super.initState();
    _f = widget.ambil(context.sesi);
  }

  void _ulang() => setState(() => _f = widget.ambil(context.sesi));

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
        future: _f,
        builder: (context, s) {
          if (s.hasError) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                KotakPesan('Gagal memuat: ${pesanGalat(s.error!)}', jenis: JenisPesan.galat),
                const SizedBox(height: 12),
                OutlinedButton.icon(onPressed: _ulang, icon: const Icon(Icons.refresh), label: const Text('Coba lagi')),
              ]),
            );
          }
          if (!s.hasData) return const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()));
          return widget.isi(context, s.data as T, _ulang);
        },
      );
}

/// Pilihan toko: null = semua toko.
class PilihCabang extends StatelessWidget {
  const PilihCabang({super.key, required this.cabang, required this.nilai, required this.onUbah, this.bolehSemua = true});
  final List<CabangPusat> cabang;
  final String? nilai;
  final ValueChanged<String?> onUbah;
  final bool bolehSemua;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 260,
        child: DropdownButtonFormField<String?>(
          initialValue: nilai,
          decoration: const InputDecoration(labelText: 'Toko', isDense: true),
          items: [
            if (bolehSemua) const DropdownMenuItem(value: null, child: Text('Semua toko')),
            for (final c in cabang) DropdownMenuItem(value: c.id, child: Text(c.label, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: onUbah,
        ),
      );
}

/// Chip pilihan periode laporan.
class PilihPeriode extends StatelessWidget {
  const PilihPeriode({super.key, required this.nilai, required this.onUbah});
  final Periode nilai;
  final ValueChanged<Periode> onUbah;

  @override
  Widget build(BuildContext context) => Wrap(spacing: 8, runSpacing: 8, children: [
        for (final p in Periode.values)
          ChoiceChip(
            label: Text(p.label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            selected: p == nilai,
            onSelected: (_) => onUbah(p),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          ),
      ]);
}

/// "5 menit lalu", "3 jam lalu", "2 hari lalu" + warna status sinkron toko.
(String, Color) statusSinkron(DateTime? t, DateTime sekarang) {
  if (t == null) return ('Belum pernah', Warna.merah);
  final d = sekarang.difference(t);
  if (d.inMinutes < 1) return ('Baru saja', Warna.hijau);
  if (d.inMinutes < 60) return ('${d.inMinutes} menit lalu', d.inMinutes <= 10 ? Warna.hijau : Warna.oranye);
  if (d.inHours < 24) return ('${d.inHours} jam lalu', Warna.oranye);
  return ('${d.inDays} hari lalu', Warna.merah);
}

String waktuLengkap(DateTime t) => '${formatTanggal(t)} ${formatJam(t)}';
