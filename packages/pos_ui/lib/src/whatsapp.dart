import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pos_core/pos_core.dart';

import 'umum.dart';

/// Hanya untuk tes: kalau diisi, tautan WhatsApp dikirim ke sini dan tidak ada program yang dibuka.
@visibleForTesting
Future<void> Function(String tautan)? pembukaTautanUji;

/// Buka WhatsApp dengan [pesan] sudah terisi (pengirim memilih penerima dan menekan kirim sendiri).
/// Kalau WhatsApp tidak bisa dibuka, pesan disalin ke clipboard supaya bisa ditempel manual.
/// Hasil: `true` kalau terbuka, `false` kalau pesan hanya disalin.
Future<bool> bukaWhatsApp(String pesan) async {
  final tautan = tautanWa(pesan).toString();
  try {
    final uji = pembukaTautanUji;
    if (uji != null) {
      await uji(tautan);
      return true;
    }
    if (Platform.isWindows) {
      // rundll32 tidak lewat cmd, jadi tanda & atau % di tautan aman.
      await Process.start('rundll32', ['url.dll,FileProtocolHandler', tautan], mode: ProcessStartMode.detached);
    } else if (Platform.isMacOS) {
      await Process.start('open', [tautan], mode: ProcessStartMode.detached);
    } else {
      await Process.start('xdg-open', [tautan], mode: ProcessStartMode.detached);
    }
    return true;
  } catch (_) {
    await Clipboard.setData(ClipboardData(text: pesan));
    return false;
  }
}

/// Tanyakan dulu, lalu buka WhatsApp dengan [pesan] terisi. Dipakai kasir setelah membuat usulan dan oleh pemutus yang
/// ingin meneruskan usulan ke orang lain. Tidak ada pengiriman otomatis: pengirim yang menekan kirim di WhatsApp.
Future<void> tawarkanKirimWa(BuildContext context, String pesan, {String judul = 'Beritahu lewat WhatsApp?', String ya = 'Kirim ke WA', String batal = 'Nanti'}) async {
  final mau = await konfirmasi(context, judul: judul, isi: pesan, ya: ya, batal: batal);
  if (!mau || !context.mounted) return;
  final terbuka = await bukaWhatsApp(pesan);
  if (!context.mounted) return;
  tampilkanPesan(context, terbuka ? 'WhatsApp dibuka. Pilih penerima lalu tekan kirim.' : 'WhatsApp tidak bisa dibuka. Pesan disalin, tempel di WhatsApp.');
}
