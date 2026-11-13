import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pos_core/pos_core.dart';

import '../../data/model.dart';
import '../../data/repo/laporan_repo.dart';
import '../../layanan/aplikasi.dart';
import '../komponen/umum.dart';
import '../tema.dart';
import 'transaksi.dart';


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
              selectedColor: Warna.utamaMuda,
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
            KartuAngka(label: 'Penjualan bersih', nilai: formatRupiah(_r.penjualanBersih), catatan: 'setelah dikurangi retur', aksen: Warna.sukses, ikon: Icons.payments),
            KartuAngka(label: 'Jumlah transaksi', nilai: '${_r.jumlahTransaksi}', catatan: 'rata-rata ${formatRupiah(_r.rataRataStruk)}', aksen: Warna.utama, ikon: Icons.receipt_long),
            KartuAngka(label: 'Tunai', nilai: formatRupiah(_r.tunai), aksen: Warna.toska, ikon: Icons.money),
            KartuAngka(label: 'Non-tunai', nilai: formatRupiah(_r.nonTunai), aksen: Warna.coklat, ikon: Icons.credit_card),
            KartuAngka(label: 'Laba kotor', nilai: formatRupiah(_r.labaKotor), catatan: 'harga jual − HPP', aksen: Warna.ungu, ikon: Icons.trending_up),
            KartuAngka(
              label: 'Batal / retur',
              nilai: '${_r.jumlahBatal} batal',
              catatan: 'retur ${formatRupiah(_r.totalRetur)}',
              warna: _r.jumlahBatal > 0 ? Warna.merah : Warna.teks,
              aksen: Warna.merahIkon,
              ikon: Icons.assignment_return,
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
  'hitung_uang_shift': 'Hitung uang tutup shift',
  'hitung_ulang_shift': 'Hitung ulang uang shift',
  'tutup_shift_belum_dihitung': 'Tutup shift (belum dihitung)',
  'hitung_amplop_shift': 'Hitung amplop shift',
  'atur_modal_tetap': 'Atur modal tetap',
  'kas_keluar': 'Kas keluar',
  'kas_masuk': 'Kas masuk',
  'ganti_alamat_server': 'Ganti alamat server',
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

const _aksiPenting = {
  'batal_transaksi', 'akun_terkunci', 'login_pin_gagal', 'login_admin_gagal', 'koreksi_disetujui', 'stok_opname', 'retur',
  'hitung_ulang_shift', 'kas_keluar', 'tutup_shift_belum_dihitung', 'hitung_amplop_shift',
};

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
    case 'hitung_uang_shift':
    case 'hitung_ulang_shift':
      return 'hitungan ke-${n('ke')}: ${formatAngka(n('kas_dihitung') ?? 0)}, selisih ${formatAngka(n('selisih') ?? 0)}';
    case 'tutup_shift_belum_dihitung':
      return 'amplop belum dihitung · ${n('jumlah_transaksi') ?? 0} transaksi · modal ditinggal ${formatAngka(n('modal_ditinggal') ?? 0)}';
    case 'hitung_amplop_shift':
      return 'isi amplop ${formatAngka(n('amplop_dihitung') ?? 0)} + modal ${formatAngka(n('modal_ditinggal') ?? 0)}, '
          'seharusnya ${formatAngka(n('kas_sistem') ?? 0)}, selisih ${formatAngka(n('selisih') ?? 0)}';
    case 'kas_keluar':
    case 'kas_masuk':
      return '${formatRupiah(n('jumlah') ?? 0)} · ${d['keterangan']}';
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
              selectedColor: Warna.utamaMuda,
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
