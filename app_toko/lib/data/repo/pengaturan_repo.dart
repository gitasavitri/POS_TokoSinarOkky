import '../database.dart';
import '../model.dart';

/// Pengaturan khusus PC ini (tabel `pengaturan_perangkat`) dan info cabang.
class PengaturanRepo {
  PengaturanRepo(this._db);
  final DatabaseToko _db;

  static const kCabangId = 'cabang_id';
  static const kNamaToko = 'nama_toko';
  static const kPrinter = 'printer_nama';
  static const kCetakOtomatis = 'cetak_otomatis';
  static const kPotongKertas = 'potong_kertas';
  static const kSalinanStruk = 'salinan_struk';
  static const kDraftBarangMasuk = 'draft_barang_masuk';
  static const kAntreanLabel = 'antrean_label';
  static const kServerUrl = 'server_url';
  static const kTokenPerangkat = 'token_perangkat';
  static const kSinkronTerakhir = 'sinkron_terakhir';
  static const kFolderCadangan2 = 'folder_cadangan_kedua';
  static const kCadanganTerakhir = 'cadangan_terakhir';

  String? ambil(String kunci) =>
      _db.satu('SELECT nilai FROM pengaturan_perangkat WHERE kunci = ?', [kunci])?['nilai'] as String?;

  void simpan(String kunci, String? nilai) {
    if (nilai == null) {
      _db.jalankan('DELETE FROM pengaturan_perangkat WHERE kunci = ?', [kunci]);
    } else {
      _db.jalankan(
        'INSERT INTO pengaturan_perangkat (kunci, nilai) VALUES (?, ?)'
        ' ON CONFLICT(kunci) DO UPDATE SET nilai = excluded.nilai',
        [kunci, nilai],
      );
    }
  }

  bool ambilBool(String kunci, {bool bawaan = false}) {
    final v = ambil(kunci);
    return v == null ? bawaan : v == '1';
  }

  void simpanBool(String kunci, bool nilai) => simpan(kunci, nilai ? '1' : '0');

  int ambilInt(String kunci, {int bawaan = 0}) => int.tryParse(ambil(kunci) ?? '') ?? bawaan;

  bool get sudahDisiapkan => ambil(kCabangId) != null;

  InfoCabang? infoCabang() {
    final id = ambil(kCabangId);
    if (id == null) return null;
    final r = _db.satu('SELECT * FROM cabang WHERE id = ?', [id]);
    if (r == null) return null;
    return InfoCabang(
      id: id,
      kode: r['kode'] as String,
      nama: r['nama'] as String,
      alamat: r['alamat'] as String,
      pesanStruk: r['pesan_struk'] as String,
      namaToko: ambil(kNamaToko) ?? 'Toko',
    );
  }

  /// Ubah alamat & pesan struk (Admin).
  void ubahInfoCabang({
    required String cabangId,
    required String nama,
    required String alamat,
    required String pesanStruk,
    required String namaToko,
    required String olehId,
  }) {
    _db.transaksi(() {
      _db.jalankan(
        'UPDATE cabang SET nama = ?, alamat = ?, pesan_struk = ?, updated_at = ? WHERE id = ?',
        [nama.trim(), alamat.trim(), pesanStruk.trim(), _db.sekarangIso(), cabangId],
      );
      simpan(kNamaToko, namaToko.trim());
      _db.outbox('cabang', cabangId);
      _db.log(cabangId: cabangId, penggunaId: olehId, aksi: 'ubah_info_cabang', detail: {'nama': nama});
    });
  }
}
