import 'package:flutter/material.dart';
import 'package:pos_core/pos_core.dart';

import '../../data/repo/harga_repo.dart';
import '../../layanan/aplikasi.dart';
import '../komponen/umum.dart';
import '../tema.dart';

/// SPV/Admin menyetujui atau menolak usulan harga dari kasir. Harga lama tetap berlaku sampai disetujui.
class IsiUsulanHarga extends StatefulWidget {
  const IsiUsulanHarga({super.key});
  @override
  State<IsiUsulanHarga> createState() => _IsiUsulanHargaState();
}

class _IsiUsulanHargaState extends State<IsiUsulanHarga> {
  late List<UsulanHargaBaris> _daftar;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  void _muat() => setState(() => _daftar = context.app.harga.daftarUsulan(context.app.cabang.id));

  String _selisih(UsulanHargaBaris u) {
    if (u.hargaLama == null) return 'Harga pertama';
    final pm = u.turunPerMilNilai;
    if (pm == 0) return 'Tetap';
    return pm > 0 ? 'Turun ${formatPerMil(pm)}' : 'Naik ${formatPerMil(-pm)}';
  }

  /// Peringatan untuk pemutus: harga turun banyak atau tidak di atas HPP.
  String? _peringatan(UsulanHargaBaris u) {
    final hpp = u.hpp;
    if (hpp != null && hpp > 0 && u.hargaBaru <= hpp) return 'Harga usulan di bawah atau sama dengan HPP (${formatRupiah(hpp)}).';
    if (u.hargaLama != null && u.turunPerMilNilai > 100) return 'Harga turun lebih dari 10%.';
    return null;
  }

  Future<void> _putuskan(UsulanHargaBaris u, bool setuju) async {
    final ok = await konfirmasi(
      context,
      judul: setuju ? 'Setujui harga baru?' : 'Tolak usulan harga?',
      isi: setuju
          ? '${u.namaBarang}: ${u.hargaLama == null ? '' : '${formatRupiah(u.hargaLama!)} → '}${formatRupiah(u.hargaBaru)}. Langsung berlaku di kasir.'
          : 'Usulan ${u.namaBarang} dari ${u.dimintaOleh} ditolak. Harga tidak berubah.',
      ya: setuju ? 'Setujui' : 'Tolak',
      bahaya: !setuju,
    );
    if (!ok || !mounted) return;
    try {
      context.app.harga.putuskanUsulan(usulanId: u.id, setuju: setuju, oleh: context.app.penggunaAktif!);
      tampilkanPesan(context, setuju ? 'Harga baru disetujui dan berlaku di kasir.' : 'Usulan ditolak. Harga tidak berubah.');
    } catch (e) {
      tampilkanPesan(context, pesanGalat(e), galat: true);
    }
    if (mounted) _muat();
  }

  String _grosirTeks(UsulanHargaBaris u) =>
      u.grosir.isEmpty ? '-' : u.grosir.map((g) => '≥${g.minQty}: ${formatRupiah(g.harga)}').join('\n');

  @override
  Widget build(BuildContext context) {
    final menunggu = _daftar.where((u) => u.status == statusUsulanMenunggu).toList();
    final selesai = _daftar.where((u) => u.status != statusUsulanMenunggu).toList();
    return ListView(padding: const EdgeInsets.all(24), children: [
      const KotakPesan(
        'Harga yang diubah kasir tidak langsung berlaku. Harga lama tetap dipakai di kasir sampai usulan disetujui.',
        jenis: JenisPesan.info,
      ),
      const SizedBox(height: 16),
      Panel(
        judul: 'Menunggu persetujuan (${menunggu.length})',
        warnaKepala: Warna.oranyeMuda,
        padding: EdgeInsets.zero,
        child: menunggu.isEmpty
            ? const Padding(padding: EdgeInsets.all(20), child: Text('Tidak ada usulan.', style: TextStyle(fontSize: 17, color: Warna.teksPudar)))
            : TabelSederhana(
                kolom: const ['Barang', 'Harga', 'Grosir', 'HPP', 'Alasan', 'Diusulkan', ''],
                lebar: const [4, 4, 3, 2, 3, 3, 4],
                baris: [
                  for (final u in menunggu)
                    [
                      Text(u.namaBarang, style: gayaSelTebal),
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${u.hargaLama == null ? '' : '${formatRupiah(u.hargaLama!)} → '}${formatRupiah(u.hargaBaru)}', style: gayaSelTebal),
                        Text(_selisih(u), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: u.turunPerMilNilai > 0 ? Warna.merah : Warna.teksPudar)),
                        if (_peringatan(u) != null) Text(_peringatan(u)!, style: const TextStyle(fontSize: 13, color: Warna.merah)),
                      ]),
                      Text(_grosirTeks(u), style: gayaSel),
                      Text(u.hpp == null ? '-' : formatRupiah(u.hpp!), style: gayaSel),
                      Text(u.alasan, style: gayaSel),
                      Text('${u.dimintaOleh}\n${formatJam(u.dibuat)} ${formatTanggal(u.dibuat)}', style: const TextStyle(fontSize: 15)),
                      Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 6, children: [
                        OutlinedButton(
                          onPressed: () => _putuskan(u, false),
                          style: OutlinedButton.styleFrom(foregroundColor: Warna.merah, minimumSize: const Size(48, 46)),
                          child: const Text('Tolak'),
                        ),
                        FilledButton(onPressed: () => _putuskan(u, true), style: FilledButton.styleFrom(minimumSize: const Size(48, 46)), child: const Text('Setujui')),
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
                kolom: const ['Barang', 'Harga', 'Alasan', 'Diputuskan', 'Status'],
                lebar: const [4, 4, 3, 3, 2],
                baris: [
                  for (final u in selesai)
                    [
                      Text(u.namaBarang, style: gayaSelTebal),
                      Text('${u.hargaLama == null ? '' : '${formatRupiah(u.hargaLama!)} → '}${formatRupiah(u.hargaBaru)}', style: gayaSel),
                      Text(u.alasan, style: gayaSel),
                      Text(u.diputuskanOleh ?? 'Admin pusat', style: gayaSel),
                      Lencana.status(u.status),
                    ],
                ],
              ),
      ),
    ]);
  }
}
