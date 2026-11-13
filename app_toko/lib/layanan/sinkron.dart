import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pos_core/pos_core.dart';

import '../data/database.dart';
import '../data/repo/pengaturan_repo.dart';
import '../data/repo/sinkron_repo.dart';

// Klien HTTP ada di pos_core (dipakai juga Aplikasi Pusat). Nama lama tetap bisa dipakai.
typedef GalatSinkron = GalatServer;
typedef KlienPusat = KlienServer;

/// Sinkronisasi otomatis toko ⇄ pusat. Kasir tetap bisa berjualan saat internet putus:
/// data menunggu di outbox dan dikirim begitu tersambung lagi.
class LayananSinkron extends ChangeNotifier {
  LayananSinkron(this._db) : repo = SinkronRepo(_db), _pengaturan = PengaturanRepo(_db);

  final DatabaseToko _db;
  final SinkronRepo repo;
  final PengaturanRepo _pengaturan;
  static const jeda = Duration(minutes: 1);

  Timer? _timer;
  Future<void>? _berjalan;
  String? galatTerakhir;

  /// Data dari toko ini yang ditolak server (akan dicoba lagi).
  List<String> ditolakTerakhir = const [];

  /// Selisih jam PC ini dengan Server Pusat (positif = jam PC lebih cepat). null = belum diketahui.
  Duration? selisihJamServer;

  /// Data dari pusat yang tidak bisa diterapkan di toko ini (mis. barcode kembar).
  List<String> masalahTerakhir = const [];

  bool get terdaftar => _pengaturan.ambil(PengaturanRepo.kTokenPerangkat) != null && _pengaturan.ambil(PengaturanRepo.kServerUrl) != null;
  bool get sedangJalan => _berjalan != null;
  String? get alamatServer => _pengaturan.ambil(PengaturanRepo.kServerUrl);
  DateTime? get terakhirBerhasil => DateTime.tryParse(_pengaturan.ambil(PengaturanRepo.kSinkronTerakhir) ?? '');
  int get antrean => repo.jumlahAntrean();

