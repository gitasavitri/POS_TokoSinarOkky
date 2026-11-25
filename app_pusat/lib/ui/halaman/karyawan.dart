import 'package:flutter/material.dart';
import 'package:pos_ui/pos_ui.dart';

import '../../data/model.dart';
import '../komponen.dart';

/// Daftar karyawan semua toko (hanya lihat). Karyawan dikelola Admin di PC toko masing-masing.
class IsiKaryawan extends StatefulWidget {
  const IsiKaryawan({super.key});
  @override
  State<IsiKaryawan> createState() => _IsiKaryawanState();
}

class _IsiKaryawanState extends State<IsiKaryawan> {
  String? _cabangId;

  @override
  Widget build(BuildContext context) => Muat<(List<KaryawanPusat>, List<CabangPusat>)>(
        key: ValueKey(_cabangId),
        ambil: (s) => s.pakai((api) async => (await api.karyawan(cabangId: _cabangId), await api.cabang())),
        isi: (context, d, _) {
          final (daftar, cabang) = d;
          return ListView(padding: const EdgeInsets.all(24), children: [
            Row(children: [
              PilihCabang(cabang: cabang, nilai: _cabangId, onUbah: (v) => setState(() => _cabangId = v)),
              const SizedBox(width: 16),
              const Expanded(
                child: Text('Tambah karyawan, ganti PIN, dan buka kunci dilakukan Admin di PC toko (menu Karyawan), supaya tetap bisa walau internet putus.',
                    style: TextStyle(fontSize: 15.5, color: Warna.teksPudar)),
              ),
            ]),
            const SizedBox(height: 16),
            Panel(
              padding: EdgeInsets.zero,
              child: TabelSederhana(
                kolom: const ['Toko', 'Nama', 'Peran', 'Status'],
                lebar: const [2, 5, 3, 2],
                baris: [
                  for (final k in daftar)
                    [
                      Text(k.kodeCabang ?? 'Pusat', style: gayaSelTebal),
                      Text(k.nama + (k.namaPengguna != null && !k.namaPengguna!.startsWith('pusat:') ? ' (${k.namaPengguna})' : ''), style: gayaSel),
                      Text(k.kodeCabang == null ? 'Admin pusat' : k.peran.label, style: gayaSel),
                      Lencana.status(!k.aktif ? 'Nonaktif' : (k.terkunci ? 'Terkunci' : 'Aktif')),
                    ],
                ],
              ),
            ),
          ]);
        },
      );
}
