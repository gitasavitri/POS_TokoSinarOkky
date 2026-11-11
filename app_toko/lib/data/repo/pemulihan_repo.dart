import 'dart:convert';

import 'package:pos_core/pos_core.dart';

import '../database.dart';
import '../model.dart';
import 'katalog_repo.dart';
import 'pengaturan_repo.dart';

/// Belanjaan yang tersimpan sebelum aplikasi tertutup (mis. listrik padam).
class KeranjangTersimpan {
  const KeranjangTersimpan({required this.aktif, required this.ditahan, required this.waktu, required this.namaKasir, required this.hilang});
  final Keranjang aktif;
  final List<Keranjang> ditahan;
  final DateTime waktu;
  final String namaKasir;

  /// Barang yang tidak bisa dimuat lagi (sudah tidak dijual di toko ini).
  final int hilang;

  bool get kosong => aktif.kosong && ditahan.isEmpty;
}

/// Data kecil untuk pulih setelah aplikasi tertutup mendadak: belanjaan yang sedang di-scan,
/// dan transaksi yang sudah tersimpan tapi mungkin belum tercetak struknya.
/// Disimpan di tabel pengaturan_perangkat (khusus PC ini, tidak dikirim ke pusat).
class PemulihanRepo {
  PemulihanRepo(this._db) : _pengaturan = PengaturanRepo(_db), _katalog = KatalogRepo(_db);
  final DatabaseToko _db;
  final PengaturanRepo _pengaturan;
  final KatalogRepo _katalog;

  static const kKeranjang = 'keranjang_tersimpan';
  static const kStrukBelumCetak = 'struk_belum_cetak';
  static const kTukar = 'tukar_tersimpan';

  // ---------------------------------------------------------------- keranjang

  static List<Map<String, Object>> _keJson(Keranjang k) => [for (final b in k.baris) {'id': b.barang.id, 'qty': b.qty}];

  /// Dipanggil setiap kali isi keranjang berubah. Keranjang kosong & tidak ada yang ditahan = hapus catatan.
  void simpanKeranjang({required String kasirId, required Keranjang aktif, required List<Keranjang> ditahan}) {
    if (aktif.kosong && ditahan.isEmpty) {
      _pengaturan.simpan(kKeranjang, null);
      return;
    }
    _pengaturan.simpan(
      kKeranjang,
      jsonEncode({
        'kasir_id': kasirId,
        'waktu': _db.sekarangIso(),
        'aktif': _keJson(aktif),
        'ditahan': [for (final k in ditahan) _keJson(k)],
      }),
    );
  }

  /// Muat belanjaan tersimpan dengan harga TERKINI (kalau harga berubah sejak itu, yang berlaku harga baru).
  KeranjangTersimpan? muatKeranjang(String cabangId) {
    final teks = _pengaturan.ambil(kKeranjang);
    if (teks == null) return null;
    final Map<String, Object?> j;
    try {
      j = jsonDecode(teks) as Map<String, Object?>;
    } on FormatException {
      _pengaturan.simpan(kKeranjang, null);
      return null;
    }
    var hilang = 0;
    Keranjang buat(Object? daftar) {
      final k = Keranjang();
      for (final b in (daftar as List? ?? const [])) {
        final m = b as Map;
        final barang = _katalog.untukKasir(m['id'] as String, cabangId);
        if (barang == null) {
          hilang++;
          continue;
        }
        k.tambah(barang, qty: (m['qty'] as num).toInt());
      }
      return k;
    }

    final aktif = buat(j['aktif']);
    final ditahan = [for (final d in (j['ditahan'] as List? ?? const [])) buat(d)]..removeWhere((k) => k.kosong);
    final kasir = _db.satu('SELECT nama FROM pengguna WHERE id = ?', [j['kasir_id']]);
    return KeranjangTersimpan(
      aktif: aktif,
      ditahan: ditahan,
      waktu: DateTime.tryParse(j['waktu'] as String? ?? '') ?? _db.sekarang(),
      namaKasir: kasir?['nama'] as String? ?? '-',
      hilang: hilang,
    );
  }

  void hapusKeranjang() => _pengaturan.simpan(kKeranjang, null);

  // ---------------------------------------------------------------- tukar barang (revisi F)

  /// Barang tukaran yang sedang dibawa di layar Transaksi (belum dibayar). Null = hapus.
  void simpanTukar(DraftTukar? tukar) => _pengaturan.simpan(kTukar, tukar == null ? null : jsonEncode(tukar.keJson()));

  /// Isi mentah draft tukar tersimpan (dimuat ulang lewat `PenjualanRepo.draftTukarDariJson`).
  Map<String, Object?>? muatTukar() {
    final teks = _pengaturan.ambil(kTukar);
    if (teks == null) return null;
    try {
      return jsonDecode(teks) as Map<String, Object?>;
    } on FormatException {
      hapusTukar();
      return null;
    }
  }

  void hapusTukar() => _pengaturan.simpan(kTukar, null);

  // ---------------------------------------------------------------- struk

  /// Dipanggil DI DALAM transaksi database yang menyimpan penjualan, jadi tanda ini ada kalau dan hanya kalau
  /// transaksinya tersimpan.
  void tandaiBelumCetak(String transaksiId) => _pengaturan.simpan(kStrukBelumCetak, transaksiId);

  /// Struk sudah tercetak, atau kasir sudah melihat hasilnya.
  void selesaiCetak() => _pengaturan.simpan(kStrukBelumCetak, null);

  /// Id transaksi yang struknya mungkin belum tercetak (aplikasi tertutup sebelum cetak selesai).
  String? strukBelumCetak() => _pengaturan.ambil(kStrukBelumCetak);
}
