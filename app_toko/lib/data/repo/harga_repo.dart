import 'dart:convert';

import 'package:pos_core/pos_core.dart';

import '../database.dart';
import '../model.dart';
import 'katalog_repo.dart';
import 'pengaturan_repo.dart';

class AntreanLabel {
  const AntreanLabel({required this.barangId, required this.hargaLama, required this.hargaBaru, required this.waktu, required this.oleh});
  final String barangId;
  final int hargaLama;
  final int hargaBaru;
  final DateTime waktu;
  final String oleh;
}

const alasanUbahHarga = [
  'Harga dari supplier naik',
  'Harga dari supplier turun',
  'Promo',
  'Harga sebelumnya salah',
  'Lainnya',
];

/// Perubahan harga (tanpa barang masuk) dan antrean label rak.
class HargaRepo {
  HargaRepo(this._db);
  final DatabaseToko _db;

  /// Tulis satu versi harga baru + tingkat grosirnya. Harus di dalam transaksi.
  /// Harga dari toko berlaku untuk toko itu saja (`cabang_id` = toko).
  String tulisHarga({
    required String cabangId,
    required String barangId,
    required int harga,
    required List<TingkatGrosir> grosir,
    required String sumber,
    String? refId,
    required String alasan,
    required String olehId,
    required String? disetujuiOleh,
  }) {
    final t = _db.sekarangIso();
    final id = buatId();
    _db.jalankan(
      'INSERT INTO harga_jual (id, barang_id, cabang_id, harga, sumber, ref_id, alasan, dibuat_oleh, disetujui_oleh,'
      ' berlaku_mulai, created_at) VALUES (?,?,?,?,?,?,?,?,?,?,?)',
      [id, barangId, cabangId, harga, sumber, refId, alasan, olehId, disetujuiOleh, t, t],
    );
    _db.outbox('harga_jual', id);
    for (final g in grosir) {
      final gid = buatId();
      _db.jalankan('INSERT INTO harga_grosir (id, harga_jual_id, min_qty, harga, created_at) VALUES (?,?,?,?,?)',
          [gid, id, g.minQty, g.harga, t]);
      _db.outbox('harga_grosir', gid);
    }
    return id;
  }

  /// Ubah harga tanpa barang masuk. Turun >10% atau ≤ HPP wajib [disetujuiOleh] (SPV/Admin) kalau [oleh] kasir.
  void ubahHarga({
    required InfoCabang cabang,
    required String barangId,
    required int hargaBaru,
    required List<TingkatGrosir> grosir,
    required String alasan,
    required Pengguna oleh,
    Pengguna? disetujuiOleh,
    int batasTurunPersen = 10,
  }) {
    if (alasan.trim().isEmpty) throw ArgumentError('Pilih alasan perubahan');
    final katalog = KatalogRepo(_db);
    final d = katalog.detail(barangId, cabang.id);
    if (d == null) throw ArgumentError('Barang tidak ditemukan');
    final lama = d.harga;
    if (lama == null) throw StateError('Barang ini belum punya harga. Isi lewat barang masuk.');
    if (hargaBaru <= 0) throw ArgumentError('Harga baru wajib diisi');
    final salah = periksaTingkatGrosir(eceran: hargaBaru, hpp: d.hpp, tingkat: grosir);
    if (salah.isNotEmpty) throw ArgumentError('Grosir tingkat ${salah.keys.first + 1}: ${salah.values.first}');
    final cek = cekUbahHarga(hargaLama: lama.eceran, hargaBaru: hargaBaru, hpp: d.hpp, batasTurunPersen: batasTurunPersen);
    if (cek.perluPinSpv && !bolehMenyetujui(oleh.peran)) {
      if (disetujuiOleh == null || !bolehMenyetujui(disetujuiOleh.peran)) {
        throw StateError('Perlu persetujuan PIN SPV: ${cek.alasan}');
      }
    }
    _db.transaksi(() {
      tulisHarga(
        cabangId: cabang.id,
        barangId: barangId,
        harga: hargaBaru,
        grosir: grosir,
        sumber: 'ubah_harga',
        alasan: alasan.trim(),
        olehId: oleh.id,
        disetujuiOleh: disetujuiOleh?.id,
      );
      _db.log(
        cabangId: cabang.id,
        penggunaId: oleh.id,
        disetujuiOleh: disetujuiOleh?.id,
        aksi: 'ubah_harga',
        detail: {
          'barang_id': barangId,
          'nama': d.nama,
          'harga_lama': lama.eceran,
          'harga_baru': hargaBaru,
          'grosir_lama': [for (final g in lama.grosir) [g.minQty, g.harga]],
          'grosir_baru': [for (final g in grosir) [g.minQty, g.harga]],
          'alasan': alasan.trim(),
        },
      );
      if (lama.eceran != hargaBaru) tambahAntreanLabel(barangId, lama.eceran, hargaBaru, oleh.nama);
    });
  }

  // ---------------------------------------------------------------- label rak

  List<AntreanLabel> antreanLabel() {
    final s = PengaturanRepo(_db).ambil(PengaturanRepo.kAntreanLabel);
    if (s == null) return [];
    return [
      for (final x in (jsonDecode(s) as List<Object?>).cast<Map<String, Object?>>())
        AntreanLabel(
          barangId: x['b'] as String,
          hargaLama: x['l'] as int,
          hargaBaru: x['h'] as int,
          waktu: DateTime.parse(x['w'] as String),
          oleh: x['o'] as String,
        ),
    ];
  }

  void tambahAntreanLabel(String barangId, int lama, int baru, String oleh) {
    final daftar = antreanLabel().where((a) => a.barangId != barangId).toList()
      ..insert(0, AntreanLabel(barangId: barangId, hargaLama: lama, hargaBaru: baru, waktu: _db.sekarang(), oleh: oleh));
    _simpanAntrean(daftar);
  }

  void hapusDariAntrean(Iterable<String> barangIds) {
    final hapus = barangIds.toSet();
    _simpanAntrean(antreanLabel().where((a) => !hapus.contains(a.barangId)).toList());
  }

  void _simpanAntrean(List<AntreanLabel> d) => PengaturanRepo(_db).simpan(
        PengaturanRepo.kAntreanLabel,
        d.isEmpty
            ? null
            : jsonEncode([
                for (final a in d) {'b': a.barangId, 'l': a.hargaLama, 'h': a.hargaBaru, 'w': isoUtc(a.waktu), 'o': a.oleh},
              ]),
      );
}
