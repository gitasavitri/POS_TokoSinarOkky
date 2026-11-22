import 'package:flutter/material.dart';
import 'package:pos_core/pos_core.dart';
import 'package:pos_ui/pos_ui.dart';

import '../../data/model.dart';
import '../../layanan/sesi.dart';
import '../komponen.dart';

/// Admin pusat menyetujui atau menolak usulan harga dari kasir. Harga lama tetap berlaku di toko sampai disetujui.
/// Yang memutuskan lebih dulu (di toko atau di sini) yang berlaku.
class IsiPersetujuan extends StatefulWidget {
  const IsiPersetujuan({super.key});
  @override
  State<IsiPersetujuan> createState() => _IsiPersetujuanState();
}

class _IsiPersetujuanState extends State<IsiPersetujuan> {
  String _status = statusUsulanMenunggu;
  String? _dipilihId;
  int _versi = 0;
  bool _sibuk = false;

  static const _tab = [
    (statusUsulanMenunggu, 'Menunggu'),
    (statusUsulanDisetujui, 'Disetujui'),
    (statusUsulanDitolak, 'Ditolak'),
  ];

  String _selisih(UsulanHargaPusat u) {
    if (u.hargaLama == null) return 'Harga pertama';
    final pm = u.turunPerMilNilai;
    if (pm == 0) return 'Harga tetap';
    return pm > 0 ? 'Turun ${formatPerMil(pm)}' : 'Naik ${formatPerMil(-pm)}';
  }

  Future<void> _putuskan(UsulanHargaPusat u, bool setuju) async {
    final harga = '${u.hargaLama == null ? '' : '${formatRupiah(u.hargaLama!)} → '}${formatRupiah(u.hargaBaru)}';
    final ok = await konfirmasi(
      context,
      judul: setuju ? 'Setujui harga baru?' : 'Tolak usulan harga?',
      isi: setuju
          ? '${u.barangNama} di ${u.kodeCabang}: $harga. Berlaku di kasir toko itu begitu PC toko tersambung (±1 menit).'
          : 'Usulan ${u.barangNama} dari ${u.peminta} ditolak. Harga di toko tidak berubah.',
      ya: setuju ? 'Setujui' : 'Tolak',
      bahaya: !setuju,
    );
    if (!ok || !mounted) return;
    setState(() => _sibuk = true);
    try {
      await context.sesi.pakai((api) => api.putuskanUsulanHarga(u.id, setuju: setuju));
      if (mounted) tampilkanPesan(context, setuju ? 'Harga disetujui. Akan sampai ke PC toko otomatis.' : 'Usulan ditolak.');
    } on GalatServer catch (e) {
      // Mis. "sudah disetujui (di toko)": daftar dimuat ulang supaya terlihat keputusan yang menang.
      if (mounted) tampilkanPesan(context, e.pesan, galat: true);
    } finally {
      if (mounted) {
        setState(() {
          _sibuk = false;
          _versi++;
          _dipilihId = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Muat<List<UsulanHargaPusat>>(
        key: ValueKey('$_status $_versi'),
        ambil: (s) => s.pakai((api) => api.usulanHarga(status: _status)),
        isi: (context, daftar, ulang) {
          final dipilih = daftar.where((u) => u.id == _dipilihId).firstOrNull ?? (daftar.isEmpty ? null : daftar.first);
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const KotakPesan(
                'Harga yang diubah kasir tidak langsung berlaku. Harga lama tetap dipakai di kasir sampai SPV/Admin di toko atau Admin di sini menyetujui.',
                jenis: JenisPesan.info,
              ),
              const SizedBox(height: 14),
              Expanded(
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(
                    width: 430,
                    child: DecoratedBox(
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), boxShadow: Warna.bayangan),
                      child: Material(
                        color: Colors.white,
                        clipBehavior: Clip.antiAlias,
                        shape: RoundedRectangleBorder(side: const BorderSide(color: Warna.garis, width: 1.5), borderRadius: BorderRadius.circular(12)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Wrap(spacing: 8, children: [
                            for (final (kode, label) in _tab)
                              ChoiceChip(
                                key: ValueKey('tab-$kode'),
                                label: Text(label, style: const TextStyle(fontSize: 16)),
                                selected: _status == kode,
                                onSelected: (_) => setState(() {
                                  _status = kode;
                                  _dipilihId = null;
                                }),
                              ),
                          ]),
                        ),
                        const Divider(height: 1),
                        Expanded(
                          child: daftar.isEmpty
                              ? const Center(child: Text('Tidak ada usulan.', style: TextStyle(fontSize: 17, color: Warna.teksPudar)))
                              : ListView(children: [
                                  for (final u in daftar)
                                    ListTile(
                                      key: ValueKey('usulan-${u.id}'),
                                      selected: u.id == dipilih?.id,
                                      selectedTileColor: Warna.utamaMuda,
                                      onTap: () => setState(() => _dipilihId = u.id),
                                      title: Text(u.barangNama, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                                      subtitle: Text('${u.kodeCabang} · ${u.peminta} · ${waktuLengkap(u.dibuat.toLocal())}', style: const TextStyle(fontSize: 14)),
                                      trailing: Text(_selisih(u),
                                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: u.turunPerMilNilai > 0 ? Warna.merah : Warna.teksPudar)),
                                    ),
                                ]),
                        ),
                      ]),
                      ),
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: dipilih == null
                        ? const SizedBox.shrink()
                        : SingleChildScrollView(child: _Detail(u: dipilih, selisih: _selisih(dipilih), sibuk: _sibuk, onPutuskan: (setuju) => _putuskan(dipilih, setuju))),
                  ),
                ]),
              ),
            ]),
          );
        },
      );
}

