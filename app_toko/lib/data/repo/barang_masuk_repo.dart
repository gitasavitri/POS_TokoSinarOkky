import 'dart:convert';

import 'package:pos_core/pos_core.dart';

import '../database.dart';
import '../model.dart';
import 'katalog_repo.dart';
import 'pengaturan_repo.dart';
import 'harga_repo.dart';

class DraftBarangMasuk {
  DraftBarangMasuk({this.supplierId, this.noFaktur = '', List<DraftItemMasuk>? item}) : item = item ?? [];
  String? supplierId;
  String noFaktur;
  final List<DraftItemMasuk> item;

  bool get kosong => item.isEmpty && noFaktur.isEmpty;
}

class RiwayatMasuk {
  const RiwayatMasuk({
    required this.id,
    required this.noFaktur,
    required this.supplier,
    required this.dikirimPada,
    required this.oleh,
    required this.item,
  });
  final String id;
  final String noFaktur;
  final String supplier;
  final DateTime dikirimPada;
  final String oleh;
  final List<({String itemId, String nama, String satuan, int jumlah, int jumlahBerlaku, String? statusKoreksi})> item;
}

class Koreksi {
  const Koreksi({
    required this.id,
    required this.noFaktur,
    required this.namaBarang,
    required this.jumlahLama,
    required this.jumlahBaru,
    required this.alasan,
    required this.dimintaOleh,
    required this.status,
    required this.waktu,
  });
  final String id;
  final String noFaktur;
  final String namaBarang;
  final int jumlahLama;
  final int jumlahBaru;
  final String alasan;
  final String dimintaOleh;
  final String status;
  final DateTime waktu;
}

/// Barang masuk: draft → kirim & kunci. Koreksi lewat SPV/Admin. Stok opname.
class BarangMasukRepo {
  BarangMasukRepo(this._db) : _katalog = KatalogRepo(_db), _pengaturan = PengaturanRepo(_db);
  final DatabaseToko _db;
  final KatalogRepo _katalog;
  final PengaturanRepo _pengaturan;

  // ---------------------------------------------------------------- draft (disimpan per PC)

  void simpanDraft(DraftBarangMasuk d) => _pengaturan.simpan(
        PengaturanRepo.kDraftBarangMasuk,
        d.kosong
            ? null
            : jsonEncode({
                'supplierId': d.supplierId,
                'noFaktur': d.noFaktur,
                'item': [for (final i in d.item) i.keJson()],
              }),
      );

  DraftBarangMasuk? muatDraft(String cabangId) {
    final s = _pengaturan.ambil(PengaturanRepo.kDraftBarangMasuk);
    if (s == null) return null;
    final j = jsonDecode(s) as Map<String, Object?>;
    final item = [
      for (final x in (j['item'] as List<Object?>? ?? const []))
        DraftItemMasuk.dariJson(Map<String, Object?>.from(x! as Map)),
    ];
    for (final i in item) {
      if (i.barangId != null) i.asal = _katalog.detail(i.barangId!, cabangId);
    }
    return DraftBarangMasuk(supplierId: j['supplierId'] as String?, noFaktur: j['noFaktur'] as String? ?? '', item: item);
  }

  void hapusDraft() => _pengaturan.simpan(PengaturanRepo.kDraftBarangMasuk, null);

  /// Isi draft dari barang yang sudah ada (harga & data saat ini).
  DraftItemMasuk itemDariBarang(DetailBarang b) => DraftItemMasuk(
        barangId: b.id,
        barcode: b.barcode ?? '',
        nama: b.nama,
        kategoriId: b.kategoriId,
        satuan: b.satuan,
        hpp: b.hpp ?? 0,
        hargaJual: b.harga?.eceran ?? 0,
        grosir: [...?b.harga?.grosir],
        asal: b,
      );

  // ---------------------------------------------------------------- validasi

