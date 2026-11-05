// Antisipasi listrik padam & masalah teknis: belanjaan tersimpan, struk tertunda, jam mundur,
// cadangan + pemulihan database rusak, catatan galat.
import 'dart:convert';
import 'dart:io';

import 'package:app_toko/data/database.dart';
import 'package:app_toko/data/model.dart';
import 'package:app_toko/data/repo/barang_masuk_repo.dart';
import 'package:app_toko/data/repo/harga_repo.dart';
import 'package:app_toko/data/repo/katalog_repo.dart';
import 'package:app_toko/data/repo/pemulihan_repo.dart';
import 'package:app_toko/data/repo/pengaturan_repo.dart';
import 'package:app_toko/data/repo/pengguna_repo.dart';
import 'package:app_toko/data/repo/penjualan_repo.dart';
import 'package:app_toko/data/repo/setup_repo.dart';
import 'package:app_toko/layanan/aplikasi.dart';
import 'package:app_toko/layanan/cadangan.dart';
import 'package:app_toko/layanan/printer.dart';
import 'package:app_toko/layanan/sistem.dart';
import 'package:app_toko/ui/akar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_core/pos_core.dart';

import 'huruf.dart';

class Jam {
  DateTime t = DateTime.utc(2026, 11, 5, 2);
  DateTime call() => t;
}

class Toko {
  Toko(this.db, this.jam, this.cabang, this.admin, this.kasir);
  final DatabaseToko db;
  final Jam jam;
  final InfoCabang cabang;
  final Pengguna admin;
  final Pengguna kasir;

  KatalogRepo get katalog => KatalogRepo(db);
  PemulihanRepo get pulih => PemulihanRepo(db);
  PenjualanRepo get jual => PenjualanRepo(db);
  BarangJual barang(String bc) => katalog.untukKasirBarcode(bc, cabang.id)!;

  static Future<Toko> baru({String? path}) async {
    final jam = Jam();
    final db = path == null ? DatabaseToko.memori(jam: jam.call) : DatabaseToko.buka(path, jam: jam.call);
    await SetupRepo(db).siapkan(
      namaToko: 'TOKO CONTOH', kodeCabang: 'A01', namaCabang: 'Contoh', alamat: 'Jl. Contoh', pesanStruk: '',
      namaAdmin: 'Admin Contoh', namaPenggunaAdmin: 'admin.contoh', sandiAdmin: 'sandi-panjang-1',
      rahasiaTotp: base32Encode(ascii.encode('12345678901234567890')), pinAdmin: '908172',
    );
    final c = PengaturanRepo(db).infoCabang()!;
    final pg = PenggunaRepo(db);
    final admin = pg.semua(c.id).firstWhere((p) => p.peran == Peran.admin);
    final kasir = pg.ambil(await pg.tambah(cabangId: c.id, nama: 'Siti', peran: Peran.kasir, pin: '482913', olehId: admin.id))!;
    BarangMasukRepo(db).kirim(cabang: c, oleh: kasir, draft: DraftBarangMasuk(supplierId: idSupplierTokoUtama, noFaktur: 'F-1', item: [
      DraftItemMasuk(barcode: '8990001', nama: 'Gula Pasir 1 kg', kategoriId: kategoriAwal['Sembako']!, satuan: 'pak', jumlah: 50, hpp: 16200, hargaJual: 17500),
      DraftItemMasuk(barcode: '8990003', nama: 'Sabun Mandi 85 g', kategoriId: kategoriAwal['Sabun & Sampo']!, satuan: 'pcs', jumlah: 40, hpp: 3100, hargaJual: 4000),
    ]));
    return Toko(db, jam, c, admin, kasir);
  }
}

