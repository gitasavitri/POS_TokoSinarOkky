/// Peran dan hak akses (AGENTS.md bagian 4).
library;

enum Peran {
  kasir('kasir', 'Kasir'),
  spv('spv', 'SPV'),
  admin('admin', 'Admin');

  const Peran(this.kode, this.label);

  final String kode;
  final String label;

  static Peran dariKode(String kode) =>
      values.firstWhere((p) => p.kode == kode, orElse: () => throw ArgumentError.value(kode, 'kode'));
}

enum Izin {
  jual,
  batalTransaksi,
  terimaRetur,
  catatBarangMasuk,
  ubahHargaNaik,

  /// Turun lebih dari batas % atau di bawah HPP.
  ubahHargaTurunBesar,
  mintaKoreksiBarangMasuk,
  setujuiKoreksiBarangMasuk,
  stokOpname,
  lihatLaporan,
  aturPrinter,
  kelolaKaryawan,

  /// Cek stok & harga barang toko ini (revisi C). Hanya melihat; stok opname tetap [stokOpname].
  lihatStok,

  /// Melihat harga beli / HPP. Disembunyikan dari kasir (revisi C, D).
  lihatHpp,

  /// Mengisi hasil hitungan amplop shift yang ditutup "Belum dihitung" (revisi P).
  hitungShiftMenunggu,

  /// Mengatur modal tetap toko (uang yang tetap di kasir saat shift ditutup "Belum dihitung", revisi P).
  aturModalTetap,

  /// Membuat order barang ke toko utama / supplier (revisi G).
  buatOrder,

  /// Impor stok awal dari Excel lewat Barang masuk (revisi J).
  imporStokAwal,

  /// Menyalakan mode latihan dari layar masuk (PIN SPV/Admin).
  nyalakanLatihan,
}

enum Akses {
  /// Boleh langsung.
  ya,

  /// Boleh setelah SPV/Admin memasukkan PIN di layar yang sama.
  pinSpv,

  /// Tidak boleh.
  tidak,
}

Akses aksesUntuk(Peran peran, Izin izin) {
  switch (peran) {
    case Peran.admin:
      return Akses.ya;
    case Peran.spv:
      return izin == Izin.kelolaKaryawan || izin == Izin.aturModalTetap ? Akses.tidak : Akses.ya;
    case Peran.kasir:
      switch (izin) {
        case Izin.jual:
        case Izin.catatBarangMasuk:
        case Izin.ubahHargaNaik:
        case Izin.mintaKoreksiBarangMasuk:
        case Izin.lihatStok:
        case Izin.buatOrder:
        // Revisi F: kasir boleh tukar/retur sendiri; batas 3 hari dicek lewat aksesRetur (retur.dart).
        case Izin.terimaRetur:
          return Akses.ya;
        case Izin.batalTransaksi:
        case Izin.ubahHargaTurunBesar:
          return Akses.pinSpv;
        case Izin.setujuiKoreksiBarangMasuk:
        case Izin.stokOpname:
        case Izin.lihatLaporan:
        case Izin.aturPrinter:
        case Izin.kelolaKaryawan:
        case Izin.lihatHpp:
        case Izin.hitungShiftMenunggu:
        case Izin.aturModalTetap:
        case Izin.imporStokAwal:
        case Izin.nyalakanLatihan:
          return Akses.tidak;
      }
  }
}

/// Siapa yang PIN-nya boleh dipakai untuk menyetujui: SPV atau Admin.
bool bolehMenyetujui(Peran peran) => peran == Peran.spv || peran == Peran.admin;
