import 'package:pos_core/pos_core.dart';

class InfoCabang {
  const InfoCabang({
    required this.id,
    required this.kode,
    required this.nama,
    required this.alamat,
    required this.pesanStruk,
    required this.namaToko,
  });

  final String id;
  final String kode;
  final String nama;
  final String alamat;
  final String pesanStruk;

  /// Nama merek toko (sama untuk semua cabang).
  final String namaToko;
}

class Pengguna {
  const Pengguna({
    required this.id,
    required this.nama,
    required this.peran,
    required this.cabangId,
    this.namaPengguna,
    this.terkunci = false,
    this.aktif = true,
  });

  final String id;
  final String nama;
  final Peran peran;
  final String? cabangId;
  final String? namaPengguna;
  final bool terkunci;
  final bool aktif;
}

class Kategori {
  const Kategori(this.id, this.nama);
  final String id;
  final String nama;
}

class Supplier {
  const Supplier(this.id, this.nama, this.jenis);
  final String id;
  final String nama;

  /// 'luar' atau 'toko_utama'
  final String jenis;
}

/// Data lengkap satu barang di toko ini (untuk daftar barang & form barang masuk).
class DetailBarang {
  const DetailBarang({
    required this.id,
    required this.barcode,
    required this.nama,
    required this.kategoriId,
    required this.kategoriNama,
    required this.satuan,
    required this.hargaJualId,
    required this.harga,
    required this.hpp,
    required this.stok,
    required this.stokMinimum,
    required this.dijualDiToko,
  });

  final String id;
  final String? barcode;
  final String nama;
  final String kategoriId;
  final String kategoriNama;
  final String satuan;

  /// null kalau barang belum punya harga.
  final String? hargaJualId;
  final HargaBarang? harga;
  final int? hpp;
  final int stok;
  final int stokMinimum;

  /// Ada di `barang_cabang` toko ini dan aktif.
  final bool dijualDiToko;

  BarangJual? get untukDijual => harga == null
      ? null
      : BarangJual(id: id, nama: nama, satuan: satuan, barcode: barcode, harga: harga!, hpp: hpp ?? 0);
}

class HasilLogin {
  const HasilLogin._(this.pengguna, this.pesan, {this.terkunci = false});

  factory HasilLogin.berhasil(Pengguna p) => HasilLogin._(p, null);
  factory HasilLogin.gagal(String pesan, {bool terkunci = false}) =>
      HasilLogin._(null, pesan, terkunci: terkunci);

  final Pengguna? pengguna;
  final String? pesan;
  final bool terkunci;

  bool get berhasil => pengguna != null;
}

class Shift {
  const Shift({required this.id, required this.kasirId, required this.modalAwal, required this.dibukaPada});
  final String id;
  final String kasirId;
  final int modalAwal;
  final DateTime dibukaPada;
}

class RingkasanShift {
  const RingkasanShift({
    required this.shift,
    required this.jumlahTransaksi,
    required this.penjualanTunai,
    required this.penjualanNonTunai,
    required this.returTunai,
    this.kasMasuk = 0,
    this.kasKeluar = 0,
  });

  final Shift shift;
  final int jumlahTransaksi;
  final int penjualanTunai;
  final int penjualanNonTunai;
  final int returTunai;
  final int kasMasuk;
  final int kasKeluar;

  /// Total penjualan (tunai + non-tunai). Boleh dilihat kasir.
  int get penjualan => penjualanTunai + penjualanNonTunai;

  /// Uang tunai yang seharusnya ada. JANGAN ditampilkan ke kasir sebelum ia menghitung (hitung buta).
  int get kasSistem => hitungKasSeharusnya(
        modalAwal: shift.modalAwal,
        penjualanTunai: penjualanTunai,
        returTunai: returTunai,
        kasMasuk: kasMasuk,
        kasKeluar: kasKeluar,
      );
}

/// Kas keluar/masuk selama shift.
class KasShift {
  const KasShift({
    required this.id,
    required this.jenis,
    required this.jumlah,
    required this.keterangan,
    required this.namaPembuat,
    required this.namaPenyetuju,
    required this.waktu,
  });
  final String id;
  final JenisKas jenis;
  final int jumlah;
  final String keterangan;
  final String namaPembuat;
  final String? namaPenyetuju;
  final DateTime waktu;
}

