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
      return izin == Izin.kelolaKaryawan ? Akses.tidak : Akses.ya;
    case Peran.kasir:
      switch (izin) {
        case Izin.jual:
        case Izin.catatBarangMasuk:
        case Izin.ubahHargaNaik:
        case Izin.mintaKoreksiBarangMasuk:
          return Akses.ya;
        case Izin.batalTransaksi:
        case Izin.ubahHargaTurunBesar:
          return Akses.pinSpv;
        case Izin.terimaRetur:
        case Izin.setujuiKoreksiBarangMasuk:
        case Izin.stokOpname:
        case Izin.lihatLaporan:
        case Izin.aturPrinter:
        case Izin.kelolaKaryawan:
          return Akses.tidak;
      }
  }
}

/// Siapa yang PIN-nya boleh dipakai untuk menyetujui: SPV atau Admin.
bool bolehMenyetujui(Peran peran) => peran == Peran.spv || peran == Peran.admin;
