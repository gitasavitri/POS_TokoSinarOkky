import 'package:flutter/material.dart';
import 'package:pos_core/pos_core.dart';

import '../../data/repo/barang_masuk_repo.dart';
import '../../layanan/aplikasi.dart';
import '../komponen/umum.dart';
import '../tema.dart';

/// SPV/Admin menyetujui atau menolak koreksi barang masuk.
class IsiKoreksi extends StatefulWidget {
  const IsiKoreksi({super.key});
  @override
  State<IsiKoreksi> createState() => _IsiKoreksiState();
}

class _IsiKoreksiState extends State<IsiKoreksi> {
  late List<Koreksi> _daftar;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  void _muat() => setState(() => _daftar = context.app.barangMasuk.daftarKoreksi(context.app.cabang.id));

  Future<void> _putuskan(Koreksi k, bool setuju) async {
    final ok = await konfirmasi(
      context,
      judul: setuju ? 'Setujui koreksi?' : 'Tolak koreksi?',
      isi: setuju
          ? '${k.namaBarang}: jumlah dari faktur ${k.noFaktur} diubah menjadi ${k.jumlahBaru}. Stok ikut disesuaikan.'
          : 'Permintaan koreksi ${k.namaBarang} dari ${k.dimintaOleh} ditolak. Stok tidak berubah.',
      ya: setuju ? 'Setujui' : 'Tolak',
      bahaya: !setuju,
    );
    if (!ok || !mounted) return;
    try {
      context.app.barangMasuk.putuskanKoreksi(koreksiId: k.id, setuju: setuju, oleh: context.app.penggunaAktif!);
      tampilkanPesan(context, setuju ? 'Koreksi disetujui. Stok sudah disesuaikan.' : 'Koreksi ditolak.');
      _muat();
    } catch (e) {
      tampilkanPesan(context, pesanGalat(e), galat: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final menunggu = _daftar.where((k) => k.status == 'menunggu').toList();
    final selesai = _daftar.where((k) => k.status != 'menunggu').toList();
    return ListView(padding: const EdgeInsets.all(24), children: [
      const KotakPesan(
        'Koreksi tidak menghapus data lama. Sistem menyimpan jumlah awal, jumlah baru, alasan, dan siapa yang menyetujui.',
        jenis: JenisPesan.info,
      ),
      const SizedBox(height: 16),
      Panel(
        judul: 'Menunggu persetujuan (${menunggu.length})',
        warnaKepala: Warna.oranyeMuda,
        padding: EdgeInsets.zero,
        child: menunggu.isEmpty
            ? const Padding(padding: EdgeInsets.all(20), child: Text('Tidak ada permintaan.', style: TextStyle(fontSize: 17, color: Warna.teksPudar)))
            : TabelSederhana(
                kolom: const ['Barang', 'Faktur', 'Jumlah', 'Alasan', 'Diminta', ''],
                lebar: const [4, 3, 3, 4, 3, 4],
                baris: [
                  for (final k in menunggu)
                    [
                      Text(k.namaBarang, style: gayaSelTebal),
                      Text(k.noFaktur, style: gayaSel),
                      Text('${k.jumlahLama} → ${k.jumlahBaru}', style: gayaSelTebal),
                      Text(k.alasan, style: gayaSel),
                      Text('${k.dimintaOleh}\n${formatJam(k.waktu)} ${formatTanggal(k.waktu)}', style: const TextStyle(fontSize: 15)),
                      Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 6, children: [
                        OutlinedButton(
                          onPressed: () => _putuskan(k, false),
                          style: OutlinedButton.styleFrom(foregroundColor: Warna.merah, minimumSize: const Size(48, 46)),
                          child: const Text('Tolak'),
                        ),
                        FilledButton(onPressed: () => _putuskan(k, true), style: FilledButton.styleFrom(minimumSize: const Size(48, 46)), child: const Text('Setujui')),
                      ]),
                    ],
                ],
              ),
      ),
      const SizedBox(height: 20),
      Panel(
        judul: 'Sudah diputuskan',
        padding: EdgeInsets.zero,
        child: selesai.isEmpty
            ? const Padding(padding: EdgeInsets.all(20), child: Text('Belum ada.', style: TextStyle(fontSize: 17, color: Warna.teksPudar)))
            : TabelSederhana(
                kolom: const ['Barang', 'Faktur', 'Jumlah', 'Alasan', 'Status'],
                lebar: const [4, 3, 3, 5, 2],
                baris: [
                  for (final k in selesai)
                    [
                      Text(k.namaBarang, style: gayaSelTebal),
                      Text(k.noFaktur, style: gayaSel),
                      Text('${k.jumlahLama} → ${k.jumlahBaru}', style: gayaSel),
                      Text(k.alasan, style: gayaSel),
                      Lencana.status(k.status),
                    ],
                ],
              ),
      ),
    ]);
  }
}