  /// Pesan kesalahan per item (index → daftar pesan). Kosong = boleh dikirim.
  Map<int, List<String>> periksa(DraftBarangMasuk d) {
    final salah = <int, List<String>>{};
    void tambah(int i, String p) => (salah[i] ??= []).add(p);
    final barcodeDipakai = <String, int>{};
    final barangDipakai = <String, int>{};
    for (var i = 0; i < d.item.length; i++) {
      final it = d.item[i];
      if (it.nama.trim().isEmpty) tambah(i, 'Nama barang wajib diisi.');
      if (it.kategoriId.isEmpty) tambah(i, 'Pilih kategori.');
      if (it.satuan.trim().isEmpty) tambah(i, 'Pilih satuan.');
      if (it.jumlah <= 0) tambah(i, 'Jumlah masuk harus lebih dari 0.');
      if (it.hargaJual <= 0) tambah(i, 'Harga jual wajib diisi.');
      if (it.hpp < 0) tambah(i, 'HPP tidak boleh minus.');
      if (it.hargaJual > 0 && it.hpp >= it.hargaJual) tambah(i, 'Harga jual harus lebih besar dari HPP.');
      final g = periksaTingkatGrosir(eceran: it.hargaJual, hpp: it.hpp, tingkat: it.grosir);
      for (final e in g.entries) {
        tambah(i, 'Grosir tingkat ${e.key + 1}: ${e.value}');
      }
      final bc = it.barcode.trim();
      if (bc.isNotEmpty) {
        final lain = _db.satu('SELECT id, nama FROM barang WHERE barcode = ?', [bc]);
        if (lain != null && lain['id'] != it.barangId) tambah(i, 'Barcode sudah dipakai "${lain['nama']}".');
        final j = barcodeDipakai[bc];
        if (j != null) tambah(i, 'Barcode sama dengan barang no. ${j + 1}.');
        barcodeDipakai[bc] = i;
      }
      if (it.barangId != null) {
        final j = barangDipakai[it.barangId!];
        if (j != null) tambah(i, 'Barang ini sudah ada di daftar (no. ${j + 1}).');
        barangDipakai[it.barangId!] = i;
      }
    }
    return salah;
  }

  // ---------------------------------------------------------------- kirim & kunci

