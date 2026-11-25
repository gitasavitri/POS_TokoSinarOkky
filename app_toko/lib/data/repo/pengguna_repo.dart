import 'package:pos_core/pos_core.dart';

import '../database.dart';
import '../model.dart';

/// Batas salah PIN berturut-turut sebelum akun terkunci.
const batasSalahPin = 5;

class PenggunaRepo {
  PenggunaRepo(this._db);
  final DatabaseToko _db;

  Pengguna _dariBaris(Map<String, Object?> r) => Pengguna(
        id: r['id']! as String,
        nama: r['nama']! as String,
        peran: Peran.dariKode(r['peran']! as String),
        cabangId: r['cabang_id'] as String?,
        namaPengguna: r['nama_pengguna'] as String?,
        terkunci: r['terkunci'] == 1,
        aktif: r['aktif'] == 1,
      );

  /// Kasir & SPV aktif di cabang ini, untuk layar Masuk.
  List<Pengguna> daftarLoginPin(String cabangId) => _db
      .pilih(
        "SELECT * FROM pengguna WHERE cabang_id = ? AND aktif = 1 AND peran IN ('kasir','spv') ORDER BY nama",
        [cabangId],
      )
      .map(_dariBaris)
      .toList();

  /// SPV & Admin yang bisa menyetujui di cabang ini (Admin pusat = cabang_id NULL ikut).
  List<Pengguna> daftarPenyetuju(String cabangId) => _db
      .pilih(
        "SELECT * FROM pengguna WHERE aktif = 1 AND terkunci = 0 AND pin_hash IS NOT NULL"
        " AND peran IN ('spv','admin') AND (cabang_id = ? OR cabang_id IS NULL) ORDER BY peran DESC, nama",
        [cabangId],
      )
      .map(_dariBaris)
      .toList();

  /// Semua pengguna (untuk halaman Karyawan).
  List<Pengguna> semua(String cabangId) => _db
      .pilih(
        'SELECT * FROM pengguna WHERE cabang_id = ? OR cabang_id IS NULL ORDER BY aktif DESC, peran, nama',
        [cabangId],
      )
      .map(_dariBaris)
      .toList();

  Pengguna? ambil(String id) {
    final r = _db.satu('SELECT * FROM pengguna WHERE id = ?', [id]);
    return r == null ? null : _dariBaris(r);
  }

  /// Login kasir/SPV dengan PIN. Salah 5 kali berturut-turut → terkunci.
  Future<HasilLogin> masukPin(String penggunaId, String pin) async {
    final r = _db.satu('SELECT * FROM pengguna WHERE id = ? AND aktif = 1', [penggunaId]);
    if (r == null) return HasilLogin.gagal('Pengguna tidak ditemukan.');
    final p = _dariBaris(r);
    if (p.terkunci) {
      return HasilLogin.gagal('Akun terkunci. Minta Admin membuka kunci.', terkunci: true);
    }
    final hash = r['pin_hash'] as String?;
    final cocok = hash != null && await cocokkanHash(pin, hash);
    return _catatHasil(p, cocok, 'login_pin');
  }

  /// Login Admin: nama pengguna + kata sandi + kode verifikasi (TOTP).
  Future<HasilLogin> masukAdmin(String namaPengguna, String sandi, String kodeTotp) async {
    final r = _db.satu(
      "SELECT * FROM pengguna WHERE nama_pengguna = ? AND aktif = 1 AND peran = 'admin'",
      [namaPengguna.trim()],
    );
    if (r == null) return HasilLogin.gagal('Nama pengguna atau kata sandi salah.');
    final p = _dariBaris(r);
    if (p.terkunci) return HasilLogin.gagal('Akun terkunci.', terkunci: true);
    final sandiCocok = await cocokkanHash(sandi, r['sandi_hash']! as String);
    final rahasia = r['totp_secret'] as String?;
    final totpCocok = rahasia != null && await cocokkanTotp(rahasia, kodeTotp, _db.sekarang());
    final h = _catatHasil(p, sandiCocok && totpCocok, 'login_admin');
    if (!h.berhasil && sandiCocok && !totpCocok && !h.terkunci) {
      return HasilLogin.gagal('Kode verifikasi salah. Cek jam di HP dan PC.');
    }
    if (!h.berhasil && !h.terkunci) return HasilLogin.gagal('Nama pengguna atau kata sandi salah.');
    return h;
  }

