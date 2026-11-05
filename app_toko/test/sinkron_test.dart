// Sinkronisasi di sisi toko.
//
// Bagian 1 (selalu jalan): antrean outbox dan penerapan data dari pusat, tanpa server.
// Bagian 2 (uji ujung-ke-ujung): hanya jalan kalau variabel lingkungan berikut diisi:
//   POS_SERVER_UJI  alamat Server Pusat uji, mis. http://127.0.0.1:3999
//   POS_KODE_UJI    dua kode pendaftaran dipisah koma (dari `npm run buat-kode`)
// Server uji sebaiknya dijalankan dengan SINKRON_JEDA_DETIK=0.

import 'dart:convert';
import 'dart:io';

import 'package:app_toko/data/database.dart';
import 'package:app_toko/data/model.dart';
import 'package:app_toko/data/repo/barang_masuk_repo.dart';
import 'package:app_toko/data/repo/katalog_repo.dart';
import 'package:app_toko/data/repo/pengaturan_repo.dart';
import 'package:app_toko/data/repo/pengguna_repo.dart';
import 'package:app_toko/data/repo/penjualan_repo.dart';
import 'package:app_toko/data/repo/setup_repo.dart';
import 'package:app_toko/data/repo/sinkron_repo.dart';
import 'package:app_toko/layanan/sinkron.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_core/pos_core.dart';

class Toko {
  Toko._(this.db, this.cabang, this.admin, this.kasir);
  final DatabaseToko db;
  final InfoCabang cabang;
  final Pengguna admin;
  final Pengguna kasir;

  KatalogRepo get katalog => KatalogRepo(db);
  SinkronRepo get sinkron => SinkronRepo(db);

  static Future<Toko> baru(String kode, {DateTime Function()? jam}) async {
    final db = DatabaseToko.memori(jam: jam);
    await SetupRepo(db).siapkan(
      namaToko: 'TOKO CONTOH',
      kodeCabang: kode,
      namaCabang: 'Contoh $kode',
      alamat: 'Jl. Contoh',
      pesanStruk: 'Terima kasih',
      namaAdmin: 'Admin $kode',
      namaPenggunaAdmin: 'admin.${kode.toLowerCase()}',
      sandiAdmin: 'sandi-panjang-1',
      rahasiaTotp: base32Encode(ascii.encode('12345678901234567890')),
      pinAdmin: '908172',
    );
    final cabang = PengaturanRepo(db).infoCabang()!;
    final pengguna = PenggunaRepo(db);
    final admin = pengguna.semua(cabang.id).firstWhere((p) => p.peran == Peran.admin);
    final kasir = pengguna.ambil(await pengguna.tambah(cabangId: cabang.id, nama: 'Kasir $kode', peran: Peran.kasir, pin: '482913', olehId: admin.id))!;
    return Toko._(db, cabang, admin, kasir);
  }

  /// Barang baru lewat barang masuk + satu penjualan.
  String barangMasukDanJual({String barcode = '8990001', int qty = 12}) {
    final kat = katalog.kategori().firstWhere((k) => k.nama == 'Sembako');
    BarangMasukRepo(db).kirim(
      cabang: cabang,
      oleh: kasir,
      draft: DraftBarangMasuk(supplierId: idSupplierTokoUtama, noFaktur: 'F-001', item: [
        DraftItemMasuk(
          barcode: barcode,
          nama: 'Gula Pasir 1 kg',
          kategoriId: kat.id,
          satuan: 'pak',
          jumlah: 50,
          hpp: 16200,
          hargaJual: 17500,
          grosir: const [TingkatGrosir(minQty: 10, harga: 17000)],
        ),
      ]),
    );
    final jual = PenjualanRepo(db);
    final shift = jual.bukaShift(cabangId: cabang.id, kasirId: kasir.id, modalAwal: 100000);
    jual.simpan(
      cabang: cabang,
      kasir: kasir,
      shift: shift,
      keranjang: Keranjang()..tambah(katalog.untukKasirBarcode(barcode, cabang.id)!, qty: qty),
      metode: MetodeBayar.tunai,
      uangDiterima: 300000,
    );
    return katalog.cariBarcode(barcode, cabang.id)!.id;
  }
}

