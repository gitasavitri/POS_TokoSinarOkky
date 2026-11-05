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
import 'package:app_toko/data/skema_v1.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_core/pos_core.dart';

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

  test('skema di aplikasi sama dengan database/schema_toko.sql', () {
    expect(skemaV1, File('../database/schema_toko.sql').readAsStringSync());
    expect(db.versiSkema, 1);
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
      final tutup = jual.tutupShift(shiftId: shift.id, kasDihitung: 517000, olehId: kasir.id);
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