  HasilLogin _catatHasil(Pengguna p, bool cocok, String aksi) {
    return _db.transaksi(() {
      if (cocok) {
        _db.jalankan('UPDATE pengguna SET gagal_login = 0 WHERE id = ?', [p.id]);
        _db.log(cabangId: p.cabangId, penggunaId: p.id, aksi: '${aksi}_berhasil');
        return HasilLogin.berhasil(p);
      }
      _db.jalankan('UPDATE pengguna SET gagal_login = gagal_login + 1 WHERE id = ?', [p.id]);
      final gagal = _db.satu('SELECT gagal_login FROM pengguna WHERE id = ?', [p.id])!['gagal_login']! as int;
      if (gagal >= batasSalahPin) {
        _db.jalankan('UPDATE pengguna SET terkunci = 1, updated_at = ? WHERE id = ?', [_db.sekarangIso(), p.id]);
        _db.log(cabangId: p.cabangId, penggunaId: p.id, aksi: 'akun_terkunci', detail: {'gagal': gagal});
        _db.outbox('pengguna', p.id);
        return HasilLogin.gagal('Salah $batasSalahPin kali. Akun terkunci, minta Admin membuka kunci.',
            terkunci: true);
      }
      _db.log(cabangId: p.cabangId, penggunaId: p.id, aksi: '${aksi}_gagal', detail: {'gagal': gagal});
      final sisa = batasSalahPin - gagal;
      return HasilLogin.gagal('PIN salah. Sisa $sisa kali percobaan.');
    });
  }

  /// Persetujuan PIN SPV/Admin di layar yang sama. Tidak menambah hitungan kunci akun penyetuju
  /// kecuali PIN salah.
  Future<Pengguna?> setujuiDenganPin(String penyetujuId, String pin) async {
    final h = await masukPin(penyetujuId, pin);
    final p = h.pengguna;
    if (p == null || !bolehMenyetujui(p.peran)) return null;
    return p;
  }

  /// Tambah kasir/SPV (pakai PIN) atau Admin (pakai kata sandi + TOTP). Hanya Admin.
  Future<String> tambah({
    required String? cabangId,
    required String nama,
    required Peran peran,
    String? pin,
    String? namaPengguna,
    String? sandi,
    String? rahasiaTotp,
    required String? olehId,
  }) async {
    if (nama.trim().isEmpty) throw ArgumentError('Nama wajib diisi');
    String? pinHash, sandiHash;
    if (peran == Peran.admin) {
      final e = periksaKataSandi(sandi ?? '');
      if (e != null) throw ArgumentError(e);
      if ((namaPengguna ?? '').trim().isEmpty) throw ArgumentError('Nama pengguna wajib diisi');
      if (rahasiaTotp == null) throw ArgumentError('Kode verifikasi belum disiapkan');
      sandiHash = await buatHash(sandi!);
      if (pin != null && pin.isNotEmpty) {
        final ep = periksaPin(pin);
        if (ep != null) throw ArgumentError(ep);
        pinHash = await buatHash(pin);
      }
    } else {
      final e = periksaPin(pin ?? '');
      if (e != null) throw ArgumentError(e);
      pinHash = await buatHash(pin!);
    }
    final id = buatId();
    final t = _db.sekarangIso();
    _db.transaksi(() {
      _db.jalankan(
        'INSERT INTO pengguna (id, cabang_id, nama, nama_pengguna, peran, pin_hash, sandi_hash, totp_secret,'
        ' created_at, updated_at) VALUES (?,?,?,?,?,?,?,?,?,?)',
        [id, cabangId, nama.trim(), namaPengguna?.trim(), peran.kode, pinHash, sandiHash, rahasiaTotp, t, t],
      );
      _db.outbox('pengguna', id);
      _db.log(
          cabangId: cabangId, penggunaId: olehId, aksi: 'tambah_pengguna', detail: {'nama': nama, 'peran': peran.kode});
    });
    return id;
  }

  Future<void> gantiPin(String penggunaId, String pinBaru, {required String olehId}) async {
    final e = periksaPin(pinBaru);
    if (e != null) throw ArgumentError(e);
    final h = await buatHash(pinBaru);
    _db.transaksi(() {
      _db.jalankan(
        'UPDATE pengguna SET pin_hash = ?, gagal_login = 0, terkunci = 0, updated_at = ? WHERE id = ?',
        [h, _db.sekarangIso(), penggunaId],
      );
      final p = ambil(penggunaId)!;
      _db.outbox('pengguna', penggunaId);
      _db.log(cabangId: p.cabangId, penggunaId: olehId, aksi: 'ganti_pin', detail: {'untuk': p.nama});
    });
  }

  void bukaKunci(String penggunaId, {required String olehId}) => _db.transaksi(() {
        _db.jalankan('UPDATE pengguna SET terkunci = 0, gagal_login = 0, updated_at = ? WHERE id = ?',
            [_db.sekarangIso(), penggunaId]);
        final p = ambil(penggunaId)!;
        _db.outbox('pengguna', penggunaId);
        _db.log(cabangId: p.cabangId, penggunaId: olehId, aksi: 'buka_kunci', detail: {'untuk': p.nama});
      });

  void aturAktif(String penggunaId, bool aktif, {required String olehId}) => _db.transaksi(() {
        _db.jalankan('UPDATE pengguna SET aktif = ?, updated_at = ? WHERE id = ?',
            [aktif ? 1 : 0, _db.sekarangIso(), penggunaId]);
        final p = ambil(penggunaId)!;
        _db.outbox('pengguna', penggunaId);
        _db.log(
            cabangId: p.cabangId,
            penggunaId: olehId,
            aksi: aktif ? 'aktifkan_pengguna' : 'nonaktifkan_pengguna',
            detail: {'untuk': p.nama});
      });
}