Map<String, Object?> ubahan(String tabel, Map<String, Object?> baris) => {'seq': 1, 'tabel': tabel, 'baris': baris};

void main() {
  group('antrean kirim', () {
    test('urut sesuai waktu dibuat; rahasia TOTP tidak ikut terkirim', () async {
      final t = await Toko.baru('A01');
      final a = t.sinkron.antrean(batas: 1000);
      expect(a.first.tabel, 'cabang');
      expect(a.where((i) => i.tabel == 'kategori').map((i) => i.barisId), containsAll(kategoriAwal.values));
      final admin = a.firstWhere((i) => i.tabel == 'pengguna' && i.barisId == t.admin.id);
      final isi = jsonDecode(admin.payload) as Map<String, Object?>;
      expect(isi.containsKey('totp_secret'), isFalse);
      expect(isi['sandi_hash'], startsWith(r'$argon2id$'));
      final masih = t.db.satu('SELECT totp_secret FROM pengguna WHERE id = ?', [t.admin.id])!;
      expect(masih['totp_secret'], isNotNull, reason: 'di PC toko tetap tersimpan');
    });

    test('yang diterima ditandai terkirim; yang ditolak dicoba lagi nanti', () async {
      final t = await Toko.baru('A01');
      final semua = t.sinkron.antrean(batas: 1000);
      t.sinkron.tandaiHasil(diterima: [for (final i in semua.skip(1)) i.id], ditolak: [semua.first.id]);
      expect(t.sinkron.jumlahAntrean(), 1);
      expect(t.sinkron.antrean().single.id, semua.first.id);
    });
  });

  group('terapkan data dari pusat', () {
    late Toko t;
    const adminPusat = 'a0000000-0000-4000-8000-000000000001';
    final penggunaPusat = {
      'id': adminPusat, 'cabang_id': null, 'nama': 'Admin Pusat', 'nama_pengguna': 'admin.a01', 'peran': 'admin',
      'pin_hash': null, 'sandi_hash': '!', 'gagal_login': 0, 'terkunci': 0, 'aktif': 1,
      'created_at': '2026-11-01T00:00:00Z', 'updated_at': '2026-11-01T00:00:00Z',
    };

    setUp(() async => t = await Toko.baru('A01'));

    test('harga pusat yang lebih baru menggantikan harga toko; grosir ikut; tidak masuk outbox', () {
      final id = t.barangMasukDanJual();
      expect(t.katalog.hargaBerlaku(id, t.cabang.id)!.$2.eceran, 17500);
      final outboxSebelum = t.sinkron.jumlahAntrean();
      final hargaId = buatId();
      final h = t.sinkron.terapkan([
        ubahan('pengguna', penggunaPusat),
        ubahan('harga_jual', {
          'id': hargaId, 'barang_id': id, 'cabang_id': null, 'harga': 18000, 'sumber': 'pusat', 'ref_id': null, 'alasan': 'naik',
          'dibuat_oleh': adminPusat, 'disetujui_oleh': null, 'berlaku_mulai': '2030-01-01T00:00:00Z', 'created_at': '2030-01-01T00:00:00Z',
        }),
        ubahan('harga_grosir', {'id': buatId(), 'harga_jual_id': hargaId, 'min_qty': 10, 'harga': 17500, 'created_at': '2030-01-01T00:00:00Z'}),
      ], kursorBaru: 42, cabangId: t.cabang.id);
      expect(h.masalah, isEmpty);
      expect(h.diterapkan, 3);
      expect(t.sinkron.kursor, 42);
      expect(t.sinkron.jumlahAntrean(), outboxSebelum, reason: 'data dari pusat tidak dikirim balik');
      // Harga pusat dijadwalkan mulai 2030 (lebih baru dari harga toko), jadi sekarang masih harga toko.
      expect(t.katalog.hargaBerlaku(id, t.cabang.id)!.$2.eceran, 17500);
      final dijadwalkan = t.db.satu('SELECT harga FROM harga_jual WHERE id = ?', [hargaId])!;
      expect(dijadwalkan['harga'], 18000);
      expect(t.db.satu('SELECT COUNT(*) AS n FROM harga_grosir WHERE harga_jual_id = ?', [hargaId])!['n'], 1);

    });

    test('harga pusat yang sudah berlaku menggantikan harga khusus toko yang lebih lama', () async {
      final lama = await Toko.baru('A01', jam: () => DateTime.utc(2026, 11, 1));
      final id = lama.barangMasukDanJual();
      final hargaId = buatId();
      lama.sinkron.terapkan([
        ubahan('pengguna', penggunaPusat),
        ubahan('harga_jual', {
          'id': hargaId, 'barang_id': id, 'cabang_id': null, 'harga': 18000, 'sumber': 'pusat', 'ref_id': null, 'alasan': 'naik',
          'dibuat_oleh': adminPusat, 'disetujui_oleh': null, 'berlaku_mulai': '2026-11-03T00:00:00Z', 'created_at': '2026-11-03T00:00:00Z',
        }),
        ubahan('harga_grosir', {'id': buatId(), 'harga_jual_id': hargaId, 'min_qty': 10, 'harga': 17500, 'created_at': '2026-11-03T00:00:00Z'}),
      ], kursorBaru: 1, cabangId: lama.cabang.id);
      final (_, h) = lama.katalog.hargaBerlaku(id, lama.cabang.id)!;
      expect(h.eceran, 18000);
      expect(h.grosir.single.harga, 17500);
      expect(hitungHargaBaris(h, 12).hargaSatuan, 17500, reason: 'harga grosir pusat dipakai di kasir');
    });

    test('akun Admin pusat tidak bisa dipakai masuk di toko, dan nama penggunanya tidak bentrok', () async {
      t.sinkron.terapkan([ubahan('pengguna', penggunaPusat)], kursorBaru: 1, cabangId: t.cabang.id);
      final r = t.db.satu('SELECT nama_pengguna, sandi_hash FROM pengguna WHERE id = ?', [adminPusat])!;
      expect(r['nama_pengguna'], 'pusat:admin.a01', reason: 'admin toko juga bernama admin.a01');
      final h = await PenggunaRepo(t.db).masukAdmin('pusat:admin.a01', '!', '000000');
      expect(h.pengguna, isNull);
    });

    test('barang dari toko lain: kategori dicocokkan dengan nama; barcode bentrok dilewati', () {
      t.barangMasukDanJual(barcode: '8990001');
      final kategoriLain = buatId();
      final barangBaru = buatId();
      final h = t.sinkron.terapkan([
        ubahan('barang', {
          'id': barangBaru, 'barcode': '8990555', 'nama': 'Kecap Manis', 'kategori_id': kategoriLain, 'kategori_nama': 'Bumbu dapur',
          'satuan': 'botol', 'aktif': 1, 'created_at': '2026-11-05T00:00:00Z', 'updated_at': '2026-11-05T00:00:00Z',
        }),
        ubahan('barang', {
          'id': buatId(), 'barcode': '8990001', 'nama': 'Gula Kembar', 'kategori_id': kategoriAwal['Sembako'], 'kategori_nama': 'Sembako',
          'satuan': 'pak', 'aktif': 1, 'created_at': '2026-11-05T00:00:00Z', 'updated_at': '2026-11-05T00:00:00Z',
        }),
      ], kursorBaru: 5, cabangId: t.cabang.id);
      expect(h.diterapkan, 1);
      expect(h.masalah.single, contains('8990001'));
      final b = t.db.satu('SELECT kategori_id FROM barang WHERE id = ?', [barangBaru])!;
      expect(b['kategori_id'], kategoriAwal['Bumbu dapur']);
      expect(t.katalog.cariBarcode('8990001', t.cabang.id)!.nama, 'Gula Pasir 1 kg');
      expect(t.katalog.untukKasirBarcode('8990555', t.cabang.id), isNull, reason: 'barang katalog belum dijual di toko ini sampai ada barang masuk / diatur pusat');
    });

    test('data master lama dari pusat tidak menimpa versi toko yang lebih baru; data cabang lain diabaikan', () {
      final id = t.barangMasukDanJual();
      final sekarang = t.db.satu('SELECT * FROM barang WHERE id = ?', [id])!;
      final h = t.sinkron.terapkan([
        ubahan('barang', {...sekarang, 'nama': 'Nama lama', 'updated_at': '2020-01-01T00:00:00Z'}),
        ubahan('barang_cabang', {'cabang_id': buatId(), 'barang_id': id, 'aktif': 1, 'stok_minimum': 0, 'created_at': 'x', 'updated_at': 'x'}),
        ubahan('cabang', {'id': buatId(), 'kode': 'Z99', 'nama': 'Lain', 'alamat': '', 'pesan_struk': '', 'aktif': 1, 'created_at': 'x', 'updated_at': 'x'}),
      ], kursorBaru: 7, cabangId: t.cabang.id);
      expect(h.diterapkan, 0);
      expect(h.dilewati, 3);
      expect(t.db.satu('SELECT nama FROM barang WHERE id = ?', [id])!['nama'], 'Gula Pasir 1 kg');
    });

    test('baris yang gagal tidak membatalkan baris lain', () {
      final h = t.sinkron.terapkan([
        ubahan('harga_grosir', {'id': buatId(), 'harga_jual_id': buatId(), 'min_qty': 10, 'harga': 100, 'created_at': 'x'}),
        ubahan('kategori', {'id': buatId(), 'nama': 'Alat tulis', 'aktif': 1, 'created_at': '2026-11-05T00:00:00Z'}),
      ], kursorBaru: 9, cabangId: t.cabang.id);
      expect(h.diterapkan, 1);
      expect(h.masalah.single, startsWith('harga_grosir'));
      expect(t.katalog.kategori().map((k) => k.nama), contains('Alat tulis'));
    });
  });

  test('alamat server wajib https (kecuali localhost untuk uji)', () {
    expect(KlienPusat.periksaAlamat('https://pos.contoh.com/').toString(), 'https://pos.contoh.com');
    expect(KlienPusat.periksaAlamat('http://127.0.0.1:3000').port, 3000);
    expect(() => KlienPusat.periksaAlamat('http://pos.contoh.com'), throwsA(isA<GalatSinkron>()));
    expect(() => KlienPusat.periksaAlamat('bukan alamat'), throwsA(isA<GalatSinkron>()));
  });

  final server = Platform.environment['POS_SERVER_UJI'];
  final kode = (Platform.environment['POS_KODE_UJI'] ?? '').split(',');
  group('ujung ke ujung dengan Server Pusat', skip: server == null || kode.length < 2 ? 'POS_SERVER_UJI / POS_KODE_UJI tidak diisi' : false, () {
    test('toko A kirim semua data; toko B menerima barang A di katalognya', () async {
      // Kode cabang acak supaya test bisa diulang di server yang sama.
      final acak = (DateTime.now().millisecondsSinceEpoch % 46656).toRadixString(36).toUpperCase().padLeft(3, '0');
      final a = await Toko.baru('A$acak');
      final b = await Toko.baru('B$acak');
      final barcode = '8997${DateTime.now().microsecondsSinceEpoch}';
      final barangA = a.barangMasukDanJual(barcode: barcode);

      final sa = LayananSinkron(a.db);
      await sa.daftar(alamat: server!, kode: kode[0], namaPerangkat: 'PC uji A', olehId: a.admin.id);
      await sa.sinkronSekarang();
      expect(sa.galatTerakhir, isNull);
      expect(sa.ditolakTerakhir, isEmpty, reason: 'semua jenis data dari aplikasi diterima server');
      expect(a.sinkron.jumlahAntrean(), 0);

      final sb = LayananSinkron(b.db);
      await sb.daftar(alamat: server, kode: kode[1], namaPerangkat: 'PC uji B', olehId: b.admin.id);
      await sb.sinkronSekarang();
      expect(sb.galatTerakhir, isNull);
      expect(b.katalog.cariBarcode(barcode, b.cabang.id)?.id, barangA, reason: 'katalog barang bersama');
      expect(b.katalog.hargaBerlaku(barangA, b.cabang.id), isNull, reason: 'harga khusus toko A tidak ikut ke toko B');

      // Daftar ulang dengan kode yang sama ditolak.
      final c = await Toko.baru('C$acak');
      await expectLater(
        LayananSinkron(c.db).daftar(alamat: server, kode: kode[0], namaPerangkat: 'PC uji C', olehId: c.admin.id),
        throwsA(isA<GalatSinkron>().having((e) => e.status, 'status', 403)),
      );
      sa.dispose();
      sb.dispose();
    });
  });
}
