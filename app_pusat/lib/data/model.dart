import 'package:pos_core/pos_core.dart';

// Model data dari Server Pusat. Uang = int rupiah, waktu = DateTime UTC.

DateTime? _waktu(Object? v) => v is String ? DateTime.tryParse(v) : null;
int _int(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
bool _bool(Object? v) => v == true || v == 1 || v == '1';

class AdminPusat {
  const AdminPusat({required this.id, required this.nama});
  final String id;
  final String nama;
}

class CabangPusat {
  const CabangPusat({required this.id, required this.kode, required this.nama, required this.alamat, required this.terakhirSinkron, required this.jumlahPerangkat});
  factory CabangPusat.dariJson(Map<String, Object?> j) => CabangPusat(
        id: j['id']! as String,
        kode: j['kode']! as String,
        nama: j['nama']! as String,
        alamat: (j['alamat'] as String?) ?? '',
        terakhirSinkron: _waktu(j['terakhir_sinkron']),
        jumlahPerangkat: _int(j['jumlah_perangkat']),
      );
  final String id;
  final String kode;
  final String nama;
  final String alamat;
  final DateTime? terakhirSinkron;
  final int jumlahPerangkat;

  String get label => '$kode · $nama';
}

class PerangkatPusat {
  const PerangkatPusat({required this.id, required this.nama, required this.aktif, required this.terdaftar, required this.terakhirSinkron, required this.cabang});
  factory PerangkatPusat.dariJson(Map<String, Object?> j) => PerangkatPusat(
        id: j['id']! as String,
        nama: j['nama']! as String,
        aktif: _bool(j['aktif']),
        terdaftar: _waktu(j['terdaftar_pada'])!,
        terakhirSinkron: _waktu(j['terakhir_sinkron']),
        cabang: '${j['kode_cabang']} · ${j['nama_cabang']}',
      );
  final String id;
  final String nama;
  final bool aktif;
  final DateTime terdaftar;
  final DateTime? terakhirSinkron;
  final String cabang;
}

class Kategori {
  const Kategori(this.id, this.nama);
  final String id;
  final String nama;
}

class HargaPusat {
  const HargaPusat({required this.eceran, required this.grosir, required this.berlakuMulai});
  final int eceran;
  final List<TingkatGrosir> grosir;
  final DateTime berlakuMulai;
}

class BarangPusat {
  const BarangPusat({
    required this.id,
    required this.barcode,
    required this.nama,
    required this.satuan,
    required this.aktif,
    required this.kategoriId,
    required this.kategori,
    required this.stokTotal,
    required this.jumlahToko,
    required this.harga,
    required this.hppTertinggi,
  });

  factory BarangPusat.dariJson(Map<String, Object?> j) {
    final h = j['harga'] as Map<String, Object?>?;
    return BarangPusat(
      id: j['id']! as String,
      barcode: j['barcode'] as String?,
      nama: j['nama']! as String,
      satuan: j['satuan']! as String,
      aktif: _bool(j['aktif']),
      kategoriId: j['kategori_id']! as String,
      kategori: (j['kategori'] as String?) ?? '-',
      stokTotal: _int(j['stok_total']),
      jumlahToko: _int(j['jumlah_toko']),
      harga: h == null
          ? null
          : HargaPusat(
              eceran: _int(h['eceran']),
              grosir: [for (final g in (h['grosir'] as List)) TingkatGrosir(minQty: _int((g as Map)['min_qty']), harga: _int(g['harga']))],
              berlakuMulai: _waktu(h['berlaku_mulai'])!,
            ),
      hppTertinggi: j['hpp_tertinggi'] == null ? null : _int(j['hpp_tertinggi']),
    );
  }

  final String id;
  final String? barcode;
  final String nama;
  final String satuan;
  final bool aktif;
  final String kategoriId;
  final String kategori;
  final int stokTotal;
  final int jumlahToko;

  /// Harga untuk semua toko (null = belum pernah diatur pusat; toko memakai harga dari barang masuk).
  final HargaPusat? harga;

  /// HPP terkini tertinggi di antara toko. Harga grosir tidak boleh ≤ ini.
  final int? hppTertinggi;
}

class RingkasanCabang {
  const RingkasanCabang({
    required this.cabangId,
    required this.label,
    required this.penjualanBersih,
    required this.jumlahTransaksi,
    required this.tunai,
    required this.nonTunai,
    required this.labaKotor,
    required this.jumlahBatal,
    required this.totalRetur,
  });

  factory RingkasanCabang.dariJson(Map<String, Object?> j) => RingkasanCabang(
        cabangId: j['cabang_id'] as String?,
        label: j['kode'] == null ? 'Semua toko' : '${j['kode']} · ${j['nama']}',
        penjualanBersih: _int(j['penjualan_bersih']),
        jumlahTransaksi: _int(j['jumlah_transaksi']),
        tunai: _int(j['tunai']),
        nonTunai: _int(j['non_tunai']),
        labaKotor: _int(j['laba_kotor']),
        jumlahBatal: _int(j['jumlah_batal']),
        totalRetur: _int(j['total_retur']),
      );

  final String? cabangId;
  final String label;
  final int penjualanBersih;
  final int jumlahTransaksi;
  final int tunai;
  final int nonTunai;
  final int labaKotor;
  final int jumlahBatal;
  final int totalRetur;

  int get rataRataStruk => jumlahTransaksi == 0 ? 0 : bagiBulat(penjualanBersih + totalRetur, jumlahTransaksi);
}

class RingkasanPusat {
  const RingkasanPusat(this.perCabang, this.total);
  final List<RingkasanCabang> perCabang;
  final RingkasanCabang total;
}

class TransaksiPusat {
  const TransaksiPusat({
    required this.noTransaksi,
    required this.waktu,
    required this.total,
    required this.jumlahBarang,
    required this.metode,
    required this.kodeCabang,
    required this.kasir,
    required this.batal,
    required this.retur,
  });
  factory TransaksiPusat.dariJson(Map<String, Object?> j) => TransaksiPusat(
        noTransaksi: j['no_transaksi']! as String,
        waktu: _waktu(j['created_at'])!,
        total: _int(j['total']),
        jumlahBarang: _int(j['jumlah_barang']),
        metode: MetodeBayar.dariKode(j['metode']! as String),
        kodeCabang: j['kode_cabang']! as String,
        kasir: (j['kasir'] as String?) ?? '-',
        batal: _bool(j['batal']),
        retur: _bool(j['retur']),
      );
  final String noTransaksi;
  final DateTime waktu;
  final int total;
  final int jumlahBarang;
  final MetodeBayar metode;
  final String kodeCabang;
  final String kasir;
  final bool batal;
  final bool retur;

  String get status => batal ? 'Batal' : (retur ? 'Ada retur' : 'Lunas');
}

class Terlaris {
  const Terlaris(this.nama, this.qty, this.total);
  final String nama;
  final int qty;
  final int total;
}

class StokBarang {
  const StokBarang({required this.nama, required this.barcode, required this.satuan, required this.stok, required this.stokMinimum, required this.hpp, required this.aktif});
  factory StokBarang.dariJson(Map<String, Object?> j) => StokBarang(
        nama: j['nama']! as String,
        barcode: j['barcode'] as String?,
        satuan: j['satuan']! as String,
        stok: _int(j['stok']),
        stokMinimum: _int(j['stok_minimum']),
        hpp: j['hpp'] == null ? null : _int(j['hpp']),
        aktif: _bool(j['aktif']),
      );
  final String nama;
  final String? barcode;
  final String satuan;
  final int stok;
  final int stokMinimum;
  final int? hpp;
  final bool aktif;

  bool get menipis => stokMinimum > 0 && stok <= stokMinimum;
}

class KaryawanPusat {
  const KaryawanPusat({required this.nama, required this.namaPengguna, required this.peran, required this.kodeCabang, required this.terkunci, required this.aktif});
  factory KaryawanPusat.dariJson(Map<String, Object?> j) => KaryawanPusat(
        nama: j['nama']! as String,
        namaPengguna: j['nama_pengguna'] as String?,
        peran: Peran.values.byName(j['peran']! as String),
        kodeCabang: j['kode_cabang'] as String?,
        terkunci: _bool(j['terkunci']),
        aktif: _bool(j['aktif']),
      );
  final String nama;
  final String? namaPengguna;
  final Peran peran;

  /// null = Admin pusat.
  final String? kodeCabang;
  final bool terkunci;
  final bool aktif;
}

class LogPusat {
  const LogPusat({required this.waktu, required this.aksi, required this.detail, required this.kodeCabang, required this.oleh, required this.penyetuju});
  factory LogPusat.dariJson(Map<String, Object?> j) => LogPusat(
        waktu: _waktu(j['created_at'])!,
        aksi: j['aksi']! as String,
        detail: (j['detail'] as String?) ?? '{}',
        kodeCabang: j['kode_cabang'] as String?,
        oleh: j['oleh'] as String?,
        penyetuju: j['penyetuju'] as String?,
      );
  final DateTime waktu;
  final String aksi;
  final String detail;
  final String? kodeCabang;
  final String? oleh;
  final String? penyetuju;
}

class BarangKembar {
  const BarangKembar(this.barcode, this.id, this.nama, this.dibuat);
  final String barcode;
  final String id;
  final String nama;
  final DateTime dibuat;
}