class _Detail extends StatelessWidget {
  const _Detail({required this.u, required this.selisih, required this.sibuk, required this.onPutuskan});
  final UsulanHargaPusat u;
  final String selisih;
  final bool sibuk;
  final ValueChanged<bool> onPutuskan;

  @override
  Widget build(BuildContext context) {
    Widget kotakHarga(String judul, String nilai, {Color? warna}) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Warna.latar, borderRadius: BorderRadius.circular(10), border: Border.all(color: Warna.garis)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(judul, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: Warna.teksPudar)),
              const SizedBox(height: 6),
              Text(nilai, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: warna)),
            ]),
          ),
        );
    final peringatan = u.peringatan;
    return Panel(
      judul: '${u.barangNama}${u.satuan.isEmpty ? '' : ' (${u.satuan})'}',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('${u.kodeCabang} · ${u.namaCabang}', style: const TextStyle(fontSize: 17, color: Warna.teksPudar)),
        const SizedBox(height: 14),
        Row(children: [
          kotakHarga('HARGA SEKARANG', u.hargaLama == null ? '-' : formatRupiah(u.hargaLama!)),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Icon(Icons.arrow_forward, size: 28)),
          kotakHarga('HARGA USULAN', formatRupiah(u.hargaBaru), warna: Warna.utama),
        ]),
        const SizedBox(height: 12),
        _Baris('Perubahan', selisih),
        _Baris('HPP', u.hpp == null ? '-' : formatRupiah(u.hpp!)),
        _Baris('Grosir', u.grosir.isEmpty ? '-' : u.grosir.map((g) => '≥${g.minQty}: ${formatRupiah(g.harga)}').join('   ')),
        _Baris('Alasan', u.alasan),
        _Baris('Diubah oleh', '${u.peminta} · ${waktuLengkap(u.dibuat.toLocal())}'),
        if (peringatan != null) ...[const SizedBox(height: 10), KotakPesan(peringatan, jenis: JenisPesan.perhatian)],
        const SizedBox(height: 16),
        if (u.menunggu)
          Row(children: [
            Expanded(
              child: OutlinedButton(
                key: const ValueKey('tolak'),
                onPressed: sibuk ? null : () => onPutuskan(false),
                style: OutlinedButton.styleFrom(foregroundColor: Warna.merah),
                child: const Text('Tolak'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: FilledButton(key: const ValueKey('setujui'), onPressed: sibuk ? null : () => onPutuskan(true), child: const Text('Setujui'))),
          ])
        else
          KotakPesan(
            '${u.status == statusUsulanDisetujui ? 'Disetujui' : 'Ditolak'} oleh ${u.namaPemutus}'
            '${u.diputuskanDi == 'pusat' ? ' (dari pusat)' : ' (di toko)'}'
            '${u.diputuskanPada == null ? '' : ' · ${waktuLengkap(u.diputuskanPada!.toLocal())}'}.',
            jenis: u.status == statusUsulanDisetujui ? JenisPesan.berhasil : JenisPesan.info,
          ),
      ]),
    );
  }
}

class _Baris extends StatelessWidget {
  const _Baris(this.label, this.nilai);
  final String label;
  final String nilai;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 130, child: Text(label, style: const TextStyle(fontSize: 17, color: Warna.teksPudar))),
          Expanded(child: Text(nilai, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
        ]),
      );
}
