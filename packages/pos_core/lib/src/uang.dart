/// Format dan baca angka rupiah. Uang selalu `int` (rupiah utuh), tidak pernah `double`.
library;

/// `17500` → `"17.500"`, `-6000` → `"-6.000"`.
String formatAngka(int nilai) {
  final negatif = nilai < 0;
  final digit = nilai.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < digit.length; i++) {
    if (i > 0 && (digit.length - i) % 3 == 0) buf.write('.');
    buf.write(digit[i]);
  }
  return negatif ? '-$buf' : buf.toString();
}

/// `17500` → `"Rp 17.500"`, `-6000` → `"-Rp 6.000"`.
String formatRupiah(int nilai) => nilai < 0 ? '-Rp ${formatAngka(-nilai)}' : 'Rp ${formatAngka(nilai)}';

/// Ambil hanya digit dari input pengguna. `"Rp 1.250.000"` → `1250000`.
/// Kosong → `0`. Dibatasi 13 digit supaya tidak melewati batas int yang aman.
int bacaAngka(String teks) {
  final digit = teks.replaceAll(RegExp(r'[^0-9]'), '');
  if (digit.isEmpty) return 0;
  final dipotong = digit.length > 13 ? digit.substring(0, 13) : digit;
  return int.parse(dipotong);
}

/// Pembagian bilangan bulat dibulatkan ke terdekat (setengah ke atas). `pembagi` harus > 0.
int bagiBulat(int pembilang, int pembagi) {
  if (pembagi <= 0) {
    throw ArgumentError.value(pembagi, 'pembagi', 'harus lebih dari 0');
  }
  if (pembilang >= 0) return (pembilang * 2 + pembagi) ~/ (pembagi * 2);
  return -((-pembilang * 2 + pembagi) ~/ (pembagi * 2));
}
