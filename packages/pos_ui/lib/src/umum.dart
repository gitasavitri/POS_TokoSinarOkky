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
  Widget build(BuildContext context) => DecoratedBox(
        // Bayangan supaya batas antarbagian jelas.
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), boxShadow: Warna.bayangan),
        child: Material(
        // Material (bukan DecoratedBox) supaya efek klik ListTile/InkWell di dalamnya tetap terlihat.
        color: Colors.white,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: Warna.garis, width: 1.5),
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (judul != null)
              Container(
                decoration: BoxDecoration(
                  color: warnaKepala ?? Warna.utamaMuda,
                  border: const Border(bottom: BorderSide(color: Warna.utamaGarisMuda, width: 2)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                child: Row(children: [
                  Expanded(child: Text(judul!, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: Warna.utamaTua))),
                  ?aksi,
                ]),
              ),
            Padding(padding: padding, child: child),
          ],
        ),
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
  const Lencana(this.teks, {super.key, this.latar = Warna.utamaMuda, this.warna = Warna.utamaGelap});

  factory Lencana.status(String teks) {
    switch (teks) {
      case 'Barang baru':
      case 'Tempo':
        return Lencana(teks, latar: Warna.biruMuda, warna: Warna.biru);
      case 'Data diubah':
      case 'Retur':
      case 'Ada retur':
      case 'Menipis':
      case 'Hampir habis':
      case 'Menunggu':
      case 'menunggu':
        return Lencana(teks, latar: Warna.oranyeMuda, warna: Warna.oranyeTua);
      case 'Dibatalkan':
      case 'Batal':
      case 'Rusak':
      case 'Habis':
      case 'Terkunci':
      case 'ditolak':
        return Lencana(teks, latar: Warna.merahMuda, warna: Warna.merah);
      case 'Stok masuk saja':
      case 'Nonaktif':
        return Lencana(teks, latar: Warna.abuIkonMuda, warna: Warna.abuIkon);
      case 'Aktif':
      case 'Aman':
      case 'Lunas':
      case 'disetujui':
      case 'Disetujui':
        return Lencana(teks, latar: Warna.suksesMuda, warna: Warna.suksesTua);
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
  const KartuAngka(
      {super.key, required this.label, required this.nilai, this.catatan, this.latar = Colors.white, this.warna = Warna.teks, this.aksen, this.ikon});
  final String label;
  final String nilai;
  final String? catatan;
  final Color latar;
  final Color warna;

  /// Warna garis kiri + ikon (supaya tiap kartu mudah dibedakan).
  final Color? aksen;
  final IconData? ikon;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), boxShadow: Warna.bayangan),
        child: Container(
          decoration: BoxDecoration(color: latar, borderRadius: BorderRadius.circular(12), border: Border.all(color: Warna.garis, width: 1.5)),
          clipBehavior: Clip.antiAlias,
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (aksen != null) Container(width: 6, color: aksen),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(children: [
                    if (ikon != null) ...[
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(color: (aksen ?? Warna.utama).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                        child: Icon(ikon, color: aksen ?? Warna.utama, size: 26),
                      ),
                      const SizedBox(width: 14),
                    ],
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Warna.teksPudar)),
                        const SizedBox(height: 4),
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
                    ),
                  ]),
                ),
              ),
            ]),
          ),
        ),
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
      JenisPesan.berhasil => (Warna.utamaMuda, Warna.utamaGelap, Icons.check_circle_outline),
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
    this.padat = false,
  });

  final TextEditingController controller;
  final String? label;
  final bool besar;

  /// Tinggi tetap 46 px, huruf 18: sama dengan kotak isian lain di formulir padat.
  final bool padat;
  final bool autofocus;
  final ValueChanged<int>? onChanged;
  final ValueChanged<int>? onSubmitted;
  final FocusNode? focusNode;
  final String? galat;

  /// Garis oranye (harga berubah).
  final bool tegas;

  @override
  Widget build(BuildContext context) {
    final ukuran = padat ? 18.0 : (besar ? 34.0 : 21.0);
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
        prefixStyle: TextStyle(fontSize: padat ? 14 : ukuran * 0.75, fontWeight: FontWeight.w800, color: Warna.teks2),
        hintText: '0',
        isDense: padat ? true : null,
        constraints: padat ? const BoxConstraints.tightFor(height: 46) : null,
        contentPadding: padat ? const EdgeInsets.symmetric(horizontal: 12) : null,
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
  const PengaturJumlah({super.key, required this.nilai, required this.onUbah, this.min = 1, this.ringkas = false});
  final int nilai;
  final ValueChanged<int> onUbah;
  final int min;

  /// Versi kecil untuk baris daftar belanja kasir (tombol 32 px).
  final bool ringkas;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        _Tombol(ikon: Icons.remove, label: 'Kurangi jumlah', ukuran: ringkas ? 32 : 46, onTap: nilai > min ? () => onUbah(nilai - 1) : null),
        SizedBox(
          width: ringkas ? 44 : 56,
          child: Text('$nilai', textAlign: TextAlign.center, style: TextStyle(fontSize: ringkas ? 18 : 22, fontWeight: FontWeight.w800)),
        ),
        _Tombol(ikon: Icons.add, label: 'Tambah jumlah', ukuran: ringkas ? 32 : 46, onTap: () => onUbah(nilai + 1)),
      ]);
}

class _Tombol extends StatelessWidget {
  const _Tombol({required this.ikon, required this.label, required this.onTap, this.ukuran = 46});
  final IconData ikon;
  final String label;
  final VoidCallback? onTap;
  final double ukuran;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: ukuran,
        height: ukuran,
        child: OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size(ukuran, ukuran)),
          child: Icon(ikon, size: ukuran * 0.52, semanticLabel: label),
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
      backgroundColor: galat ? Warna.merah : Warna.utamaTua,
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
