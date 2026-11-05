import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pos_core/pos_core.dart';

import '../../data/model.dart';
import '../../data/repo/laporan_repo.dart';
import '../../layanan/aplikasi.dart';
import '../komponen/kerangka.dart';
import '../komponen/umum.dart';
import '../tema.dart';
import 'transaksi.dart';

enum Periode {
  hariIni('Hari ini'),
  kemarin('Kemarin'),
  tujuhHari('7 hari'),
  bulanIni('Bulan ini'),
  bulanLalu('Bulan lalu'),
  tahunIni('Tahun ini');

  const Periode(this.label);
  final String label;

  /// (dari, sampai) dalam UTC, batas hari mengikuti WIB.
  (DateTime, DateTime) rentang(DateTime sekarang) {
    final hari = awalHariWibUtc(sekarang);
    final w = keWib(sekarang);
    DateTime awalBulanWib(int tahun, int bulan) => DateTime.utc(tahun, bulan).subtract(const Duration(hours: 7));
    return switch (this) {
      Periode.hariIni => (hari, hari.add(const Duration(days: 1))),
      Periode.kemarin => (hari.subtract(const Duration(days: 1)), hari),
      Periode.tujuhHari => (hari.subtract(const Duration(days: 6)), hari.add(const Duration(days: 1))),
      Periode.bulanIni => (awalBulanWib(w.year, w.month), awalBulanWib(w.year, w.month + 1)),
      Periode.bulanLalu => (awalBulanWib(w.year, w.month - 1), awalBulanWib(w.year, w.month)),
      Periode.tahunIni => (awalBulanWib(w.year, 1), awalBulanWib(w.year + 1, 1)),
    };
  }
}

class IsiLaporan extends StatefulWidget {
  const IsiLaporan({super.key});
  @override
  State<IsiLaporan> createState() => _IsiLaporanState();
}

class _IsiLaporanState extends State<IsiLaporan> {
  Periode _periode = Periode.hariIni;
  MetodeBayar? _metode;
  String? _kasirId;
  late Ringkasan _r;
  late List<BarisTransaksi> _daftar;
  late Map<DateTime, int> _perHari;
  late List<Pengguna> _kasir;

  @override
  void initState() {
    super.initState();
    _kasir = context.app.pengguna.semua(context.app.cabang.id);
    _muat();
  }

  void _muat() {
    final app = context.app;
    final (dari, sampai) = _periode.rentang(DateTime.now());
    final c = app.cabang.id;
    setState(() {
      _r = app.laporan.ringkasan(c, dari, sampai);
      _daftar = app.laporan.daftarTransaksi(c, dari, sampai, kasirId: _kasirId, metode: _metode, batas: 2000);
      _perHari = _periode == Periode.tahunIni ? {} : app.laporan.penjualanPerHari(c, dari, sampai);
    });
  }

