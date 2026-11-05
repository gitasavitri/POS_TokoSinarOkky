import 'dart:convert';
import 'dart:io';

import 'package:pos_core/pos_core.dart';
import 'package:test/test.dart';

void main() {
  late HttpServer server;
  late Uri dasar;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    dasar = Uri.parse('http://127.0.0.1:${server.port}');
    server.listen((req) async {
      final isi = await utf8.decodeStream(req);
      req.response.headers.contentType = ContentType.json;
      switch (req.uri.path) {
        case '/ok':
          req.response.write(jsonEncode({
            'auth': req.headers.value(HttpHeaders.authorizationHeader),
            'isi': isi.isEmpty ? null : jsonDecode(isi),
            'q': req.uri.queryParameters['sejak'],
          }));
        case '/galat':
          req.response.statusCode = 403;
          req.response.write(jsonEncode({'galat': 'Kode pendaftaran salah'}));
        default:
          req.response.statusCode = 500;
          req.response.write('bukan json');
      }
      await req.response.close();
    });
  });

  tearDown(() => server.close(force: true));

  test('kirim token, isi JSON, dan query', () async {
    final k = KlienServer(dasar, token: 'rahasia');
    final r = await k.minta('POST', '/ok', isi: {'a': 1}, query: {'sejak': '5'});
    expect(r['auth'], 'Bearer rahasia');
    expect(r['isi'], {'a': 1});
    expect(r['q'], '5');
    k.tutup();
  });

  test('pesan galat dari server diteruskan apa adanya, dengan kode status', () async {
    final k = KlienServer(dasar);
    await expectLater(
      k.minta('GET', '/galat'),
      throwsA(isA<GalatServer>().having((e) => e.pesan, 'pesan', 'Kode pendaftaran salah').having((e) => e.status, 'status', 403)),
    );
    await expectLater(k.minta('GET', '/rusak'), throwsA(isA<GalatServer>()));
    k.tutup();
  });

  test('server mati: pesan yang dimengerti kasir', () async {
    final port = server.port;
    await server.close(force: true);
    final k = KlienServer(Uri.parse('http://127.0.0.1:$port'));
    await expectLater(k.minta('GET', '/ok'), throwsA(isA<GalatServer>().having((e) => e.pesan, 'pesan', contains('Tidak tersambung'))));
    k.tutup();
  });

  test('alamat wajib https kecuali localhost', () {
    expect(KlienServer.periksaAlamat('https://pos.contoh.com//').toString(), 'https://pos.contoh.com');
    expect(() => KlienServer.periksaAlamat('http://pos.contoh.com'), throwsA(isA<GalatServer>()));
  });
}
