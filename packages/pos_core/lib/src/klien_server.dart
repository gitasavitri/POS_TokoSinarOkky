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

  /// Alamat server wajib HTTPS, kecuali localhost (untuk uji coba).
  static Uri periksaAlamat(String alamat) {
    final u = Uri.tryParse(alamat.trim().replaceAll(RegExp(r'/+$'), ''));
    if (u == null || !u.hasScheme || u.host.isEmpty) throw const GalatServer('Alamat server tidak valid, contoh: https://pos.tokoanda.com');
    final lokal = u.host == 'localhost' || u.host == '127.0.0.1';
    if (u.scheme != 'https' && !(lokal && u.scheme == 'http')) {
      throw const GalatServer('Alamat server harus diawali https:// supaya data terenkripsi');
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
