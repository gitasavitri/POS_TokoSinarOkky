import 'package:pos_core/pos_core.dart';

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

  /// Modal tetap toko (revisi P): uang yang tetap di kasir saat shift ditutup "Belum dihitung"
  /// dan isian awal modal saat buka shift. 0 = tidak dipakai.
  static const kModalTetap = 'modal_tetap';

  /// Tulisan opsional di kepala struk (revisi struk): khusus PC ini, tidak disinkronkan.
  static const kStrukTelepon = 'struk_telepon';
  static const kStrukTambahan = 'struk_tambahan';

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

  int get modalTetap => ambilInt(kModalTetap);

  /// Admin mengatur modal tetap toko. Tercatat di log.
  void aturModalTetap(int nilai, {required String cabangId, required Pengguna oleh}) {
    if (aksesUntuk(oleh.peran, Izin.aturModalTetap) != Akses.ya) throw StateError('Modal tetap hanya bisa diatur Admin.');
    if (nilai < 0) throw ArgumentError('Modal tetap tidak boleh minus');
    _db.transaksi(() {
      final lama = modalTetap;
      simpan(kModalTetap, '$nilai');
      _db.log(cabangId: cabangId, penggunaId: oleh.id, aksi: 'atur_modal_tetap', detail: {'lama': lama, 'baru': nilai});
    });
  }

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
      telepon: ambil(kStrukTelepon) ?? '',
      tambahan: ambil(kStrukTambahan) ?? '',
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
    String telepon = '',
    String tambahan = '',
  }) {
    for (final teks in [pesanStruk, tambahan]) {
      final galat = cekPesanStruk(teks);
      if (galat != null) throw ArgumentError(galat);
    }
    _db.transaksi(() {
      _db.jalankan(
        'UPDATE cabang SET nama = ?, alamat = ?, pesan_struk = ?, updated_at = ? WHERE id = ?',
        [nama.trim(), alamat.trim(), pesanStruk.trim(), _db.sekarangIso(), cabangId],
      );
      simpan(kNamaToko, namaToko.trim());
      final tel = telepon.trim();
      final tam = tambahan.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).join('\n');
      simpan(kStrukTelepon, tel.isEmpty ? null : tel);
      simpan(kStrukTambahan, tam.isEmpty ? null : tam);
      _db.outbox('cabang', cabangId);
      _db.log(cabangId: cabangId, penggunaId: olehId, aksi: 'ubah_info_cabang', detail: {'nama': nama});
    });
  }
}