  Future<void> _ekspor() async {
    final app = context.app;
    try {
      final dok = await getApplicationDocumentsDirectory();
      final w = keWib(DateTime.now());
      final nama = 'laporan-${app.cabang.kode}-${_periode.name}-${w.year}${w.month.toString().padLeft(2, '0')}${w.day.toString().padLeft(2, '0')}.csv';
      final f = File('${dok.path}${Platform.pathSeparator}$nama');
      // BOM supaya Excel membaca huruf dengan benar.
      await f.writeAsString('﻿${app.laporan.csvTransaksi(_daftar)}');
      if (mounted) tampilkanPesan(context, 'Tersimpan: ${f.path}');
    } catch (e) {
      if (mounted) tampilkanPesan(context, 'Gagal menyimpan: ${pesanGalat(e)}', galat: true);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(24), children: [
        Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
          for (final p in Periode.values)
            ChoiceChip(
              label: Text(p.label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              selected: p == _periode,
              selectedColor: Warna.hijauMuda,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              onSelected: (_) {
                _periode = p;
                _muat();
              },
            ),
          const SizedBox(width: 12),
          SizedBox(
            width: 220,
            child: DropdownButtonFormField<String?>(
              initialValue: _kasirId,
              decoration: const InputDecoration(labelText: 'Kasir'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Semua kasir')),
                for (final k in _kasir) DropdownMenuItem(value: k.id, child: Text(k.nama)),
              ],
              onChanged: (v) {
                _kasirId = v;
                _muat();
              },
            ),
          ),
          SizedBox(
            width: 220,
            child: DropdownButtonFormField<MetodeBayar?>(
              initialValue: _metode,
              decoration: const InputDecoration(labelText: 'Cara bayar'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Semua')),
                for (final m in MetodeBayar.values) DropdownMenuItem(value: m, child: Text(m.label)),
              ],
              onChanged: (v) {
                _metode = v;
                _muat();
              },
            ),
          ),
          OutlinedButton.icon(onPressed: _ekspor, icon: const Icon(Icons.download), label: const Text('Unduh Excel (CSV)')),
        ]),
        const SizedBox(height: 20),
        LayoutBuilder(builder: (context, c) {
          final kartu = [
            KartuAngka(label: 'Penjualan bersih', nilai: formatRupiah(_r.penjualanBersih), catatan: 'setelah dikurangi retur'),
            KartuAngka(label: 'Jumlah transaksi', nilai: '${_r.jumlahTransaksi}', catatan: 'rata-rata ${formatRupiah(_r.rataRataStruk)}'),
            KartuAngka(label: 'Tunai', nilai: formatRupiah(_r.tunai)),
            KartuAngka(label: 'Non-tunai', nilai: formatRupiah(_r.nonTunai)),
            KartuAngka(label: 'Laba kotor', nilai: formatRupiah(_r.labaKotor), catatan: 'harga jual − HPP'),
            KartuAngka(
              label: 'Batal / retur',
              nilai: '${_r.jumlahBatal} batal',
              catatan: 'retur ${formatRupiah(_r.totalRetur)}',
              warna: _r.jumlahBatal > 0 ? Warna.merah : Warna.teks,
            ),
          ];
          final lebar = (c.maxWidth - 14 * 2) / 3;
          return Wrap(spacing: 14, runSpacing: 14, children: [for (final k in kartu) SizedBox(width: lebar, child: k)]);
        }),
        if (_perHari.length > 1) ...[
          const SizedBox(height: 20),
          Panel(judul: 'Penjualan per hari', child: GrafikBatang(data: _perHari)),
        ],
        const SizedBox(height: 20),
        Panel(
          judul: 'Daftar transaksi (${_daftar.length})',
          padding: EdgeInsets.zero,
          child: _daftar.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Belum ada transaksi di periode ini.', style: TextStyle(fontSize: 17, color: Warna.teksPudar)))
              : TabelSederhana(
                  kolom: const ['Waktu', 'No. transaksi', 'Kasir', 'Barang', 'Cara bayar', 'Total', 'Status'],
                  lebar: const [3, 5, 3, 2, 3, 3, 2],
                  rataKanan: const {3, 5},
                  onTap: (i) async {
                    await bukaDetailTransaksi(context, _daftar[i].id);
                    _muat();
                  },
                  baris: [
                    for (final t in _daftar)
                      [
                        Text('${formatTanggal(t.waktu)} ${formatJam(t.waktu)}', style: gayaSel),
                        Text(t.noTransaksi, style: gayaSelTebal),
                        Text(t.kasir, style: gayaSel),
                        Text('${t.jumlahBarang}', style: gayaSel),
                        Text(t.metode.label, style: gayaSel),
                        Text(formatRupiah(t.total), style: gayaSelTebal),
                        Lencana.status(t.status),
                      ],
                  ],
                ),
        ),
      ]);
}

/// Grafik batang sederhana penjualan per hari.
class GrafikBatang extends StatelessWidget {
  const GrafikBatang({super.key, required this.data});
  final Map<DateTime, int> data;

