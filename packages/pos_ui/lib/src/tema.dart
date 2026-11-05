import 'package:flutter/material.dart';

/// Warna tema biru cerah (desain revisi 2, 5 Nov 2026).
/// Hijau dipakai khusus untuk hal yang "berhasil/lunas/aman" (tombol Bayar, Transaksi selesai, status Aman).
abstract final class Warna {
  // Biru utama
  static const utamaTua = Color(0xFF0D47A1);
  static const utama = Color(0xFF1565C0);
  static const utamaGelap = Color(0xFF0D58AE);
  static const utamaTerang = Color(0xFF1E88E5);
  static const utamaMuda = Color(0xFFE3F2FD);
  static const utamaSorot = Color(0xFFD2E8FD);
  static const utamaGarisMuda = Color(0xFF90CAF9);
  static const utamaTeksTerang = Color(0xFFD6EAFF);

  /// Kotak tembus pandang di atas kepala biru.
  static const utamaPanel = Color(0x26FFFFFF);
  static const utamaGaris = Color(0x66FFFFFF);

  /// Gradasi kepala layar (kiri biru tua → kanan biru terang).
  static const gradasiKepala = LinearGradient(colors: [utamaTua, utama, utamaTerang], stops: [0, 0.45, 1]);

  static const latar = Color(0xFFE8EEF6);
  static const latarTerang = Color(0xFFF5F8FC);
  static const putih = Colors.white;
  static const baris2 = Color(0xFFF6F9FD);
  static const kepalaTabel = Color(0xFFDCEAFB);
  static const garisTipis = Color(0xFFE1E8F0);
  static const garis = Color(0xFFB7C4D4);
  static const garisInput = Color(0xFFAEBBCB);
  static const abuMuda = Color(0xFFEEF2F7);

  static const teks = Color(0xFF122033);
  static const teks2 = Color(0xFF2A3A50);
  static const teksPudar = Color(0xFF53627A);

  // Hijau = berhasil / bayar / aman
  static const sukses = Color(0xFF1E9E57);
  static const suksesTua = Color(0xFF147A42);
  static const suksesMuda = Color(0xFFE3F6EA);

  // Kuning-oranye = kembalian, perhatian
  static const oranyeMuda = Color(0xFFFFF3D6);
  static const oranyeGaris = Color(0xFFF2BD55);
  static const oranye = Color(0xFF8A4500);
  static const oranyeTua = Color(0xFF7A4300);
  static const oranyeTegas = Color(0xFFE39A16);
  static const ambarTombol = Color(0xFFFFE7B0);
  static const lencanaOranye = Color(0xFFD9480F);

  static const merahMuda = Color(0xFFFDECEA);
  static const merah = Color(0xFFB42318);
  static const merahGaris = Color(0xFFE7978F);
  static const merahTua = Color(0xFF8A1F14);

  // Warna kelompok menu & ikon
  static const toska = Color(0xFF0E7C86);
  static const toskaMuda = Color(0xFFD8F1F2);
  static const ungu = Color(0xFF6E44C2);
  static const unguMuda = Color(0xFFEDE5FB);
  static const coklat = Color(0xFFC0620F);
  static const coklatMuda = Color(0xFFFDEBD8);
  static const hijauIkon = Color(0xFF23843F);
  static const hijauIkonMuda = Color(0xFFDFF3E4);
  static const merahIkon = Color(0xFFC2334A);
  static const merahIkonMuda = Color(0xFFFBE3E7);
  static const abuIkon = Color(0xFF4B5A70);
  static const abuIkonMuda = Color(0xFFE6EBF2);

  static const biruMuda = utamaMuda;
  static const biru = utama;

  static const bayangan = [
    BoxShadow(color: Color(0x1A102850), blurRadius: 2, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x1A102850), blurRadius: 14, offset: Offset(0, 4)),
  ];
  static const bayanganKuat = [
    BoxShadow(color: Color(0x1F102850), blurRadius: 4, offset: Offset(0, 2)),
    BoxShadow(color: Color(0x33102850), blurRadius: 32, offset: Offset(0, 12)),
  ];
}

const fontUtama = 'PlusJakartaSans';
const fontMono = 'JetBrainsMono';

ThemeData buatTema() {
  final dasar = ThemeData(
    useMaterial3: true,
    fontFamily: fontUtama,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Warna.utama,
      primary: Warna.utama,
      onPrimary: Colors.white,
      surface: Colors.white,
      error: Warna.merah,
    ),
    scaffoldBackgroundColor: Warna.latar,
  );
  final r = BorderRadius.circular(10);
  OutlineInputBorder garisInput(Color c, [double lebar = 2]) =>
      OutlineInputBorder(borderRadius: r, borderSide: BorderSide(color: c, width: lebar));
  return dasar.copyWith(
    textTheme: dasar.textTheme.apply(bodyColor: Warna.teks, displayColor: Warna.teks, fontFamily: fontUtama),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      border: garisInput(Warna.garisInput),
      enabledBorder: garisInput(Warna.garisInput),
      focusedBorder: garisInput(Warna.utama, 3),
      errorBorder: garisInput(Warna.merahGaris),
      focusedErrorBorder: garisInput(Warna.merah, 3),
      labelStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Warna.teks2),
      floatingLabelBehavior: FloatingLabelBehavior.always,
      hintStyle: const TextStyle(color: Color(0xFF8793A3)),
      errorStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Warna.utama,
        foregroundColor: Colors.white,
        disabledBackgroundColor: const Color(0xFFDCE3EC),
        disabledForegroundColor: Warna.teksPudar,
        minimumSize: const Size(64, 56),
        padding: const EdgeInsets.symmetric(horizontal: 22),
        textStyle: const TextStyle(fontFamily: fontUtama, fontSize: 18, fontWeight: FontWeight.w800),
        shape: RoundedRectangleBorder(borderRadius: r),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Warna.teks,
        backgroundColor: Colors.white,
        minimumSize: const Size(56, 56),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        side: const BorderSide(color: Warna.garisInput, width: 2),
        textStyle: const TextStyle(fontFamily: fontUtama, fontSize: 17, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: r),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: Warna.utamaGelap,
        minimumSize: const Size(48, 48),
        textStyle: const TextStyle(fontFamily: fontUtama, fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      contentTextStyle: TextStyle(fontFamily: fontUtama, fontSize: 17, fontWeight: FontWeight.w600),
    ),
    dividerTheme: const DividerThemeData(color: Warna.garisTipis, thickness: 1.5, space: 1),
  );
}
