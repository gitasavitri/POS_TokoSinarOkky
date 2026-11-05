import 'package:flutter/material.dart';

/// Warna dari desain (kanvas "Desain POS Minimarket").
abstract final class Warna {
  static const hijauTua = Color(0xFF0F3D2E);
  static const hijauPanel = Color(0xFF1A4A39);
  static const hijauGaris = Color(0xFF2E6450);
  static const hijau = Color(0xFF0F6B4E);
  static const hijauGelap = Color(0xFF0A4D38);
  static const hijauMuda = Color(0xFFE3F1EA);
  static const hijauSorot = Color(0xFFDDF0E6);
  static const hijauTeksTerang = Color(0xFFB9D3C8);

  static const latar = Color(0xFFE3E8E5);
  static const latarTerang = Color(0xFFF4F5F2);
  static const putih = Colors.white;
  static const baris2 = Color(0xFFF7F9F8);
  static const kepalaTabel = Color(0xFFD9E1DD);
  static const garisTipis = Color(0xFFE4E9E6);
  static const garis = Color(0xFFC3CDC8);
  static const garisInput = Color(0xFFB7C2BD);
  static const abuMuda = Color(0xFFEEF2EF);

  static const teks = Color(0xFF14201B);
  static const teks2 = Color(0xFF2A3631);
  static const teksPudar = Color(0xFF4A5752);

  static const oranyeMuda = Color(0xFFFDF0DD);
  static const oranyeGaris = Color(0xFFE9C48E);
  static const oranye = Color(0xFF8A4500);
  static const oranyeTua = Color(0xFF5C2E00);
  static const oranyeTegas = Color(0xFFC27400);

  static const merahMuda = Color(0xFFF9E3E0);
  static const merah = Color(0xFFA3271B);
  static const merahGaris = Color(0xFFC4473A);
  static const merahTua = Color(0xFF8A1F14);

  static const biruMuda = Color(0xFFE4ECF7);
  static const biru = Color(0xFF1F4E8C);
}

const fontUtama = 'PlusJakartaSans';
const fontMono = 'JetBrainsMono';

ThemeData buatTema() {
  final dasar = ThemeData(
    useMaterial3: true,
    fontFamily: fontUtama,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Warna.hijau,
      primary: Warna.hijau,
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
      focusedBorder: garisInput(Warna.hijau, 3),
      errorBorder: garisInput(Warna.merahGaris),
      focusedErrorBorder: garisInput(Warna.merah, 3),
      labelStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Warna.teks2),
      floatingLabelBehavior: FloatingLabelBehavior.always,
      hintStyle: const TextStyle(color: Color(0xFF8A9690)),
      errorStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Warna.hijau,
        foregroundColor: Colors.white,
        disabledBackgroundColor: const Color(0xFFDCE3DF),
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
        foregroundColor: Warna.hijauGelap,
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
