import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pos_core/pos_core.dart';
import 'package:pos_ui/pos_ui.dart';

import '../../data/model.dart';
import '../../layanan/sesi.dart';
import '../komponen.dart';

/// Daftar toko, PC kasir yang terdaftar, dan kode pendaftaran untuk PC baru.
class IsiToko extends StatefulWidget {
  const IsiToko({super.key});
  @override
  State<IsiToko> createState() => _IsiTokoState();
}

class _IsiTokoState extends State<IsiToko> {
  int _versi = 0;

  Future<void> _buatKode() async {
    try {
      final (kode, kedaluwarsa) = await context.sesi.pakai((api) => api.buatKodePendaftaran());
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('Kode pendaftaran PC toko', style: TextStyle(fontWeight: FontWeight.w800)),
          content: SizedBox(
            width: 520,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                padding: const EdgeInsets.symmetric(vertical: 22),
                decoration: BoxDecoration(color: Warna.utamaMuda, borderRadius: BorderRadius.circular(12)),
                child: SelectableText(kode, textAlign: TextAlign.center, style: const TextStyle(fontFamily: fontMono, fontSize: 40, fontWeight: FontWeight.w700, letterSpacing: 4)),
              ),
              const SizedBox(height: 14),
              Text('Berlaku sampai ${formatLayar(kedaluwarsa)} WIB, hanya untuk 1 PC.', style: const TextStyle(fontSize: 17)),
              const SizedBox(height: 10),
              const Text(
                'Di PC toko: masuk sebagai Admin → Pengaturan & printer → Kirim data ke kantor pusat → isi alamat server dan kode ini.',
                style: TextStyle(fontSize: 16, color: Warna.teksPudar),
              ),
            ]),
          ),
          actions: [
            OutlinedButton.icon(
              onPressed: () => Clipboard.setData(ClipboardData(text: kode)),
              icon: const Icon(Icons.copy),
              label: const Text('Salin'),
            ),
            FilledButton(onPressed: () => Navigator.pop(d), child: const Text('Selesai')),
          ],
        ),
      );
    } on GalatServer catch (e) {
      if (mounted) tampilkanPesan(context, e.pesan, galat: true);
    }
  }

  Future<void> _cabut(PerangkatPusat p) async {
    final ok = await konfirmasi(
      context,
      judul: 'Cabut ${p.nama}?',
      isi: 'PC ini tidak bisa mengirim/menerima data lagi (data yang sudah terkirim tetap ada). '
          'Lakukan kalau PC hilang, dijual, atau diganti. Data yang belum terkirim dari PC itu akan tertahan.',
      ya: 'Cabut',
      bahaya: true,
    );
    if (!ok || !mounted) return;
    try {
      await context.sesi.pakai((api) => api.cabutPerangkat(p.id));
      setState(() => _versi++);
    } on GalatServer catch (e) {
      if (mounted) tampilkanPesan(context, e.pesan, galat: true);
    }
  }

  @override
  Widget build(BuildContext context) => Muat<(List<CabangPusat>, List<PerangkatPusat>)>(
        key: ValueKey(_versi),
        ambil: (s) => s.pakai((api) async => (await api.cabang(), await api.perangkat())),
        isi: (context, d, ulang) {
          final (cabang, perangkat) = d;
          final sekarang = DateTime.now();
          return ListView(padding: const EdgeInsets.all(24), children: [
            Row(children: [
              const Expanded(
                child: Text('Toko baru muncul di sini setelah PC kasirnya didaftarkan dengan kode pendaftaran.',
                    style: TextStyle(fontSize: 17, color: Warna.teksPudar)),
              ),
              FilledButton.icon(onPressed: _buatKode, icon: const Icon(Icons.key), label: const Text('Buat kode pendaftaran')),
            ]),
            const SizedBox(height: 16),
            Panel(
              judul: 'Toko (${cabang.length})',
              padding: EdgeInsets.zero,
              child: cabang.isEmpty
                  ? const Padding(padding: EdgeInsets.all(20), child: Text('Belum ada toko.', style: TextStyle(fontSize: 17, color: Warna.teksPudar)))
                  : TabelSederhana(
                      kolom: const ['Kode', 'Nama', 'Alamat', 'PC aktif', 'Data terakhir'],
                      lebar: const [1, 3, 5, 2, 3],
                      rataKanan: const {3},
                      baris: [
                        for (final c in cabang)
                          () {
                            final (teks, warna) = statusSinkron(c.terakhirSinkron, sekarang);
                            return [
                              Text(c.kode, style: gayaSelTebal),
                              Text(c.nama, style: gayaSel),
                              Text(c.alamat, style: const TextStyle(fontSize: 15.5)),
                              Text('${c.jumlahPerangkat}', style: gayaSel),
                              Text(teks, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: warna)),
                            ];
                          }(),
                      ],
                    ),
            ),
            const SizedBox(height: 20),
            Panel(
              judul: 'PC kasir terdaftar',
              padding: EdgeInsets.zero,
              child: perangkat.isEmpty
                  ? const Padding(padding: EdgeInsets.all(20), child: Text('Belum ada.', style: TextStyle(fontSize: 17, color: Warna.teksPudar)))
                  : TabelSederhana(
                      kolom: const ['PC', 'Toko', 'Terdaftar', 'Data terakhir', 'Status', ''],
                      lebar: const [3, 3, 3, 3, 2, 2],
                      baris: [
                        for (final p in perangkat)
                          [
                            Text(p.nama, style: gayaSelTebal),
                            Text(p.cabang, style: gayaSel),
                            Text(formatTanggal(p.terdaftar), style: gayaSel),
                            Text(statusSinkron(p.terakhirSinkron, sekarang).$1, style: gayaSel),
                            Lencana.status(p.aktif ? 'Aktif' : 'Nonaktif'),
                            p.aktif
                                ? OutlinedButton(
                                    onPressed: () => _cabut(p),
                                    style: OutlinedButton.styleFrom(foregroundColor: Warna.merah, minimumSize: const Size(48, 44)),
                                    child: const Text('Cabut'),
                                  )
                                : const SizedBox(),
                          ],
                      ],
                    ),
            ),
          ]);
        },
      );
}
