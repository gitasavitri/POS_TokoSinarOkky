import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pos_core/pos_core.dart';

import 'tema.dart';

/// Kotak putih bergaris dengan judul opsional (gaya "Panel" di desain).
class Panel extends StatelessWidget {
  const Panel({super.key, this.judul, this.aksi, required this.child, this.padding = const EdgeInsets.all(18), this.warnaKepala});

  final String? judul;
  final Widget? aksi;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? warnaKepala;

  @override
  Widget build(BuildContext context) => Material(
        // Material (bukan DecoratedBox) supaya efek klik ListTile/InkWell di dalamnya tetap terlihat.
        color: Colors.white,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: Warna.garis, width: 2),
          borderRadius: BorderRadius.circular(10),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (judul != null)
              Container(
                color: warnaKepala ?? Warna.kepalaTabel,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                child: Row(children: [
                  Expanded(child: Text(judul!, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800))),
                  ?aksi,
                ]),
              ),
            Padding(padding: padding, child: child),
          ],
        ),
      );
}

/// Label kecil huruf besar di atas isian (gaya desain).
class LabelKecil extends StatelessWidget {
  const LabelKecil(this.teks, {super.key, this.warna = Warna.teks2});
  final String teks;
  final Color warna;
  @override
  Widget build(BuildContext context) => Text(teks.toUpperCase(),
      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: warna));
}

/// Lencana status kecil.
class Lencana extends StatelessWidget {
  const Lencana(this.teks, {super.key, this.latar = Warna.hijauMuda, this.warna = Warna.hijauGelap});

  factory Lencana.status(String teks) {
    switch (teks) {
      case 'Barang baru':
      case 'Tempo':
        return Lencana(teks, latar: Warna.biruMuda, warna: Warna.biru);
      case 'Data diubah':
      case 'Retur':
      case 'Ada retur':
      case 'Menunggu':
      case 'menunggu':
        return Lencana(teks, latar: Warna.oranyeMuda, warna: Warna.oranye);
      case 'Dibatalkan':
      case 'Batal':
      case 'Terkunci':
      case 'ditolak':
        return Lencana(teks, latar: Warna.merahMuda, warna: Warna.merah);
      case 'Stok masuk saja':
      case 'Nonaktif':
        return Lencana(teks, latar: const Color(0xFFE4E9E6), warna: const Color(0xFF2F3A36));
      default:
        return Lencana(teks);
    }
  }

  final String teks;
  final Color latar;
  final Color warna;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: latar, borderRadius: BorderRadius.circular(6)),
        child: Text(teks, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: warna)),
      );
}

/// Kotak angka ringkasan (laporan/dashboard).
class KartuAngka extends StatelessWidget {
  const KartuAngka({super.key, required this.label, required this.nilai, this.catatan, this.latar = Colors.white, this.warna = Warna.teks});
  final String label;
  final String nilai;
  final String? catatan;
  final Color latar;
  final Color warna;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(color: latar, borderRadius: BorderRadius.circular(12), border: Border.all(color: Warna.garisTipis, width: 1.5)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Warna.teks2)),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(nilai, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: warna)),
          ),
          if (catatan != null) ...[
            const SizedBox(height: 4),
            Text(catatan!, style: const TextStyle(fontSize: 14, color: Warna.teksPudar, fontWeight: FontWeight.w600)),
          ],
        ]),
      );
}

/// Kotak info pesan (oranye = perhatian, merah = galat, hijau = berhasil).
class KotakPesan extends StatelessWidget {
  const KotakPesan(this.teks, {super.key, this.jenis = JenisPesan.perhatian, this.ikon});
  final String teks;
  final JenisPesan jenis;
  final IconData? ikon;

  @override
  Widget build(BuildContext context) {
    final (latar, warna, ik) = switch (jenis) {
      JenisPesan.perhatian => (Warna.oranyeMuda, Warna.oranyeTua, Icons.lock_outline),
      JenisPesan.galat => (Warna.merahMuda, Warna.merahTua, Icons.error_outline),
      JenisPesan.berhasil => (Warna.hijauMuda, Warna.hijauGelap, Icons.check_circle_outline),
      JenisPesan.info => (Warna.abuMuda, Warna.teks2, Icons.info_outline),
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: latar, borderRadius: BorderRadius.circular(10)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(ikon ?? ik, color: warna, size: 24),
        const SizedBox(width: 12),
        Expanded(child: Text(teks, style: TextStyle(fontSize: 16.5, height: 1.45, color: warna, fontWeight: FontWeight.w600))),
      ]),
    );
  }
}

