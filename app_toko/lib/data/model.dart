import 'package:pos_core/pos_core.dart';

class InfoCabang {
  const InfoCabang({
    required this.id,
    required this.kode,
    required this.nama,
    required this.alamat,
    required this.pesanStruk,
    required this.namaToko,
    this.telepon = '',
    this.tambahan = '',
  });

  final String id;
  final String kode;
  final String nama;
  final String alamat;
  final String pesanStruk;

  /// Nama merek toko (sama untuk semua cabang).
  final String namaToko;

  /// Opsional, khusus PC ini (tidak ikut sinkron): dicetak di kepala struk.
  final String telepon;
  final String tambahan;
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
    this.potonganTukar = 0,
  });

  final Shift shift;
  final int jumlahTransaksi;

  /// Uang tunai yang diterima dari penjualan (sudah dikurangi potongan tukar barang).
  final int penjualanTunai;

  /// Uang non-tunai yang diterima (sudah dikurangi potongan tukar barang).
  final int penjualanNonTunai;

  /// Uang tunai yang dikembalikan ke pembeli karena retur (bagian yang jadi potongan tukar tidak termasuk).
  final int returTunai;
  final int kasMasuk;
  final int kasKeluar;

  /// Bagian belanja yang dibayar dengan barang tukaran (revisi F), bukan uang.
  final int potonganTukar;

  /// Total penjualan (tunai + non-tunai + potongan tukar). Boleh dilihat kasir.
  int get penjualan => penjualanTunai + penjualanNonTunai + potonganTukar;

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
/// Shift yang ditutup kasir "Belum dihitung" dan amplopnya belum dihitung SPV/Admin (revisi P).
class ShiftMenunggu {
  const ShiftMenunggu({
    required this.shiftId,
    required this.kasirId,
    required this.namaKasir,
    required this.modalAwal,
    required this.dibukaPada,
    required this.ditutupPada,
    required this.kasSistem,
    required this.modalDitinggal,
    required this.labelAmplop,
    required this.jumlahTransaksi,
  });

  final String shiftId;
  final String kasirId;
  final String namaKasir;
  final int modalAwal;
  final DateTime dibukaPada;
  final DateTime ditutupPada;

  /// Uang tunai seharusnya saat ditutup. Hanya untuk SPV/Admin, tampilkan SETELAH amplop dihitung.
  final int kasSistem;
  final int modalDitinggal;
  final String labelAmplop;
  final int jumlahTransaksi;
}

/// Hasil SPV/Admin menghitung amplop shift "Belum dihitung".
class HasilHitungAmplop {
  const HasilHitungAmplop({required this.amplopDihitung, required this.modalDitinggal, required this.kasSistem, required this.selisih});
  final int amplopDihitung;
  final int modalDitinggal;
  final int kasSistem;
  final int selisih;
  int get amplopSeharusnya => hitungIsiAmplopSeharusnya(kasSistem: kasSistem, modalDitinggal: modalDitinggal);
}

/// Satu baris barang di detail riwayat transaksi (revisi E).
class ItemDetailTransaksi {
  const ItemDetailTransaksi({
    required this.barangId,
    required this.nama,
    required this.qty,
    required this.hargaSatuan,
    required this.isGrosir,
    required this.subtotal,
    required this.sudahRetur,
  });
  final String barangId;
  final String nama;
  final int qty;
  final int hargaSatuan;
  final bool isGrosir;
  final int subtotal;
  final int sudahRetur;
}

/// Detail transaksi untuk layar riwayat: data struk (cetak ulang) + barang per baris.
class DetailTransaksi {
  const DetailTransaksi({required this.id, required this.struk, required this.item, required this.adaRetur, required this.kasirId});
  final String id;
  final DataStruk struk;
  final List<ItemDetailTransaksi> item;
  final bool adaRetur;
  final String kasirId;

  /// Transaksi ini hasil tukar barang (tidak bisa dibatalkan, revisi F).
  bool get dariTukar => struk.tukar != null;

