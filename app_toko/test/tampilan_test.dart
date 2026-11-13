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
import 'package:app_toko/layanan/mode_latihan.dart';
import 'package:app_toko/layanan/printer.dart';
import 'package:app_toko/ui/akar.dart';
import 'package:app_toko/ui/halaman/impor_stok.dart';
import 'package:app_toko/ui/halaman/kasir.dart';
import 'package:app_toko/ui/halaman/order.dart';
import 'package:app_toko/ui/halaman/shift.dart';
import 'package:app_toko/ui/halaman/transaksi.dart';
import 'package:app_toko/ui/komponen/kerangka.dart';
import 'package:app_toko/ui/komponen/umum.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:excel/excel.dart' hide Border, BorderStyle;
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_core/pos_core.dart';

import 'huruf.dart';

/// Printer palsu di memori (tanpa menulis file), supaya cetak selesai di dalam uji tampilan.
class PrinterUji implements LayananPrinter {
  final riwayat = <Uint8List>[];
  @override
  List<String> daftarPrinter() => const ['Printer uji'];
  @override
  String? printerBawaan() => 'Printer uji';
  @override
  Future<void> cetak(String nama, Uint8List data, {String judul = 'Struk POS'}) async => riwayat.add(data);
}

final _gambar = Platform.environment['GAMBAR'] == '1';
const _ukuran = Size(1366, 768);


