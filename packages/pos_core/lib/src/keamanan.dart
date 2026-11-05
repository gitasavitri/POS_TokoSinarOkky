/// Hash PIN/kata sandi (Argon2id, format PHC) dan kode verifikasi TOTP untuk Admin.
/// PIN dan kata sandi tidak pernah disimpan atau dicatat dalam bentuk asli.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// UUID v4 untuk semua ID di database.
String buatId() => _uuid.v4();

// Parameter Argon2id. Sengaja sedang supaya tetap cepat di PC kasir biasa.
const _memoriKiB = 8192;
const _iterasi = 3;
const _paralel = 1;
const _panjangHash = 32;

final _acak = Random.secure();

String _b64(List<int> b) => base64.encode(b).replaceAll('=', '');
List<int> _unb64(String s) => base64.decode(s.padRight((s.length + 3) ~/ 4 * 4, '='));

/// Hasil: `$argon2id$v=19$m=8192,t=3,p=1$<salt>$<hash>` (format PHC, bisa dicek juga oleh server Node.js).
Future<String> buatHash(String rahasia) async {
  final garam = List<int>.generate(16, (_) => _acak.nextInt(256));
  final hash = await _argon2(rahasia, garam, _memoriKiB, _iterasi, _paralel, _panjangHash);
  return '\$argon2id\$v=19\$m=$_memoriKiB,t=$_iterasi,p=$_paralel\$${_b64(garam)}\$${_b64(hash)}';
}

/// Cocokkan rahasia dengan hash PHC. Format rusak → false.
Future<bool> cocokkanHash(String rahasia, String hashPhc) async {
  final bagian = hashPhc.split('\$');
  // ['', 'argon2id', 'v=19', 'm=..,t=..,p=..', salt, hash]
  if (bagian.length != 6 || bagian[1] != 'argon2id' || bagian[2] != 'v=19') return false;
  final param = <String, int>{};
  for (final kv in bagian[3].split(',')) {
    final p = kv.split('=');
    if (p.length != 2) return false;
    final n = int.tryParse(p[1]);
    if (n == null) return false;
    param[p[0]] = n;
  }
  final m = param['m'], t = param['t'], par = param['p'];
  if (m == null || t == null || par == null) return false;
  try {
    final garam = _unb64(bagian[4]);
    final harap = _unb64(bagian[5]);
    final hasil = await _argon2(rahasia, garam, m, t, par, harap.length);
    return _samaWaktuKonstan(hasil, harap);
  } on FormatException {
    return false;
  }
}

Future<List<int>> _argon2(String rahasia, List<int> garam, int m, int t, int p, int panjang) async {
  final algo = Argon2id(parallelism: p, memory: m, iterations: t, hashLength: panjang);
  final kunci = await algo.deriveKey(secretKey: SecretKey(utf8.encode(rahasia)), nonce: garam);
  return kunci.extractBytes();
}

bool _samaWaktuKonstan(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var beda = 0;
  for (var i = 0; i < a.length; i++) {
    beda |= a[i] ^ b[i];
  }
  return beda == 0;
}

/// PIN kasir/SPV: tepat 6 angka. Mengembalikan pesan kesalahan atau null.
String? periksaPin(String pin) {
  if (!RegExp(r'^[0-9]{6}$').hasMatch(pin)) return 'PIN harus 6 angka.';
  if (RegExp(r'^(\d)\1{5}$').hasMatch(pin)) return 'PIN tidak boleh angka yang sama semua.';
  const urut = [
    '012345',
    '123456',
    '234567',
    '345678',
    '456789',
    '987654',
    '876543',
    '765432',
    '654321',
    '543210',
  ];
  if (urut.contains(pin)) return 'PIN tidak boleh angka berurutan.';
  return null;
}

/// Kata sandi Admin: minimal 10 karakter.
String? periksaKataSandi(String sandi) => sandi.length < 10 ? 'Kata sandi minimal 10 karakter.' : null;

// ---------------------------------------------------------------------------
// TOTP (RFC 6238): kode 6 angka dari aplikasi autentikator, berganti tiap 30 detik.
// ---------------------------------------------------------------------------

const _alfabetBase32 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

/// Rahasia TOTP baru (20 byte acak) dalam Base32, untuk dimasukkan ke aplikasi autentikator.
String buatRahasiaTotp() => base32Encode(List<int>.generate(20, (_) => _acak.nextInt(256)));

String base32Encode(List<int> data) {
  final buf = StringBuffer();
  var nilai = 0, bit = 0;
  for (final b in data) {
    nilai = (nilai << 8) | b;
    bit += 8;
    while (bit >= 5) {
      buf.write(_alfabetBase32[(nilai >> (bit - 5)) & 31]);
      bit -= 5;
    }
  }
  if (bit > 0) buf.write(_alfabetBase32[(nilai << (5 - bit)) & 31]);
  return buf.toString();
}

Uint8List base32Decode(String teks) {
  final bersih = teks.toUpperCase().replaceAll(RegExp(r'[\s=-]'), '');
  final out = <int>[];
  var nilai = 0, bit = 0;
  for (final c in bersih.split('')) {
    final i = _alfabetBase32.indexOf(c);
    if (i < 0) throw FormatException('Karakter Base32 tidak valid', teks);
    nilai = (nilai << 5) | i;
    bit += 5;
    if (bit >= 8) {
      out.add((nilai >> (bit - 8)) & 0xff);
      bit -= 8;
    }
  }
  return Uint8List.fromList(out);
}

/// Kode TOTP untuk waktu tertentu (HMAC-SHA1, langkah 30 detik).
Future<String> kodeTotp(String rahasiaBase32, DateTime waktu, {int digit = 6}) =>
    _kodeHotp(base32Decode(rahasiaBase32), waktu.toUtc().millisecondsSinceEpoch ~/ 1000 ~/ 30, digit);

Future<String> _kodeHotp(List<int> kunci, int penghitung, int digit) async {
  final pesan = ByteData(8)..setUint64(0, penghitung);
  final mac = await Hmac.sha1().calculateMac(pesan.buffer.asUint8List(), secretKey: SecretKey(kunci));
  final h = mac.bytes;
  final o = h[h.length - 1] & 0x0f;
  final bin = ((h[o] & 0x7f) << 24) | (h[o + 1] << 16) | (h[o + 2] << 8) | h[o + 3];
  var mod = 1;
  for (var i = 0; i < digit; i++) {
    mod *= 10;
  }
  return (bin % mod).toString().padLeft(digit, '0');
}

/// Cocokkan kode dari pengguna. Toleransi ±1 langkah (30 detik) untuk jam PC yang sedikit meleset.
Future<bool> cocokkanTotp(String rahasiaBase32, String kode, DateTime waktu) async {
  final k = kode.replaceAll(' ', '');
  if (!RegExp(r'^[0-9]{6}$').hasMatch(k)) return false;
  final kunci = base32Decode(rahasiaBase32);
  final langkah = waktu.toUtc().millisecondsSinceEpoch ~/ 1000 ~/ 30;
  for (final d in const [0, -1, 1]) {
    if (await _kodeHotp(kunci, langkah + d, 6) == k) return true;
  }
  return false;
}

/// Tautan otpauth:// untuk dibuat QR code di aplikasi autentikator.
String tautanOtpAuth({
  required String rahasiaBase32,
  required String namaAkun,
  String penerbit = 'POS Toko',
}) =>
    'otpauth://totp/${Uri.encodeComponent('$penerbit:$namaAkun')}'
    '?secret=$rahasiaBase32&issuer=${Uri.encodeComponent(penerbit)}&digits=6&period=30';
