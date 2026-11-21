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

/// Satu usulan perubahan harga dari kasir (menunggu / disetujui / ditolak).
class UsulanHargaBaris {
  const UsulanHargaBaris({
    required this.id,
    required this.cabangId,
    required this.barangId,
    required this.namaBarang,
    required this.satuan,
    required this.hargaLama,
    required this.hargaBaru,
    required this.grosir,
    required this.hpp,
    required this.sumber,
    required this.alasan,
    required this.dimintaOleh,
    required this.status,
    required this.dibuat,
    this.diputuskanOleh,
    this.diputuskanPada,
  });
  final String id;
  final String cabangId;
  final String barangId;
  final String namaBarang;
  final String satuan;
  final int? hargaLama;
  final int hargaBaru;
  final List<TingkatGrosir> grosir;
  final int? hpp;
  final String sumber;
  final String alasan;
  final String dimintaOleh;
  final String status;
  final DateTime dibuat;
  final String? diputuskanOleh;
  final DateTime? diputuskanPada;

  /// Turun dalam per-mil (156 = 15,6%); negatif kalau naik; 0 kalau belum ada harga lama.
  int get turunPerMilNilai => hargaLama == null ? 0 : turunPerMil(hargaLama!, hargaBaru);
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

  /// Ubah harga tanpa barang masuk.
  /// - SPV/Admin: langsung berlaku.
  /// - Kasir: menjadi usulan yang menunggu SPV/Admin (harga lama tetap berlaku). Hasilnya id usulan.
  /// - Kasir + [disetujuiOleh] (SPV/Admin memasukkan PIN di layar yang sama): langsung berlaku, hasil null.
  String? ubahHarga({
    required InfoCabang cabang,
    required String barangId,
    required int hargaBaru,
    required List<TingkatGrosir> grosir,
    required String alasan,
    required Pengguna oleh,
    Pengguna? disetujuiOleh,
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
    if (disetujuiOleh != null && !bolehMenyetujui(disetujuiOleh.peran)) {
      throw StateError('Persetujuan harus dari SPV atau Admin');
    }
    final perluUsulan = hargaPerluPersetujuan(oleh.peran) && disetujuiOleh == null;
    return _db.transaksi(() {
      if (perluUsulan) {
        final id = tulisUsulan(
          cabangId: cabang.id,
          barangId: barangId,
          hargaLama: lama.eceran,
          hargaBaru: hargaBaru,
          grosir: grosir,
          hpp: d.hpp,
          sumber: 'ubah_harga',
          alasan: alasan.trim(),
          olehId: oleh.id,
        );
        _db.log(cabangId: cabang.id, penggunaId: oleh.id, aksi: 'usulan_harga', detail: {
          'usulan_id': id,
          'barang_id': barangId,
          'nama': d.nama,
          'harga_lama': lama.eceran,
          'harga_baru': hargaBaru,
          'alasan': alasan.trim(),
        });
        return id;
      }
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
      return null;
    });
  }

  // ---------------------------------------------------------------- usulan harga

  /// Tulis usulan harga berstatus menunggu. Harus di dalam transaksi. Harga berlaku TIDAK berubah.
  String tulisUsulan({
    required String cabangId,
    required String barangId,
    required int? hargaLama,
    required int hargaBaru,
    required List<TingkatGrosir> grosir,
    required int? hpp,
    required String sumber,
    String? refId,
    required String alasan,
    required String olehId,
  }) {
    final id = buatId();
    _db.jalankan(
      'INSERT INTO usulan_harga (id, cabang_id, barang_id, harga_lama, harga_baru, grosir_json, hpp, sumber, ref_id, alasan,'
      ' diminta_oleh, created_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)',
      [
        id, cabangId, barangId, hargaLama, hargaBaru,
        jsonEncode([for (final g in grosir) [g.minQty, g.harga]]),
        hpp, sumber, refId, alasan, olehId, _db.sekarangIso(),
      ],
    );
    _db.outbox('usulan_harga', id);
    return id;
  }

  UsulanHargaBaris _usulanDari(Map<String, Object?> r) => UsulanHargaBaris(
        id: r['id'] as String,
        cabangId: r['cabang_id'] as String,
        barangId: r['barang_id'] as String,
        namaBarang: r['nama'] as String,
        satuan: r['satuan'] as String,
        hargaLama: r['harga_lama'] as int?,
        hargaBaru: r['harga_baru'] as int,
        grosir: [
          for (final x in (jsonDecode(r['grosir_json'] as String) as List<Object?>).cast<List<Object?>>())
            TingkatGrosir(minQty: x[0] as int, harga: x[1] as int),
        ],
        hpp: r['hpp'] as int?,
        sumber: r['sumber'] as String,
        alasan: r['alasan'] as String,
        dimintaOleh: r['peminta'] as String,
        status: r['status'] as String,
        dibuat: DateTime.parse(r['created_at'] as String),
        diputuskanOleh: r['pemutus'] as String?,
        diputuskanPada: r['diputuskan_pada'] == null ? null : DateTime.parse(r['diputuskan_pada'] as String),
      );

  /// Usulan toko ini. [status] null = semua. Yang terbaru di atas.
  List<UsulanHargaBaris> daftarUsulan(String cabangId, {String? status, int batas = 100}) => _db
      .pilih(
        'SELECT u.*, b.nama, b.satuan, p.nama AS peminta, m.nama AS pemutus FROM usulan_harga u'
        ' JOIN barang b ON b.id = u.barang_id JOIN pengguna p ON p.id = u.diminta_oleh'
        ' LEFT JOIN pengguna m ON m.id = u.diputuskan_oleh'
        ' WHERE u.cabang_id = ?${status == null ? '' : ' AND u.status = ?'} ORDER BY u.created_at DESC LIMIT ?',
        [cabangId, ?status, batas],
      )
      .map(_usulanDari)
      .toList();

  int jumlahUsulanMenunggu(String cabangId) =>
      _db.satu("SELECT COUNT(*) AS n FROM usulan_harga WHERE cabang_id = ? AND status = 'menunggu'", [cabangId])!['n'] as int;

  /// SPV/Admin menyetujui atau menolak. Disetujui → baris harga_jual (+ grosir) baru dengan `disetujui_oleh`.
  /// Usulan yang sudah diputuskan (di sini atau dari pusat) ditolak.
  void putuskanUsulan({required String usulanId, required bool setuju, required Pengguna oleh}) {
    _db.transaksi(() {
      final r = _db.satu('SELECT * FROM usulan_harga WHERE id = ?', [usulanId]);
      if (r == null) throw StateError('Usulan tidak ditemukan');
      final alasanTolak = alasanTidakBolehMemutuskan(peran: oleh.peran, statusUsulan: r['status'] as String);
      if (alasanTolak != null) throw StateError(alasanTolak);
      final t = _db.sekarangIso();
      final cabangId = r['cabang_id'] as String;
      final barangId = r['barang_id'] as String;
      final hargaBaru = r['harga_baru'] as int;
      String? hargaJualId;
      if (setuju) {
        final grosir = [
          for (final x in (jsonDecode(r['grosir_json'] as String) as List<Object?>).cast<List<Object?>>())
            TingkatGrosir(minQty: x[0] as int, harga: x[1] as int),
        ];
        hargaJualId = tulisHarga(
          cabangId: cabangId,
          barangId: barangId,
          harga: hargaBaru,
          grosir: grosir,
          sumber: r['sumber'] as String,
          refId: r['ref_id'] as String?,
          alasan: r['alasan'] as String,
          olehId: r['diminta_oleh'] as String,
          disetujuiOleh: oleh.id,
        );
        final lama = r['harga_lama'] as int?;
        if (lama != null && lama != hargaBaru) {
          tambahAntreanLabel(barangId, lama, hargaBaru, oleh.nama);
        }
      }
      _db.jalankan(
        'UPDATE usulan_harga SET status = ?, diputuskan_oleh = ?, diputuskan_di = \'toko\', diputuskan_pada = ?,'
        ' harga_jual_id = ? WHERE id = ?',
        [setuju ? statusUsulanDisetujui : statusUsulanDitolak, oleh.id, t, hargaJualId, usulanId],
      );
      _db.outbox('usulan_harga', usulanId);
      _db.log(
        cabangId: cabangId,
        penggunaId: r['diminta_oleh'] as String,
        disetujuiOleh: oleh.id,
        aksi: setuju ? 'usulan_harga_disetujui' : 'usulan_harga_ditolak',
        detail: {'usulan_id': usulanId, 'barang_id': barangId, 'harga_lama': r['harga_lama'], 'harga_baru': hargaBaru},
      );
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
