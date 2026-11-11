// Uji data revisi tahap 4: G. Order barang, J. Impor stok awal dari Excel, Mode latihan.
import 'dart:convert';
import 'dart:typed_data';

import 'package:app_toko/data/database.dart';
import 'package:app_toko/data/model.dart';
import 'package:app_toko/data/repo/barang_masuk_repo.dart';
import 'package:app_toko/data/repo/impor_repo.dart';
import 'package:app_toko/data/repo/katalog_repo.dart';
import 'package:app_toko/data/repo/latihan_repo.dart';
import 'package:app_toko/data/repo/laporan_repo.dart';
import 'package:app_toko/data/repo/order_repo.dart';
import 'package:app_toko/data/repo/pengaturan_repo.dart';
import 'package:app_toko/data/repo/pengguna_repo.dart';
import 'package:app_toko/data/repo/penjualan_repo.dart';
import 'package:app_toko/data/repo/setup_repo.dart';
import 'package:app_toko/data/repo/sinkron_repo.dart';
import 'package:app_toko/layanan/aplikasi.dart';
import 'package:app_toko/layanan/dokumen.dart';
import 'package:app_toko/layanan/mode_latihan.dart';
import 'package:app_toko/layanan/printer.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_core/pos_core.dart';

class JamUji {
  DateTime t = DateTime.utc(2026, 11, 5, 2); // 09:00 WIB
  DateTime call() => t;
  void maju([int detik = 1]) => t = t.add(Duration(seconds: detik));
}

/// File Excel contoh seperti yang diisi toko (judul di baris 1).
Uint8List buatExcel(List<List<Object?>> baris, {String sheet = 'Stok awal'}) {
  final e = Excel.createExcel();
  e.rename(e.getDefaultSheet()!, sheet);
  final s = e[sheet];
  s.appendRow([for (final k in kolomImporStok) TextCellValue(k)]);
  for (final r in baris) {
    s.appendRow([
      for (final v in r)
        switch (v) {
          null => null,
          final int n => IntCellValue(n),
          final double d => DoubleCellValue(d),
          _ => TextCellValue('$v'),
        },
    ]);
  }
  return Uint8List.fromList(e.encode()!);
}