  /// Simpan semua dalam satu transaksi database, lalu kunci. Mengembalikan id barang_masuk.
  String kirim({required InfoCabang cabang, required Pengguna oleh, required DraftBarangMasuk draft}) {
    if (draft.supplierId == null) throw ArgumentError('Pilih supplier');
    if (draft.noFaktur.trim().isEmpty) throw ArgumentError('Isi nomor faktur / surat jalan');
    if (draft.item.isEmpty) throw ArgumentError('Belum ada barang');
    final salah = periksa(draft);
    if (salah.isNotEmpty) {
      final i = salah.keys.first;
      throw ArgumentError('Barang no. ${i + 1}: ${salah[i]!.first}');
    }
    final hargaRepo = HargaRepo(_db);
    return _db.transaksi(() {
      final t = _db.sekarangIso();
      final bmId = buatId();
      _db.jalankan(
        'INSERT INTO barang_masuk (id, cabang_id, supplier_id, no_faktur, dibuat_oleh, created_at) VALUES (?,?,?,?,?,?)',
        [bmId, cabang.id, draft.supplierId, draft.noFaktur.trim(), oleh.id, t],
      );
      final itemIds = <String>[];
      // Id barang per item. Draft tidak diubah, supaya kalau gagal dan diulang, barang baru tetap dianggap baru.
      final barangIds = <DraftItemMasuk, String>{};
      for (final it in draft.item) {
        final barangId = it.barangId ?? buatId();
        barangIds[it] = barangId;
        final barcode = it.barcode.trim().isEmpty ? null : it.barcode.trim();
        if (it.barangBaru) {
          _db.jalankan(
            'INSERT INTO barang (id, barcode, nama, kategori_id, satuan, created_at, updated_at) VALUES (?,?,?,?,?,?,?)',
            [barangId, barcode, it.nama.trim(), it.kategoriId, it.satuan.trim(), t, t],
          );
          _db.outbox('barang', barangId);
          _db.log(cabangId: cabang.id, penggunaId: oleh.id, aksi: 'tambah_barang', detail: {'nama': it.nama.trim()});
        } else if (it.dataBarangBerubah) {
          final a = it.asal!;
          _db.jalankan(
            'UPDATE barang SET barcode = ?, nama = ?, kategori_id = ?, satuan = ?, aktif = 1, updated_at = ? WHERE id = ?',
            [barcode, it.nama.trim(), it.kategoriId, it.satuan.trim(), t, barangId],
          );
          _db.outbox('barang', barangIds[it]!);
          _db.log(cabangId: cabang.id, penggunaId: oleh.id, aksi: 'ubah_barang', detail: {
            'barang_id': barangId,
            'sebelum': {'nama': a.nama, 'barcode': a.barcode, 'kategori_id': a.kategoriId, 'satuan': a.satuan},
            'sesudah': {'nama': it.nama.trim(), 'barcode': barcode, 'kategori_id': it.kategoriId, 'satuan': it.satuan},
          });
        }
        _db.jalankan(
          'INSERT INTO barang_cabang (cabang_id, barang_id, aktif, created_at, updated_at) VALUES (?,?,1,?,?)'
          ' ON CONFLICT(cabang_id, barang_id) DO UPDATE SET aktif = 1, updated_at = excluded.updated_at',
          [cabang.id, barangId, t, t],
        );
        _db.outbox('barang_cabang', '${cabang.id}|$barangId',
            isi: Map<String, Object?>.from(_db.satu(
                'SELECT * FROM barang_cabang WHERE cabang_id = ? AND barang_id = ?', [cabang.id, barangId])!));
        final itemId = buatId();
        itemIds.add(itemId);
        _db.jalankan(
          'INSERT INTO barang_masuk_item (id, barang_masuk_id, barang_id, jumlah, hpp_satuan, harga_jual_baru, created_at)'
          ' VALUES (?,?,?,?,?,?,?)',
          [itemId, bmId, barangId, it.jumlah, it.hpp, it.hargaBerubah ? it.hargaJual : null, t],
        );
      }
      // Kunci. Setelah ini trigger database menolak perubahan apa pun.
      _db.jalankan("UPDATE barang_masuk SET status = 'terkirim', dikirim_pada = ? WHERE id = ?", [t, bmId]);
      _db.outbox('barang_masuk', bmId);
      for (final id in itemIds) {
        _db.outbox('barang_masuk_item', id);
      }

      for (final it in draft.item) {
        final stokLama = _katalog.stok(barangIds[it]!, cabang.id);
        final hppLama = _katalog.hpp(barangIds[it]!, cabang.id);
        final hppBaru = hppRataRata(stokLama: stokLama, hppLama: hppLama, jumlahMasuk: it.jumlah, hppMasuk: it.hpp);
        final mid = buatId();
        _db.jalankan(
          "INSERT INTO mutasi_stok (id, cabang_id, barang_id, jumlah, jenis, ref_id, dibuat_oleh, created_at)"
          " VALUES (?,?,?,?,'masuk',?,?,?)",
          [mid, cabang.id, barangIds[it]!, it.jumlah, bmId, oleh.id, t],
        );
        _db.outbox('mutasi_stok', mid);
        final hid = buatId();
        _db.jalankan('INSERT INTO hpp_barang (id, cabang_id, barang_id, hpp, ref_id, created_at) VALUES (?,?,?,?,?,?)',
            [hid, cabang.id, barangIds[it]!, hppBaru, bmId, t]);
        _db.outbox('hpp_barang', hid);
        if (it.hargaBerubah) {
          hargaRepo.tulisHarga(
            cabangId: cabang.id,
            barangId: barangIds[it]!,
            harga: it.hargaJual,
            grosir: it.grosir,
            sumber: 'barang_masuk',
            refId: bmId,
            alasan: 'Barang masuk faktur ${draft.noFaktur.trim()}',
            olehId: oleh.id,
            disetujuiOleh: null,
          );
          if (it.asal?.harga != null && it.asal!.harga!.eceran != it.hargaJual) {
            hargaRepo.tambahAntreanLabel(barangIds[it]!, it.asal!.harga!.eceran, it.hargaJual, oleh.nama);
          }
        }
      }
      _db.log(cabangId: cabang.id, penggunaId: oleh.id, aksi: 'kirim_barang_masuk', detail: {
        'barang_masuk_id': bmId,
        'no_faktur': draft.noFaktur.trim(),
        'jumlah_jenis': draft.item.length,
        'jumlah_barang': draft.item.fold<int>(0, (s, i) => s + i.jumlah),
      });
      return bmId;
    });
  }

  // ---------------------------------------------------------------- riwayat & koreksi

  int _jumlahBerlaku(String itemId, int asli) {
    final r = _db.satu(
      "SELECT jumlah_baru FROM koreksi_barang_masuk WHERE barang_masuk_item_id = ? AND status = 'disetujui'"
      ' ORDER BY diputuskan_pada DESC LIMIT 1',
      [itemId],
    );
    return (r?['jumlah_baru'] as int?) ?? asli;
  }

