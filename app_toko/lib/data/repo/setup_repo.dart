import 'package:pos_core/pos_core.dart';

import '../database.dart';
import 'pengaturan_repo.dart';
import 'pengguna_repo.dart';

/// Kategori bawaan. Id-nya TETAP (UUID v4 yang dibuat sekali dan ditulis di sini) supaya kategori
/// "Sembako" di semua toko adalah baris yang sama di Server Pusat, bukan 8 baris kembar per toko.
const kategoriAwal = {
  'Sembako': '0d5135fa-5e1e-4bfd-9654-bdb975b35d70',
  'Snack': 'fcdf57a3-a925-4982-b43a-47108d5b4545',
  'Minuman': '10a955a3-4652-46f5-90ef-6bb37985868c',
  'Sabun & Sampo': '101f8030-3a70-418a-aa76-678139254423',
  'Bumbu dapur': '732df61d-a055-48b4-a035-3aca2ff04f14',
  'Kebutuhan bayi': '80a99928-3446-405a-8403-4587508dcb52',
  'Rokok': '1e9c5874-51fb-446b-be1f-f0efb66cf153',
  'Lainnya': '93a8925d-8f75-4454-b629-9eabb666d0a3',
};

/// Supplier "Toko Utama" juga satu baris yang sama untuk semua toko.
const idSupplierTokoUtama = '8254c626-ad4e-41d7-9ad5-7e75b656ace4';

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
      for (final MapEntry(key: nama, value: id) in kategoriAwal.entries) {
        _db.jalankan('INSERT INTO kategori (id, nama, created_at) VALUES (?,?,?)', [id, nama, t]);
        _db.outbox('kategori', id);
      }
      const sup = idSupplierTokoUtama;
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