/// Satu hitungan uang saat tutup shift.
class HitunganShift {
  const HitunganShift({
    required this.ke,
    required this.kasDihitung,
    required this.kasSistem,
    required this.selisih,
    required this.disetujuiOleh,
    required this.waktu,
  });
  final int ke;
  final int kasDihitung;
  final int kasSistem;
  final int selisih;
  final String? disetujuiOleh;
  final DateTime waktu;
}

/// Ringkasan transaksi untuk daftar/laporan.
class BarisTransaksi {
  const BarisTransaksi({
    required this.id,
    required this.noTransaksi,
    required this.waktu,
    required this.kasir,
    required this.jumlahBarang,
    required this.total,
    required this.metode,
    required this.dibatalkan,
    required this.adaRetur,
  });

  final String id;
  final String noTransaksi;
  final DateTime waktu;
  final String kasir;
  final int jumlahBarang;
  final int total;
  final MetodeBayar metode;
  final bool dibatalkan;
  final bool adaRetur;

  String get status => dibatalkan ? 'Dibatalkan' : (adaRetur ? 'Retur' : 'Lunas');
}

/// Satu barang dalam draft barang masuk (belum tersimpan sebagai data terkunci).
class DraftItemMasuk {
  DraftItemMasuk({
    this.barangId,
    this.barcode = '',
    this.nama = '',
    this.kategoriId = '',
    this.satuan = 'pcs',
    this.jumlah = 0,
    this.hpp = 0,
    this.hargaJual = 0,
    List<TingkatGrosir>? grosir,
    this.asal,
  }) : grosir = grosir ?? [];

  /// null = barang baru (belum ada di sistem).
  String? barangId;
  String barcode;
  String nama;
  String kategoriId;
  String satuan;
  int jumlah;
  int hpp;
  int hargaJual;
  List<TingkatGrosir> grosir;

  /// Data barang sebelum diubah (untuk menandai perubahan dan halaman konfirmasi). null untuk barang baru.
  DetailBarang? asal;

  bool get barangBaru => barangId == null;

  bool get dataBarangBerubah =>
      asal != null &&
      (asal!.nama != nama ||
          asal!.kategoriId != kategoriId ||
          asal!.satuan != satuan ||
          (asal!.barcode ?? '') != barcode);

  bool get hargaBerubah {
    if (asal == null) return true;
    final h = asal!.harga;
    if (h == null) return true;
    if (h.eceran != hargaJual) return true;
    if (h.grosir.length != grosir.length) return true;
    for (var i = 0; i < grosir.length; i++) {
      if (h.grosir[i] != grosir[i]) return true;
    }
    return false;
  }

  String get status => barangBaru ? 'Barang baru' : ((dataBarangBerubah || hargaBerubah) ? 'Data diubah' : 'Stok masuk saja');

  Map<String, Object?> keJson() => {
        'barangId': barangId,
        'barcode': barcode,
        'nama': nama,
        'kategoriId': kategoriId,
        'satuan': satuan,
        'jumlah': jumlah,
        'hpp': hpp,
        'hargaJual': hargaJual,
        'grosir': [for (final t in grosir) [t.minQty, t.harga]],
      };

  static DraftItemMasuk dariJson(Map<String, Object?> j) => DraftItemMasuk(
        barangId: j['barangId'] as String?,
        barcode: j['barcode'] as String? ?? '',
        nama: j['nama'] as String? ?? '',
        kategoriId: j['kategoriId'] as String? ?? '',
        satuan: j['satuan'] as String? ?? 'pcs',
        jumlah: j['jumlah'] as int? ?? 0,
        hpp: j['hpp'] as int? ?? 0,
        hargaJual: j['hargaJual'] as int? ?? 0,
        grosir: [
          for (final t in (j['grosir'] as List<Object?>? ?? const []))
            TingkatGrosir(minQty: (t! as List<Object?>)[0]! as int, harga: t[1]! as int),
        ],
      );
}
