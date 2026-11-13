// Uji layar Aplikasi Pusat dengan server palsu, ukuran 1366×768.
// Gambar layar: GAMBAR=1 flutter test test/tampilan_test.dart --update-goldens  (hasil di test/gambar/, tidak ikut git)

import 'dart:io';

import 'package:app_pusat/layanan/sesi.dart';
import 'package:app_pusat/ui/akar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_core/pos_core.dart';
import 'package:pos_ui/pos_ui.dart';

import 'api_palsu.dart';

final _gambar = Platform.environment['GAMBAR'] == '1';

Future<void> _muatHuruf() async {
  Future<void> muat(String keluarga, List<String> berkas) async {
    final l = FontLoader(keluarga);
    for (final b in berkas) {
      l.addFont(Future.value(ByteData.sublistView(File(b).readAsBytesSync())));
    }
    await l.load();
  }

  await muat('PlusJakartaSans', [for (final w in ['400Regular', '500Medium', '600SemiBold', '700Bold', '800ExtraBold']) 'assets/fonts/PlusJakartaSans_$w.ttf']);
  await muat('JetBrainsMono', ['assets/fonts/JetBrainsMono_400Regular.ttf', 'assets/fonts/JetBrainsMono_700Bold.ttf']);
  final root = Platform.environment['FLUTTER_ROOT'];
  final ikon = File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (root != null && ikon.existsSync()) await muat('MaterialIcons', [ikon.path]);
}

Future<(Sesi, ApiPalsu)> _pasang(WidgetTester t, {bool masuk = true}) async {
  t.view.physicalSize = const Size(1366, 768);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final api = ApiPalsu();
  final lokal = PengaturanLokal.memori();
  await lokal.simpanAlamatServer('https://pos.contoh.test');
  final sesi = Sesi(lokal: lokal, buatApi: (_) => api);
  if (masuk) await sesi.masuk('admin.contoh', 'sandi-contoh-1', '123456');
  await t.pumpWidget(RepaintBoundary(key: const ValueKey('layar'), child: AplikasiPusat(sesi: sesi)));
  await t.pump(const Duration(milliseconds: 300));
  await t.pump(const Duration(milliseconds: 300));
  return (sesi, api);
}

Future<void> _foto(WidgetTester t, String nama) async {
  expect(t.takeException(), isNull, reason: 'galat tampilan di $nama');
  if (_gambar) await expectLater(find.byKey(const ValueKey('layar')), matchesGoldenFile('gambar/$nama.png'));
}

/// Ikon menu (bukan teks yang sama di kartu angka).
Finder _ubin(MenuPusat m) => find.descendant(of: find.byType(UbinMenu), matching: find.text(m.label));

