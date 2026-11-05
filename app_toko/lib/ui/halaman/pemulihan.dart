import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pos_core/pos_core.dart';

import '../../layanan/cadangan.dart';
import '../komponen/umum.dart';
import '../tema.dart';

/// Muncul sebagai pengganti aplikasi biasa kalau database tidak bisa dibuka / rusak.
/// Pemulihan butuh PIN SPV/Admin (dicek terhadap akun di file cadangan).
class AplikasiPemulihan extends StatelessWidget {
  const AplikasiPemulihan({super.key, required this.lokasiDatabase, required this.folderCadangan, required this.masalah, required this.onSelesai});
  final String lokasiDatabase;
  final List<String> folderCadangan;
  final String masalah;
  final VoidCallback onSelesai;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'POS Toko · Pemulihan',
        debugShowCheckedModeBanner: false,
        theme: buatTema(),
        home: HalamanPemulihan(lokasiDatabase: lokasiDatabase, folderCadangan: folderCadangan, masalah: masalah, onSelesai: onSelesai),
      );
}

class HalamanPemulihan extends StatefulWidget {
  const HalamanPemulihan({super.key, required this.lokasiDatabase, required this.folderCadangan, required this.masalah, required this.onSelesai});
  final String lokasiDatabase;
  final List<String> folderCadangan;
  final String masalah;
  final VoidCallback onSelesai;
  @override
  State<HalamanPemulihan> createState() => _HalamanPemulihanState();
}

typedef _Cadangan = ({File file, DateTime? waktu, HasilPeriksa cek});

/// Waktu dari nama file pos-A01-20261105-153000.db (WIB) → UTC.
DateTime? waktuCadangan(String nama) {
  final m = RegExp(r'-(\d{4})(\d{2})(\d{2})-(\d{2})(\d{2})(\d{2})\.db$').firstMatch(nama);
  if (m == null) return null;
  final g = [for (var i = 1; i <= 6; i++) int.parse(m.group(i)!)];
  return DateTime.utc(g[0], g[1], g[2], g[3], g[4], g[5]).subtract(const Duration(hours: 7));
}

class _HalamanPemulihanState extends State<HalamanPemulihan> {
  late final List<_Cadangan> _daftar = [
    for (final folder in widget.folderCadangan)
      for (final f in LayananCadangan.daftar(folder).take(20)) (file: f, waktu: waktuCadangan(f.uri.pathSegments.last), cek: LayananCadangan.periksa(f.path)),
  ]..sort((a, b) => (b.waktu ?? DateTime(0)).compareTo(a.waktu ?? DateTime(0)));
  String? _hasil;

  Future<void> _pulihkan(_Cadangan c) async {
    final pin = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Pulihkan dari cadangan ini?', style: TextStyle(fontWeight: FontWeight.w800)),
        content: SizedBox(
          width: 520,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(
              'Data di PC ini akan kembali seperti ${c.waktu == null ? 'saat cadangan dibuat' : '${formatLayar(c.waktu!)} WIB'}. '
              'Transaksi sesudah waktu itu tidak ada di PC ini (kalau sudah terkirim, datanya tetap ada di kantor pusat). '
              'File database lama tidak dihapus, hanya diganti nama.',
              style: const TextStyle(fontSize: 16.5),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: pin,
              autofocus: true,
              obscureText: true,
              maxLength: 6,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(fontSize: 24, letterSpacing: 8),
              decoration: const InputDecoration(labelText: 'PIN SPV atau Admin', counterText: ''),
            ),
          ]),
        ),
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(d, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Pulihkan')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (!await pinPenyetujuCocok(c.file.path, pin.text)) {
      if (mounted) tampilkanPesan(context, 'PIN salah atau bukan PIN SPV/Admin.', galat: true);
      return;
    }
    try {
      final lama = LayananCadangan.pulihkan(cadangan: c.file.path, tujuan: widget.lokasiDatabase);
      setState(() => _hasil = 'Berhasil dipulihkan. File lama disimpan sebagai:\n$lama');
    } catch (e) {
      if (mounted) tampilkanPesan(context, 'Gagal memulihkan: ${pesanGalat(e)}', galat: true);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: SizedBox(
              width: 860,
              child: Panel(
                judul: 'Database perlu dipulihkan',
                warnaKepala: Warna.oranyeMuda,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (_hasil != null) ...[
                    KotakPesan(_hasil!, jenis: JenisPesan.info),
                    const SizedBox(height: 16),
                    Align(alignment: Alignment.centerRight, child: FilledButton(onPressed: widget.onSelesai, child: const Text('Buka aplikasi'))),
                  ] else ...[
                    const Text(
                      'File data di PC ini tidak bisa dibaca dengan benar (biasanya karena hardisk bermasalah). '
                      'Pilih cadangan terbaru yang bertanda "Baik", lalu masukkan PIN SPV/Admin.',
                      style: TextStyle(fontSize: 17),
                    ),
                    const SizedBox(height: 10),
                    SelectableText('Rincian: ${widget.masalah}', style: const TextStyle(fontSize: 14, color: Warna.teksPudar)),
                    const SizedBox(height: 16),
                    if (_daftar.isEmpty)
                      const KotakPesan('Tidak ada file cadangan di Documents\\POS-Cadangan. Hubungi developer, jangan hapus file apa pun.',
                          jenis: JenisPesan.galat)
                    else
                      for (final (i, c) in _daftar.indexed)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(children: [
                            Expanded(
                              child: Text(c.waktu == null ? c.file.uri.pathSegments.last : '${formatLayar(c.waktu!)} WIB',
                                  style: TextStyle(fontSize: 18, fontWeight: i == 0 ? FontWeight.w800 : FontWeight.w600)),
                            ),
                            Lencana.status(c.cek.utuh ? 'Aman' : 'Rusak'),
                            const SizedBox(width: 12),
                            FilledButton(onPressed: c.cek.utuh ? () => _pulihkan(c) : null, child: const Text('Pulihkan')),
                          ]),
                        ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton(onPressed: widget.onSelesai, child: const Text('Coba buka lagi tanpa memulihkan')),
                    ),
                  ],
                ]),
              ),
            ),
          ),
        ),
      );
}