  List<RiwayatMasuk> riwayat(String cabangId, {int batas = 30}) => _db
      .pilih(
        "SELECT bm.*, s.nama AS supplier, u.nama AS oleh FROM barang_masuk bm"
        " JOIN supplier s ON s.id = bm.supplier_id JOIN pengguna u ON u.id = bm.dibuat_oleh"
        " WHERE bm.cabang_id = ? AND bm.status = 'terkirim' ORDER BY bm.dikirim_pada DESC LIMIT ?",
        [cabangId, batas],
      )
      .map((r) => RiwayatMasuk(
            id: r['id'] as String,
            noFaktur: r['no_faktur'] as String,
            supplier: r['supplier'] as String,
            dikirimPada: DateTime.parse(r['dikirim_pada'] as String),
            oleh: r['oleh'] as String,
            item: _db
                .pilih(
                  'SELECT i.id, i.jumlah, b.nama, b.satuan,'
                  ' (SELECT status FROM koreksi_barang_masuk k WHERE k.barang_masuk_item_id = i.id'
                  '  ORDER BY k.created_at DESC LIMIT 1) AS status_koreksi'
                  ' FROM barang_masuk_item i JOIN barang b ON b.id = i.barang_id WHERE i.barang_masuk_id = ?'
                  ' ORDER BY i.rowid',
                  [r['id']],
                )
                .map((i) => (
                      itemId: i['id'] as String,
                      nama: i['nama'] as String,
                      satuan: i['satuan'] as String,
                      jumlah: i['jumlah'] as int,
                      jumlahBerlaku: _jumlahBerlaku(i['id'] as String, i['jumlah'] as int),
                      statusKoreksi: i['status_koreksi'] as String?,
                    ))
                .toList(),
          ))
      .toList();

  /// Kasir minta koreksi jumlah. Disetujui/ditolak oleh SPV/Admin.
  String mintaKoreksi({required String itemId, required int jumlahBaru, required String alasan, required Pengguna oleh}) {
    if (jumlahBaru < 0) throw ArgumentError('Jumlah tidak boleh minus');
    if (alasan.trim().isEmpty) throw ArgumentError('Alasan wajib diisi');
    final it = _db.satu(
      'SELECT i.jumlah, bm.cabang_id FROM barang_masuk_item i JOIN barang_masuk bm ON bm.id = i.barang_masuk_id WHERE i.id = ?',
      [itemId],
    );
    if (it == null) throw ArgumentError('Barang tidak ditemukan');
    if (_db.satu("SELECT 1 FROM koreksi_barang_masuk WHERE barang_masuk_item_id = ? AND status = 'menunggu'", [itemId]) !=
        null) {
      throw StateError('Barang ini masih punya permintaan koreksi yang menunggu');
    }
    if (jumlahBaru == _jumlahBerlaku(itemId, it['jumlah'] as int)) throw ArgumentError('Jumlah baru sama dengan yang tercatat');
    final id = buatId();
    _db.transaksi(() {
      _db.jalankan(
        'INSERT INTO koreksi_barang_masuk (id, barang_masuk_item_id, jumlah_baru, alasan, diminta_oleh, created_at)'
        ' VALUES (?,?,?,?,?,?)',
        [id, itemId, jumlahBaru, alasan.trim(), oleh.id, _db.sekarangIso()],
      );
      _db.outbox('koreksi_barang_masuk', id);
      _db.log(cabangId: it['cabang_id'] as String, penggunaId: oleh.id, aksi: 'minta_koreksi', detail: {
        'item_id': itemId,
        'jumlah_baru': jumlahBaru,
        'alasan': alasan.trim(),
      });
    });
    return id;
  }

  List<Koreksi> daftarKoreksi(String cabangId, {bool hanyaMenunggu = false}) => _db
      .pilih(
        'SELECT k.*, bm.no_faktur, b.nama AS barang, i.jumlah, u.nama AS peminta FROM koreksi_barang_masuk k'
        ' JOIN barang_masuk_item i ON i.id = k.barang_masuk_item_id JOIN barang_masuk bm ON bm.id = i.barang_masuk_id'
        ' JOIN barang b ON b.id = i.barang_id JOIN pengguna u ON u.id = k.diminta_oleh'
        " WHERE bm.cabang_id = ? ${hanyaMenunggu ? "AND k.status = 'menunggu'" : ''} ORDER BY k.created_at DESC LIMIT 100",
        [cabangId],
      )
      .map((r) => Koreksi(
            id: r['id'] as String,
            noFaktur: r['no_faktur'] as String,
            namaBarang: r['barang'] as String,
            jumlahLama: r['jumlah'] as int,
            jumlahBaru: r['jumlah_baru'] as int,
            alasan: r['alasan'] as String,
            dimintaOleh: r['peminta'] as String,
            status: r['status'] as String,
            waktu: DateTime.parse(r['created_at'] as String),
          ))
      .toList();

