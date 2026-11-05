import 'package:pos_core/pos_core.dart';

import '../database.dart';
import 'pengaturan_repo.dart';
import 'pengguna_repo.dart';

const kategoriAwal = [
  'Sembako',
  'Snack',
  'Minuman',
  'Sabun & Sampo',
  'Bumbu dapur',
  'Kebutuhan bayi',
  'Rokok',
  'Lainnya',
];

/// Penyiapan pertama kali di PC toko: data cabang + akun Admin pertama.
class SetupRepo {
  SetupRepo(this._db);
  final DatabaseToko _db;

  Future<void> siapkan({
    required String namaToko,
    required String kodeCabang,
    required String namaCabang,
    required String alamat,
    required String pesanStruk,
    required String namaAdmin,
    required String namaPenggunaAdmin,
    required String sandiAdmin,
    required String rahasiaTotp,
    String? pinAdmin,
  }) async {
    final pengaturan = PengaturanRepo(_db);
    if (pengaturan.sudahDisiapkan) throw StateError('Toko ini sudah disiapkan');
    final kode = kodeCabang.trim().toUpperCase();
    if (!RegExp(r'^[A-Z0-9]{2,6}$').hasMatch(kode)) {
      throw ArgumentError('Kode cabang 2–6 huruf/angka, contoh A01');
    }
    if (namaToko.trim().isEmpty || namaCabang.trim().isEmpty) throw ArgumentError('Nama toko dan cabang wajib diisi');

    final cabangId = buatId();
    final t = _db.sekarangIso();
    _db.transaksi(() {
      _db.jalankan(
        'INSERT INTO cabang (id, kode, nama, alamat, pesan_struk, created_at, updated_at) VALUES (?,?,?,?,?,?,?)',
        [cabangId, kode, namaCabang.trim(), alamat.trim(), pesanStruk.trim(), t, t],
      );
      _db.outbox('cabang', cabangId);
      for (final k in kategoriAwal) {
        final id = buatId();
        _db.jalankan('INSERT INTO kategori (id, nama, created_at) VALUES (?,?,?)', [id, k, t]);
        _db.outbox('kategori', id);
      }
      final sup = buatId();
      _db.jalankan(
        "INSERT INTO supplier (id, nama, jenis, created_at) VALUES (?, 'Toko Utama', 'toko_utama', ?)",
        [sup, t],
      );
      _db.outbox('supplier', sup);
      pengaturan.simpan(PengaturanRepo.kNamaToko, namaToko.trim());
      pengaturan.simpan(PengaturanRepo.kCabangId, cabangId);
      pengaturan.simpanBool(PengaturanRepo.kCetakOtomatis, true);
    });
    await PenggunaRepo(_db).tambah(
      cabangId: cabangId,
      nama: namaAdmin,
      peran: Peran.admin,
      namaPengguna: namaPenggunaAdmin,
      sandi: sandiAdmin,
      rahasiaTotp: rahasiaTotp,
      pin: pinAdmin,
      olehId: null,
    );
  }
}
