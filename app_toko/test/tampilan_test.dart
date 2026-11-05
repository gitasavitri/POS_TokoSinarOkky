// Uji tampilan: setiap layar dibuka di ukuran layar kasir (1366×768) dengan data contoh,
// lalu dipastikan tidak ada galat tata letak (overflow, ukuran tak terbatas, dll.).
//
// Untuk membuat gambar layar (untuk dicek mata), jalankan:
//   flutter test test/tampilan_test.dart --update-goldens   (dengan variabel lingkungan GAMBAR=1)
// Gambar tersimpan di test/gambar/ (tidak ikut ke git).

import 'dart:convert';
import 'dart:io';

import 'package:app_toko/data/database.dart';
import 'package:app_toko/data/model.dart';
import 'package:app_toko/data/repo/barang_masuk_repo.dart';
import 'package:app_toko/layanan/aplikasi.dart';
import 'package:app_toko/layanan/printer.dart';
import 'package:app_toko/ui/akar.dart';
import 'package:app_toko/ui/halaman/kasir.dart';
import 'package:app_toko/ui/komponen/kerangka.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_core/pos_core.dart';

import 'huruf.dart';

final _gambar = Platform.environment['GAMBAR'] == '1';
const _ukuran = Size(1366, 768);


/// Toko contoh: 3 barang, 2 transaksi, 1 permintaan koreksi, kasir + SPV.
Future<({Aplikasi app, Pengguna admin, Pengguna kasir, Pengguna spv})> _siapkanToko() async {
  final db = DatabaseToko.memori();
  final app = Aplikasi(db: db, printer: PrinterBerkas(), lokasiDatabase: r'C:\Users\Kasir\AppData\Roaming\pos_toko.db');
  await app.setup.siapkan(
    namaToko: 'TOKO CONTOH',
    kodeCabang: 'A01',
    namaCabang: 'Contoh 1',
    alamat: 'Jl. Contoh No. 1',
    pesanStruk: 'Terima kasih sudah berbelanja',
    namaAdmin: 'Admin Contoh',
    namaPenggunaAdmin: 'admin.contoh',
    sandiAdmin: 'sandi-panjang-1',
    rahasiaTotp: base32Encode(ascii.encode('12345678901234567890')),
    pinAdmin: '908172',
  );
  final c = app.cabang;
  final admin = app.pengguna.semua(c.id).firstWhere((p) => p.peran == Peran.admin);
  final kasir = app.pengguna.ambil(await app.pengguna.tambah(cabangId: c.id, nama: 'Siti', peran: Peran.kasir, pin: '482913', olehId: admin.id))!;
  final spv = app.pengguna.ambil(await app.pengguna.tambah(cabangId: c.id, nama: 'Dewi', peran: Peran.spv, pin: '739104', olehId: admin.id))!;

  final kat = {for (final k in app.katalog.kategori()) k.nama: k.id};
  final sup = app.katalog.supplier().first.id;
  DraftItemMasuk item(String bc, String nama, String k, String sat, int qty, int hpp, int jual, [List<TingkatGrosir> g = const []]) =>
      DraftItemMasuk(barcode: bc, nama: nama, kategoriId: kat[k] ?? kat.values.first, satuan: sat, jumlah: qty, hpp: hpp, hargaJual: jual, grosir: g);
  app.barangMasuk.kirim(
    cabang: c,
    oleh: kasir,
    draft: DraftBarangMasuk(supplierId: sup, noFaktur: 'F-CONTOH-01', item: [
      item('8990001', 'Gula Pasir 1 kg', 'Sembako', 'pak', 50, 16200, 17500, const [TingkatGrosir(minQty: 10, harga: 17000), TingkatGrosir(minQty: 50, harga: 16800)]),
      item('8990002', 'Minyak Goreng 2 L', 'Sembako', 'pcs', 3, 33000, 36000),
      item('8990003', 'Sabun Mandi 85 g', 'Sabun & Sampo', 'pcs', 40, 3100, 4000),
    ]),
  );
  final rm = app.barangMasuk.riwayat(c.id).first;
  app.barangMasuk.mintaKoreksi(
    itemId: rm.item.firstWhere((i) => i.nama.startsWith('Sabun')).itemId,
    jumlahBaru: 36,
    alasan: 'Salah hitung 4 pcs',
    oleh: kasir,
  );

  final shift = app.penjualan.bukaShift(cabangId: c.id, kasirId: kasir.id, modalAwal: 200000);
  BarangJual b(String bc) => app.katalog.untukKasirBarcode(bc, c.id)!;
  app.penjualan.simpan(
      cabang: c, kasir: kasir, shift: shift, keranjang: Keranjang()..tambah(b('8990001'), qty: 12)..tambah(b('8990003'), qty: 2),
      metode: MetodeBayar.tunai, uangDiterima: 250000);
  app.penjualan.simpan(
      cabang: c, kasir: kasir, shift: shift, keranjang: Keranjang()..tambah(b('8990002')), metode: MetodeBayar.qris);
  app.pemulihan.selesaiCetak(); // data contoh: anggap struknya sudah tercetak
  return (app: app, admin: admin, kasir: kasir, spv: spv);
}

