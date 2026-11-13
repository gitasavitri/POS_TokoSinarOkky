import 'dart:convert';

import 'package:pos_core/pos_core.dart';
import 'package:test/test.dart';

void main() {
  final data = DataStruk(
    namaToko: 'TOKO CONTOH',
    namaCabang: 'Cabang Uji',
    alamat: 'Jl. Contoh No. 1',
    noTransaksi: 'TRX-A01-261105-0001',
    waktu: DateTime.utc(2026, 11, 5, 6, 9),
    namaKasir: 'Siti',
    item: const [
      ItemStruk(nama: 'Beras Premium 5 kg', qty: 2, hargaSatuan: 78500, isGrosir: false),
      ItemStruk(
        nama: 'Mi Instan Goreng — dus isi 40 bungkus extra panjang',
        qty: 2,
        hargaSatuan: 112000,
        isGrosir: true,
      ),
    ],
    metode: MetodeBayar.tunai,
    diterima: 500000,
    kembalian: 99000,
    pesanBawah: 'Barang yang sudah dibeli tidak dapat ditukar',
  );

  group('struk 58 mm', () {
    final baris = susunStruk(data);

    test('tidak ada baris lebih dari 32 karakter', () {
      for (final b in baris) {
        expect(b.teks.length, lessThanOrEqualTo(lebarStruk), reason: b.teks);
      }
    });

    test('isi utama ada dan benar', () {
      final teks = strukSebagaiTeks(baris);
      expect(teks, contains('TRX-A01-261105-0001'));
      expect(teks, contains('05/11/26 13:09'));
      expect(teks, contains('  2 x 112.000 *G'));
      expect(teks, contains('*G = harga grosir'));
      expect(baris.firstWhere((b) => b.teks.startsWith('TOTAL')).teks, kiriKanan('TOTAL', '381.000'));
      expect(teks, contains(kiriKanan('Kembali', '99.000')));
    });

    test('karakter non-ASCII diganti', () {
      expect(teksAman('Mi — dus × 2'), 'Mi - dus x 2');
      expect(teksAman('Kopi Café'), 'Kopi Cafe');
    });

    test('nama panjang dibungkus di spasi', () {
      final l = bungkus('Mi Instan Goreng dus isi 40 bungkus extra panjang sekali');
      expect(l.every((s) => s.length <= 32), isTrue);
      expect(l.first, 'Mi Instan Goreng dus isi 40');
    });

    test('kiriKanan selalu tepat 32 karakter', () {
      expect(kiriKanan('Tunai', '1.000.000').length, 32);
      expect(kiriKanan('Nama yang sangat panjang sekali melebihi', '9.999').length, 32);
    });

    test('struk non-tunai menampilkan referensi tanpa kembalian', () {
      final kartu = DataStruk(
        namaToko: 'T',
        namaCabang: '',
        alamat: '',
        noTransaksi: 'TRX-A01-261105-0002',
        waktu: DateTime.utc(2026),
        namaKasir: 'S',
        item: const [ItemStruk(nama: 'X', qty: 1, hargaSatuan: 1000, isGrosir: false)],
        metode: MetodeBayar.kartu,
        diterima: 1000,
        kembalian: 0,
        noReferensi: '004521',
      );
      final teks = strukSebagaiTeks(susunStruk(kartu));
      expect(teks, contains('Ref'));
      expect(teks, isNot(contains('Kembali')));
    });

    test('barcode struk bolak-balik', () {
      expect(isiBarcodeStruk('TRX-A01-261105-0001'), 'A012611050001');
      expect(noTransaksiDariBarcode('A012611050001'), 'TRX-A01-261105-0001');
      expect(noTransaksiDariBarcode('TOKO12261105'), isNull);
    });
  });

  group('ESC/POS', () {
    test('perintah dasar', () {
      expect(EscPos().mulai().bytes, [0x1B, 0x40]);
      expect(EscPos().rata(Rata.tengah).bytes, [0x1B, 0x61, 1]);
      expect(EscPos().tebal(true).bytes, [0x1B, 0x45, 1]);
      expect(EscPos().besar(true).bytes, [0x1D, 0x21, 0x01]);
      expect(EscPos().baris('Hi').bytes, [0x48, 0x69, 0x0A]);
      expect(EscPos().potong().bytes, [0x1D, 0x56, 0x42, 0x00]);
    });

    test('CODE128 memakai set C untuk deretan angka', () {
      expect(dataCode128('A012611050001'), [
        ...ascii.encode('{BA'),
        ...ascii.encode('{C'),
        1,
        26,
        11,
        5,
        0,
        1,
      ]);
      expect(dataCode128('AB1'), ascii.encode('{BAB1'));
      expect(dataCode128('{'), [...ascii.encode('{B'), 0x7B, 0x7B]);
    });

    test('struk lengkap diawali reset dan berisi teks ASCII saja', () {
      final b = cetakStruk(data);
      expect(b.sublist(0, 2), [0x1B, 0x40]);
      expect(b.every((x) => x < 0x80), isTrue);
      final teks = latin1.decode(b);
      expect(teks, contains('Terima kasih'));
      expect(teks, isNot(contains('—')));
    });

    test('potong kertas hanya bila diminta', () {
      final dengan = cetakStruk(data, potongKertas: true);
      final tanpa = cetakStruk(data);
      expect(dengan.sublist(dengan.length - 4), [0x1D, 0x56, 0x42, 0x00]);
      expect(tanpa.length, dengan.length - 4);
    });
  });

  group('keamanan', () {
    test('hash PIN cocok dan tidak menyimpan PIN asli', () async {
      final h = await buatHash('482913');
      expect(h, startsWith(r'$argon2id$v=19$m=8192,t=3,p=1$'));
      expect(h, isNot(contains('482913')));
      expect(await cocokkanHash('482913', h), isTrue);
      expect(await cocokkanHash('482914', h), isFalse);
    });

    test('hash berbeda tiap kali (garam acak)', () async {
      expect(await buatHash('482913'), isNot(await buatHash('482913')));
    });

    test('hash rusak → false, bukan error', () async {
      expect(await cocokkanHash('1', 'bukan-hash'), isFalse);
      expect(await cocokkanHash('1', r'$argon2id$v=19$m=x$a$b'), isFalse);
    });

    test('aturan PIN dan sandi', () {
      expect(periksaPin('482913'), isNull);
      expect(periksaPin('12345'), isNotNull);
      expect(periksaPin('12a456'), isNotNull);
      expect(periksaPin('111111'), isNotNull);
      expect(periksaPin('123456'), isNotNull);
      expect(periksaKataSandi('pendek'), isNotNull);
      expect(periksaKataSandi('cukup-panjang'), isNull);
    });

    test('TOTP sesuai vektor uji RFC 6238', () async {
      // Rahasia ASCII "12345678901234567890"
      final rahasia = base32Encode(ascii.encode('12345678901234567890'));
      expect(rahasia, 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ');
      final t = DateTime.fromMillisecondsSinceEpoch(59 * 1000, isUtc: true);
      expect(await kodeTotp(rahasia, t, digit: 8), '94287082');
      final t2 = DateTime.fromMillisecondsSinceEpoch(1111111109 * 1000, isUtc: true);
      expect(await kodeTotp(rahasia, t2, digit: 8), '07081804');
      expect(await cocokkanTotp(rahasia, '287082', t), isTrue);
      expect(await cocokkanTotp(rahasia, '000000', t), isFalse);
    });

    test('base32 bolak-balik dan id unik', () {
      final r = buatRahasiaTotp();
      expect(base32Encode(base32Decode(r)), r);
      expect(
        buatId(),
        matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')),
      );
      expect(buatId(), isNot(buatId()));
    });
  });
}