void main() {
  group('belanjaan tersimpan (listrik padam saat kasir masih scan)', () {
    test('dimuat lagi dengan harga terkini; barang yang tidak dijual lagi dihitung', () async {
      final t = await Toko.baru();
      final aktif = Keranjang()..tambah(t.barang('8990001'), qty: 3)..tambah(t.barang('8990003'));
      final ditahan = [Keranjang()..tambah(t.barang('8990003'), qty: 2)];
      t.pulih.simpanKeranjang(kasirId: t.kasir.id, aktif: aktif, ditahan: ditahan);

      t.jam.t = t.jam.t.add(const Duration(minutes: 5));
      HargaRepo(t.db).ubahHarga(
          cabang: t.cabang, barangId: t.barang('8990001').id, hargaBaru: 18000, grosir: const [], alasan: 'Harga supplier naik', oleh: t.admin);
      final m = t.pulih.muatKeranjang(t.cabang.id)!;
      expect(m.namaKasir, 'Siti');
      expect(m.aktif.jumlahBarang, 4);
      expect(m.aktif.baris.first.harga.hargaSatuan, 18000, reason: 'harga terbaru yang berlaku');
      expect(m.ditahan.single.jumlahBarang, 2);
      expect(m.hilang, 0);

      t.db.jalankan('UPDATE barang_cabang SET aktif = 0 WHERE barang_id = ?', [t.barang('8990003').id]);
      final m2 = t.pulih.muatKeranjang(t.cabang.id)!;
      expect(m2.hilang, 2);
      expect(m2.ditahan, isEmpty);
    });

    test('keranjang kosong = catatan dihapus; isi rusak diabaikan', () async {
      final t = await Toko.baru();
      t.pulih.simpanKeranjang(kasirId: t.kasir.id, aktif: Keranjang(), ditahan: const []);
      expect(t.pulih.muatKeranjang(t.cabang.id), isNull);
      PengaturanRepo(t.db).simpan(PemulihanRepo.kKeranjang, '{rusak');
      expect(t.pulih.muatKeranjang(t.cabang.id), isNull);
    });

    test('transaksi tersimpan → belanjaan tersimpan hilang & struk ditandai belum cetak, dalam satu transaksi database', () async {
      final t = await Toko.baru();
      final k = Keranjang()..tambah(t.barang('8990001'), qty: 2);
      t.pulih.simpanKeranjang(kasirId: t.kasir.id, aktif: k, ditahan: const []);
      final shift = t.jual.bukaShift(cabangId: t.cabang.id, kasirId: t.kasir.id, modalAwal: 0);
      final h = t.jual.simpan(cabang: t.cabang, kasir: t.kasir, shift: shift, keranjang: k, metode: MetodeBayar.tunai, uangDiterima: 50000);
      expect(t.pulih.muatKeranjang(t.cabang.id), isNull, reason: 'tidak boleh ditawarkan lagi → mencegah dobel bayar');
      expect(t.pulih.strukBelumCetak(), h.transaksiId);
      t.pulih.selesaiCetak();
      expect(t.pulih.strukBelumCetak(), isNull);
    });
  });

  group('jam komputer mundur', () {
    test('penjualan ditolak kalau jam lebih awal >10 menit dari transaksi terakhir; data tidak berubah', () async {
      final t = await Toko.baru();
      final shift = t.jual.bukaShift(cabangId: t.cabang.id, kasirId: t.kasir.id, modalAwal: 0);
      Keranjang k() => Keranjang()..tambah(t.barang('8990003'));
      t.jual.simpan(cabang: t.cabang, kasir: t.kasir, shift: shift, keranjang: k(), metode: MetodeBayar.tunai, uangDiterima: 5000);

      t.jam.t = t.jam.t.subtract(const Duration(minutes: 5));
      t.jual.simpan(cabang: t.cabang, kasir: t.kasir, shift: shift, keranjang: k(), metode: MetodeBayar.tunai, uangDiterima: 5000);

      t.jam.t = DateTime.utc(2001, 1, 1); // baterai BIOS habis
      t.pulih.simpanKeranjang(kasirId: t.kasir.id, aktif: k(), ditahan: const []);
      expect(
        () => t.jual.simpan(cabang: t.cabang, kasir: t.kasir, shift: shift, keranjang: k(), metode: MetodeBayar.tunai, uangDiterima: 5000),
        throwsA(isA<JamMundur>().having((e) => e.pesan, 'pesan', contains('Betulkan tanggal'))),
      );
      expect(t.db.satu('SELECT COUNT(*) AS n FROM transaksi')!['n'], 2);
      expect(t.pulih.muatKeranjang(t.cabang.id), isNotNull, reason: 'belanjaan tetap ada setelah gagal');
    });
  });

  group('cadangan & pemulihan', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('pos_uji_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('cadangan utuh, hanya 14 terbaru disimpan, ikut disalin ke flashdisk', () async {
      final t = await Toko.baru();
      final flashdisk = Directory('${tmp.path}/E')..createSync();
      final c = LayananCadangan(t.db, folder: '${tmp.path}/cadangan', folderKedua: () => flashdisk.path);
      for (var i = 0; i < 16; i++) {
        t.jam.t = t.jam.t.add(const Duration(hours: 1));
        final f = c.buat('A01');
        expect(LayananCadangan.periksa(f).utuh, isTrue);
      }
      final daftar = LayananCadangan.daftar('${tmp.path}/cadangan');
      expect(daftar, hasLength(14));
      expect(daftar.first.uri.pathSegments.last.compareTo(daftar.last.uri.pathSegments.last), greaterThan(0), reason: 'terbaru dulu');
      expect(LayananCadangan.daftar('${flashdisk.path}/POS-Cadangan'), hasLength(14));
    });

    test('database rusak terdeteksi, dipulihkan dari cadangan; file rusak disimpan, bukan dihapus', () async {
      final path = '${tmp.path}/pos_toko.db';
      final t = await Toko.baru(path: path);
      final c = LayananCadangan(t.db, folder: '${tmp.path}/cadangan');
      final cadangan = c.buat('A01');
      t.db.tutup();

      // Rusakkan isi file di tengah (seperti sektor hardisk rusak).
      final isi = File(path).readAsBytesSync();
      isi.setRange(4096, 4096 + 8192, List.filled(8192, 0x5A));
      File(path).writeAsBytesSync(isi);
      for (final ext in ['-wal', '-shm']) {
        if (File('$path$ext').existsSync()) File('$path$ext').deleteSync();
      }
      final cek = LayananCadangan.periksa(path, bacaSaja: false);
      expect(cek.utuh, isFalse);

      expect(await pinPenyetujuCocok(cadangan, '908172'), isTrue, reason: 'PIN Admin');
      expect(await pinPenyetujuCocok(cadangan, '482913'), isFalse, reason: 'PIN kasir tidak boleh');
      expect(await pinPenyetujuCocok(cadangan, '000000'), isFalse);

      final lama = LayananCadangan.pulihkan(cadangan: cadangan, tujuan: path);
      expect(File(lama).existsSync(), isTrue);
      expect(LayananCadangan.periksa(path, bacaSaja: false).utuh, isTrue);
      final db = DatabaseToko.buka(path);
      expect(db.satu('SELECT COUNT(*) AS n FROM barang')!['n'], 2);
      db.tutup();
    });

    test('cadangan yang rusak tidak bisa dipakai memulihkan', () {
      final palsu = File('${tmp.path}/pos-A01-20261105-090000.db')..writeAsStringSync('bukan database');
      expect(LayananCadangan.periksa(palsu.path).utuh, isFalse);
      expect(() => LayananCadangan.pulihkan(cadangan: palsu.path, tujuan: '${tmp.path}/x.db'), throwsStateError);
    });

    test('database yang tertutup mendadak (masih ada file -wal) tetap dinilai utuh', () async {
      final path = '${tmp.path}/pos_toko.db';
      final t = await Toko.baru(path: path);
      final shift = t.jual.bukaShift(cabangId: t.cabang.id, kasirId: t.kasir.id, modalAwal: 0);
      t.jual.simpan(cabang: t.cabang, kasir: t.kasir, shift: shift, keranjang: Keranjang()..tambah(t.barang('8990003')), metode: MetodeBayar.tunai, uangDiterima: 4000);
      // Salin file selagi database masih terbuka = keadaan disk saat listrik padam.
      for (final ext in ['', '-wal']) {
        if (File('$path$ext').existsSync()) File('$path$ext').copySync('${tmp.path}/padam.db$ext');
      }
      t.db.tutup();
      expect(LayananCadangan.periksa('${tmp.path}/padam.db', bacaSaja: false).utuh, isTrue);
      final db = DatabaseToko.buka('${tmp.path}/padam.db');
      expect(db.satu('SELECT COUNT(*) AS n FROM transaksi')!['n'], 1, reason: 'transaksi yang sudah selesai tidak hilang');
      db.tutup();
    });
  });

  test('catatan galat ditulis ke file per bulan', () {
    final tmp = Directory.systemTemp.createTempSync('pos_log_');
    CatatanGalat(tmp.path).tulis(StateError('contoh galat'), StackTrace.current, konteks: 'uji');
    final f = tmp.listSync().single as File;
    expect(f.uri.pathSegments.last, matches(RegExp(r'^galat-\d{6}\.txt$')));
    expect(f.readAsStringSync(), contains('contoh galat'));
    tmp.deleteSync(recursive: true);
  });

  test('peringatan: jam mundur & cadangan otomatis', () async {
    final tmp = Directory.systemTemp.createTempSync('pos_app_');
    final t = await Toko.baru();
    final app = Aplikasi(db: t.db, printer: PrinterBerkas(), folderCadangan: tmp.path);
    app.jalankanTugasLatar();
    expect(LayananCadangan.daftar(tmp.path), hasLength(1));
    app.jalankanTugasLatar();
    expect(LayananCadangan.daftar(tmp.path), hasLength(1), reason: 'belum 1 jam');
    final shift = t.jual.bukaShift(cabangId: t.cabang.id, kasirId: t.kasir.id, modalAwal: 0);
    t.jual.simpan(cabang: t.cabang, kasir: t.kasir, shift: shift, keranjang: Keranjang()..tambah(t.barang('8990003')), metode: MetodeBayar.tunai, uangDiterima: 4000);
    expect(app.peringatan, isEmpty);
    t.jam.t = DateTime.utc(2001, 1, 1);
    expect(app.peringatan.single, contains('Jam komputer mundur'));
    app.dispose();
    tmp.deleteSync(recursive: true);
  });

  testWidgets('layar kasir menawarkan belanjaan tadi & cetak struk tertunda', (tester) async {
    await tester.runAsync(muatHuruf);
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final t = await tester.runAsync(Toko.baru);
    final app = Aplikasi(db: t!.db, printer: PrinterBerkas());
    final shift = t.jual.bukaShift(cabangId: t.cabang.id, kasirId: t.kasir.id, modalAwal: 0);
    final h = t.jual.simpan(
        cabang: t.cabang, kasir: t.kasir, shift: shift, keranjang: Keranjang()..tambah(t.barang('8990003')), metode: MetodeBayar.tunai, uangDiterima: 4000);
    expect(t.pulih.strukBelumCetak(), h.transaksiId);
    t.pulih.simpanKeranjang(kasirId: t.kasir.id, aktif: Keranjang()..tambah(t.barang('8990001'), qty: 3), ditahan: const []);

    app.masuk(t.kasir);
    await tester.pumpWidget(AplikasiToko(app: app));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Struk mungkin belum tercetak'), findsOneWidget);
    await tester.tap(find.text('Tidak perlu'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(t.pulih.strukBelumCetak(), isNull);

    expect(find.text('Ada belanjaan yang belum dibayar'), findsOneWidget);
    await tester.tap(find.text('Lanjutkan belanjaan'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Gula Pasir 1 kg'), findsOneWidget);
    expect(find.text('Rp 52.500'), findsWidgets);
    app.keluar();
  });
}