  @override
  Widget build(BuildContext context) {
    final maks = data.values.fold<int>(0, (a, b) => b > a ? b : a);
    String singkat(int v) => v >= 1000000 ? '${(v / 1000000).toStringAsFixed(1).replaceAll('.', ',')} jt' : formatAngka(v);
    return SizedBox(
      height: 240,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (final e in data.entries)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                if (data.length <= 14) Text(singkat(e.value), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Container(
                  height: maks == 0 ? 2 : 4 + 170 * e.value / maks,
                  decoration: const BoxDecoration(color: Warna.hijau, borderRadius: BorderRadius.vertical(top: Radius.circular(6))),
                ),
                const SizedBox(height: 6),
                Text('${keWib(e.key).day}', style: const TextStyle(fontSize: 13, color: Warna.teks2, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
      ]),
    );
  }
}

// ============================================================================ log aktivitas

const _namaAksi = {
  'login_pin_berhasil': 'Masuk',
  'login_admin_berhasil': 'Masuk (Admin)',
  'login_pin_gagal': 'PIN salah',
  'login_admin_gagal': 'Login Admin gagal',
  'akun_terkunci': 'Akun terkunci',
  'keluar': 'Keluar',
  'keluar_otomatis': 'Keluar otomatis',
  'buka_shift': 'Buka shift',
  'tutup_shift': 'Tutup shift',
  'batal_transaksi': 'Membatalkan transaksi',
  'retur': 'Retur',
  'kirim_barang_masuk': 'Kirim barang masuk',
  'tambah_barang': 'Tambah barang',
  'ubah_barang': 'Ubah data barang',
  'ubah_harga': 'Ubah harga',
  'minta_koreksi': 'Minta koreksi',
  'koreksi_disetujui': 'Koreksi disetujui',
  'koreksi_ditolak': 'Koreksi ditolak',
  'stok_opname': 'Stok opname',
  'tambah_pengguna': 'Tambah karyawan',
  'ganti_pin': 'Ganti PIN',
  'buka_kunci': 'Buka kunci akun',
  'aktifkan_pengguna': 'Aktifkan karyawan',
  'nonaktifkan_pengguna': 'Nonaktifkan karyawan',
  'tambah_kategori': 'Tambah kategori',
  'tambah_supplier': 'Tambah supplier',
  'ubah_info_cabang': 'Ubah info toko',
  'atur_stok_minimum': 'Atur stok minimum',
};

const _aksiPenting = {'batal_transaksi', 'akun_terkunci', 'login_pin_gagal', 'login_admin_gagal', 'koreksi_disetujui', 'stok_opname', 'retur'};

String ringkasDetail(String aksi, Map<String, Object?> d) {
  int? n(String k) => d[k] is int ? d[k] as int : null;
  switch (aksi) {
    case 'batal_transaksi':
      return '${d['no_transaksi']} · ${formatRupiah(n('total') ?? 0)} · ${d['alasan']}';
    case 'ubah_harga':
      return '${d['nama']}: ${formatAngka(n('harga_lama') ?? 0)} → ${formatAngka(n('harga_baru') ?? 0)} · ${d['alasan']}';
    case 'tutup_shift':
      return 'kas ${formatAngka(n('kas_dihitung') ?? 0)}, seharusnya ${formatAngka(n('kas_sistem') ?? 0)}, selisih ${formatAngka(n('selisih') ?? 0)}';
    case 'buka_shift':
      return 'modal ${formatAngka(n('modal_awal') ?? 0)}';
    case 'kirim_barang_masuk':
      return 'faktur ${d['no_faktur']} · ${d['jumlah_jenis']} jenis, ${d['jumlah_barang']} barang';
    case 'retur':
      return '${formatRupiah(n('total_kembali') ?? 0)} · ${d['alasan']}';
    case 'stok_opname':
      return 'sistem ${d['stok_sistem']}, fisik ${d['stok_fisik']}, selisih ${d['selisih']}';
    case 'koreksi_disetujui':
    case 'koreksi_ditolak':
      return '${d['jumlah_sebelum']} → ${d['jumlah_baru']}';
    case 'minta_koreksi':
      return 'jumlah baru ${d['jumlah_baru']} · ${d['alasan']}';
    default:
      final s = [
        for (final e in d.entries)
          if (e.value is String || e.value is num) '${e.value}',
      ].join(' · ');
      return s;
  }
}

class IsiLog extends StatefulWidget {
  const IsiLog({super.key});
  @override
  State<IsiLog> createState() => _IsiLogState();
}

class _IsiLogState extends State<IsiLog> {
  Periode _periode = Periode.hariIni;
  List<BarisLog> _log = [];

  @override
  void initState() {
    super.initState();
    _muat();
  }

  void _muat() {
    final app = context.app;
    final (a, b) = _periode.rentang(DateTime.now());
    setState(() => _log = app.laporan.log(app.cabang.id, a, b, batas: 1000));
  }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(24), children: [
        Wrap(spacing: 10, children: [
          for (final p in [Periode.hariIni, Periode.kemarin, Periode.tujuhHari, Periode.bulanIni])
            ChoiceChip(
              label: Text(p.label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              selected: p == _periode,
              selectedColor: Warna.hijauMuda,
              onSelected: (_) {
                _periode = p;
                _muat();
              },
            ),
        ]),
        const SizedBox(height: 16),
        const KotakPesan('Log tidak bisa diubah atau dihapus oleh siapa pun.', jenis: JenisPesan.info),
        const SizedBox(height: 16),
        Panel(
          padding: EdgeInsets.zero,
          child: TabelSederhana(
            kolom: const ['Waktu', 'Aktivitas', 'Oleh', 'Rincian'],
            lebar: const [3, 4, 4, 9],
            baris: [
              for (final l in _log)
                [
                  Text('${formatTanggal(l.waktu)} ${formatJam(l.waktu)}', style: gayaSel),
                  Text(_namaAksi[l.aksi] ?? l.aksi,
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: _aksiPenting.contains(l.aksi) ? Warna.merah : Warna.teks)),
                  Text(l.penyetuju == null ? l.oleh : '${l.oleh} · disetujui ${l.penyetuju}', style: gayaSel),
                  Text(ringkasDetail(l.aksi, l.detail), style: const TextStyle(fontSize: 15.5, color: Warna.teks2)),
                ],
            ],
          ),
        ),
      ]);
}