void main() {
  late DatabaseToko db;
  late JamUji jam;
  late InfoCabang cabang;
  late Pengguna admin, kasir, spv;
  late KatalogRepo katalog;
  late BarangMasukRepo masuk;
  late OrderRepo order;
  late ImporRepo impor;

  setUp(() async {
    jam = JamUji();
    db = DatabaseToko.memori(jam: jam.call);
    await SetupRepo(db).siapkan(
      namaToko: 'TOKO UJI',
      kodeCabang: 'a01',
      namaCabang: 'Uji',
      alamat: 'Jl. Uji 1',
      pesanStruk: 'Terima kasih',
      namaAdmin: 'Admin Uji',
      namaPenggunaAdmin: 'admin.uji',
      sandiAdmin: 'sandi-panjang-1',
      rahasiaTotp: base32Encode(ascii.encode('12345678901234567890')),
      pinAdmin: '908172',
    );
    cabang = PengaturanRepo(db).infoCabang()!;
    final pengguna = PenggunaRepo(db);
    admin = pengguna.semua(cabang.id).firstWhere((p) => p.peran == Peran.admin);
    kasir = pengguna.ambil(await pengguna.tambah(cabangId: cabang.id, nama: 'Siti', peran: Peran.kasir, pin: '482913', olehId: admin.id))!;
    spv = pengguna.ambil(await pengguna.tambah(cabangId: cabang.id, nama: 'Dewi', peran: Peran.spv, pin: '739104', olehId: admin.id))!;
    katalog = KatalogRepo(db);
    masuk = BarangMasukRepo(db);
    order = OrderRepo(db);
    impor = ImporRepo(db);
  });
  tearDown(() => db.tutup());

  String kategori(String nama) => katalog.kategori().firstWhere((k) => k.nama == nama).id;
  String tokoUtama() => katalog.supplier().firstWhere((s) => s.jenis == 'toko_utama').id;

  /// Gula 50 pak (min 10), minyak 3 pcs (min 5), sabun 40 pcs (min 0).
  Map<String, String> isiBarang() {
    masuk.kirim(
      cabang: cabang,
      oleh: kasir,
      draft: DraftBarangMasuk(supplierId: tokoUtama(), noFaktur: 'F-001', item: [
        DraftItemMasuk(barcode: '8990001', nama: 'Gula Pasir 1 kg', kategoriId: kategori('Sembako'), satuan: 'pak', jumlah: 50, hpp: 16200, hargaJual: 17500),
        DraftItemMasuk(barcode: '8990002', nama: 'Minyak Goreng 2 L', kategoriId: kategori('Sembako'), satuan: 'pcs', jumlah: 3, hpp: 33000, hargaJual: 36000),
        DraftItemMasuk(barcode: '8990003', nama: 'Sabun Mandi 85 g', kategoriId: kategori('Sabun & Sampo'), satuan: 'pcs', jumlah: 40, hpp: 3100, hargaJual: 4000),
      ]),
    );
    jam.maju();
    final id = {for (final b in ['8990001', '8990002', '8990003']) b: katalog.cariBarcode(b, cabang.id)!.id};
    katalog.aturStokMinimum(id['8990001']!, cabang.id, 10, olehId: spv.id);
    katalog.aturStokMinimum(id['8990002']!, cabang.id, 5, olehId: spv.id);
    jam.maju();
    return id;
  }

  // ==================================================================== G. order barang

  group('order barang (G)', () {
    test('daftar barang: stok, minimum, saran; filter perlu order; scan barcode', () {
      final id = isiBarang();
      final semua = order.daftarBarang(cabang.id);
      expect(semua.map((b) => b.nama), ['Gula Pasir 1 kg', 'Minyak Goreng 2 L', 'Sabun Mandi 85 g']);
      final minyak = semua.firstWhere((b) => b.id == id['8990002']);
      expect((minyak.stok, minyak.stokMinimum, minyak.saran, minyak.perlu), (3, 5, 7, true));
      expect(semua.firstWhere((b) => b.id == id['8990001']).saran, 0);
      expect(order.daftarBarang(cabang.id, hanyaPerlu: true).map((b) => b.id), [id['8990002']]);
      expect(order.daftarBarang(cabang.id, kata: 'sabun').single.id, id['8990003']);
      expect(order.cariBarcode(cabang.id, '8990003')!.id, id['8990003']);
      expect(order.cariBarcode(cabang.id, '899000'), isNull, reason: 'harus persis');
    });

    test('simpan: nomor ORD urut per hari, stok tidak berubah, tidak ada outbox selain log', () {
      final id = isiBarang();
      final outboxSebelum = db.pilih('SELECT tabel FROM outbox').length;
      final d = DaftarOrder(supplierId: tokoUtama(), catatan: ' kirim Senin ')
        ..tambah(order.daftarBarang(cabang.id).firstWhere((b) => b.id == id['8990002']).keBaris())
        ..tambah(order.daftarBarang(cabang.id).firstWhere((b) => b.id == id['8990003']).keBaris());
      order.simpanDraft(d);
      final o = order.simpan(cabang: cabang, oleh: kasir, order: d);
      expect(o.noOrder, 'ORD-A01-261105-0001');
      expect(o.tujuanTokoUtama, isTrue);
      expect(o.catatan, 'kirim Senin');
      expect(o.dibuatOleh, 'Siti');
      expect(o.baris.map((b) => (b.nama, b.jumlah, b.stok)), [('Minyak Goreng 2 L', 7, 3), ('Sabun Mandi 85 g', 1, 40)]);
      expect(katalog.stok(id['8990002']!, cabang.id), 3, reason: 'order tidak menambah stok');
      expect(order.muatDraft(), isNull, reason: 'draft dihapus setelah disimpan');
      final outboxBaru = db.pilih('SELECT tabel FROM outbox').skip(outboxSebelum).map((r) => r['tabel']).toList();
      expect(outboxBaru, ['log_aktivitas'], reason: 'kirim order ke pusat belum dibuat');
      expect(db.satu("SELECT aksi FROM log_aktivitas WHERE aksi = 'buat_order'"), isNotNull);

      jam.maju();
      final o2 = order.simpan(cabang: cabang, oleh: spv, order: DaftarOrder(supplierId: tokoUtama())..tambah(o.baris.first));
      expect(o2.noOrder, 'ORD-A01-261105-0002');
      jam.t = DateTime.utc(2026, 11, 5, 17, 1); // 6 Nov 00.01 WIB
      final o3 = order.simpan(cabang: cabang, oleh: admin, order: DaftarOrder(supplierId: tokoUtama())..tambah(o.baris.first));
      expect(o3.noOrder, 'ORD-A01-261106-0001');
      expect(order.riwayat(cabang.id).map((r) => r.noOrder), ['ORD-A01-261106-0001', 'ORD-A01-261105-0002', 'ORD-A01-261105-0001']);
      expect(() => db.jalankan("UPDATE order_barang SET catatan = 'x'"), throwsA(anything), reason: 'order tidak bisa diubah');
    });

    test('ditolak: daftar kosong, tujuan belum dipilih, tujuan tidak ada', () {
      isiBarang();
      final b = order.daftarBarang(cabang.id).first.keBaris();
      expect(() => order.simpan(cabang: cabang, oleh: kasir, order: DaftarOrder(supplierId: tokoUtama())), throwsArgumentError);
      expect(() => order.simpan(cabang: cabang, oleh: kasir, order: DaftarOrder()..tambah(b)), throwsArgumentError);
      expect(() => order.simpan(cabang: cabang, oleh: kasir, order: DaftarOrder(supplierId: buatId())..tambah(b)), throwsArgumentError);
      expect(db.pilih('SELECT * FROM order_barang'), isEmpty);
    });

    test('draft order tersimpan per PC dan dimuat lagi', () {
      isiBarang();
      final d = DaftarOrder(supplierId: tokoUtama(), catatan: 'cepat')..tambah(order.daftarBarang(cabang.id).first.keBaris());
      order.simpanDraft(d);
      final m = order.muatDraft()!;
      expect(m.catatan, 'cepat');
      expect(m.baris.single.nama, 'Gula Pasir 1 kg');
      order.simpanDraft(DaftarOrder());
      expect(order.muatDraft(), isNull);
    });

    test('PDF surat pesanan & Excel order berisi nomor, barang, dan kolom Diterima', () async {
      final id = isiBarang();
      final o = order.simpan(
        cabang: cabang,
        oleh: kasir,
        order: DaftarOrder(supplierId: tokoUtama())
          ..tambah(order.daftarBarang(cabang.id).firstWhere((b) => b.id == id['8990002']).keBaris()),
      );
      const k = KepalaDokumen(namaToko: 'TOKO UJI', namaCabang: 'Uji', kodeCabang: 'A01', alamat: 'Jl. Uji 1');
      final pdf = await pdfSuratPesanan(o, k);
      expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
      expect(pdf.length, greaterThan(1000));

      final x = Excel.decodeBytes(excelOrder(o, k));
      final isi = x.tables['Order']!.rows.expand((r) => r).map((d) => d?.value?.toString() ?? '').toList();
      expect(isi, containsAll(['SURAT PESANAN BARANG', 'ORD-A01-261105-0001', 'Minyak Goreng 2 L', '8990002', 'Diterima', '7']));
      expect(isi, isNot(contains(teksDokumenLatihan)));
      final latihan = Excel.decodeBytes(excelOrder(o, const KepalaDokumen(namaToko: 'T', namaCabang: 'U', kodeCabang: 'A01', alamat: '', latihan: true)));
      expect(latihan.tables['Order']!.rows.expand((r) => r).map((d) => d?.value?.toString()), contains(teksDokumenLatihan));
    });
  });

  // ==================================================================== I. salin daftar barang (sisi PC toko)

  test('daftar barang yang disalin pusat (I) masuk ke PC toko: muncul di Order barang, stok 0, harga ikut', () {
    const t = '2026-11-05T01:00:00Z';
    final barangId = buatId(), hargaId = buatId(), adminPusat = buatId();
    final kat = kategori('Sembako');
    final h = SinkronRepo(db).terapkan([
      {'tabel': 'pengguna', 'baris': {'id': adminPusat, 'cabang_id': null, 'nama': 'Admin Pusat', 'nama_pengguna': 'admin.pusat', 'peran': 'admin', 'sandi_hash': '!', 'created_at': t, 'updated_at': t}},
      {'tabel': 'barang', 'baris': {'id': barangId, 'barcode': '8997777', 'nama': 'Kecap Manis 520 ml', 'kategori_id': kat, 'kategori_nama': 'Sembako', 'satuan': 'botol', 'aktif': 1, 'created_at': t, 'updated_at': t}},
      {'tabel': 'barang_cabang', 'baris': {'cabang_id': cabang.id, 'barang_id': barangId, 'aktif': 1, 'stok_minimum': 6, 'created_at': t, 'updated_at': t}},
      {'tabel': 'harga_jual', 'baris': {'id': hargaId, 'barang_id': barangId, 'cabang_id': cabang.id, 'harga': 23000, 'sumber': 'pusat', 'ref_id': null, 'alasan': 'Disalin dari toko lain', 'dibuat_oleh': adminPusat, 'disetujui_oleh': null, 'berlaku_mulai': t, 'created_at': t}},
    ], kursorBaru: 10, cabangId: cabang.id);
    expect(h.masalah, isEmpty);
    final b = order.daftarBarang(cabang.id).single;
    expect((b.nama, b.stok, b.stokMinimum, b.saran, b.perlu), ('Kecap Manis 520 ml', 0, 6, 12, true));
    expect(katalog.untukKasirBarcode('8997777', cabang.id)!.harga.eceran, 23000);
  });

  // ==================================================================== J. impor stok awal

  group('impor stok awal dari Excel (J)', () {
    test('template: judul kolom saja (tidak ada baris contoh yang ikut terimpor)', () {
      final t = templateImporStok(kategori: ['Sembako'], satuan: ['pcs']);
      expect(bacaExcelImporStok(t), isEmpty);
      final x = Excel.decodeBytes(t);
      expect(x.tables.keys, containsAll(['Stok awal', 'Petunjuk']));
      expect(x.tables['Stok awal']!.rows.first.map((d) => d?.value.toString()), kolomImporStok);
    });

    test('file bukan Excel ditolak dengan pesan yang dimengerti', () {
      expect(() => bacaExcelImporStok(Uint8List.fromList(utf8.encode('bukan excel'))), throwsFormatException);
    });

    test('pratinjau: barang lama, baru, kategori belum ada, barcode kembar, harga salah', () {
      final id = isiBarang();
      final data = bacaExcelImporStok(buatExcel([
        [8990001.0, 'Gula pasir (nama lain)', 'Sembako', 'pak', 50, '16.400', 18000], // baris 2: sudah ada
        ['8990101', 'Teh Celup isi 25', 'Minuman', 'Kotak', 12, 4500, 6000], // 3: baru
        ['8990102', 'Kopi Bubuk 200 g', 'Kopi & Teh', 'pcs', 6, 15000, 19000], // 4: kategori belum ada
        ['8990101', 'Teh Celup lagi', 'Minuman', 'pcs', 1, 100, 200], // 5: barcode kembar dengan baris 3
        ['', 'Garam 250 g', 'Sembako', 'pcs', 10, 2000, 2000], // 6: harga = HPP
        ['', 'Kerupuk Contoh', 'Sembako', '', 5, 1000, 1500], // 7: satuan kosong
        [null, null, null, null, null, null, null], // kosong, dilewati
      ]));
      final p = impor.periksa(data, cabang.id);
      final status = {for (final b in p.baris) b.sumber.nomorBaris: b.status};
      expect(status, {
        2: StatusImpor.sudahAda,
        3: StatusImpor.baru,
        4: StatusImpor.salah,
        5: StatusImpor.salah,
        6: StatusImpor.salah,
        7: StatusImpor.salah,
      });
      final b2 = p.baris.first;
      expect(b2.item!.barangId, id['8990001']);
      expect(b2.item!.nama, 'Gula Pasir 1 kg', reason: 'barang lama: nama tidak diubah');
      expect(b2.catatan.single, contains('Nama di file tidak dipakai'));
      expect((b2.item!.jumlah, b2.item!.hpp, b2.item!.hargaJual), (50, 16400, 18000));
      expect(p.baris[1].item!.satuan, 'kotak');
      expect(p.kategoriBelumAda, ['Kopi & Teh']);
      expect(p.baris[3].salah.join(), contains('baris Excel 3'));
      expect(p.baris[4].salah.join(), contains('lebih besar dari HPP'));
      expect(p.baris[5].salah.join(), contains('Satuan'));
      expect(p.benar.length, 2);
    });

    test('simpan: stok, HPP rata-rata, harga, daftar barang toko, terkunci seperti barang masuk', () {
      final id = isiBarang();
      impor.tambahKategori(['Kopi & Teh'], cabangId: cabang.id, oleh: spv);
      final p = impor.periksa(
        bacaExcelImporStok(buatExcel([
          ['8990001', '', '', '', 50, 16400, 18000],
          ['8990102', 'Kopi Bubuk 200 g', 'kopi & teh', 'pcs', 6, 15000, 19000],
          ['', 'Garam 250 g', 'Sembako', 'pcs', 10, 2000, 2500],
          ['', 'Salah', 'Sembako', 'pcs', 0, 2000, 2500],
        ])),
        cabang.id,
      );
      expect(p.jumlahSalah, 1);
      expect(() => impor.simpan(cabang: cabang, oleh: kasir, pratinjau: p, supplierId: tokoUtama(), noFaktur: 'STOK-AWAL'), throwsStateError);
      final bmId = impor.simpan(cabang: cabang, oleh: spv, pratinjau: p, supplierId: tokoUtama(), noFaktur: impor.noFakturBawaan());

      final gula = katalog.detail(id['8990001']!, cabang.id)!;
      expect(gula.stok, 100);
      expect(gula.hpp, 16300, reason: '(50×16.200 + 50×16.400) / 100');
      expect(gula.harga!.eceran, 18000);
      final kopi = katalog.cariBarcode('8990102', cabang.id)!;
      expect((kopi.stok, kopi.hpp, kopi.harga!.eceran, kopi.dijualDiToko, kopi.kategoriNama), (6, 15000, 19000, true, 'Kopi & Teh'));
      final garam = katalog.cari('Garam', cabang.id).single;
      expect((garam.barcode, garam.stok), (null, 10));
      expect(katalog.cari('Salah', cabang.id), isEmpty, reason: 'baris salah dilewati');

      final bm = db.satu('SELECT * FROM barang_masuk WHERE id = ?', [bmId])!;
      expect((bm['status'], bm['no_faktur']), ('terkirim', 'STOK-AWAL-261105'));
      expect(db.pilih('SELECT * FROM barang_masuk_item WHERE barang_masuk_id = ?', [bmId]).length, 3);
      expect(() => db.jalankan('UPDATE barang_masuk_item SET jumlah = 1 WHERE barang_masuk_id = ?', [bmId]), throwsA(anything));
      final log = db.satu("SELECT detail FROM log_aktivitas WHERE aksi = 'impor_stok_awal'")!;
      expect(jsonDecode(log['detail'] as String), containsPair('baris_dilewati', 1));
      final tabel = db.pilih('SELECT DISTINCT tabel FROM outbox').map((r) => r['tabel']).toSet();
      expect(tabel, containsAll(['barang', 'barang_cabang', 'barang_masuk', 'mutasi_stok', 'hpp_barang', 'harga_jual']));
    });

    test('tanpa barcode: cocok dengan nama barang yang sudah ada (huruf besar/kecil diabaikan)', () {
      masuk.kirim(
        cabang: cabang,
        oleh: kasir,
        draft: DraftBarangMasuk(supplierId: tokoUtama(), noFaktur: 'F-2', item: [
          DraftItemMasuk(nama: 'Tempe Papan', kategoriId: kategori('Sembako'), satuan: 'pcs', jumlah: 2, hpp: 4000, hargaJual: 5000),
        ]),
      );
      jam.maju();
      final p = impor.periksa(bacaExcelImporStok(buatExcel([['', 'tempe papan', 'Sembako', 'pcs', 3, 4000, 5000]])), cabang.id);
      expect(p.baris.single.status, StatusImpor.sudahAda);
    });

    test('tambah kategori dari pratinjau hanya SPV/Admin', () {
      expect(() => impor.tambahKategori(['Baru'], cabangId: cabang.id, oleh: kasir), throwsStateError);
      impor.tambahKategori(['Baru', 'Sembako'], cabangId: cabang.id, oleh: admin);
      expect(katalog.kategori().where((k) => k.nama == 'Baru'), hasLength(1));
      expect(katalog.kategori().where((k) => k.nama == 'Sembako'), hasLength(1), reason: 'kategori yang sudah ada tidak dobel');
    });
  });

  // ==================================================================== mode latihan

  group('mode latihan', () {
    test('salinan: barang, harga, HPP, stok, akun, printer; tanpa server/token, transaksi, outbox', () {
      final id = isiBarang();
      final p = PengaturanRepo(db);
      p.simpan(PengaturanRepo.kServerUrl, 'https://pusat.contoh');
      p.simpan(PengaturanRepo.kTokenPerangkat, 'token-rahasia');
      p.simpan(PengaturanRepo.kPrinter, 'Printer uji');
      final shift = PenjualanRepo(db).bukaShift(cabangId: cabang.id, kasirId: kasir.id, modalAwal: 0);
      PenjualanRepo(db).simpan(
          cabang: cabang, kasir: kasir, shift: shift, keranjang: Keranjang()..tambah(katalog.untukKasirBarcode('8990001', cabang.id)!, qty: 2),
          metode: MetodeBayar.qris);

      final l = DatabaseToko.memori(jam: jam.call);
      LatihanRepo.isiDariAsli(asli: db, latihan: l, olehId: spv.id);
      final lk = KatalogRepo(l);
      expect(LatihanRepo.adalahLatihan(l), isTrue);
      expect(LatihanRepo.adalahLatihan(db), isFalse);
      expect(PengaturanRepo(l).infoCabang()!.kode, 'A01');
      final gula = lk.detail(id['8990001']!, cabang.id)!;
      expect((gula.stok, gula.hpp, gula.harga!.eceran, gula.stokMinimum), (48, 16200, 17500, 10));
      expect(PenggunaRepo(l).daftarLoginPin(cabang.id).map((u) => u.nama), containsAll(['Siti', 'Dewi']));
      expect(PengaturanRepo(l).ambil(PengaturanRepo.kPrinter), 'Printer uji');
      expect(PengaturanRepo(l).ambil(PengaturanRepo.kServerUrl), isNull);
      expect(PengaturanRepo(l).ambil(PengaturanRepo.kTokenPerangkat), isNull);
      expect(l.pilih('SELECT * FROM transaksi'), isEmpty);
      expect(l.pilih('SELECT * FROM outbox'), isEmpty);
      expect(() => LatihanRepo.isiDariAsli(asli: db, latihan: l, olehId: spv.id), throwsStateError, reason: 'hanya ke database kosong');
      expect(() => LatihanRepo.isiDariAsli(asli: l, latihan: DatabaseToko.memori(), olehId: spv.id), throwsStateError);
      l.tutup();
    });

    test('nyalakan (SPV), jual di latihan, kembali: stok, laporan, outbox asli tidak berubah; hapus data latihan', () async {
      final id = isiBarang();
      final asli = Aplikasi(db: db, printer: PrinterBerkas());
      final dibuka = <DatabaseToko>[];
      var dihapus = 0;
      final mode = PengaturMode(
        asli: asli,
        bukaDatabaseLatihan: () => DatabaseToko.memori(jam: jam.call)..let(dibuka.add),
        hapusDatabaseLatihan: () => dihapus++,
      );
      expect(() => mode.nyalakan(kasir), throwsStateError);
      expect(mode.latihanAktif, isFalse);

      final outboxDataAsli = db.pilih("SELECT * FROM outbox WHERE tabel <> 'log_aktivitas'").length;
      final logAsli = db.pilih('SELECT * FROM log_aktivitas').length;
      mode.nyalakan(spv);
      final l = mode.aktif;
      expect(l.latihan, isTrue);
      expect(l.sinkron.terdaftar, isFalse);
      expect(l.cadangkan(), contains('latihan'));
      l.masuk(kasir);
      final shift = l.penjualan.bukaShift(cabangId: cabang.id, kasirId: kasir.id, modalAwal: 100000);
      final h = l.penjualan.simpan(
          cabang: l.cabang, kasir: kasir, shift: shift, keranjang: Keranjang()..tambah(l.katalog.untukKasirBarcode('8990001', cabang.id)!, qty: 5),
          metode: MetodeBayar.tunai, uangDiterima: 100000);
      expect(h.noTransaksi, 'TRX-A01-261105-0001');
      expect(l.katalog.stok(id['8990001']!, cabang.id), 45);

      expect(katalog.stok(id['8990001']!, cabang.id), 50, reason: 'stok asli tidak berubah');
      final (dari, sampai) = (DateTime.utc(2026, 11, 4), DateTime.utc(2026, 11, 6));
      expect(LaporanRepo(db).ringkasan(cabang.id, dari, sampai).jumlahTransaksi, 0, reason: 'tidak masuk laporan asli');
      expect(db.pilih('SELECT * FROM transaksi'), isEmpty);
      expect(db.pilih("SELECT * FROM outbox WHERE tabel <> 'log_aktivitas'").length, outboxDataAsli,
          reason: 'tidak ada data latihan di antrean kirim asli');
      expect(db.pilih("SELECT aksi FROM log_aktivitas WHERE aksi = 'mode_latihan_nyala'"), hasLength(1));

      mode.matikan();
      expect(mode.latihanAktif, isFalse);
      expect(identical(mode.aktif, asli), isTrue);
      expect(db.pilih('SELECT * FROM log_aktivitas').length, logAsli + 2, reason: 'nyala + mati tercatat');

      // Nyalakan lagi dengan database yang sama berisi data latihan lama → tidak disalin ulang.
      mode.nyalakan(spv);
      expect(dibuka.length, 2);
      mode.hapusDataLatihan(spv);
      expect(dihapus, 1);
      expect(mode.latihanAktif, isTrue, reason: 'langsung diisi ulang dari data asli');
      expect(mode.aktif.katalog.stok(id['8990001']!, cabang.id), 50);
      expect(mode.aktif.db.pilih('SELECT * FROM transaksi'), isEmpty);
      mode.matikan();
    });

    test('struk latihan bertulisan LATIHAN dan tanpa barcode; cetakan lain diberi tulisan LATIHAN', () async {
      isiBarang();
      final printer = _PrinterCatat();
      final asli = Aplikasi(db: db, printer: printer);
      PengaturanRepo(db).simpan(PengaturanRepo.kPrinter, 'Printer uji');
      final mode = PengaturMode(asli: asli, bukaDatabaseLatihan: () => DatabaseToko.memori(jam: jam.call), hapusDatabaseLatihan: () {});
      mode.nyalakan(spv);
      final l = mode.aktif;
      final d = DataStruk(
        namaToko: 'TOKO UJI',
        namaCabang: 'Uji',
        alamat: '',
        noTransaksi: 'TRX-A01-261105-0001',
        waktu: jam.t,
        namaKasir: 'Siti',
        item: const [ItemStruk(nama: 'Gula', qty: 1, hargaSatuan: 17500, isGrosir: false)],
        metode: MetodeBayar.tunai,
        diterima: 20000,
        kembalian: 2500,
      );
      expect(await l.cetakStrukTransaksi(d), isNull);
      final teks = latin1.decode(printer.data.last);
      expect(RegExp(teksStrukLatihan).allMatches(teks).length, 2);
      expect(await l.kirimKePrinter(cetakBaris(const [BarisStruk('TUTUP SHIFT')])), isNull);
      expect(latin1.decode(printer.data.last), contains(teksStrukLatihan));
      expect(await asli.cetakStrukTransaksi(d), isNull);
      expect(latin1.decode(printer.data.last), isNot(contains(teksStrukLatihan)));
      mode.matikan();
    });
  });
}

extension<T> on T {
  T let(void Function(T) f) {
    f(this);
    return this;
  }
}

class _PrinterCatat implements LayananPrinter {
  final data = <Uint8List>[];
  @override
  List<String> daftarPrinter() => const ['Printer uji'];
  @override
  String? printerBawaan() => 'Printer uji';
  @override
  Future<void> cetak(String nama, Uint8List isi, {String judul = 'Struk POS'}) async => data.add(isi);
}