  void mulai() {
    _timer?.cancel();
    if (!terdaftar) return;
    _timer = Timer.periodic(jeda, (_) => sinkronSekarang());
    unawaited(sinkronSekarang());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  KlienPusat _klien() => KlienPusat(KlienPusat.periksaAlamat(alamatServer!), token: _pengaturan.ambil(PengaturanRepo.kTokenPerangkat));

  /// Daftarkan PC ini ke Server Pusat dengan kode sekali pakai dari Admin pusat.
  Future<void> daftar({required String alamat, required String kode, required String namaPerangkat, required String olehId}) async {
    final dasar = KlienPusat.periksaAlamat(alamat);
    final cabangId = _pengaturan.ambil(PengaturanRepo.kCabangId)!;
    final cabang = Map<String, Object?>.from(_db.satu('SELECT * FROM cabang WHERE id = ?', [cabangId])!);
    final k = KlienPusat(dasar);
    try {
      final r = await k.minta('POST', '/api/perangkat/daftar', isi: {'kode': kode.trim(), 'nama_perangkat': namaPerangkat, 'cabang': cabang});
      _db.transaksi(() {
        _pengaturan.simpan(PengaturanRepo.kServerUrl, dasar.toString());
        _pengaturan.simpan(PengaturanRepo.kTokenPerangkat, r['token']! as String);
        _pengaturan.simpan(SinkronRepo.kKursor, '0');
        _db.log(cabangId: cabangId, penggunaId: olehId, aksi: 'perangkat_terdaftar', detail: {'server': dasar.host, 'perangkat': namaPerangkat});
      });
    } finally {
      k.tutup();
    }
    notifyListeners();
    mulai();
  }

  /// Ganti alamat server tanpa mendaftar ulang (server sama, alamat berbeda), mis. dari
  /// `http://localhost:3000` (server di PC ini) ke `http://192.168.1.10:3000` (PC kasir pindah ke komputer sendiri)
  /// atau ke alamat https tunnel. Alamat baru dicek dulu harus bisa dihubungi.
  Future<void> gantiAlamat({required String alamat, required String olehId}) async {
    if (!terdaftar) throw StateError('PC ini belum terdaftar ke kantor pusat');
    final dasar = KlienPusat.periksaAlamat(alamat);
    final k = KlienPusat(dasar);
    try {
      final r = await k.minta('GET', '/api/sehat');
      if (r['ok'] != true) throw const GalatSinkron('Alamat itu bukan Server POS');
    } finally {
      k.tutup();
    }
    final lama = alamatServer;
    final cabangId = _pengaturan.ambil(PengaturanRepo.kCabangId);
    _db.transaksi(() {
      _pengaturan.simpan(PengaturanRepo.kServerUrl, dasar.toString());
      _db.log(cabangId: cabangId, penggunaId: olehId, aksi: 'ganti_alamat_server', detail: {
        'lama': lama == null ? null : Uri.tryParse(lama)?.host,
        'baru': dasar.host,
      });
    });
    galatTerakhir = null;
    notifyListeners();
    mulai();
  }

  void lupakanServer() {
    _timer?.cancel();
    _pengaturan.simpan(PengaturanRepo.kTokenPerangkat, null);
    notifyListeners();
  }

  /// Kirim semua antrean, lalu ambil perubahan dari pusat. Kalau sedang berjalan, menunggu putaran yang sama.
  Future<void> sinkronSekarang() {
    if (!terdaftar) return Future.value();
    return _berjalan ??= _sinkron().whenComplete(() {
      _berjalan = null;
      notifyListeners();
    });
  }

  Future<void> _sinkron() async {
    notifyListeners();
    KlienPusat? k;
    try {
      k = _klien();
      // 1. kirim
      for (var putaran = 0; putaran < 50; putaran++) {
        final item = repo.antrean();
        if (item.isEmpty) break;
        final r = await k.minta('POST', '/api/sinkron/kirim', isi: {'item': [for (final i in item) i.keJson()]});
        final diterima = (r['diterima'] as List).cast<String>();
        final ditolak = [for (final d in (r['ditolak'] as List)) (d as Map)['id'] as String];
        repo.tandaiHasil(diterima: diterima, ditolak: ditolak);
        ditolakTerakhir = [for (final d in (r['ditolak'] as List)) '${(d as Map)['alasan']}'];
        if (diterima.isEmpty) break; // semua ditolak: coba lagi nanti, jangan berputar terus
      }
      // 2. ambil
      final cabangId = _pengaturan.ambil(PengaturanRepo.kCabangId)!;
      for (var putaran = 0; putaran < 50; putaran++) {
        final r = await k.minta('GET', '/api/sinkron/ambil', query: {'sejak': '${repo.kursor}'});
        final waktuServer = DateTime.tryParse(r['waktu'] as String? ?? '');
        if (waktuServer != null) selisihJamServer = DateTime.now().toUtc().difference(waktuServer);
        final perubahan = [for (final p in (r['perubahan'] as List)) Map<String, Object?>.from(p as Map)];
        final h = repo.terapkan(perubahan, kursorBaru: (r['kursor'] as num).toInt(), cabangId: cabangId);
        if (h.masalah.isNotEmpty) masalahTerakhir = h.masalah;
        if (r['masih_ada'] != true) break;
      }
      _pengaturan.simpan(PengaturanRepo.kSinkronTerakhir, DateTime.now().toUtc().toIso8601String());
      galatTerakhir = null;
    } on GalatSinkron catch (e) {
      galatTerakhir = e.pesan;
      if (e.status == 401) galatTerakhir = '${e.pesan}. Daftarkan ulang PC ini di Pengaturan.';
    } catch (e) {
      galatTerakhir = 'Sinkronisasi gagal: $e';
    } finally {
      k?.tutup();
    }
  }
}
