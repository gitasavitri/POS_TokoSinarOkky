import 'dart:convert';

import '../database.dart';
import 'pengaturan_repo.dart';

/// Satu baris outbox yang siap dikirim ke Server Pusat.
class ItemOutbox {
  const ItemOutbox({required this.id, required this.tabel, required this.barisId, required this.payload, required this.createdAt});
  final String id;
  final String tabel;
  final String barisId;
  final String payload;
  final String createdAt;

  Map<String, Object?> keJson() => {'id': id, 'tabel': tabel, 'baris_id': barisId, 'payload': payload, 'created_at': createdAt};
}

/// Hasil menerapkan perubahan dari pusat.
class HasilTerap {
  int diterapkan = 0;
  int dilewati = 0;

  /// Baris yang tidak bisa diterapkan (mis. barcode sudah dipakai barang lain di toko ini).
  final List<String> masalah = [];
}

/// Antrean kirim (outbox) dan penerapan data dari pusat ke database toko.
class SinkronRepo {
  SinkronRepo(this._db) : _pengaturan = PengaturanRepo(_db);
  final DatabaseToko _db;
  final PengaturanRepo _pengaturan;

  static const kKursor = 'sinkron_kursor';
  static const kGalat = 'sinkron_galat';

  // ---------------------------------------------------------------- kirim

  /// Item yang belum terkirim, urut sesuai waktu dibuat (rowid). Rahasia TOTP tidak pernah ikut terkirim.
  List<ItemOutbox> antrean({int batas = 200}) => _db
      .pilih('SELECT id, tabel, baris_id, payload, created_at FROM outbox WHERE terkirim_pada IS NULL ORDER BY rowid LIMIT ?', [batas])
      .map((r) {
        var payload = r['payload'] as String;
        if (r['tabel'] == 'pengguna') {
          final m = jsonDecode(payload) as Map<String, Object?>..remove('totp_secret');
          payload = jsonEncode(m);
        }
        return ItemOutbox(
          id: r['id'] as String,
          tabel: r['tabel'] as String,
          barisId: r['baris_id'] as String,
          payload: payload,
          createdAt: r['created_at'] as String,
        );
      })
      .toList();

  int jumlahAntrean() => _db.satu('SELECT COUNT(*) AS n FROM outbox WHERE terkirim_pada IS NULL')!['n'] as int;

  /// Item yang sudah gagal berkali-kali (perlu dicek).
  int jumlahBermasalah() => _db.satu('SELECT COUNT(*) AS n FROM outbox WHERE terkirim_pada IS NULL AND percobaan >= 5')!['n'] as int;

  void tandaiHasil({required List<String> diterima, required List<String> ditolak}) {
    final t = _db.sekarangIso();
    _db.transaksi(() {
      for (final id in diterima) {
        _db.jalankan('UPDATE outbox SET terkirim_pada = ? WHERE id = ? AND terkirim_pada IS NULL', [t, id]);
      }
      for (final id in ditolak) {
        _db.jalankan('UPDATE outbox SET percobaan = percobaan + 1 WHERE id = ?', [id]);
      }
    });
  }

  // ---------------------------------------------------------------- ambil

  int get kursor => _pengaturan.ambilInt(kKursor);

  final _kolom = <String, Set<String>>{};
  Set<String> _kolomTabel(String tabel) =>
      _kolom.putIfAbsent(tabel, () => _db.pilih('PRAGMA table_info($tabel)').map((r) => r['name'] as String).toSet());

  /// Terapkan perubahan dari pusat dalam satu transaksi, lalu simpan kursor baru.
  /// Perubahan dari pusat TIDAK ditulis ke outbox (supaya tidak dikirim balik).
  HasilTerap terapkan(List<Map<String, Object?>> perubahan, {required int kursorBaru, required String cabangId}) {
    final hasil = HasilTerap();
    _db.transaksi(() {
      for (final p in perubahan) {
        final tabel = p['tabel'] as String;
        final baris = Map<String, Object?>.from(p['baris']! as Map);
        _db.jalankan('SAVEPOINT baris');
        try {
          final ok = _terapkanBaris(tabel, baris, cabangId, hasil);
          _db.jalankan('RELEASE baris');
          ok ? hasil.diterapkan++ : hasil.dilewati++;
        } catch (e) {
          _db.jalankan('ROLLBACK TO baris');
          _db.jalankan('RELEASE baris');
          hasil.dilewati++;
          hasil.masalah.add('$tabel ${baris['id'] ?? ''}: $e');
        }
      }
      _pengaturan.simpan(kKursor, '$kursorBaru');
    });
    return hasil;
  }

