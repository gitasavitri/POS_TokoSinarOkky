import 'dart:convert';
import 'dart:io';

import 'package:app_toko/data/database.dart';
import 'package:app_toko/data/model.dart';
import 'package:app_toko/data/repo/barang_masuk_repo.dart';
import 'package:app_toko/data/repo/harga_repo.dart';
import 'package:app_toko/data/repo/katalog_repo.dart';
import 'package:app_toko/data/repo/laporan_repo.dart';
import 'package:app_toko/data/repo/pengaturan_repo.dart';
import 'package:app_toko/data/repo/pemulihan_repo.dart';
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
      expect(() => jual.retur(cabang: cabang, transaksiId: h1.transaksiId, qtyPerItem: {itemId: 3}, alasan: 'salah beli', oleh: spv),
          throwsArgumentError);
      final kembali = jual.retur(
          cabang: cabang, transaksiId: h1.transaksiId, qtyPerItem: {itemId: 1}, alasan: 'rusak kemasan', oleh: spv);
      expect(kembali.total, 17500);
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

  group('tutup shift "Belum dihitung" (revisi P)', () {
    test('kasir menutup tanpa menghitung → menunggu dihitung; SPV menghitung amplop, selisih tercatat ke kasir', () {
      final id = masukkanGula();
      final gula = katalog.untukKasir(id, cabang.id)!;
      final shift = jual.bukaShift(cabangId: cabang.id, kasirId: kasir.id, modalAwal: 200000);
      jual.simpan(cabang: cabang, kasir: kasir, shift: shift, keranjang: Keranjang()..tambah(gula, qty: 2), metode: MetodeBayar.tunai, uangDiterima: 50000);
      jam.maju();
      jual.catatKas(shiftId: shift.id, jenis: JenisKas.keluar, jumlah: 10000, keterangan: 'Beli galon', oleh: kasir);
      jam.maju();
      // Uang seharusnya: 200.000 + 35.000 − 10.000 = 225.000. Modal tetap 200.000 → amplop seharusnya 25.000.
      final m = jual.tutupShiftBelumDihitung(shiftId: shift.id, oleh: kasir, modalTetap: 200000);
      expect(m.kasSistem, 225000);
      expect(m.modalDitinggal, 200000);
      expect(m.namaKasir, 'Siti');
      expect(m.labelAmplop, startsWith('Siti · '));
      expect(m.jumlahTransaksi, 1);
      expect(jual.shiftAktif(kasir.id), isNull, reason: 'shift tidak aktif lagi');
      expect(jual.shiftMenungguDihitung(cabang.id).map((x) => x.shiftId), [shift.id]);
      expect(LaporanRepo(db).perluDicek(cabang.id, DateTime.utc(2000), DateTime.utc(2100)).shiftMenunggu, 1);
      expect(() => jual.catatKas(shiftId: shift.id, jenis: JenisKas.masuk, jumlah: 1000, keterangan: 'telat', oleh: kasir), throwsStateError);
      expect(() => jual.simpan(cabang: cabang, kasir: kasir, shift: shift, keranjang: Keranjang()..tambah(gula), metode: MetodeBayar.qris),
          throwsA(anything), reason: 'tidak boleh berjualan di shift yang sudah ditutup');
      expect(() => jual.tutupShiftBelumDihitung(shiftId: shift.id, oleh: kasir, modalTetap: 0), throwsStateError);

      // Kasir berikutnya bisa langsung buka shift baru.
      expect(jual.bukaShift(cabangId: cabang.id, kasirId: kasir.id, modalAwal: 200000).id, isNot(shift.id));

      expect(() => jual.hitungAmplop(shiftId: shift.id, amplopDihitung: 20000, oleh: kasir), throwsStateError, reason: 'kasir tidak boleh');
      jam.maju(3600);
      final h = jual.hitungAmplop(shiftId: shift.id, amplopDihitung: 20000, oleh: spv);
      expect(h.selisih, -5000);
      expect(h.amplopSeharusnya, 25000);
      final tutup = db.satu('SELECT * FROM shift_tutup WHERE shift_id = ?', [shift.id])!;
      expect(tutup['kas_dihitung'], 220000);
      expect(tutup['selisih'], -5000);
      expect(tutup['ditutup_oleh'], spv.id);
      final hitung = jual.hitunganShift(shift.id).single;
      expect(hitung.kasDihitung, 220000);
      expect(db.satu("SELECT dihitung_oleh FROM shift_hitung WHERE shift_id = ?", [shift.id])!['dihitung_oleh'], spv.id);
      final log = db.satu("SELECT detail, disetujui_oleh FROM log_aktivitas WHERE aksi = 'hitung_amplop_shift'")!;
      expect(jsonDecode(log['detail']! as String)['kasir_id'], kasir.id);
      expect(jual.shiftMenungguDihitung(cabang.id), isEmpty);
      expect(() => jual.hitungAmplop(shiftId: shift.id, amplopDihitung: 25000, oleh: spv), throwsStateError, reason: 'hanya sekali');
      // Ringkasan shift tetap memakai batas waktu saat kasir menutup.
      expect(jual.ringkasanShift(shift.id).kasSistem, 225000);
      for (final t in ['shift_belum_dihitung', 'shift_hitung', 'shift_tutup']) {
        expect(db.satu('SELECT COUNT(*) AS n FROM outbox WHERE tabel = ?', [t])!['n'], 1, reason: t);
      }
    });

    test('tanpa modal tetap semua uang masuk amplop; tidak bisa dipakai kalau uang sudah dihitung', () {
      final shift = jual.bukaShift(cabangId: cabang.id, kasirId: kasir.id, modalAwal: 150000);
      final m = jual.tutupShiftBelumDihitung(shiftId: shift.id, oleh: kasir, modalTetap: 0);
      expect(m.modalDitinggal, 0);
      expect(jual.hitungAmplop(shiftId: shift.id, amplopDihitung: 150000, oleh: admin).selisih, 0);

      final s2 = jual.bukaShift(cabangId: cabang.id, kasirId: kasir.id, modalAwal: 100000);
      jual.simpanHitungan(shiftId: s2.id, kasDihitung: 100000, oleh: kasir);
      expect(() => jual.tutupShiftBelumDihitung(shiftId: s2.id, oleh: kasir, modalTetap: 0), throwsStateError);
    });

    test('modal tetap hanya diatur Admin', () {
      final p = PengaturanRepo(db);
      expect(p.modalTetap, 0);
      expect(() => p.aturModalTetap(200000, cabangId: cabang.id, oleh: spv), throwsStateError);
      expect(() => p.aturModalTetap(-1, cabangId: cabang.id, oleh: admin), throwsArgumentError);
      p.aturModalTetap(200000, cabangId: cabang.id, oleh: admin);
      expect(p.modalTetap, 200000);
      expect(db.satu("SELECT COUNT(*) AS n FROM log_aktivitas WHERE aksi = 'atur_modal_tetap'")!['n'], 1);
    });
  });

  group('riwayat transaksi (revisi D, E)', () {
    test('transaksi shift hanya milik shift itu; detail berisi barang per baris', () {
      final id = masukkanGula();
      final gula = katalog.untukKasir(id, cabang.id)!;
      final s1 = jual.bukaShift(cabangId: cabang.id, kasirId: kasir.id, modalAwal: 0);
      final s2 = jual.bukaShift(cabangId: cabang.id, kasirId: spv.id, modalAwal: 0);
      final t1 = jual.simpan(cabang: cabang, kasir: kasir, shift: s1, keranjang: Keranjang()..tambah(gula, qty: 12), metode: MetodeBayar.tunai, uangDiterima: 300000);
      jam.maju();
      jual.simpan(cabang: cabang, kasir: spv, shift: s2, keranjang: Keranjang()..tambah(gula), metode: MetodeBayar.qris);
      jam.maju();
      final t3 = jual.simpan(cabang: cabang, kasir: kasir, shift: s1, keranjang: Keranjang()..tambah(gula), metode: MetodeBayar.qris);
      jam.maju();
      jual.batalkan(transaksiId: t3.transaksiId, alasan: 'salah input', dimintaOleh: kasir.id, disetujuiOleh: spv.id);

      final daftar = jual.transaksiShift(s1.id);
      expect(daftar.map((t) => t.noTransaksi), [t3.noTransaksi, t1.noTransaksi], reason: 'terbaru dulu, tanpa transaksi shift lain');
      expect(daftar.first.dibatalkan, isTrue);
      final r = jual.ringkasanShift(s1.id);
      expect(r.jumlahTransaksi, 1, reason: 'yang dibatalkan tidak dihitung');
      expect(r.penjualanTunai, 12 * 17000);

      final d = jual.detailTransaksi(t1.transaksiId, cabang)!;
      expect(d.item.single.qty, 12);
      expect(d.item.single.hargaSatuan, 17000);
      expect(d.item.single.isGrosir, isTrue);
      expect(d.item.single.subtotal, 204000);
      expect(d.item.single.barangId, id);
      expect(d.status, 'Lunas');
      expect(d.kasirId, kasir.id);
      expect(d.struk.kembalian, 96000);
      expect(jual.detailTransaksi(t3.transaksiId, cabang)!.status, 'Dibatalkan');
      expect(jual.detailTransaksi('tidak-ada', cabang), isNull);
    });
  });

  group('tukar / kembalikan barang (revisi F)', () {
    /// Gula 2 pak dibayar [metode] di shift kasir. Mengembalikan (shift, transaksi, item id).
    (Shift, HasilSimpanTransaksi, String) jualGula({MetodeBayar metode = MetodeBayar.tunai, int qty = 2, int modal = 100000}) {
      masukkanGula();
      final shift = jual.bukaShift(cabangId: cabang.id, kasirId: kasir.id, modalAwal: modal);
      final gula = katalog.untukKasirBarcode('8990001', cabang.id)!;
      final h = jual.simpan(
        cabang: cabang,
        kasir: kasir,
        shift: shift,
        keranjang: Keranjang()..tambah(gula, qty: qty),
        metode: metode,
        uangDiterima: metode == MetodeBayar.tunai ? 50000 : 0,
        noReferensi: metode.perluReferensi ? '0045' : null,
      );
      jam.maju(60);
      return (shift, h, jual.itemUntukRetur(h.transaksiId).single.itemId);
    }

    String idGula() => katalog.untukKasirBarcode('8990001', cabang.id)!.id;

    test('kasir retur sendiri: uang tunai walau bayar QRIS, nomor RTR, barang rusak tidak masuk stok, perlu dicek', () {
      final (shift, h, itemId) = jualGula(metode: MetodeBayar.qris);
      final r = jual.retur(
        cabang: cabang,
        transaksiId: h.transaksiId,
        qtyPerItem: {itemId: 2},
        rusak: {itemId},
        alasan: 'kemasan bocor',
        oleh: kasir,
        shiftId: shift.id,
      );
      expect(r.noRetur, 'RTR-A01-261105-0001');
      expect(r.total, 35000);
      expect(katalog.stok(idGula(), cabang.id), 48, reason: 'rusak: tidak kembali ke stok jual');
      final ring = jual.ringkasanShift(shift.id);
      expect(ring.penjualanNonTunai, 35000);
      expect(ring.returTunai, 35000, reason: 'uang retur selalu tunai');
      expect(ring.kasSistem, 100000 - 35000);
      final baris = db.satu('SELECT * FROM retur')!;
      expect((baris['shift_id'], baris['cabang_id'], baris['disetujui_oleh']), (shift.id, cabang.id, null));
      expect(db.satu('SELECT kembali_ke_stok FROM retur_item')!['kembali_ke_stok'], 0);
      final log = db.satu("SELECT * FROM log_aktivitas WHERE aksi = 'retur'")!;
      expect(log['pengguna_id'], kasir.id);
      expect(jsonDecode(log['detail'] as String)['jumlah_rusak'], 2);
      final dari = awalHariWibUtc(jam.t), sampai = dari.add(const Duration(days: 1));
      expect(LaporanRepo(db).perluDicek(cabang.id, dari, sampai).returKasir, 1);
      final riwayat = jual.daftarRetur(cabang.id, dari, sampai, hanyaKasir: true).single;
      expect((riwayat.noRetur, riwayat.olehKasir, riwayat.jumlahRusak, riwayat.tunai), ('RTR-A01-261105-0001', true, 2, 35000));
      final struk = strukSebagaiTeks(susunStrukRetur(jual.strukRetur(r.returId, cabang)!));
      expect(struk, contains('RTR-A01-261105-0001'));
      expect(struk, contains(h.noTransaksi));
      // Retur kedua hari yang sama: urut berikutnya; barang sudah habis diretur.
      expect(() => jual.retur(cabang: cabang, transaksiId: h.transaksiId, qtyPerItem: {itemId: 1}, alasan: 'lagi', oleh: kasir),
          throwsArgumentError);
    });

    test('lewat 3 hari: kasir butuh PIN SPV; hari ke-3 masih boleh', () {
      final (shift, h, itemId) = jualGula(); // 5 Nov 09.00 WIB
      jam.t = DateTime.utc(2026, 11, 8, 16, 59); // 8 Nov 23.59 WIB (hari ke-3)
      expect(jual.aksesReturStruk(h.transaksiId, Peran.kasir), Akses.ya);
      jam.t = DateTime.utc(2026, 11, 8, 17, 0); // 9 Nov 00.00 WIB (hari ke-4)
      expect(jual.aksesReturStruk(h.transaksiId, Peran.kasir), Akses.pinSpv);
      expect(jual.aksesReturStruk(h.transaksiId, Peran.spv), Akses.ya);
      expect(() => jual.retur(cabang: cabang, transaksiId: h.transaksiId, qtyPerItem: {itemId: 1}, alasan: 'salah beli', oleh: kasir),
          throwsStateError);
      expect(
          () => jual.retur(
              cabang: cabang, transaksiId: h.transaksiId, qtyPerItem: {itemId: 1}, alasan: 'salah beli', oleh: kasir, disetujuiOleh: kasir),
          throwsStateError,
          reason: 'PIN kasir lain tidak sah');
      final r = jual.retur(
          cabang: cabang, transaksiId: h.transaksiId, qtyPerItem: {itemId: 1}, alasan: 'salah beli', oleh: kasir, disetujuiOleh: spv, shiftId: shift.id);
      expect(r.noRetur, 'RTR-A01-261109-0001', reason: 'nomor memakai tanggal retur');
      expect(db.satu('SELECT disetujui_oleh FROM retur')!['disetujui_oleh'], spv.id);
      expect(db.satu("SELECT disetujui_oleh FROM log_aktivitas WHERE aksi = 'retur'")!['disetujui_oleh'], spv.id);
    });

    test('jumlah dijaga juga oleh database; transaksi dibatalkan tidak bisa diretur', () {
      final (_, h, itemId) = jualGula();
      jual.retur(cabang: cabang, transaksiId: h.transaksiId, qtyPerItem: {itemId: 1}, alasan: 'salah beli', oleh: kasir);
      final returId = db.satu('SELECT id FROM retur')!['id'];
      expect(
          () => db.jalankan('INSERT INTO retur_item (id, retur_id, transaksi_item_id, qty, kembali_ke_stok) VALUES (?,?,?,?,1)',
              [buatId(), returId, itemId, 2]),
          throwsA(isA<SqliteException>()));
      final h2 = jual.simpan(
          cabang: cabang,
          kasir: kasir,
          shift: jual.shiftAktif(kasir.id)!,
          keranjang: Keranjang()..tambah(katalog.untukKasirBarcode('8990001', cabang.id)!),
          metode: MetodeBayar.tunai,
          uangDiterima: 20000);
      jual.batalkan(transaksiId: h2.transaksiId, alasan: 'salah', dimintaOleh: kasir.id, disetujuiOleh: spv.id);
      final i2 = jual.itemUntukRetur(h2.transaksiId).single.itemId;
      expect(() => jual.retur(cabang: cabang, transaksiId: h2.transaksiId, qtyPerItem: {i2: 1}, alasan: 'salah beli', oleh: kasir),
          throwsStateError);
    });

    test('tukar: nilai retur jadi potongan, pembeli bayar selisih, satu struk tukar', () {
      final (shift, h, itemId) = jualGula(); // 2 × 17.500 tunai
      final draft = jual.siapkanTukar(transaksiId: h.transaksiId, qtyPerItem: {itemId: 1}, alasan: 'mau yang lain', oleh: kasir);
      expect(draft.nilai, 17500);
      final gula = katalog.untukKasirBarcode('8990001', cabang.id)!;
      // Belanja baru 2 pak = 35.000 → bayar 17.500.
      expect(
          () => jual.simpan(
              cabang: cabang, kasir: kasir, shift: shift, keranjang: Keranjang()..tambah(gula, qty: 2), metode: MetodeBayar.tunai,
              uangDiterima: 17000, tukar: draft),
          throwsArgumentError,
          reason: 'uang kurang dari selisih');
      final t = jual.simpan(
        cabang: cabang,
        kasir: kasir,
        shift: shift,
        keranjang: Keranjang()..tambah(gula, qty: 2),
        metode: MetodeBayar.tunai,
        uangDiterima: 20000,
        tukar: draft,
      );
      expect(t.struk.tukar!.noRetur, 'RTR-A01-261105-0001');
      expect(t.struk.totalBayar, 17500);
      expect(t.struk.kembalian, 2500);
      expect(katalog.stok(gula.id, cabang.id), 50 - 2 + 1 - 2);
      final p = db.satu('SELECT * FROM pembayaran WHERE transaksi_id = ?', [t.transaksiId])!;
      expect((p['potongan_retur'], p['jumlah_diterima'], p['kembalian']), (17500, 20000, 2500));
      final r = db.satu('SELECT * FROM retur')!;
      expect((r['transaksi_tukar_id'], r['dipotong'], r['total_kembali']), (t.transaksiId, 17500, 17500));

      final ring = jual.ringkasanShift(shift.id);
      expect(ring.penjualanTunai, 35000 + 17500);
      expect(ring.potonganTukar, 17500);
      expect(ring.returTunai, 0, reason: 'tidak ada uang yang keluar');
      expect(ring.penjualan, 70000);
      expect(ring.kasSistem, 100000 + 52500);

      final dari = awalHariWibUtc(jam.t), sampai = dari.add(const Duration(days: 1));
      final lap = LaporanRepo(db).ringkasan(cabang.id, dari, sampai);
      expect(lap.penjualanBersih, 70000 - 17500);
      expect((lap.tunai, lap.nonTunai), (52500, 0));

      // Cetak ulang tetap berisi bagian tukar; transaksi tukar tidak bisa dibatalkan.
      final ulang = strukSebagaiTeks(susunStruk(jual.struk(t.transaksiId, cabang)!));
      expect(ulang, contains('TUKAR BARANG'));
      expect(ulang, contains(h.noTransaksi));
      expect(jual.detailTransaksi(t.transaksiId, cabang)!.dariTukar, isTrue);
      expect(() => jual.batalkan(transaksiId: t.transaksiId, alasan: 'x', dimintaOleh: kasir.id, disetujuiOleh: spv.id), throwsStateError);
      expect(
          () => db.jalankan('INSERT INTO pembatalan (transaksi_id, alasan, diminta_oleh, disetujui_oleh, created_at) VALUES (?,?,?,?,?)',
              [t.transaksiId, 'x', kasir.id, spv.id, isoUtc(jam.t)]),
          throwsA(isA<SqliteException>()));
      // Draft yang sama tidak bisa dipakai dua kali (barang sudah diretur semua di baris itu? tidak — sisa 1).
      expect(jual.itemUntukRetur(h.transaksiId).single.sisa, 1);
    });

    test('tukar ke barang lebih murah: sisa dikembalikan tunai, bayar Rp 0 dicatat tunai', () {
      final (shift, h, itemId) = jualGula(); // 35.000 tunai
      final draft = jual.siapkanTukar(transaksiId: h.transaksiId, qtyPerItem: {itemId: 2}, rusak: {itemId}, alasan: 'mau satu saja', oleh: kasir);
      final gula = katalog.untukKasirBarcode('8990001', cabang.id)!;
      final t = jual.simpan(
        cabang: cabang,
        kasir: kasir,
        shift: shift,
        keranjang: Keranjang()..tambah(gula),
        metode: MetodeBayar.qris, // diabaikan: tidak ada uang yang dibayar
        tukar: draft,
      );
      expect(t.struk.metode, MetodeBayar.tunai);
      expect(t.struk.totalBayar, 0);
      expect(t.struk.tukar!.sisaDikembalikan, 17500);
      final ring = jual.ringkasanShift(shift.id);
      expect(ring.returTunai, 17500);
      expect(ring.potonganTukar, 17500);
      expect(ring.kasSistem, 100000 + 35000 - 17500);
      expect(katalog.stok(gula.id, cabang.id), 50 - 2 - 1, reason: 'barang lama rusak, tidak masuk stok');
    });

    test('draft tukar tersimpan untuk listrik padam dan terhapus saat transaksi tersimpan', () {
      final (shift, h, itemId) = jualGula();
      final pulih = PemulihanRepo(db);
      final draft = jual.siapkanTukar(transaksiId: h.transaksiId, qtyPerItem: {itemId: 1}, alasan: 'mau yang lain', oleh: kasir);
      pulih.simpanTukar(draft);
      final muat = jual.draftTukarDariJson(pulih.muatTukar()!, cabang.id)!;
      expect((muat.transaksiId, muat.nilai, muat.qtyPerItem[itemId]), (h.transaksiId, 17500, 1));
      jual.simpan(
        cabang: cabang,
        kasir: kasir,
        shift: shift,
        keranjang: Keranjang()..tambah(katalog.untukKasirBarcode('8990001', cabang.id)!),
        metode: MetodeBayar.tunai,
        tukar: muat,
      );
      expect(pulih.muatTukar(), isNull);
      // Sudah dipakai: barangnya sudah diretur, draft lama tidak berlaku lagi kalau melebihi sisa.
      expect(jual.draftTukarDariJson({...draft.keJson(), 'qty': {itemId: 2}}, cabang.id), isNull);
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