Future<void> _pasang(WidgetTester t, Aplikasi app) async {
  t.view.physicalSize = _ukuran;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(RepaintBoundary(key: const ValueKey('layar'), child: AplikasiToko(app: app)));
  await t.pump(const Duration(milliseconds: 300));
}

Future<void> _foto(WidgetTester t, String nama) async {
  expect(t.takeException(), isNull, reason: 'galat tampilan di $nama');
  if (_gambar) await expectLater(find.byKey(const ValueKey('layar')), matchesGoldenFile('gambar/$nama.png'));
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await muatHuruf();
  });

  testWidgets('halaman masuk', (t) async {
    final s = await t.runAsync(_siapkanToko);
    await _pasang(t, s!.app);
    expect(find.text('TOKO CONTOH'), findsOneWidget);
    await _foto(t, '01-masuk');
    s.app.keluar();
  });

  testWidgets('setup awal (toko baru)', (t) async {
    final app = Aplikasi(db: DatabaseToko.memori(), printer: PrinterBerkas());
    await _pasang(t, app);
    await _foto(t, '00-setup-awal');
  });

  testWidgets('kasir: layar penjualan dengan barang, lalu dialog bayar', (t) async {
    final s = await t.runAsync(_siapkanToko);
    s!.app.masuk(s.kasir);
    await _pasang(t, s.app);
    for (final bc in ['8990001', '8990003', '8990001']) {
      await t.enterText(find.byKey(const ValueKey('scan')), bc);
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pump(const Duration(milliseconds: 100));
    }
    await _foto(t, '10-kasir');
    expect(find.text('TRX-A01-${kodeTanggal(DateTime.now())}-0003'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.f12);
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('Pembayaran'), findsOneWidget, reason: 'F12 harus membuka dialog bayar');
    await t.pump(const Duration(milliseconds: 400)); // animasi dialog baru mulai di frame berikutnya
    await _foto(t, '11-kasir-bayar');

    // Bayar tunai Rp50.000 → kartu kembalian tetap tampil di layar kasir.
    await t.enterText(find.descendant(of: find.byType(DialogBayar), matching: find.byType(TextField)), '50000');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pump(const Duration(milliseconds: 400));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byType(DialogBayar), findsNothing);
    expect(find.text('Transaksi selesai'), findsOneWidget);
    expect(find.text('KEMBALIAN'), findsOneWidget);
    expect(find.text(formatRupiah(11000)), findsOneWidget);
    await _foto(t, '12-kasir-kembalian');

    // Barang berikutnya di-scan → kartu hilang, belanja baru dimulai.
    await t.enterText(find.byKey(const ValueKey('scan')), '8990003');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('Transaksi selesai'), findsNothing);
    expect(find.text('Sabun Mandi 85 g'), findsOneWidget);
    s.app.keluar();
  });

  testWidgets('kasir: uang pas tetap menampilkan kembalian Rp 0', (t) async {
    final s = await t.runAsync(_siapkanToko);
    s!.app.masuk(s.kasir);
    await _pasang(t, s.app);
    await t.enterText(find.byKey(const ValueKey('scan')), '8990003');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pump(const Duration(milliseconds: 100));
    await t.sendKeyEvent(LogicalKeyboardKey.f12);
    await t.pump(const Duration(milliseconds: 400));
    await t.pump(const Duration(milliseconds: 400));
    await t.enterText(find.descendant(of: find.byType(DialogBayar), matching: find.byType(TextField)), '4000');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pump(const Duration(milliseconds: 400));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('KEMBALIAN'), findsOneWidget);
    expect(find.text('UANG PAS'), findsOneWidget);
    expect(find.text(formatRupiah(0)), findsWidgets);
    await _foto(t, '13-kasir-uang-pas');
    s.app.keluar();
  });

  testWidgets('admin: Esc dari halaman dalam kembali ke menu ikon', (t) async {
    final s = await t.runAsync(_siapkanToko);
    s!.app.masuk(s.admin);
    await _pasang(t, s.app);
    await t.tap(find.text(MenuAdmin.laporan.label).first);
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('PENJUALAN'), findsNothing);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('PENJUALAN'), findsOneWidget);
    s.app.keluar();
  });

  for (final m in MenuAdmin.values.where((m) => m != MenuAdmin.penjualan)) {
    testWidgets('admin: ${m.label}', (t) async {
      final s = await t.runAsync(_siapkanToko);
      s!.app.masuk(s.admin);
      await _pasang(t, s.app);
      if (m != MenuAdmin.beranda) {
        await t.tap(find.text(m.label).first);
        await t.pump(const Duration(milliseconds: 400));
        await t.pump(const Duration(milliseconds: 400));
      }
      await _foto(t, '2${m.index.toString().padLeft(2, '0')}-${m.name}');
      s.app.keluar();
    });
  }

  testWidgets('SPV tidak melihat menu Karyawan', (t) async {
    final s = await t.runAsync(_siapkanToko);
    s!.app.masuk(s.spv);
    await _pasang(t, s.app);
    expect(find.text(MenuAdmin.karyawan.label), findsNothing);
    expect(find.text(MenuAdmin.laporan.label), findsOneWidget);
    s.app.keluar();
  });
}