void main() {
  setUpAll(_muatHuruf);

  testWidgets('alamat server: wajib https', (t) async {
    t.view.physicalSize = const Size(1366, 768);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final sesi = Sesi(lokal: PengaturanLokal.memori(), buatApi: (_) => ApiPalsu());
    await t.pumpWidget(RepaintBoundary(key: const ValueKey('layar'), child: AplikasiPusat(sesi: sesi)));
    await t.enterText(find.byType(TextField), 'http://pos.contoh.test');
    await t.tap(find.text('Simpan & periksa'));
    await t.pump();
    expect(find.textContaining('https://'), findsWidgets);
    expect(sesi.server, isNull);
    await _foto(t, '00-server');
  });

  testWidgets('masuk: salah kode ditolak, benar masuk ke ringkasan', (t) async {
    final (sesi, _) = await _pasang(t, masuk: false);
    await _foto(t, '01-masuk');
    final isian = find.byType(TextField);
    await t.enterText(isian.at(0), 'admin.contoh');
    await t.enterText(isian.at(1), 'sandi-contoh-1');
    await t.enterText(isian.at(2), '000000');
    await t.tap(find.text('Masuk').last);
    await t.pump();
    expect(find.text('Nama pengguna, kata sandi, atau kode tidak cocok'), findsOneWidget);
    await t.enterText(isian.at(1), 'sandi-contoh-1');
    await t.enterText(isian.at(2), '123456');
    await t.tap(find.text('Masuk').last);
    await t.pump(const Duration(milliseconds: 300));
    await t.pump(const Duration(milliseconds: 300));
    expect(sesi.admin?.nama, 'Admin Contoh');
    expect(find.text('KANTOR PUSAT'), findsOneWidget);
    expect(find.text('Ringkasan semua toko'), findsWidgets);
    await sesi.keluar();
  });

  testWidgets('menu ikon: ringkasan hari ini + toko yang tidak mengirim data', (t) async {
    final (sesi, _) = await _pasang(t);
    expect(find.text('KANTOR PUSAT'), findsOneWidget);
    expect(find.text('Rp 3.805.000'), findsOneWidget);
    for (final m in MenuPusat.values) {
      expect(_ubin(m), findsOneWidget);
    }
    await _foto(t, '09-menu');
    await sesi.keluar();
  });

  for (final m in MenuPusat.values) {
    testWidgets('layar ${m.label}', (t) async {
      final (sesi, _) = await _pasang(t);
      await t.tap(_ubin(m));
      await t.pump(const Duration(milliseconds: 300));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('KANTOR PUSAT'), findsNothing);
      await _foto(t, '1${m.index}-${m.name}');
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('KANTOR PUSAT'), findsOneWidget, reason: 'Esc kembali ke menu');
      await sesi.keluar();
    });
  }

  testWidgets('ringkasan: angka per toko tampil, toko yang belum kirim data ditandai', (t) async {
    final (sesi, _) = await _pasang(t);
    await t.tap(_ubin(MenuPusat.ringkasan));
    await t.pump(const Duration(milliseconds: 300));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Rp 3.805.000'), findsOneWidget);
    expect(find.text('A01 · Contoh Satu'), findsOneWidget);
    expect(find.text('Belum pernah'), findsOneWidget);
    expect(find.text('5 jam lalu'), findsOneWidget);
    await sesi.keluar();
  });

  testWidgets('harga pusat: grosir di bawah HPP ditolak sebelum dikirim; yang benar terkirim', (t) async {
    final (sesi, api) = await _pasang(t);
    await t.tap(_ubin(MenuPusat.barang));
    await t.pump(const Duration(milliseconds: 300));
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.text('Gula Pasir 1 kg'));
    await t.pump(const Duration(milliseconds: 400));
    await t.pump(const Duration(milliseconds: 400));
    final dialog = find.byType(AlertDialog);
    final isian = find.descendant(of: dialog, matching: find.byType(TextField));
    // isian: 0 eceran, 1 min qty, 2 harga grosir, 3 alasan
    await t.enterText(isian.at(0), '18000');
    await t.enterText(isian.at(2), '16000');
    await t.enterText(isian.at(3), 'Harga supplier naik');
    await t.pump();
    if (_gambar) await _foto(t, '30-dialog-harga');
    await t.tap(find.text('Simpan untuk semua toko'));
    await t.pump();
    expect(find.textContaining('HPP'), findsWidgets);
    expect(api.hargaTerkirim, isEmpty);

    await t.enterText(isian.at(2), '17500');
    await t.tap(find.text('Simpan untuk semua toko'));
    await t.pump(const Duration(milliseconds: 300));
    expect(api.hargaTerkirim.single.eceran, 18000);
    expect(api.hargaTerkirim.single.grosir.single, const TingkatGrosir(minQty: 10, harga: 17500));
    expect(api.hargaTerkirim.single.alasan, 'Harga supplier naik');
    await sesi.keluar();
  });

  testWidgets('toko & perangkat: salin daftar barang dari toko lain ke toko baru (I)', (t) async {
    final (sesi, api) = await _pasang(t);
    await t.tap(_ubin(MenuPusat.toko));
    await t.pump(const Duration(milliseconds: 300));
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.byKey(const ValueKey('salin-barang-c3')));
    await t.pump(const Duration(milliseconds: 300));
    await t.pump(const Duration(milliseconds: 300)); // animasi dialog
    expect(find.text('Salin daftar barang ke C03 · Contoh Tiga'), findsOneWidget);
    expect(find.textContaining('STOK TIDAK IKUT'), findsOneWidget);
    await _foto(t, '40-salin-daftar-barang');
    await t.tap(find.byKey(const ValueKey('salin-barang-ya')));
    await t.pump(const Duration(milliseconds: 300));
    await t.pump(const Duration(milliseconds: 300));
    expect(api.salinan.single, (ke: 'c3', dari: 'c1'));
    expect(find.textContaining('120 barang ditambahkan ke daftar toko C03'), findsOneWidget);
    await _foto(t, '41-salin-daftar-barang-selesai');

    await t.tap(find.byKey(const ValueKey('salin-barang-c3')));
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.byKey(const ValueKey('salin-dari')));
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.text('Semua barang (dari semua toko)').last);
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.byKey(const ValueKey('salin-barang-ya')));
    await t.pump(const Duration(milliseconds: 300));
    expect(api.salinan.last, (ke: 'c3', dari: null), reason: 'semua barang = tanpa toko asal');
    await sesi.keluar();
  });

  testWidgets('sesi habis di server → kembali ke layar masuk dengan pesan', (t) async {
    final (sesi, api) = await _pasang(t);
    api.sesiHabis = true;
    await t.tap(_ubin(MenuPusat.transaksi));
    await t.pump(const Duration(milliseconds: 300));
    await t.pump(const Duration(milliseconds: 300));
    expect(sesi.admin, isNull);
    expect(find.text('Sesi berakhir, silakan masuk lagi'), findsOneWidget);
  });

  testWidgets('keluar otomatis setelah 10 menit tidak dipakai', (t) async {
    final (sesi, _) = await _pasang(t);
    await t.pump(const Duration(minutes: 9));
    expect(sesi.admin, isNotNull);
    await t.tap(_ubin(MenuPusat.log)); // ada aktivitas: hitungan diulang
    await t.pump(const Duration(minutes: 9));
    expect(sesi.admin, isNotNull);
    await t.pump(const Duration(minutes: 2));
    expect(sesi.admin, isNull);
    expect(find.textContaining('10 menit'), findsWidgets);
  });
}