  /// SPV/Admin menyetujui atau menolak. Disetujui → mutasi stok sebesar selisihnya.
  void putuskanKoreksi({required String koreksiId, required bool setuju, required Pengguna oleh}) {
    if (!bolehMenyetujui(oleh.peran)) throw StateError('Hanya SPV atau Admin');
    _db.transaksi(() {
      final k = _db.satu(
        'SELECT k.*, i.jumlah, i.barang_id, bm.cabang_id FROM koreksi_barang_masuk k'
        ' JOIN barang_masuk_item i ON i.id = k.barang_masuk_item_id JOIN barang_masuk bm ON bm.id = i.barang_masuk_id'
        ' WHERE k.id = ?',
        [koreksiId],
      );
      if (k == null) throw StateError('Koreksi tidak ditemukan');
      if (k['status'] != 'menunggu') throw StateError('Koreksi sudah diputuskan');
      final t = _db.sekarangIso();
      final berlaku = _jumlahBerlaku(k['barang_masuk_item_id'] as String, k['jumlah'] as int);
      _db.jalankan('UPDATE koreksi_barang_masuk SET status = ?, diputuskan_oleh = ?, diputuskan_pada = ? WHERE id = ?',
          [setuju ? 'disetujui' : 'ditolak', oleh.id, t, koreksiId]);
      _db.outbox('koreksi_barang_masuk', koreksiId);
      final selisih = (k['jumlah_baru'] as int) - berlaku;
      if (setuju && selisih != 0) {
        final mid = buatId();
        _db.jalankan(
          "INSERT INTO mutasi_stok (id, cabang_id, barang_id, jumlah, jenis, ref_id, dibuat_oleh, created_at)"
          " VALUES (?,?,?,?,'koreksi',?,?,?)",
          [mid, k['cabang_id'], k['barang_id'], selisih, koreksiId, oleh.id, t],
        );
        _db.outbox('mutasi_stok', mid);
      }
      _db.log(
        cabangId: k['cabang_id'] as String,
        penggunaId: k['diminta_oleh'] as String,
        disetujuiOleh: oleh.id,
        aksi: setuju ? 'koreksi_disetujui' : 'koreksi_ditolak',
        detail: {'koreksi_id': koreksiId, 'jumlah_sebelum': berlaku, 'jumlah_baru': k['jumlah_baru'], 'selisih': selisih},
      );
    });
  }

  // ---------------------------------------------------------------- stok opname

  /// SPV/Admin mencatat hasil hitung fisik. Selisih ditulis sebagai mutasi `opname`.
  int stokOpname({
    required String cabangId,
    required String barangId,
    required int stokFisik,
    required String alasan,
    required Pengguna oleh,
  }) {
    if (!bolehMenyetujui(oleh.peran)) throw StateError('Hanya SPV atau Admin');
    if (stokFisik < 0) throw ArgumentError('Stok fisik tidak boleh minus');
    return _db.transaksi(() {
      final sistem = _katalog.stok(barangId, cabangId);
      final selisih = stokFisik - sistem;
      if (selisih != 0) {
        final mid = buatId();
        _db.jalankan(
          "INSERT INTO mutasi_stok (id, cabang_id, barang_id, jumlah, jenis, ref_id, dibuat_oleh, created_at)"
          " VALUES (?,?,?,?,'opname',NULL,?,?)",
          [mid, cabangId, barangId, selisih, oleh.id, _db.sekarangIso()],
        );
        _db.outbox('mutasi_stok', mid);
      }
      _db.log(cabangId: cabangId, penggunaId: oleh.id, aksi: 'stok_opname', detail: {
        'barang_id': barangId,
        'stok_sistem': sistem,
        'stok_fisik': stokFisik,
        'selisih': selisih,
        'alasan': alasan.trim(),
      });
      return selisih;
    });
  }
}