  bool _terapkanBaris(String tabel, Map<String, Object?> b, String cabangId, HasilTerap hasil) {
    switch (tabel) {
      case 'cabang':
        if (b['id'] != cabangId) return false;
        return _upsertTerbaru('cabang', b, ['id']);
      case 'pengguna':
        // Admin pusat disimpan hanya sebagai nama pembuat harga; tidak bisa dipakai masuk di toko.
        if (b['cabang_id'] == null) {
          b['nama_pengguna'] = 'pusat:${b['nama_pengguna'] ?? b['id']}';
          b['sandi_hash'] = '!';
          b['pin_hash'] = null;
          b['totp_secret'] = null;
        } else if (b['cabang_id'] != cabangId) {
          return false;
        }
        return _upsertTerbaru('pengguna', b, ['id']);
      case 'kategori':
        if (_ada('kategori', 'id', b['id'])) return false;
        if (_db.satu('SELECT 1 FROM kategori WHERE nama = ?', [b['nama']]) != null) return false; // nama sama, id lain
        _insert('kategori', b);
        return true;
      case 'barang':
        b['kategori_id'] = _kategoriLokal(b);
        final barcode = b['barcode'];
        if (barcode != null) {
          final lain = _db.satu('SELECT id, nama FROM barang WHERE barcode = ? AND id <> ?', [barcode, b['id']]);
          if (lain != null) {
            hasil.masalah.add('Barcode $barcode dari pusat ("${b['nama']}") sudah dipakai "${lain['nama']}" di toko ini');
            return false;
          }
        }
        return _upsertTerbaru('barang', b, ['id']);
      case 'barang_cabang':
        if (b['cabang_id'] != cabangId) return false;
        return _upsertTerbaru('barang_cabang', b, ['cabang_id', 'barang_id']);
      case 'harga_jual':
        if (b['cabang_id'] != null && b['cabang_id'] != cabangId) return false;
        if (_ada('harga_jual', 'id', b['id'])) return false;
        _insert('harga_jual', b);
        return true;
      case 'harga_grosir':
        if (_ada('harga_grosir', 'id', b['id'])) return false;
        _insert('harga_grosir', b);
        return true;
      default:
        return false;
    }
  }

  /// Kategori barang dari pusat: pakai id yang sama kalau ada, kalau tidak cocokkan nama, kalau tidak ada buat baru.
  String _kategoriLokal(Map<String, Object?> b) {
    final id = b['kategori_id'] as String;
    if (_ada('kategori', 'id', id)) return id;
    final nama = (b['kategori_nama'] as String?) ?? 'Lainnya';
    final sama = _db.satu('SELECT id FROM kategori WHERE nama = ?', [nama]);
    if (sama != null) return sama['id'] as String;
    _db.jalankan('INSERT INTO kategori (id, nama, created_at) VALUES (?,?,?)', [id, nama, _db.sekarangIso()]);
    return id;
  }

  bool _ada(String tabel, String kolom, Object? nilai) => _db.satu('SELECT 1 FROM $tabel WHERE $kolom = ?', [nilai]) != null;

  void _insert(String tabel, Map<String, Object?> b) {
    final kolom = _kolomTabel(tabel);
    final k = b.keys.where(kolom.contains).toList();
    _db.jalankan('INSERT INTO $tabel (${k.join(', ')}) VALUES (${List.filled(k.length, '?').join(', ')})', [for (final x in k) b[x]]);
  }

  /// Simpan baris master; kalau sudah ada, hanya ditimpa jika updated_at dari pusat lebih baru.
  bool _upsertTerbaru(String tabel, Map<String, Object?> b, List<String> kunci) {
    final where = kunci.map((k) => '$k = ?').join(' AND ');
    final lama = _db.satu('SELECT updated_at FROM $tabel WHERE $where', [for (final k in kunci) b[k]]);
    if (lama == null) {
      _insert(tabel, b);
      return true;
    }
    if (((b['updated_at'] as String?) ?? '').compareTo(lama['updated_at'] as String) <= 0) return false;
    final kolom = _kolomTabel(tabel);
    final ubah = b.keys.where((k) => kolom.contains(k) && !kunci.contains(k)).toList();
    _db.jalankan(
      'UPDATE $tabel SET ${ubah.map((k) => '$k = ?').join(', ')} WHERE $where',
      [for (final k in ubah) b[k], for (final k in kunci) b[k]],
    );
    return true;
  }
}
