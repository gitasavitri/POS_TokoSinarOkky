import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Galat dari Server Pusat atau jaringan. [pesan] aman ditampilkan ke pengguna.
class GalatServer implements Exception {
  const GalatServer(this.pesan, {this.status});
  final String pesan;
  final int? status;
  @override
  String toString() => pesan;
}

/// Klien HTTP sederhana ke Server Pusat (tanpa paket tambahan, memakai dart:io).
/// Dipakai Aplikasi Toko (sinkronisasi) dan Aplikasi Pusat (laporan, harga).
class KlienServer {
  KlienServer(this.dasar, {this.token, HttpClient? http}) : _http = http ?? (HttpClient()..connectionTimeout = const Duration(seconds: 15));

  final Uri dasar;
  final String? token;
  final HttpClient _http;

  /// Alamat server wajib HTTPS, kecuali server di PC ini (localhost) atau di jaringan lokal toko
  /// (IP 192.168.x.x, 10.x.x.x, 172.16–31.x.x), mis. PC kasir kedua yang tersambung ke PC server lewat kabel/WiFi toko.
  /// Dari luar toko (rumah, cabang lain) tetap wajib https (lewat tunnel/domain).
  static Uri periksaAlamat(String alamat) {
    final u = Uri.tryParse(alamat.trim().replaceAll(RegExp(r'/+$'), ''));
    if (u == null || !u.hasScheme || u.host.isEmpty) throw const GalatServer('Alamat server tidak valid, contoh: https://pos.tokoanda.com');
    if (u.scheme != 'https' && !(u.scheme == 'http' && alamatLokal(u.host))) {
      throw const GalatServer('Alamat server harus diawali https:// supaya data terenkripsi '
          '(http:// hanya boleh untuk server di PC ini atau di jaringan lokal toko, mis. http://192.168.1.10:3000)');
    }
    return u;
  }

  /// localhost atau alamat IPv4 jaringan lokal (privat).
  static bool alamatLokal(String host) {
    if (host == 'localhost' || host == '127.0.0.1') return true;
    final m = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$').firstMatch(host);
    if (m == null) return false;
    final b = [for (var i = 1; i <= 4; i++) int.parse(m.group(i)!)];
    if (b.any((x) => x > 255)) return false;
    return b[0] == 10 || (b[0] == 192 && b[1] == 168) || (b[0] == 172 && b[1] >= 16 && b[1] <= 31);
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
        throw GalatServer(pesan, status: res.statusCode);
      }
      return json is Map<String, Object?> ? json : {'data': json};
    } on GalatServer {
      rethrow;
    } on TimeoutException {
      throw const GalatServer('Server Pusat tidak menjawab (internet lambat atau putus)');
    } on SocketException {
      throw const GalatServer('Tidak tersambung ke Server Pusat (internet putus?)');
    } on HandshakeException {
      throw const GalatServer('Sertifikat HTTPS server tidak valid');
    } on FormatException {
      throw const GalatServer('Jawaban server tidak bisa dibaca');
    }
  }

  void tutup() => _http.close(force: true);
}