enum JenisPesan { perhatian, galat, berhasil, info }

/// Format angka ribuan saat mengetik: "1250000" → "1.250.000".
class FormatRibuan extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digit = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digit.isEmpty) return const TextEditingValue();
    final n = bacaAngka(digit);
    final teks = formatAngka(n);
    return TextEditingValue(text: teks, selection: TextSelection.collapsed(offset: teks.length));
  }
}

/// Isian rupiah besar dengan awalan "Rp".
class InputRupiah extends StatelessWidget {
  const InputRupiah({
    super.key,
    required this.controller,
    this.label,
    this.besar = false,
    this.autofocus = false,
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
    this.galat,
    this.tegas = false,
  });

  final TextEditingController controller;
  final String? label;
  final bool besar;
  final bool autofocus;
  final ValueChanged<int>? onChanged;
  final ValueChanged<int>? onSubmitted;
  final FocusNode? focusNode;
  final String? galat;

  /// Garis oranye (harga berubah).
  final bool tegas;

  @override
  Widget build(BuildContext context) {
    final ukuran = besar ? 34.0 : 21.0;
    final garis = tegas
        ? OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Warna.oranyeTegas, width: 3))
        : null;
    return TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      keyboardType: TextInputType.number,
      inputFormatters: [FormatRibuan()],
      textAlign: TextAlign.right,
      style: TextStyle(fontSize: ukuran, fontWeight: FontWeight.w800),
      decoration: InputDecoration(
        labelText: label,
        errorText: galat,
        prefixText: 'Rp  ',
        prefixStyle: TextStyle(fontSize: ukuran * 0.75, fontWeight: FontWeight.w800, color: Warna.teks2),
        hintText: '0',
        fillColor: tegas ? const Color(0xFFFFF8EC) : Colors.white,
        enabledBorder: garis,
        focusedBorder: garis,
      ),
      onChanged: onChanged == null ? null : (s) => onChanged!(bacaAngka(s)),
      onSubmitted: onSubmitted == null ? null : (s) => onSubmitted!(bacaAngka(s)),
    );
  }
}

/// Tombol minus/angka/plus untuk jumlah barang.
class PengaturJumlah extends StatelessWidget {
  const PengaturJumlah({super.key, required this.nilai, required this.onUbah, this.min = 1});
  final int nilai;
  final ValueChanged<int> onUbah;
  final int min;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        _Tombol(ikon: Icons.remove, label: 'Kurangi jumlah', onTap: nilai > min ? () => onUbah(nilai - 1) : null),
        SizedBox(
          width: 56,
          child: Text('$nilai', textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        ),
        _Tombol(ikon: Icons.add, label: 'Tambah jumlah', onTap: () => onUbah(nilai + 1)),
      ]);
}

class _Tombol extends StatelessWidget {
  const _Tombol({required this.ikon, required this.label, required this.onTap});
  final IconData ikon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 46,
        height: 46,
        child: OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(46, 46)),
          child: Icon(ikon, size: 24, semanticLabel: label),
        ),
      );
}

void tampilkanPesan(BuildContext context, String teks, {bool galat = false}) {
  final m = ScaffoldMessenger.maybeOf(context);
  if (m == null) return;
  m
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(teks),
      backgroundColor: galat ? Warna.merah : Warna.hijauTua,
      duration: Duration(seconds: galat ? 6 : 3),
      showCloseIcon: true,
    ));
}

Future<bool> konfirmasi(BuildContext context, {required String judul, required String isi, String ya = 'Ya', String batal = 'Batal', bool bahaya = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(judul, style: const TextStyle(fontWeight: FontWeight.w800)),
      content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480), child: Text(isi, style: const TextStyle(fontSize: 17, height: 1.5))),
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(c, false), child: Text(batal)),
        FilledButton(
          style: bahaya ? FilledButton.styleFrom(backgroundColor: Warna.merah) : null,
          onPressed: () => Navigator.pop(c, true),
          child: Text(ya),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// Pesan galat dari exception, tanpa awalan teknis.
String pesanGalat(Object e) {
  final s = e.toString();
  for (final awal in ['Invalid argument(s): ', 'Bad state: ', 'Exception: ', 'ArgumentError: ', 'StateError: ']) {
    if (s.startsWith(awal)) return s.substring(awal.length);
  }
  return s;
}