/// Toko contoh: 3 barang, 2 transaksi, 1 permintaan koreksi, kasir + SPV.
Future<({Aplikasi app, Pengguna admin, Pengguna kasir, Pengguna spv})> _siapkanToko() async {
  final db = DatabaseToko.memori();
  final app = Aplikasi(db: db, printer: PrinterUji(), lokasiDatabase: r'C:\Users\Kasir\AppData\Roaming\pos_toko.db');
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

/// Kasir masuk ke menu ikon dulu (revisi B); buka layar Transaksi.
Future<void> _keTransaksi(WidgetTester t) async {
  await t.tap(find.text(MenuKasir.transaksi.label));
  await t.pump(const Duration(milliseconds: 400));
  await t.pump(const Duration(milliseconds: 400));
  expect(find.byKey(const ValueKey('scan')), findsOneWidget);
}

Future<void> _tunggu(WidgetTester t) async {
  await t.pump(const Duration(milliseconds: 400));
  await t.pump(const Duration(milliseconds: 400));
}

/// Scan barcode lalu Enter di Jumlah (jumlah 1) → barang masuk daftar belanja.
Future<void> _scanMasuk(WidgetTester t, String barcode) async {
  await t.enterText(find.byKey(const ValueKey('scan')), barcode);
  await t.testTextInput.receiveAction(TextInputAction.done);
  await t.pump(const Duration(milliseconds: 100));
  await t.testTextInput.receiveAction(TextInputAction.done);
  await t.pump(const Duration(milliseconds: 100));
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
    await _keTransaksi(t);
    for (final bc in ['8990001', '8990003', '8990001']) {
      await _scanMasuk(t, bc);
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

  testWidgets('kasir: scan berhenti di Jumlah, ↓/↑ pindah kolom, Enter masuk daftar', (t) async {
    final s = await t.runAsync(_siapkanToko);
    s!.app.masuk(s.kasir);
    await _pasang(t, s.app);
    await _keTransaksi(t);
    EditableText ketik(String kunci) =>
        t.widget<EditableText>(find.descendant(of: find.byKey(ValueKey(kunci)), matching: find.byType(EditableText)));
    bool fokus(String kunci) => ketik(kunci).focusNode.hasFocus;

    expect(fokus('scan'), isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pump();
    expect(fokus('jumlah'), isTrue, reason: '↓ dari Barcode pindah ke Jumlah');
    await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await t.pump();
    expect(fokus('scan'), isTrue, reason: '↑ dari Jumlah kembali ke Barcode');

    // Scan → nama muncul, kursor di Jumlah, belum masuk daftar.
    await t.enterText(find.byKey(const ValueKey('scan')), '8990003');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pump(const Duration(milliseconds: 100));
    expect(fokus('jumlah'), isTrue, reason: 'setelah scan berhenti di Jumlah');
    expect(find.text('Sabun Mandi 85 g'), findsOneWidget, reason: 'nama tampil di kotak input');
    expect(find.text('Jenis barang: '), findsNothing, reason: 'daftar belanja masih kosong');

    await t.enterText(find.byKey(const ValueKey('jumlah')), '2');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pump(const Duration(milliseconds: 100));
    expect(fokus('scan'), isTrue, reason: 'Enter di Jumlah → masuk daftar, kembali ke Barcode');
    expect(find.text(formatRupiah(8000)), findsWidgets, reason: 'Sabun 2 × Rp4.000');
    await _foto(t, '10b-kasir-input');
    s.app.keluar();
  });

  testWidgets('kasir: Enter 2× di Barcode kosong membuka Bayar; Esc menutup kartu kembalian', (t) async {
    final s = await t.runAsync(_siapkanToko);
    s!.app.masuk(s.kasir);
    await _pasang(t, s.app);
    await _keTransaksi(t);

    // Daftar belanja kosong: Enter 2× tidak membuka Bayar.
    for (var i = 0; i < 2; i++) {
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pump();
    }
    expect(find.byType(DialogBayar), findsNothing);

    await t.enterText(find.byKey(const ValueKey('scan')), '8990003');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pump(const Duration(milliseconds: 100));
    await t.testTextInput.receiveAction(TextInputAction.done); // Enter di Jumlah → masuk daftar
    await t.pump(const Duration(milliseconds: 100));

    await t.testTextInput.receiveAction(TextInputAction.done); // Enter ke-1 (kolom kosong)
    await t.pump();
    expect(find.byType(DialogBayar), findsNothing);
    expect(find.text('Tekan Enter sekali lagi untuk BAYAR'), findsOneWidget);
    await _foto(t, '10c-kasir-enter-sekali-lagi');
    await t.testTextInput.receiveAction(TextInputAction.done); // Enter ke-2
    await t.pump(const Duration(milliseconds: 400));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byType(DialogBayar), findsOneWidget, reason: 'Enter 2× membuka layar Bayar');

    await t.enterText(find.descendant(of: find.byType(DialogBayar), matching: find.byType(TextField)), '5000');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pump(const Duration(milliseconds: 400));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('Transaksi selesai'), findsOneWidget);
    expect(find.byKey(const ValueKey('tutup-kembalian')), findsOneWidget);

    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('Transaksi selesai'), findsNothing, reason: 'Esc menutup kartu kembalian');
    expect(find.text('Scan barcode barang untuk mulai'), findsOneWidget);

    // Cek harga setelah kartu ditutup: scan saja, tidak masuk daftar.
    await t.enterText(find.byKey(const ValueKey('scan')), '8990001');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('Gula Pasir 1 kg'), findsOneWidget);
    expect(find.text(formatRupiah(17500)), findsWidgets);
    s.app.keluar();
  });

  testWidgets('kasir: uang pas tetap menampilkan kembalian Rp 0', (t) async {
    final s = await t.runAsync(_siapkanToko);
    s!.app.masuk(s.kasir);
    await _pasang(t, s.app);
    await _keTransaksi(t);
    await _scanMasuk(t, '8990003');
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

  testWidgets('kasir: kas keluar (F6), di bawah Rp100.000 tanpa PIN', (t) async {
    final s = await t.runAsync(_siapkanToko);
    s!.app.masuk(s.kasir);
    await _pasang(t, s.app);
    await _keTransaksi(t);
    await t.sendKeyEvent(LogicalKeyboardKey.f6);
    await t.pump(const Duration(milliseconds: 400));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byType(DialogKas), findsOneWidget);
    await t.enterText(find.descendant(of: find.byKey(const ValueKey('jumlah-kas')), matching: find.byType(EditableText)), '150000');
    await t.pump();
    expect(find.text('Simpan (PIN SPV)'), findsOneWidget, reason: 'Rp150.000 perlu PIN SPV');
    await t.enterText(find.descendant(of: find.byKey(const ValueKey('jumlah-kas')), matching: find.byType(EditableText)), '25000');
    await t.tap(find.text('Beli barang dari sales'));
    await t.pump();
    await _foto(t, '14-kasir-kas-keluar');
    await t.tap(find.byKey(const ValueKey('simpan-kas')));
    await t.pump(const Duration(milliseconds: 400));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byType(DialogKas), findsNothing);
    final kas = s.app.penjualan.daftarKas(s.app.shiftAktif!.id);
    expect(kas.single.jumlah, 25000);
    expect(kas.single.keterangan, 'Beli barang dari sales');
    s.app.keluar();
  });

  testWidgets('kasir: tutup shift hitung buta', (t) async {
    final s = await t.runAsync(_siapkanToko);
    s!.app.masuk(s.kasir);
    await _pasang(t, s.app);
    await t.tap(find.text('Tutup shift'));
    await t.pump(const Duration(milliseconds: 400));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byType(DialogTutupShift), findsOneWidget);
    // Uang seharusnya: modal 200.000 + tunai 212.000 = 412.000. Tidak boleh tampil sebelum dihitung.
    final kasSistem = s.app.penjualan.ringkasanShift(s.app.shiftAktif!.id).kasSistem;
    expect(kasSistem, 412000);
    final seharusnya = formatRupiah(kasSistem);
    expect(find.textContaining(seharusnya), findsNothing, reason: 'hitung buta');
    expect(find.textContaining('seharusnya'), findsNothing);
    await _foto(t, '15-kasir-tutup-shift-hitung');

    Future<void> hitung(String uang) async {
      await t.enterText(find.descendant(of: find.byKey(const ValueKey('uang-dihitung')), matching: find.byType(EditableText)), uang);
      await t.pump();
      await t.tap(find.byKey(const ValueKey('simpan-hitungan')));
      await t.pump(const Duration(milliseconds: 300));
    }

    await hitung('392000');
    expect(find.textContaining('Uang KURANG ${formatRupiah(20000)}'), findsOneWidget);
    expect(find.text('Hitung ulang (sisa 2)'), findsOneWidget);
    await _foto(t, '16-kasir-tutup-shift-selisih');
    await t.tap(find.byKey(const ValueKey('hitung-ulang')));
    await t.pump();
    await hitung('404000');
    await t.tap(find.byKey(const ValueKey('hitung-ulang')));
    await t.pump();
    await hitung('409000');
    expect(find.text('Hitung ulang (PIN SPV)'), findsOneWidget);
    expect(find.text('Hitungan 1'), findsOneWidget);
    expect(s.app.penjualan.hitunganShift(s.app.shiftAktif!.id).length, 3);
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

  // ------------------------------------------------------------------ revisi tahap 2 (B, C, D, E, P)

  testWidgets('kasir: menu ikon, kotak shift aktif; kembali ke menu & keluar tidak menutup shift (B)', (t) async {
    final s = await t.runAsync(_siapkanToko);
    s!.app.masuk(s.kasir);
    await _pasang(t, s.app);
    expect(find.byKey(const ValueKey('kotak-shift')), findsOneWidget);
    expect(find.textContaining('Shift aktif sejak'), findsOneWidget);
    for (final m in MenuKasir.values.where((m) => m != MenuKasir.beranda)) {
      expect(find.text(m.label), findsOneWidget, reason: m.label);
    }
    for (final dilarang in ['Stok opname', MenuAdmin.produk.label, MenuAdmin.laporan.label, MenuAdmin.log.label, MenuAdmin.karyawan.label, MenuAdmin.pengaturan.label]) {
      expect(find.text(dilarang), findsNothing, reason: '$dilarang bukan untuk kasir');
    }
    expect(find.textContaining('Laba'), findsNothing);
    await _foto(t, '30-kasir-menu');

    final shiftId = s.app.shiftAktif!.id;
    await _keTransaksi(t);
    await t.tap(find.text('← Menu'));
    await _tunggu(t);
    expect(find.byKey(const ValueKey('kotak-shift')), findsOneWidget);
    expect(s.app.penjualan.shiftAktif(s.kasir.id)?.id, shiftId);
    await t.tap(find.text('Keluar'));
    await _tunggu(t);
    expect(s.app.penggunaAktif, isNull);
    expect(s.app.penjualan.shiftAktif(s.kasir.id)?.id, shiftId, reason: 'keluar tidak menutup shift');
  });

  testWidgets('kasir: belum buka shift → kotak "Belum buka shift"', (t) async {
    final s = await t.runAsync(_siapkanToko);
    s!.app.masuk(s.spv); // SPV belum punya shift; pakai kasir kedua
    s.app.keluar();
    final kasir2 = s.app.pengguna.ambil(await t.runAsync(() => s.app.pengguna.tambah(cabangId: s.app.cabang.id, nama: 'Rina', peran: Peran.kasir, pin: '135792', olehId: s.admin.id)) as String)!;
    s.app.masuk(kasir2);
    await _pasang(t, s.app);
    expect(find.text('Belum buka shift'), findsOneWidget);
    expect(find.byKey(const ValueKey('buka-shift')), findsOneWidget);
    await _foto(t, '31-kasir-menu-belum-shift');
    s.app.keluar();
  });

  testWidgets('kasir: Cek stok & harga tanpa HPP, filter hampir habis (C)', (t) async {
    final s = await t.runAsync(_siapkanToko);
    final minyak = s!.app.katalog.cariBarcode('8990002', s.app.cabang.id)!;
    s.app.katalog.aturStokMinimum(minyak.id, s.app.cabang.id, 5, olehId: s.admin.id);
    s.app.masuk(s.kasir);
    await _pasang(t, s.app);
    await t.tap(find.text(MenuKasir.cekStok.label));
    await _tunggu(t);
    expect(find.text('Gula Pasir 1 kg'), findsOneWidget);
    expect(find.text('Rp 17.500'), findsOneWidget);
    expect(find.text('HPP'), findsNothing);
    expect(find.text('Rp 16.200'), findsNothing, reason: 'harga beli disembunyikan');
    expect(find.text('Rp 3.100'), findsNothing);
    expect(find.text('Hampir habis'), findsOneWidget);
    await _foto(t, '32-kasir-cek-stok');
    await t.tap(find.byKey(const ValueKey('filter-menipis')));
    await t.pump();
    expect(find.text('Minyak Goreng 2 L'), findsOneWidget);
    expect(find.text('Gula Pasir 1 kg'), findsNothing);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await _tunggu(t);
    expect(find.byKey(const ValueKey('kotak-shift')), findsOneWidget, reason: 'Esc kembali ke menu');
    s.app.keluar();
  });

  testWidgets('kasir: Penjualan shift saya + detail bentuk daftar belanja (D, E)', (t) async {
    final s = await t.runAsync(_siapkanToko);
    s!.app.masuk(s.kasir);
    await _pasang(t, s.app);
    await t.tap(find.text(MenuKasir.penjualanShift.label));
    await _tunggu(t);
    // Tunai: 12 gula × 17.000 (grosir) + 2 sabun × 4.000 = 212.000. QRIS: minyak 36.000.
    expect(find.text('Rp 248.000'), findsOneWidget);
    expect(find.text('Rp 212.000'), findsWidgets);
    expect(find.text('Rp 36.000'), findsWidgets);
    expect(find.textContaining('Laba'), findsNothing);
    expect(find.textContaining('seharusnya'), findsNothing, reason: 'hitung buta');
    await _foto(t, '33-kasir-penjualan-shift');
    await t.tap(find.text('TRX-A01-${kodeTanggal(DateTime.now())}-0001'));
    await _tunggu(t);
    expect(find.byType(DialogDetailTransaksi), findsOneWidget);
    expect(find.text('Gula Pasir 1 kg'), findsOneWidget);
    expect(find.text('GROSIR'), findsOneWidget);
    expect(find.text('Rp 204.000'), findsOneWidget, reason: 'subtotal baris');
    expect(find.byKey(const ValueKey('cetak-ulang')), findsOneWidget);
    expect(find.text('Batalkan (PIN SPV)'), findsOneWidget);
    expect(find.text('Ubah transaksi (PIN SPV)'), findsOneWidget);
    expect(find.text('Tukar / kembalikan'), findsOneWidget);
    await _foto(t, '34-detail-transaksi');
    await t.tap(find.byKey(const ValueKey('cetak-ulang')));
    await t.pump(const Duration(milliseconds: 300));
    expect((s.app.printer as PrinterUji).riwayat, isNotEmpty);
    s.app.keluar();
  });

  testWidgets('kasir: Cetak ulang struk lewat nomor transaksi (B)', (t) async {
    final s = await t.runAsync(_siapkanToko);
    s!.app.masuk(s.kasir);
    await _pasang(t, s.app);
    await t.tap(find.text(MenuKasir.cetakUlang.label));
    await _tunggu(t);
    await t.enterText(find.byKey(const ValueKey('cari-transaksi')), 'TRX-A01-000000-9999');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pump();
    expect(find.textContaining('tidak ditemukan'), findsOneWidget);
    await _foto(t, '35-kasir-cetak-ulang');
    await t.enterText(find.byKey(const ValueKey('cari-transaksi')), 'TRX-A01-${kodeTanggal(DateTime.now())}-0002');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await _tunggu(t);
    expect(find.byType(DialogDetailTransaksi), findsOneWidget);
    expect(find.text('Minyak Goreng 2 L'), findsOneWidget);
    s.app.keluar();
  });

  testWidgets('admin: Ubah transaksi = batalkan + barangnya masuk lagi ke layar Transaksi (E)', (t) async {
    final s = await t.runAsync(_siapkanToko);
    s!.app.penjualan.bukaShift(cabangId: s.app.cabang.id, kasirId: s.admin.id, modalAwal: 0);
    s.app.masuk(s.admin);
    await _pasang(t, s.app);
    await t.tap(find.widgetWithText(UbinMenu, MenuAdmin.penjualan.label));
    await _tunggu(t);
    await t.sendKeyEvent(LogicalKeyboardKey.f9);
    await _tunggu(t);
    final no = 'TRX-A01-${kodeTanggal(DateTime.now())}-0001';
    await t.tap(find.text(no));
    await _tunggu(t);
    await t.tap(find.byKey(const ValueKey('ubah-transaksi')));
    await _tunggu(t);
    await t.tap(find.text('Lanjut'));
    await _tunggu(t);
    expect(find.text('Ubah transaksi'), findsWidgets, reason: 'alasan sudah terisi');
    await t.tap(find.byKey(const ValueKey('lanjut-batal')));
    await _tunggu(t);
    final id = s.app.penjualan.idDariNomor(s.app.cabang.id, no)!;
    expect(s.app.penjualan.sudahDibatalkan(id), isTrue);
    expect(find.byType(DialogDetailTransaksi), findsNothing);
    expect(find.byType(DialogTransaksiTerakhir), findsNothing);
    expect(find.text('Gula Pasir 1 kg'), findsOneWidget, reason: 'barang masuk lagi ke daftar belanja');
    expect(find.text('Sabun Mandi 85 g'), findsOneWidget);
    expect(find.text(formatRupiah(212000)), findsOneWidget, reason: 'total belanja sama (harga belum berubah)');
    await _foto(t, '36-admin-ubah-transaksi');
    s.app.keluar();
  });

  testWidgets('kasir: tutup shift "Belum dihitung" → SPV menghitung amplop (P)', (t) async {
    final s = await t.runAsync(_siapkanToko);
    s!.app.pengaturan.aturModalTetap(200000, cabangId: s.app.cabang.id, oleh: s.admin);
    s.app.masuk(s.kasir);
    await _pasang(t, s.app);
    final shiftId = s.app.shiftAktif!.id;
    await t.tap(find.text(MenuKasir.tutupShift.label));
    await _tunggu(t);
    await t.tap(find.byKey(const ValueKey('belum-dihitung')));
    await _tunggu(t);
    expect(find.textContaining('Sisakan uang modal Rp 200.000'), findsOneWidget);
    expect(find.textContaining(formatRupiah(412000)), findsNothing, reason: 'hitung buta');
    await _foto(t, '37-kasir-belum-dihitung');
    await t.tap(find.byKey(const ValueKey('konfirmasi-belum-dihitung')));
    await _tunggu(t);
    expect(s.app.penggunaAktif, isNull, reason: 'kasir keluar setelah tutup shift');
    expect(s.app.penjualan.shiftAktif(s.kasir.id), isNull);
    final label = utf8.decode((s.app.printer as PrinterUji).riwayat.last, allowMalformed: true);
    expect(label, contains('AMPLOP SHIFT'));
    expect(label, isNot(contains('412.000')));

    s.app.masuk(s.spv);
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('1 shift menunggu dihitung'), findsOneWidget);
    await t.tap(find.text(MenuAdmin.shiftMenunggu.label));
    await _tunggu(t);
    await _foto(t, '38-spv-shift-menunggu');
    await t.tap(find.text('Siti'));
    await _tunggu(t);
    expect(find.byType(DialogHitungAmplop), findsOneWidget);
    expect(find.textContaining(formatRupiah(212000)), findsNothing, reason: 'isi amplop seharusnya baru tampil setelah disimpan');
    await t.enterText(find.descendant(of: find.byKey(const ValueKey('isi-amplop')), matching: find.byType(EditableText)), '202000');
    await t.pump();
    await t.tap(find.byKey(const ValueKey('simpan-amplop')));
    await _tunggu(t);
    await t.tap(find.text('Simpan'));
    await _tunggu(t);
    expect(find.textContaining('Uang KURANG ${formatRupiah(10000)}'), findsOneWidget);
    expect(find.textContaining('atas nama Siti'), findsOneWidget);
    await _foto(t, '39-spv-hitung-amplop');
    expect(s.app.db.satu('SELECT selisih FROM shift_tutup WHERE shift_id = ?', [shiftId])!['selisih'], -10000);
    await t.tap(find.text('Selesai'));
    await _tunggu(t);
    expect(find.textContaining('Tidak ada shift yang menunggu dihitung'), findsOneWidget);
    s.app.keluar();
  });

  // ------------------------------------------------------------------ revisi F: tukar / kembalikan barang

  Future<void> tambahRetur(WidgetTester t, String itemId) async {
    await t.tap(find.descendant(of: find.byKey(ValueKey('retur-$itemId')), matching: find.byIcon(Icons.add)));
    await t.pump();
  }

  testWidgets('kasir: kembalikan uang tunai dari menu, struk RTR dicetak, SPV melihat di Perlu dicek (F)', (t) async {
    final s = await t.runAsync(_siapkanToko);
    s!.app.masuk(s.kasir);
    await _pasang(t, s.app);
    await t.tap(find.text(MenuKasir.retur.label));
    await _tunggu(t);
    await _foto(t, '40-kasir-retur-scan');
    final no = 'TRX-A01-${kodeTanggal(DateTime.now())}-0002'; // minyak, dibayar QRIS
    final trx = s.app.penjualan.idDariNomor(s.app.cabang.id, no)!;
    await t.enterText(find.byKey(const ValueKey('scan-struk-retur')), isiBarcodeStruk(no));
    await t.testTextInput.receiveAction(TextInputAction.done);
    await _tunggu(t);
    final item = s.app.penjualan.itemUntukRetur(trx).single;
    await tambahRetur(t, item.itemId);
    await t.tap(find.byKey(ValueKey('rusak-${item.itemId}')));
    await t.enterText(find.byKey(const ValueKey('alasan-retur')), 'Tutup botol bocor');
    await t.pump();
    expect(find.byKey(const ValueKey('nilai-retur')), findsOneWidget);
    expect(find.text(formatRupiah(36000)), findsWidgets);
    await _foto(t, '41-kasir-retur-pilih');
    await t.tap(find.byKey(const ValueKey('tombol-kembalikan-uang')));
    await _tunggu(t);
    await t.tap(find.text('Kembalikan uang'));
    await _tunggu(t);
    expect(find.byKey(const ValueKey('hasil-retur')), findsOneWidget);
    expect(find.text('KEMBALIKAN UANG TUNAI'), findsOneWidget);
    final cetak = utf8.decode((s.app.printer as PrinterUji).riwayat.last, allowMalformed: true);
    expect(cetak, contains('STRUK RETUR'));
    expect(cetak, contains('RTR-A01-${kodeTanggal(DateTime.now())}-0001'));
    expect(cetak.toLowerCase(), isNot(contains('tidak dapat')));
    await _foto(t, '42-kasir-retur-selesai');
    final ring = s.app.penjualan.ringkasanShift(s.app.shiftAktif!.id);
    expect(ring.returTunai, 36000, reason: 'QRIS tetap dikembalikan tunai');
    await t.tap(find.byKey(const ValueKey('selesai-retur')));
    await _tunggu(t);
    s.app.keluar();

    s.app.masuk(s.spv);
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('1 tukar / retur oleh kasir'), findsOneWidget);
    await _foto(t, '43-spv-perlu-dicek-retur');
    await t.tap(find.text('1 tukar / retur oleh kasir'));
    await _tunggu(t);
    expect(find.textContaining('Retur & tukar hari ini (1)'), findsOneWidget);
    expect(find.text('Uang tunai'), findsOneWidget);
    expect(find.text('1 (1 rusak)'), findsOneWidget);
    await _foto(t, '44-spv-riwayat-retur');
    s.app.keluar();
  });

  testWidgets('kasir: scan struk di layar Transaksi → tukar barang, bayar selisih, satu struk tukar (F)', (t) async {
    final s = await t.runAsync(_siapkanToko);
    s!.app.masuk(s.kasir);
    await _pasang(t, s.app);
    await _keTransaksi(t);
    final no = 'TRX-A01-${kodeTanggal(DateTime.now())}-0001'; // 12 gula + 2 sabun
    final trx = s.app.penjualan.idDariNomor(s.app.cabang.id, no)!;
    await t.enterText(find.byKey(const ValueKey('scan')), isiBarcodeStruk(no));
    await t.testTextInput.receiveAction(TextInputAction.done);
    await _tunggu(t);
    expect(find.text('Tukar / kembalikan barang'), findsOneWidget, reason: 'barcode struk membuka dialog retur');
    final sabun = s.app.penjualan.itemUntukRetur(trx).firstWhere((i) => i.nama.startsWith('Sabun'));
    await tambahRetur(t, sabun.itemId);
    await tambahRetur(t, sabun.itemId);
    await t.enterText(find.byKey(const ValueKey('alasan-retur')), 'Salah varian');
    await t.pump();
    await _foto(t, '45-kasir-tukar-pilih');
    await t.tap(find.byKey(const ValueKey('tombol-tukar')));
    await _tunggu(t);
    expect(find.byKey(const ValueKey('banner-tukar')), findsOneWidget);
    await _scanMasuk(t, '8990002'); // minyak 36.000
    await t.pump(const Duration(milliseconds: 300));
    // 36.000 − 2 × 4.000 = 28.000
    expect(find.text(formatRupiah(28000)), findsWidgets);
    expect(find.text('TOTAL BAYAR (TUKAR)'), findsOneWidget);
    await _foto(t, '46-kasir-tukar-layar');
    expect(s.app.pemulihan.muatTukar(), isNotNull, reason: 'tersimpan kalau listrik padam');
    await t.sendKeyEvent(LogicalKeyboardKey.f12);
    await _tunggu(t);
    expect(find.text('Pembayaran tukar barang'), findsOneWidget);
    await _foto(t, '47-kasir-tukar-bayar');
    await t.enterText(find.descendant(of: find.byType(DialogBayar), matching: find.byType(TextField)), '30000');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await _tunggu(t);
    expect(find.text('Tukar barang selesai'), findsOneWidget);
    expect(find.text(formatRupiah(2000)), findsOneWidget);
    expect(find.byKey(const ValueKey('banner-tukar')), findsNothing);
    await _foto(t, '48-kasir-tukar-selesai');
    final cetak = utf8.decode((s.app.printer as PrinterUji).riwayat.last, allowMalformed: true);
    expect(cetak, contains('TUKAR BARANG'));
    expect(cetak, contains(no));
    expect(s.app.pemulihan.muatTukar(), isNull);
    final ring = s.app.penjualan.ringkasanShift(s.app.shiftAktif!.id);
    expect((ring.potonganTukar, ring.returTunai), (8000, 0));
    s.app.keluar();
  });

  testWidgets('buka shift berikutnya: modal awal terisi modal tetap (P)', (t) async {
    final s = await t.runAsync(_siapkanToko);
    s!.app.pengaturan.aturModalTetap(200000, cabangId: s.app.cabang.id, oleh: s.admin);
    s.app.masuk(s.spv);
    await _pasang(t, s.app);
    await t.tap(find.widgetWithText(UbinMenu, MenuAdmin.penjualan.label));
    await _tunggu(t);
    expect(find.text('Buka shift'), findsOneWidget);
    expect(find.text('200.000'), findsOneWidget);
    s.app.keluar();
  });

  testWidgets('pengaturan: modal tetap hanya untuk Admin (P)', (t) async {
    final s = await t.runAsync(_siapkanToko);
    s!.app.masuk(s.admin);
    await _pasang(t, s.app);
    await t.tap(find.text(MenuAdmin.pengaturan.label).first);
    await _tunggu(t);
    await t.scrollUntilVisible(find.text('Modal tetap kasir (Admin)'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('Modal tetap kasir (Admin)'), findsOneWidget);
    s.app.keluar();
    s.app.masuk(s.spv);
    await t.pump(const Duration(milliseconds: 400));
    await t.tap(find.text(MenuAdmin.pengaturan.label).first);
    await _tunggu(t);
    expect(find.text('Modal tetap kasir (Admin)'), findsNothing);
    s.app.keluar();
  });

  // ------------------------------------------------------------------ revisi tahap 4 (G, J, mode latihan)

  testWidgets('kasir: Order barang → (+), jumlah ±, simpan → PDF & Excel surat pesanan (G)', (t) async {
    final s = await t.runAsync(_siapkanToko);
    final c = s!.app.cabang;
    final minyak = s.app.katalog.cariBarcode('8990002', c.id)!.id;
    s.app.katalog.aturStokMinimum(minyak, c.id, 5, olehId: s.spv.id);
    final tersimpan = <String, Uint8List>{};
    simpanDokumenOrder = (nama, isi) async {
      tersimpan[nama] = isi;
      return 'C:\\Users\\Kasir\\Documents\\POS-Order\\$nama';
    };
    final dibuka = <String>[];
    bukaFileOrder = (p) async {
      dibuka.add(p);
      return null;
    };
    addTearDown(() {
      simpanDokumenOrder = simpanDiFolderOrder;
      bukaFileOrder = (p) async => null;
    });
    s.app.masuk(s.kasir);
    await _pasang(t, s.app);
    expect(find.text('segera'), findsNothing);
    await t.tap(find.text(MenuKasir.orderBarang.label));
    await _tunggu(t);
    expect(find.text('Perlu order saja (1)'), findsOneWidget);
    expect(find.text('Minyak Goreng 2 L'), findsOneWidget);
    expect(find.text('Gula Pasir 1 kg'), findsNothing, reason: 'filter "Perlu order saja" menyala karena ada yang perlu');
    await t.tap(find.byKey(ValueKey('tambah-order-$minyak')));
    await t.pump();
    expect(find.byKey(ValueKey('baris-order-$minyak')), findsOneWidget);
    expect(find.text('8'), findsWidgets, reason: 'saran 2 × 5 − 2 = 8');
    await t.tap(find.byKey(const ValueKey('filter-perlu-order')));
    await t.pump();
    await t.enterText(find.byKey(const ValueKey('cari-order')), '8990003');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pump();
    expect(find.textContaining('2 jenis barang'), findsOneWidget, reason: 'scan barcode langsung masuk daftar');
    await t.enterText(find.byKey(const ValueKey('catatan-order')), 'Kirim sebelum Sabtu');
    await t.pump();
    await _foto(t, '50-kasir-order-barang');
    await t.tap(find.byKey(const ValueKey('simpan-order')));
    await t.runAsync(() => Future<void>.delayed(const Duration(seconds: 2)));
    await _tunggu(t);
    final no = 'ORD-A01-${kodeTanggal(DateTime.now())}-0001';
    expect(find.text('Order $no tersimpan'), findsOneWidget);
    expect(tersimpan.keys, ['$no.pdf', '$no.xlsx']);
    expect(String.fromCharCodes(tersimpan['$no.pdf']!.take(5)), '%PDF-');
    await _foto(t, '51-kasir-order-tersimpan');
    await t.tap(find.text('Buka PDF'));
    await t.pump();
    expect(dibuka.single, endsWith('$no.pdf'));
    await t.tap(find.text('Selesai'));
    await _tunggu(t);
    expect(find.textContaining('0 jenis barang'), findsOneWidget, reason: 'daftar order kosong lagi');
    expect(s.app.katalog.stok(minyak, c.id), 2, reason: 'order tidak mengubah stok');
    s.app.keluar();
  });

  testWidgets('barang masuk: kursor di Barcode, Enter/panah antar kolom, Enter di Harga jual = barang berikutnya', (t) async {
    final s = await t.runAsync(_siapkanToko);
    s!.app.masuk(s.kasir);
    await _pasang(t, s.app);
    await t.tap(find.text(MenuKasir.barangMasuk.label));
    await _tunggu(t);

    bool fokus(String kunci) => t.widget<TextField>(find.byKey(ValueKey(kunci))).focusNode!.hasFocus;
    Future<void> enter() async {
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pump(const Duration(milliseconds: 100));
    }

    expect(t.takeException(), isNull, reason: 'form muat di layar tanpa overflow');
    expect(find.byType(Scrollbar), findsNothing, reason: 'tanpa scroll');
    expect(fokus('kolom-barcode'), isTrue, reason: 'kursor langsung di Barcode');

    // Barang baru: barcode → nama → kategori → satuan → jumlah → HPP → harga jual.
    await t.enterText(find.byKey(const ValueKey('kolom-barcode')), '8990099');
    await enter();
    expect(fokus('kolom-nama'), isTrue);
    await t.enterText(find.byKey(const ValueKey('kolom-nama')), 'Kopi Hitam 100 g');
    await enter();
    final kategoriAwal = s.app.barangMasuk.muatDraft(s.app.cabang.id)!.item.first.kategoriId;
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown); // di Kategori: ganti pilihan
    await t.pump(const Duration(milliseconds: 100));
    expect(s.app.barangMasuk.muatDraft(s.app.cabang.id)!.item.first.kategoriId, isNot(kategoriAwal));
    await t.sendKeyEvent(LogicalKeyboardKey.enter); // → Satuan
    await t.pump(const Duration(milliseconds: 100));
    await t.sendKeyEvent(LogicalKeyboardKey.enter); // → Jumlah
    await t.pump(const Duration(milliseconds: 100));
    expect(fokus('kolom-jumlah'), isTrue);
    await t.enterText(find.byKey(const ValueKey('kolom-jumlah')), '5');
    await enter();
    Finder kotakRupiah(int n) => find.descendant(of: find.byType(InputRupiah).at(n), matching: find.byType(TextField));
    await t.enterText(kotakRupiah(0), '1000'); // HPP
    await enter();
    await t.enterText(kotakRupiah(1), '1500'); // Harga jual
    // Harga grosir: 3 tingkat kosong selalu tampil, semua kotak setinggi 46 px, tambah tingkat ke-4.
    for (var i = 0; i < 3; i++) {
      expect(find.byKey(ValueKey('grosir-min-$i')), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('grosir-min-3')), findsNothing);
    final tinggi = {
      for (final k in ['kolom-barcode', 'kolom-nama', 'kolom-jumlah', 'grosir-min-0'])
        t.getSize(find.byKey(ValueKey(k))).height,
      t.getSize(kotakRupiah(0)).height,
      t.getSize(kotakRupiah(1)).height,
      t.getSize(kotakRupiah(2)).height,
    };
    expect(tinggi.length, 1, reason: 'semua kotak isian sama tinggi: $tinggi');
    if (_gambar) await expectLater(find.byKey(const ValueKey('layar')), matchesGoldenFile('gambar/barang-masuk-form.png'));
    await t.ensureVisible(find.byKey(const ValueKey('tambah-grosir')));
    await t.tap(find.byKey(const ValueKey('tambah-grosir')));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('grosir-min-3')), findsOneWidget);
    await t.enterText(find.byKey(const ValueKey('kolom-jumlah')), '5');
    await t.enterText(kotakRupiah(1), '1500');
    await enter(); // lengkap → barang berikutnya
    await _tunggu(t);
    expect(find.text('1 barang'), findsOneWidget);
    expect(fokus('kolom-barcode'), isTrue, reason: 'form kosong, kursor kembali ke Barcode');
    expect(t.widget<TextField>(find.byKey(const ValueKey('kolom-barcode'))).controller!.text, '');

    // Barcode yang sudah ada di sistem: nama terisi otomatis, kursor ke Jumlah.
    await t.enterText(find.byKey(const ValueKey('kolom-barcode')), '8990001');
    await enter();
    await _tunggu(t);
    expect(fokus('kolom-jumlah'), isTrue);
    expect(t.widget<TextField>(find.byKey(const ValueKey('kolom-nama'))).controller!.text, 'Gula Pasir 1 kg');

    // Enter di Barcode yang kosong (form kosong) = selesai input → konfirmasi (nomor faktur wajib dulu).
    await t.enterText(find.byKey(const ValueKey('kolom-jumlah')), '3');
    await enter();
    await enter(); // HPP → Harga jual
    await enter(); // Harga jual lengkap → form kosong
    await _tunggu(t);
    expect(find.text('2 barang'), findsOneWidget);
    await enter(); // Barcode kosong, form kosong
    await _tunggu(t);
    expect(find.textContaining('nomor faktur'), findsWidgets);
    s.app.keluar();
  });

  testWidgets('admin: Impor stok awal dari Excel → pratinjau, baris salah ditandai, simpan (J)', (t) async {
    final s = await t.runAsync(_siapkanToko);
    final c = s!.app.cabang;
    final e = Excel.createExcel();
    e.rename(e.getDefaultSheet()!, 'Stok awal');
    final sh = e['Stok awal'];
    sh.appendRow([for (final k in kolomImporStok) TextCellValue(k)]);
    for (final r in [
      ['8990001', 'Gula Pasir 1 kg', 'Sembako', 'pak', 30, 16400, 17500],
      ['8990201', 'Teh Celup isi 25', 'Minuman', 'kotak', 12, 4500, 6000],
      ['8990202', 'Kopi Bubuk 200 g', 'Kopi', 'pcs', 6, 15000, 19000],
      ['', 'Garam 250 g', 'Sembako', 'pcs', 10, 2000, 2000],
    ]) {
      sh.appendRow([for (final v in r) v is int ? IntCellValue(v) : TextCellValue('$v')]);
    }
    final file = Uint8List.fromList(e.encode()!);
    pilihFileExcel = () async => ('stok-awal-contoh.xlsx', file);
    String? template;
    simpanTemplateExcel = (nama, isi) async => template = nama;
    addTearDown(() {
      pilihFileExcel = pilihFileExcelBawaan;
      simpanTemplateExcel = simpanTemplateBawaan;
    });
    s.app.masuk(s.kasir);
    await _pasang(t, s.app);
    await t.tap(find.text(MenuKasir.barangMasuk.label));
    await _tunggu(t);
    expect(find.byKey(const ValueKey('buka-impor-stok')), findsNothing, reason: 'kasir tidak boleh impor');
    s.app.keluar();
    s.app.masuk(s.admin);
    await t.pump(const Duration(milliseconds: 400));
    await t.tap(find.text(MenuAdmin.barangMasuk.label).first);
    await _tunggu(t);
    await t.tap(find.byKey(const ValueKey('buka-impor-stok')));
    await _tunggu(t);
    await _foto(t, '52-admin-impor-awal');
    await t.tap(find.byKey(const ValueKey('simpan-template')));
    await _tunggu(t);
    expect(template, 'Template-stok-awal-A01.xlsx');
    await t.tap(find.byKey(const ValueKey('pilih-file-impor')));
    await _tunggu(t);
    expect(find.text('Kategori "Kopi" belum ada.'), findsOneWidget);
    expect(find.text('Harga jual harus lebih besar dari HPP.'), findsOneWidget);
    expect(find.textContaining('lewati 2'), findsOneWidget);
    await _foto(t, '53-admin-impor-pratinjau');
    await t.tap(find.byKey(const ValueKey('tambah-kategori-impor')));
    await _tunggu(t);
    await t.tap(find.text('Tambah kategori'));
    await _tunggu(t);
    expect(find.textContaining('lewati 1'), findsOneWidget, reason: 'setelah kategori ditambah, tinggal baris harga = HPP');
    await t.pump(const Duration(seconds: 6)); // pesan "Template disimpan" hilang dulu
    await t.pump(const Duration(seconds: 1));
    await t.tap(find.byKey(const ValueKey('simpan-impor')));
    await _tunggu(t);
    await t.tap(find.text('Simpan').last);
    await _tunggu(t);
    await _tunggu(t);
    expect(find.byKey(const ValueKey('simpan-impor')), findsNothing, reason: 'kembali ke Barang masuk');
    expect(s.app.katalog.cariBarcode('8990001', c.id)!.stok, 50 - 12 + 30);
    expect(s.app.katalog.cariBarcode('8990202', c.id)!.kategoriNama, 'Kopi');
    expect(s.app.katalog.cari('Garam', c.id), isEmpty);
    s.app.keluar();
  });

  testWidgets('mode latihan: SPV menyalakan dari layar masuk, pita oranye, struk LATIHAN, kembali ke data asli', (t) async {
    final s = await t.runAsync(_siapkanToko);
    final c = s!.app.cabang;
    final gula = s.app.katalog.cariBarcode('8990001', c.id)!.id;
    final mode = PengaturMode(asli: s.app, bukaDatabaseLatihan: () => DatabaseToko.memori(), hapusDatabaseLatihan: () {});
    await _pasang(t, s.app);
    expect(find.byKey(const ValueKey('pita-latihan')), findsNothing);
    await _foto(t, '01b-masuk-tombol-latihan');
    await t.tap(find.byKey(const ValueKey('nyalakan-latihan')));
    await _tunggu(t);
    expect(find.text('Perlu persetujuan SPV'), findsOneWidget);
    await t.tap(find.byType(DropdownButtonFormField<Pengguna>).last);
    await _tunggu(t);
    await t.tap(find.text('Dewi (SPV)').last);
    await _tunggu(t);
    for (final d in '739104'.split('')) {
      await t.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text(d)).first);
      await t.pump();
    }
    await t.tap(find.text('Setujui'));
    // Pemeriksaan PIN (hash) berjalan sungguhan di luar jam palsu test.
    for (var i = 0; i < 20 && !mode.latihanAktif; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await t.pump(const Duration(milliseconds: 50));
    }
    await _tunggu(t);
    expect(mode.latihanAktif, isTrue);
    expect(find.byKey(const ValueKey('pita-latihan')), findsOneWidget);
    expect(find.text('MODE LATIHAN'), findsOneWidget);
    expect(find.text('Mode latihan menyala'), findsOneWidget);
    await _foto(t, '54-masuk-mode-latihan');

    final l = mode.aktif;
    l.masuk(l.pengguna.ambil(s.kasir.id)!);
    await _tunggu(t);
    await _bukaShiftJikaPerlu(t, l);
    await _keTransaksi(t);
    await _scanMasuk(t, '8990001');
    await _foto(t, '55-latihan-transaksi');
    await t.sendKeyEvent(LogicalKeyboardKey.f12);
    await _tunggu(t);
    await t.enterText(find.descendant(of: find.byType(DialogBayar), matching: find.byType(TextField)), '20000');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await _tunggu(t);
    expect(find.text('Transaksi selesai'), findsOneWidget);
    await _foto(t, '56-latihan-struk-selesai');
    final cetak = latin1.decode((s.app.printer as PrinterUji).riwayat.last);
    expect(cetak, contains(teksStrukLatihan));
    expect(l.katalog.stok(gula, c.id), 37, reason: 'stok latihan berkurang');
    expect(s.app.katalog.stok(gula, c.id), 38, reason: 'stok asli tetap');

    l.keluar();
    await _tunggu(t);
    await t.tap(find.byKey(const ValueKey('matikan-latihan')));
    await _tunggu(t);
    expect(mode.latihanAktif, isFalse);
    expect(find.byKey(const ValueKey('pita-latihan')), findsNothing);
    expect(find.byKey(const ValueKey('nyalakan-latihan')), findsOneWidget);
  });

  testWidgets('kasir: layar transaksi pas di laptop skala 150% (1280×730) dan 1366×768', (t) async {
    final s = await t.runAsync(_siapkanToko);
    final app = s!.app;
    final c = app.cabang;
    final kat = app.katalog.kategori().first.id;
    app.barangMasuk.kirim(
      cabang: c,
      oleh: s.kasir,
      draft: DraftBarangMasuk(supplierId: app.katalog.supplier().first.id, noFaktur: 'F-CONTOH-02', item: [
        DraftItemMasuk(barcode: '8990004', nama: 'Teh Celup isi 25', kategoriId: kat, satuan: 'kotak', jumlah: 20, hpp: 4500, hargaJual: 6000),
        DraftItemMasuk(barcode: '8990005', nama: 'Gas Elpiji 3 kg', kategoriId: kat, satuan: 'tabung', jumlah: 10, hpp: 18000, hargaJual: 18900),
        DraftItemMasuk(barcode: '8990006', nama: 'Mi Instan Goreng', kategoriId: kat, satuan: 'pcs', jumlah: 80, hpp: 2700, hargaJual: 3500),
      ]),
    );
    app.masuk(s.kasir);
    t.view.physicalSize = const Size(1920, 1095);
    t.view.devicePixelRatio = 1.5;
    addTearDown(t.view.reset);
    await t.pumpWidget(RepaintBoundary(key: const ValueKey('layar'), child: AplikasiToko(app: app)));
    await t.pump(const Duration(milliseconds: 300));
    await _keTransaksi(t);
    for (final bc in ['8990001', '8990002', '8990003', '8990004', '8990006']) {
      await _scanMasuk(t, bc);
    }
    await t.enterText(find.byKey(const ValueKey('scan')), '8990005');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('Gas Elpiji 3 kg'), findsOneWidget, reason: 'nama barang muncul di kotak input');
    await _foto(t, '60-kasir-laptop-150');
    t.view.physicalSize = _ukuran;
    t.view.devicePixelRatio = 1;
    await t.pump(const Duration(milliseconds: 300));
    await _foto(t, '61-kasir-1366');
    expect(find.byKey(const ValueKey('kembali-menu')), findsOneWidget);
    app.keluar();
  });
}

/// Kasir yang belum buka shift: buka shift lewat kotak shift di menu.
Future<void> _bukaShiftJikaPerlu(WidgetTester t, Aplikasi app) async {
  if (app.shiftAktif != null) return;
  app.aturShift(app.penjualan.bukaShift(cabangId: app.cabang.id, kasirId: app.penggunaAktif!.id, modalAwal: 100000));
  await t.pump(const Duration(milliseconds: 400));
}
