import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:pos_ui/pos_ui.dart';

import '../../data/model.dart';
import '../komponen.dart';

/// Nama aksi yang mudah dibaca. Aksi lain ditampilkan apa adanya.
const namaAksi = {
  'login_pin': 'Masuk (PIN)',
  'login_pin_gagal': 'PIN salah',
  'login_admin': 'Admin masuk',
  'login_admin_gagal': 'Admin gagal masuk',
  'akun_terkunci': 'Akun terkunci',
  'keluar': 'Keluar',
  'keluar_otomatis': 'Keluar otomatis',
  'batal_transaksi': 'Transaksi dibatalkan',
  'retur': 'Retur',
  'barang_masuk': 'Barang masuk',
  'ubah_harga': 'Ubah harga',
  'koreksi_diminta': 'Minta koreksi barang masuk',
  'koreksi_disetujui': 'Koreksi disetujui',
  'koreksi_ditolak': 'Koreksi ditolak',
  'stok_opname': 'Stok opname',
  'buka_shift': 'Buka shift',
  'tutup_shift': 'Tutup shift',
  'hitung_uang_shift': 'Hitung uang tutup shift',
  'hitung_ulang_shift': 'Hitung ulang uang shift',
  'kas_keluar': 'Kas keluar',
  'kas_masuk': 'Kas masuk',
  'tambah_pengguna': 'Tambah karyawan',
  'perangkat_terdaftar': 'PC toko terdaftar',
  'login_pusat': 'Admin pusat masuk',
  'login_gagal': 'Admin pusat gagal masuk',
  'ubah_harga_pusat': 'Harga pusat diubah',
  'tambah_barang': 'Barang baru (pusat)',
  'ubah_barang': 'Data barang diubah (pusat)',
  'cabut_perangkat': 'PC toko dicabut',
  'buat_kode_pendaftaran': 'Kode pendaftaran dibuat',
};

const _aksiPenting = {'batal_transaksi', 'akun_terkunci', 'login_pin_gagal', 'login_admin_gagal', 'login_gagal', 'koreksi_disetujui', 'stok_opname', 'retur', 'cabut_perangkat', 'hitung_ulang_shift', 'kas_keluar'};

String _ringkas(String detail) {
  try {
    final d = jsonDecode(detail);
    if (d is! Map || d.isEmpty) return '';
    return d.entries.where((e) => e.value != null && e.value is! Map && e.value is! List).take(4).map((e) => '${e.key}: ${e.value}').join(' · ');
  } on FormatException {
    return '';
  }
}

class IsiLog extends StatefulWidget {
  const IsiLog({super.key});
  @override
  State<IsiLog> createState() => _IsiLogState();
}

class _IsiLogState extends State<IsiLog> {
  Periode _periode = Periode.hariIni;
  String? _cabangId;
  bool _hanyaPenting = false;

  @override
  Widget build(BuildContext context) {
    final (dari, sampai) = _periode.rentang(DateTime.now());
    return Muat<(List<LogPusat>, List<CabangPusat>)>(
      key: ValueKey('$_periode $_cabangId'),
      ambil: (s) => s.pakai((api) async => (await api.log(dari, sampai, cabangId: _cabangId), await api.cabang())),
      isi: (context, d, _) {
        final (semua, cabang) = d;
        final daftar = _hanyaPenting ? semua.where((l) => _aksiPenting.contains(l.aksi)).toList() : semua;
        return ListView(padding: const EdgeInsets.all(24), children: [
          Wrap(spacing: 16, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
            PilihPeriode(nilai: _periode, onUbah: (p) => setState(() => _periode = p)),
            PilihCabang(cabang: cabang, nilai: _cabangId, onUbah: (v) => setState(() => _cabangId = v)),
            FilterChip(
              label: const Text('Hanya yang perlu dicek', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              selected: _hanyaPenting,
              onSelected: (v) => setState(() => _hanyaPenting = v),
            ),
          ]),
          const SizedBox(height: 16),
          Panel(
            padding: EdgeInsets.zero,
            child: daftar.isEmpty
                ? const Padding(padding: EdgeInsets.all(20), child: Text('Tidak ada aktivitas.', style: TextStyle(fontSize: 17, color: Warna.teksPudar)))
                : TabelSederhana(
                    kolom: const ['Waktu', 'Toko', 'Aktivitas', 'Oleh', 'Rincian'],
                    lebar: const [3, 1, 4, 3, 6],
                    baris: [
                      for (final l in daftar)
                        [
                          Text(waktuLengkap(l.waktu), style: const TextStyle(fontSize: 15.5)),
                          Text(l.kodeCabang ?? 'Pusat', style: gayaSelTebal),
                          Text(namaAksi[l.aksi] ?? l.aksi,
                              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: _aksiPenting.contains(l.aksi) ? Warna.oranye : Warna.teks)),
                          Text([l.oleh ?? '-', if (l.penyetuju != null) 'disetujui ${l.penyetuju}'].join('\n'), style: const TextStyle(fontSize: 15.5)),
                          Text(_ringkas(l.detail), style: const TextStyle(fontSize: 14.5, color: Warna.teksPudar)),
                        ],
                    ],
                  ),
          ),
        ]);
      },
    );
  }
}
