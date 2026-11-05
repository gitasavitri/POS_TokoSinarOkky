import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../data/database.dart';
import '../data/repo/pengaturan_repo.dart';
import '../data/repo/sinkron_repo.dart';

/// Galat dari Server Pusat atau jaringan. [pesan] aman ditampilkan ke pengguna.
class GalatSinkron implements Exception {
  const GalatSinkron(this.pesan, {this.status});
  final String pesan;
  final int? status;
  @override
  String toString() => pesan;
}

/// Klien HTTP sederhana ke Server Pusat (tanpa paket tambahan, memakai dart:io).
class KlienPusat {
  KlienPusat(this.dasar, {this.token, HttpClient? http}) : _http = http ?? (HttpClient()..connectionTimeout = const Duration(seconds: 15));

  final Uri dasar;
  final String? token;
  final HttpClient _http;

  /// Alamat server wajib HTTPS, kecuali localhost (untuk uji coba).
  static Uri periksaAlamat(String alamat) {
    final u = Uri.tryParse(alamat.trim().replaceAll(RegExp(r'/+$'), ''));
    if (u == null || !u.hasScheme || u.host.isEmpty) throw const GalatSinkron('Alamat server tidak valid, contoh: https://pos.tokoanda.com');
    final lokal = u.host == 'localhost' || u.host == '127.0.0.1';
    if (u.scheme != 'https' && !(lokal && u.scheme == 'http')) {
      throw const GalatSinkron('Alamat server harus diawali https:// supaya data terenkripsi');
    }
    return u;
  }

  Future<Map<String, Object?>> minta(String metode, String jalur, {Object? isi, Map<String, String>? query}) async {
    final uri = dasar.replace(path: '${dasar.path}$jalur', queryParameters: query);
    try {
      final req = await _http.openUrl(metode, uri).timeout(const Duration(seconds: 20));
      req.headers.contentType = ContentType.json;
      if (token != null) req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      if (isi != null) req.add(utf8.encode(jsonEncode(isi)));
      final res = await req.close().timeout(const Duration(seconds: 60));
      final teks = await utf8.decodeStream(res);
      final Object? json = teks.isEmpty ? null : jsonDecode(teks);
      if (res.statusCode >= 400) {
        final pesan = json is Map && json['galat'] is String ? json['galat'] as String : 'Server menjawab ${res.statusCode}';
        throw GalatSinkron(pesan, status: res.statusCode);
      }
      return json is Map<String, Object?> ? json : {'data': json};
    } on GalatSinkron {
      rethrow;
    } on TimeoutException {
      throw const GalatSinkron('Server Pusat tidak menjawab (internet lambat atau putus)');
    } on SocketException {
      throw const GalatSinkron('Tidak tersambung ke Server Pusat (internet putus?)');
    } on HandshakeException {
      throw const GalatSinkron('Sertifikat HTTPS server tidak valid');
    } on FormatException {
      throw const GalatSinkron('Jawaban server tidak bisa dibaca');
    }
  }

  void tutup() => _http.close(force: true);
}

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
