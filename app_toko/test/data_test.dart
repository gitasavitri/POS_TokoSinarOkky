import 'dart:convert';
import 'dart:io';

import 'package:app_toko/data/database.dart';
import 'package:app_toko/data/model.dart';
import 'package:app_toko/data/repo/barang_masuk_repo.dart';
import 'package:app_toko/data/repo/harga_repo.dart';
import 'package:app_toko/data/repo/katalog_repo.dart';
import 'package:app_toko/data/repo/laporan_repo.dart';
import 'package:app_toko/data/repo/pengaturan_repo.dart';
import 'package:app_toko/data/repo/pengguna_repo.dart';
import 'package:app_toko/data/repo/penjualan_repo.dart';
import 'package:app_toko/data/repo/setup_repo.dart';
import 'package:app_toko/data/skema_migrasi.dart';
import 'package:app_toko/data/skema_v1.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_core/pos_core.dart';
import 'package:sqlite3/sqlite3.dart';

/// Jam palsu yang bisa dimajukan, supaya urutan waktu di test pasti.
class JamUji {
  DateTime t = DateTime.utc(2026, 11, 5, 2); // 09:00 WIB
  DateTime call() => t;
  void maju([int detik = 1]) => t = t.add(Duration(seconds: detik));
}

void main() {
  late DatabaseToko db;
  late JamUji jam;
  late InfoCabang cabang;
  late Pengguna admin, kasir, spv;
  late KatalogRepo katalog;
  late PenjualanRepo jual;
  late BarangMasukRepo masuk;

  Future<void> siapkan() async {
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
    final pengaturan = PengaturanRepo(db);
    cabang = pengaturan.infoCabang()!;
    final pengguna = PenggunaRepo(db);
    admin = pengguna.semua(cabang.id).firstWhere((p) => p.peran == Peran.admin);
    kasir = pengguna.ambil(await pengguna.tambah(
        cabangId: cabang.id, nama: 'Siti', peran: Peran.kasir, pin: '482913', olehId: admin.id))!;
    spv = pengguna.ambil(await pengguna.tambah(
        cabangId: cabang.id, nama: 'Dewi', peran: Peran.spv, pin: '739104', olehId: admin.id))!;
    katalog = KatalogRepo(db);
    jual = PenjualanRepo(db);
    masuk = BarangMasukRepo(db);
  }

  /// Barang baru lewat barang masuk: gula 50 pak HPP 16.200, eceran 17.500, grosir min 10 = 17.000.
  String masukkanGula({int jumlah = 50}) {
    final kat = katalog.kategori().firstWhere((k) => k.nama == 'Sembako');
    final draft = DraftBarangMasuk(supplierId: katalog.supplier().first.id, noFaktur: 'F-001', item: [
      DraftItemMasuk(
        barcode: '8990001',
        nama: 'Gula Pasir 1 kg',
        kategoriId: kat.id,
        satuan: 'pak',
        jumlah: jumlah,
        hpp: 16200,
        hargaJual: 17500,
        grosir: [const TingkatGrosir(minQty: 10, harga: 17000)],
      ),
    ]);
    masuk.kirim(cabang: cabang, oleh: kasir, draft: draft);
    jam.maju();
    return katalog.cariBarcode('8990001', cabang.id)!.id;
  }

  setUp(siapkan);
  tearDown(() => db.tutup());

  test('skema di aplikasi sama dengan database/schema_toko.sql + database/migrasi', () {
    expect(skemaV1, File('../database/schema_toko.sql').readAsStringSync());
    final file = Directory('../database/migrasi').listSync().whereType<File>().where((f) => f.path.endsWith('.sql')).toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    expect(skemaMigrasi, [for (final f in file) f.readAsStringSync()], reason: 'jalankan: dart run tool/salin_skema.dart');
    expect(db.versiSkema, 1 + skemaMigrasi.length);
  });

  test('database versi 1 lama naik ke versi terbaru tanpa kehilangan data', () {
    final folder = Directory.systemTemp.createTempSync('pos_migrasi');
    final path = '${folder.path}/lama.db';
    final lama = DatabaseToko.buka(path);
    lama.tutup();
    // Buat ulang sebagai versi 1 murni (seperti PC toko yang memakai versi aplikasi sebelumnya).
    File(path).deleteSync();
    final v1 = sqlite3.open(path)
      ..execute(skemaV1)
      ..execute('PRAGMA user_version = 1')
      ..execute("INSERT INTO kategori VALUES ('k1','Sembako',1,'2026-11-01T00:00:00Z')");
    v1.close();
    final baru = DatabaseToko.buka(path);
    expect(baru.versiSkema, 1 + skemaMigrasi.length);
    expect(baru.satu('SELECT nama FROM kategori')!['nama'], 'Sembako');
    expect(baru.satu("SELECT name FROM sqlite_master WHERE name = 'kas_shift'"), isNotNull);
    baru.tutup();
    folder.deleteSync(recursive: true);
  });

  group('setup & pengguna', () {
    test('setup membuat cabang, kategori awal, supplier toko utama', () {
      expect(cabang.kode, 'A01');
      expect(cabang.namaToko, 'TOKO UJI');
      expect(katalog.kategori().map((k) => k.nama), contains('Sabun & Sampo'));
      expect(katalog.supplier().first.jenis, 'toko_utama');
      expect(PengaturanRepo(db).sudahDisiapkan, isTrue);
    });

    test('setup kedua kali ditolak', () async {
      expect(
        () => SetupRepo(db).siapkan(
            namaToko: 'X', kodeCabang: 'B01', namaCabang: 'X', alamat: '', pesanStruk: '', namaAdmin: 'X',
            namaPenggunaAdmin: 'x', sandiAdmin: 'xxxxxxxxxxxx', rahasiaTotp: 'GEZDGNBV'),
        throwsStateError,
      );
    });

    test('login PIN benar, salah, lalu terkunci setelah 5 kali', () async {
      final repo = PenggunaRepo(db);
      expect((await repo.masukPin(kasir.id, '482913')).berhasil, isTrue);
      for (var i = 1; i <= 4; i++) {
        final h = await repo.masukPin(kasir.id, '000001');
        expect(h.berhasil, isFalse);
        expect(h.pesan, contains('Sisa ${5 - i}'));
      }
      final kunci = await repo.masukPin(kasir.id, '000001');
      expect(kunci.terkunci, isTrue);
      // PIN benar pun ditolak saat terkunci
      expect((await repo.masukPin(kasir.id, '482913')).terkunci, isTrue);
      repo.bukaKunci(kasir.id, olehId: admin.id);
      expect((await repo.masukPin(kasir.id, '482913')).berhasil, isTrue);
    });

    test('PIN tidak pernah tersimpan atau tercatat dalam bentuk asli', () async {
      await PenggunaRepo(db).masukPin(kasir.id, '000001');
      for (final tabel in ['pengguna', 'log_aktivitas', 'outbox']) {
        final semua = db.pilih('SELECT * FROM $tabel').map((r) => r.values.join('|')).join('\n');
        expect(semua, isNot(contains('482913')), reason: tabel);
        expect(semua, isNot(contains('000001')), reason: tabel);
      }
    });

    test('login admin butuh sandi dan kode verifikasi', () async {
      final repo = PenggunaRepo(db);
      final kode = await kodeTotp(base32Encode(ascii.encode('12345678901234567890')), jam.t);
      expect((await repo.masukAdmin('admin.uji', 'salah-sandi-1', kode)).berhasil, isFalse);
      final salahKode = await repo.masukAdmin('admin.uji', 'sandi-panjang-1', '000000');
      expect(salahKode.pesan, contains('Kode verifikasi'));
      expect((await repo.masukAdmin('admin.uji', 'sandi-panjang-1', kode)).berhasil, isTrue);
    });

    test('persetujuan PIN hanya untuk SPV/Admin', () async {
      final repo = PenggunaRepo(db);
      expect(await repo.setujuiDenganPin(spv.id, '739104'), isNotNull);
      expect(await repo.setujuiDenganPin(kasir.id, '482913'), isNull);
      expect(repo.daftarPenyetuju(cabang.id).map((p) => p.nama), containsAll(['Dewi', 'Admin Uji']));
    });
  });

  group('barang masuk', () {
    test('barang baru: stok, HPP, harga, grosir, terdaftar di toko', () {
      final id = masukkanGula();
      final d = katalog.detail(id, cabang.id)!;
      expect(d.stok, 50);
      expect(d.hpp, 16200);
      expect(d.harga!.eceran, 17500);
      expect(d.harga!.grosir, [const TingkatGrosir(minQty: 10, harga: 17000)]);
      expect(d.dijualDiToko, isTrue);
      expect(katalog.untukKasirBarcode('8990001', cabang.id), isNotNull);
    });

    test('barang masuk terkunci setelah dikirim', () {
      masukkanGula();
      expect(() => db.jalankan("UPDATE barang_masuk_item SET jumlah = 1"), throwsA(anything));
      expect(() => db.jalankan("DELETE FROM barang_masuk"), throwsA(anything));
    });

    test('barang datang lagi: HPP rata-rata tertimbang dan harga baru + antrean label', () {
      final id = masukkanGula(jumlah: 12);
      final item = masuk.itemDariBarang(katalog.detail(id, cabang.id)!)
        ..jumlah = 50
        ..hpp = 16400
        ..hargaJual = 18000
        ..grosir = [const TingkatGrosir(minQty: 10, harga: 17500)];
      expect(item.status, 'Data diubah');
      masuk.kirim(
          cabang: cabang,
          oleh: kasir,
          draft: DraftBarangMasuk(supplierId: katalog.supplier().first.id, noFaktur: 'F-002', item: [item]));
      final d = katalog.detail(id, cabang.id)!;
      expect(d.stok, 62);
      // (12 × 16.200 + 50 × 16.400) / 62 = 16.361,29 → 16.361
      expect(d.hpp, 16361);
      expect(d.harga!.eceran, 18000);
      expect(HargaRepo(db).antreanLabel().single.hargaBaru, 18000);
    });

    test('validasi: harga jual ≤ HPP, grosir lebih mahal, barcode dobel', () {
      masukkanGula();
      final kat = katalog.kategori().first.id;
      final draft = DraftBarangMasuk(supplierId: katalog.supplier().first.id, noFaktur: 'F-3', item: [
        DraftItemMasuk(barcode: '8990001', nama: 'Dobel', kategoriId: kat, jumlah: 1, hpp: 100, hargaJual: 200),
        DraftItemMasuk(nama: 'Rugi', kategoriId: kat, jumlah: 1, hpp: 500, hargaJual: 400),
        DraftItemMasuk(
            nama: 'Grosir', kategoriId: kat, jumlah: 1, hpp: 100, hargaJual: 200,
            grosir: [const TingkatGrosir(minQty: 5, harga: 250)]),
      ]);
      final salah = masuk.periksa(draft);
      expect(salah[0]!.first, contains('Barcode sudah dipakai'));
      expect(salah[1]!.first, contains('lebih besar dari HPP'));
      expect(salah[2]!.first, contains('lebih murah'));
      expect(() => masuk.kirim(cabang: cabang, oleh: kasir, draft: draft), throwsArgumentError);
      expect(db.pilih('SELECT * FROM barang_masuk').length, 1, reason: 'yang gagal tidak tersimpan sama sekali');
    });

    test('koreksi: kasir minta, SPV setujui → stok ikut berubah', () {
      final id = masukkanGula();
      final itemId = masuk.riwayat(cabang.id).single.item.single.itemId;
      final kid = masuk.mintaKoreksi(itemId: itemId, jumlahBaru: 45, alasan: 'salah ketik', oleh: kasir);
      expect(masuk.daftarKoreksi(cabang.id, hanyaMenunggu: true).length, 1);
      expect(() => masuk.putuskanKoreksi(koreksiId: kid, setuju: true, oleh: kasir), throwsStateError);
      masuk.putuskanKoreksi(koreksiId: kid, setuju: true, oleh: spv);
      expect(katalog.stok(id, cabang.id), 45);
      expect(masuk.riwayat(cabang.id).single.item.single.jumlahBerlaku, 45);
      expect(() => masuk.putuskanKoreksi(koreksiId: kid, setuju: false, oleh: spv), throwsStateError);
      // koreksi kedua dihitung dari jumlah yang sudah dikoreksi
      jam.maju();
      final k2 = masuk.mintaKoreksi(itemId: itemId, jumlahBaru: 47, alasan: 'hitung ulang', oleh: kasir);
      jam.maju();
      masuk.putuskanKoreksi(koreksiId: k2, setuju: true, oleh: spv);
      expect(katalog.stok(id, cabang.id), 47);
    });

    test('stok opname mencatat selisih', () {
      final id = masukkanGula();
      expect(masuk.stokOpname(cabangId: cabang.id, barangId: id, stokFisik: 48, alasan: 'hitung', oleh: spv), -2);
      expect(katalog.stok(id, cabang.id), 48);
      expect(() => masuk.stokOpname(cabangId: cabang.id, barangId: id, stokFisik: 1, alasan: '', oleh: kasir),
          throwsStateError);
    });
  });

  group('penjualan', () {
    test('simpan transaksi: nomor urut, grosir, stok berkurang, outbox terisi', () {
      final id = masukkanGula();
      final shift = jual.bukaShift(cabangId: cabang.id, kasirId: kasir.id, modalAwal: 500000);
      final k = Keranjang()..tambah(katalog.untukKasirBarcode('8990001', cabang.id)!, qty: 15);
      final h = jual.simpan(
          cabang: cabang, kasir: kasir, shift: shift, keranjang: k, metode: MetodeBayar.tunai, uangDiterima: 300000);
      expect(h.noTransaksi, 'TRX-A01-261105-0001');
      expect(h.struk.total, 15 * 17000);
      expect(h.struk.kembalian, 300000 - 255000);
      expect(h.struk.item.single.isGrosir, isTrue);
      expect(katalog.stok(id, cabang.id), 35);
      final tabelOutbox = db.pilih('SELECT DISTINCT tabel FROM outbox').map((r) => r['tabel']).toSet();
      expect(tabelOutbox, containsAll(['transaksi', 'transaksi_item', 'pembayaran', 'mutasi_stok']));
      jam.maju();
      final h2 = jual.simpan(
          cabang: cabang, kasir: kasir, shift: shift, keranjang: Keranjang()..tambah(k.baris.first.barang),
          metode: MetodeBayar.qris);
      expect(h2.noTransaksi, 'TRX-A01-261105-0002');
    });

    test('uang kurang tidak tersimpan', () {
      masukkanGula();
      final shift = jual.bukaShift(cabangId: cabang.id, kasirId: kasir.id, modalAwal: 0);
      final k = Keranjang()..tambah(katalog.untukKasirBarcode('8990001', cabang.id)!);
      expect(
          () => jual.simpan(
              cabang: cabang, kasir: kasir, shift: shift, keranjang: k, metode: MetodeBayar.tunai, uangDiterima: 1000),
          throwsArgumentError);
      expect(db.pilih('SELECT * FROM transaksi'), isEmpty);
    });

    test('pembatalan mengembalikan stok tanpa mengubah transaksi asli', () {
      final id = masukkanGula();
      final shift = jual.bukaShift(cabangId: cabang.id, kasirId: kasir.id, modalAwal: 0);
      final k = Keranjang()..tambah(katalog.untukKasirBarcode('8990001', cabang.id)!, qty: 3);
      final h = jual.simpan(
          cabang: cabang, kasir: kasir, shift: shift, keranjang: k, metode: MetodeBayar.tunai, uangDiterima: 60000);
      jual.batalkan(transaksiId: h.transaksiId, alasan: 'salah input', dimintaOleh: kasir.id, disetujuiOleh: spv.id);
      expect(katalog.stok(id, cabang.id), 50);
      expect(() => jual.batalkan(transaksiId: h.transaksiId, alasan: 'x', dimintaOleh: kasir.id, disetujuiOleh: spv.id),
          throwsStateError);
      expect(jual.struk(h.transaksiId, cabang)!.dibatalkan, isTrue);
      final log = db.satu("SELECT * FROM log_aktivitas WHERE aksi = 'batal_transaksi'")!;
      expect(log['pengguna_id'], kasir.id);
      expect(log['disetujui_oleh'], spv.id);
    });

    test('retur, shift, dan laporan harian', () {
      final id = masukkanGula();
      final shift = jual.bukaShift(cabangId: cabang.id, kasirId: kasir.id, modalAwal: 500000);
      final gula = katalog.untukKasirBarcode('8990001', cabang.id)!;
      final h1 = jual.simpan(
          cabang: cabang, kasir: kasir, shift: shift, keranjang: Keranjang()..tambah(gula, qty: 2),
          metode: MetodeBayar.tunai, uangDiterima: 50000); // 35.000
      jam.maju();
      jual.simpan(
          cabang: cabang, kasir: kasir, shift: shift, keranjang: Keranjang()..tambah(gula, qty: 10),
          metode: MetodeBayar.kartu, noReferensi: '0045'); // 170.000
      jam.maju();
      final itemId = jual.itemUntukRetur(h1.transaksiId).single.itemId;
      expect(() => jual.retur(transaksiId: h1.transaksiId, qtyPerItem: {itemId: 3}, kembaliKeStok: true, alasan: 'x', olehId: spv.id),
          throwsArgumentError);
      final kembali = jual.retur(
          transaksiId: h1.transaksiId, qtyPerItem: {itemId: 1}, kembaliKeStok: true, alasan: 'rusak kemasan', olehId: spv.id);
      expect(kembali, 17500);
      expect(katalog.stok(id, cabang.id), 50 - 12 + 1);

      final ring = jual.ringkasanShift(shift.id);
      expect(ring.penjualanTunai, 35000);
      expect(ring.penjualanNonTunai, 170000);
      expect(ring.kasSistem, 500000 + 35000 - 17500);
      expect(() => jual.tutupShift(shiftId: shift.id, olehId: kasir.id), throwsStateError, reason: 'wajib hitung dulu');
      jual.simpanHitungan(shiftId: shift.id, kasDihitung: 517000, oleh: kasir);
      final tutup = jual.tutupShift(shiftId: shift.id, olehId: kasir.id);
      expect(tutup.kasSistem, 517500);
      expect(db.satu('SELECT selisih FROM shift_tutup')!['selisih'], -500);
      expect(jual.shiftAktif(kasir.id), isNull);

      final lap = LaporanRepo(db);
      final dari = awalHariWibUtc(jam.t), sampai = dari.add(const Duration(days: 1));
      final r = lap.ringkasan(cabang.id, dari, sampai);
      expect(r.jumlahTransaksi, 2);
      expect(r.penjualanBersih, 35000 + 170000 - 17500);
      expect(r.tunai, 35000);
      expect(r.nonTunai, 170000);
      // laba: 2×(17.500−16.200) + 10×(17.000−16.200) − 1×(17.500−16.200)
      expect(r.labaKotor, 2600 + 8000 - 1300);
      expect(lap.daftarTransaksi(cabang.id, dari, sampai).first.metode, MetodeBayar.kartu);
      expect(lap.daftarTransaksi(cabang.id, dari, sampai).last.status, 'Retur');
      expect(lap.terlaris(cabang.id, dari, sampai).single.qty, 12);
      expect(lap.perluDicek(cabang.id, dari, sampai).selisihKas, 1);
      expect(lap.csvTransaksi(lap.daftarTransaksi(cabang.id, dari, sampai)), contains('TRX-A01-261105-0002'));
    });
  });

  group('kas keluar/masuk & hitung buta', () {
    test('kas keluar/masuk mengubah uang seharusnya; kasir ≥ Rp100.000 wajib PIN SPV', () {
      final shift = jual.bukaShift(cabangId: cabang.id, kasirId: kasir.id, modalAwal: 200000);
      jual.catatKas(shiftId: shift.id, jenis: JenisKas.keluar, jumlah: 20000, keterangan: 'Beli galon', oleh: kasir);
      jam.maju();
      jual.catatKas(shiftId: shift.id, jenis: JenisKas.masuk, jumlah: 50000, keterangan: 'Tambah uang kecil', oleh: kasir);
      jam.maju();
      expect(
        () => jual.catatKas(shiftId: shift.id, jenis: JenisKas.keluar, jumlah: 100000, keterangan: 'Bayar titipan kue', oleh: kasir),
        throwsStateError,
      );
      expect(
        () => jual.catatKas(
            shiftId: shift.id, jenis: JenisKas.keluar, jumlah: 100000, keterangan: 'Bayar titipan kue', oleh: kasir, disetujuiOleh: kasir),
        throwsStateError,
        reason: 'kasir tidak bisa menyetujui sendiri',
      );
      expect(() => jual.catatKas(shiftId: shift.id, jenis: JenisKas.keluar, jumlah: 5000, keterangan: ' ', oleh: kasir), throwsArgumentError);
      jual.catatKas(shiftId: shift.id, jenis: JenisKas.keluar, jumlah: 100000, keterangan: 'Bayar titipan kue', oleh: kasir, disetujuiOleh: spv);

      final ring = jual.ringkasanShift(shift.id);
      expect(ring.kasMasuk, 50000);
      expect(ring.kasKeluar, 120000);
      expect(ring.kasSistem, 200000 + 50000 - 120000);
      final daftar = jual.daftarKas(shift.id);
      expect(daftar.map((k) => k.jumlah), [20000, 50000, 100000]);
      expect(daftar.last.namaPenyetuju, 'Dewi');
      expect(db.satu("SELECT COUNT(*) AS n FROM outbox WHERE tabel = 'kas_shift'")!['n'], 3);
      expect(db.satu("SELECT disetujui_oleh FROM log_aktivitas WHERE aksi = 'kas_keluar' ORDER BY created_at DESC LIMIT 1")!['disetujui_oleh'],
          spv.id);
    });

    test('hitung buta: hitungan + 2 hitung ulang tercatat, ke-4 butuh PIN SPV, tutup pakai hitungan terakhir', () {
      final shift = jual.bukaShift(cabangId: cabang.id, kasirId: kasir.id, modalAwal: 200000);
      final h1 = jual.simpanHitungan(shiftId: shift.id, kasDihitung: 180000, oleh: kasir);
      expect(h1.ke, 1);
      expect(h1.selisih, -20000);
      jam.maju();
      jual.simpanHitungan(shiftId: shift.id, kasDihitung: 190000, oleh: kasir);
      jam.maju();
      jual.simpanHitungan(shiftId: shift.id, kasDihitung: 195000, oleh: kasir);
      jam.maju();
      expect(() => jual.simpanHitungan(shiftId: shift.id, kasDihitung: 200000, oleh: kasir), throwsStateError);
      final h4 = jual.simpanHitungan(shiftId: shift.id, kasDihitung: 200000, oleh: kasir, disetujuiOleh: spv);
      expect(h4.ke, 4);
      expect(h4.disetujuiOleh, spv.id);
      expect(jual.hitunganShift(shift.id).map((h) => h.kasDihitung), [180000, 190000, 195000, 200000]);

      jual.tutupShift(shiftId: shift.id, olehId: kasir.id);
      expect(db.satu('SELECT kas_dihitung, selisih FROM shift_tutup')!['kas_dihitung'], 200000);
      expect(() => jual.simpanHitungan(shiftId: shift.id, kasDihitung: 1, oleh: spv), throwsStateError);
      expect(() => jual.catatKas(shiftId: shift.id, jenis: JenisKas.masuk, jumlah: 1000, keterangan: 'telat', oleh: spv), throwsStateError);
      expect(db.satu("SELECT COUNT(*) AS n FROM outbox WHERE tabel = 'shift_hitung'")!['n'], 4);
    });

    test('hitungan lama tidak berlaku kalau ada transaksi baru sesudahnya', () {
      final id = masukkanGula();
      final gula = katalog.untukKasir(id, cabang.id)!;
      final shift = jual.bukaShift(cabangId: cabang.id, kasirId: kasir.id, modalAwal: 100000);
      for (var i = 0; i < 3; i++) {
        jual.simpanHitungan(shiftId: shift.id, kasDihitung: 100000, oleh: kasir);
        jam.maju();
      }
      // Batal tutup shift, lalu berjualan lagi.
      jual.simpan(cabang: cabang, kasir: kasir, shift: shift, keranjang: Keranjang()..tambah(gula), metode: MetodeBayar.tunai, uangDiterima: 17500);
      jam.maju();
      expect(() => jual.tutupShift(shiftId: shift.id, olehId: kasir.id), throwsStateError, reason: 'hitungan sudah basi');
      expect(jual.hitunganBerlaku(shift.id), 0);
      final h = jual.simpanHitungan(shiftId: shift.id, kasDihitung: 117500, oleh: kasir); // tanpa PIN SPV
      expect(h.ke, 4);
      expect(h.selisih, 0);
      jual.tutupShift(shiftId: shift.id, olehId: kasir.id);
    });

    test('SPV boleh hitung ulang tanpa batas', () {
      final shift = jual.bukaShift(cabangId: cabang.id, kasirId: spv.id, modalAwal: 0);
      for (var i = 0; i < 5; i++) {
        jual.simpanHitungan(shiftId: shift.id, kasDihitung: i, oleh: spv);
        jam.maju();
      }
      expect(jual.hitunganShift(shift.id).length, 5);
    });
  });

  group('ubah harga', () {
    test('naik: kasir boleh langsung; harga khusus toko', () {
      final id = masukkanGula();
      HargaRepo(db).ubahHarga(cabang: cabang, barangId: id, hargaBaru: 18000, grosir: const [], alasan: 'Harga dari supplier naik', oleh: kasir);
      expect(katalog.detail(id, cabang.id)!.harga!.eceran, 18000);
      expect(db.satu("SELECT cabang_id FROM harga_jual WHERE sumber = 'ubah_harga'")!['cabang_id'], cabang.id);
    });

    test('turun > 10% atau di bawah HPP: kasir butuh PIN SPV', () {
      final id = masukkanGula();
      final repo = HargaRepo(db);
      expect(
          () => repo.ubahHarga(cabang: cabang, barangId: id, hargaBaru: 15000, grosir: const [], alasan: 'Promo', oleh: kasir),
          throwsStateError);
      repo.ubahHarga(
          cabang: cabang, barangId: id, hargaBaru: 15000, grosir: const [], alasan: 'Promo', oleh: kasir, disetujuiOleh: spv);
      expect(katalog.detail(id, cabang.id)!.harga!.eceran, 15000);
      final log = db.satu("SELECT * FROM log_aktivitas WHERE aksi = 'ubah_harga'")!;
      expect(log['disetujui_oleh'], spv.id);
    });

    test('harga dari pusat yang lebih baru menggantikan harga khusus toko', () {
      final id = masukkanGula();
      jam.maju(60);
      db.jalankan(
        "INSERT INTO harga_jual (id, barang_id, cabang_id, harga, sumber, alasan, dibuat_oleh, berlaku_mulai, created_at)"
        " VALUES ('pusat-1', ?, NULL, 19000, 'pusat', '', ?, ?, ?)",
        [id, admin.id, db.sekarangIso(), db.sekarangIso()],
      );
      expect(katalog.detail(id, cabang.id)!.harga!.eceran, 19000);
    });
  });

  test('semua perubahan tercatat di outbox dalam bentuk JSON lengkap', () {
    masukkanGula();
    final r = db.satu("SELECT payload FROM outbox WHERE tabel = 'barang'")!;
    final j = jsonDecode(r['payload'] as String) as Map<String, Object?>;
    expect(j['nama'], 'Gula Pasir 1 kg');
    expect(j['barcode'], '8990001');
  });
}