  /// Masih ada barang yang bisa ditukar/dikembalikan.
  bool get bisaRetur => !dibatalkan && item.any((i) => i.sudahRetur < i.qty);

  bool get dibatalkan => struk.dibatalkan;
  int get jumlahBarang => item.fold(0, (n, i) => n + i.qty);
  String get status => dibatalkan ? 'Dibatalkan' : (adaRetur ? 'Retur' : 'Lunas');
}

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

// ------------------------------------------------------------------ tukar / kembalikan barang (revisi F)

/// Satu barang di struk yang bisa diretur.
class ItemRetur {
  const ItemRetur({
    required this.itemId,
    required this.barangId,
    required this.nama,
    required this.qty,
    required this.harga,
    required this.sudahRetur,
  });
  final String itemId;
  final String barangId;
  final String nama;
  final int qty;
  final int harga;
  final int sudahRetur;
  int get sisa => sisaBolehRetur(dibeli: qty, sudahDiretur: sudahRetur);
}

/// Struk yang di-scan di layar tukar / kembalikan barang.
class StrukUntukRetur {
  const StrukUntukRetur({required this.id, required this.noTransaksi, required this.waktu, required this.dibatalkan, required this.item});
  final String id;
  final String noTransaksi;
  final DateTime waktu;
  final bool dibatalkan;
  final List<ItemRetur> item;
  bool get habis => item.every((i) => i.sisa == 0);
}

/// Barang yang dikembalikan pembeli untuk ditukar. Dibawa ke layar Transaksi; disimpan bersama transaksi baru.
/// Sudah dicek (jumlah, alasan, batas hari / PIN SPV) saat dibuat lewat `PenjualanRepo.siapkanTukar`.
class DraftTukar {
  const DraftTukar({
    required this.transaksiId,
    required this.noTransaksiAsal,
    required this.qtyPerItem,
    required this.rusak,
    required this.alasan,
    required this.olehId,
    required this.disetujuiOlehId,
    required this.item,
  });
  final String transaksiId;
  final String noTransaksiAsal;
  final Map<String, int> qtyPerItem;

  /// Id item yang rusak (tidak masuk stok jual).
  final Set<String> rusak;
  final String alasan;
  final String olehId;
  final String? disetujuiOlehId;

  /// Untuk ditampilkan & dicetak.
  final List<ItemStrukRetur> item;

  int get nilai => item.fold(0, (s, i) => s + i.subtotal);
  int get jumlahBarang => item.fold(0, (s, i) => s + i.qty);

  Map<String, Object?> keJson() => {
        'transaksi_id': transaksiId,
        'qty': qtyPerItem,
        'rusak': rusak.toList(),
        'alasan': alasan,
        'oleh_id': olehId,
        'disetujui_oleh': disetujuiOlehId,
      };
}

/// Hasil retur uang tunai.
class HasilRetur {
  const HasilRetur({required this.returId, required this.noRetur, required this.total, required this.struk});
  final String returId;
  final String noRetur;
  final int total;
  final DataStrukRetur struk;
}

/// Satu baris riwayat retur (SPV/Admin).
class BarisRetur {
  const BarisRetur({
    required this.id,
    required this.noRetur,
    required this.noTransaksiAsal,
    required this.waktu,
    required this.oleh,
    required this.olehKasir,
    required this.penyetuju,
    required this.total,
    required this.dipotong,
    required this.noTransaksiTukar,
    required this.jumlahBarang,
    required this.jumlahRusak,
    required this.alasan,
  });
  final String id;
  final String noRetur;
  final String noTransaksiAsal;
  final DateTime waktu;
  final String oleh;
  final bool olehKasir;
  final String? penyetuju;
  final int total;
  final int dipotong;
  final String? noTransaksiTukar;
  final int jumlahBarang;
  final int jumlahRusak;
  final String alasan;

  bool get tukar => noTransaksiTukar != null;
  int get tunai => total - dipotong;
}
