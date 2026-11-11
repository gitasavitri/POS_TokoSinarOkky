import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pos_core/pos_core.dart';

import '../../data/model.dart';
import '../../data/repo/penjualan_repo.dart';
import '../../layanan/aplikasi.dart';
import '../komponen/pin.dart';
import '../komponen/umum.dart';
import '../tema.dart';
import 'retur.dart';
import 'shift.dart';
import 'transaksi.dart';

/// Layar kasir: fokus penjualan. Pembayaran muncul di atas layar ini.
class HalamanKasir extends StatefulWidget {
  const HalamanKasir({super.key, this.onKembaliKeMenu, this.onBukaBarangMasuk, this.onBukaUbahHarga, this.onBukaPengaturan, this.isiAwal});

  /// Kembali ke menu ikon (Kasir, SPV, Admin). Shift tetap aktif.
  final VoidCallback? onKembaliKeMenu;
  final VoidCallback? onBukaBarangMasuk;
  final VoidCallback? onBukaUbahHarga;
  final VoidCallback? onBukaPengaturan;

  /// Dari menu: barang transaksi yang dibatalkan lewat "Ubah transaksi", atau barang tukaran (revisi F).
  final KeTransaksi? isiAwal;
  @override
  State<HalamanKasir> createState() => _HalamanKasirState();
}

class _HalamanKasirState extends State<HalamanKasir> {
  final _keranjang = Keranjang();
  final _ditahan = <Keranjang>[];
  final _scan = TextEditingController();
  final _qty = TextEditingController(text: '1');
  late final _fokusScan = FocusNode(onKeyEvent: _tombolScan);
  late final _fokusQty = FocusNode(onKeyEvent: _tombolQty);
  final _gulir = ScrollController();
  int? _barisDipilih;
  Timer? _jam;

  /// Transaksi yang baru selesai: kembaliannya tampil sampai barang berikutnya di-scan.
  ({HasilSimpanTransaksi hasil, bool mencetak, String? galatCetak})? _selesai;

  /// Barang yang sedang diinput (sudah dikenali dari barcode/cari, belum masuk daftar).
  BarangJual? _pilih;

  /// Tukar barang (revisi F): barang yang dikembalikan pembeli. Nilainya memotong total belanja di layar.
  DraftTukar? _tukar;

  /// Enter ditekan tapi barcode/nama tidak ditemukan.
  bool _tidakKetemu = false;

  /// Waktu Enter pertama di kolom Barcode yang kosong. Enter kedua (dalam [_jedaEnterBayar]) membuka layar Bayar.
  DateTime? _enterKosong;
  static const _jedaEnterBayar = Duration(milliseconds: 1500);
  DateTime _sekarang = DateTime.now();

  @override
  void initState() {
    super.initState();
    _jam = Timer.periodic(const Duration(seconds: 20), (_) => setState(() => _sekarang = DateTime.now()));
    WidgetsBinding.instance.addPostFrameCallback((_) => _pastikanShift());
  }

  @override
  void dispose() {
    _jam?.cancel();
    _scan.dispose();
    _qty.dispose();
    _fokusScan.dispose();
    _fokusQty.dispose();
    _gulir.dispose();
    super.dispose();
  }

  Aplikasi get app => context.app;

  Future<void> _pastikanShift() async {
    if (app.shiftAktif != null) {
      await _pulihkan();
      if (widget.isiAwal != null && mounted) _lanjut(widget.isiAwal!);
      return;
    }
    final s = await bukaShiftDialog(context);
    if (!mounted) return;
    if (s == null) {
      if (widget.onKembaliKeMenu != null) {
        widget.onKembaliKeMenu!();
      } else {
        app.keluar();
      }
      return;
    }
    app.aturShift(s);
    await _pulihkan();
    if (widget.isiAwal != null && mounted) _lanjut(widget.isiAwal!);
    _fokuskan();
  }

  void _lanjut(KeTransaksi k) {
    if (k.isiUlang != null) _isiUlang(k.isiUlang!);
    if (k.tukar != null) _mulaiTukar(k.tukar!);
  }

  /// Tukar barang (revisi F): barang yang dikembalikan memotong total belanja di layar.
  /// Belanjaan yang sudah di-scan tetap (biasanya barang penggantinya).
  void _mulaiTukar(DraftTukar d) {
    if (_tukar != null) {
      tampilkanPesan(context, 'Masih ada tukar barang yang belum dibayar. Selesaikan atau batalkan dulu.', galat: true);
      return;
    }
    setState(() {
      _tutupKartuSelesai();
      _tukar = d;
    });
    _simpanTukar();
    tampilkanPesan(context, 'Tukar barang: scan barang penggantinya. Nilai ${formatRupiah(d.nilai)} memotong total.');
    _fokuskan();
  }

  void _simpanTukar() {
    try {
      app.pemulihan.simpanTukar(_tukar);
    } catch (e, st) {
      app.catatan?.tulis(e, st, konteks: 'simpan tukar');
    }
  }

  Future<void> _batalTukar() async {
    final ok = await konfirmasi(
      context,
      judul: 'Batalkan tukar barang?',
      isi: 'Barang dari ${_tukar!.noTransaksiAsal} tidak jadi ditukar. Belum ada yang tersimpan. '
          'Barang yang sudah di-scan tetap di daftar belanja.',
      ya: 'Batalkan tukar',
      bahaya: true,
    );
    if (!ok || !mounted) return _fokuskan();
    setState(() => _tukar = null);
    _simpanTukar();
    _fokuskan();
  }

  /// Tukar / kembalikan barang dari layar Transaksi (tombol, atau scan barcode struk di kolom Barcode).
  Future<void> _bukaRetur([String? transaksiId]) async {
    if (_tukar != null) {
      tampilkanPesan(context, 'Selesaikan atau batalkan tukar barang yang sedang berjalan dulu.', galat: true);
      return _fokuskan();
    }
    final d = await bukaDialogRetur(context, transaksiId, bisaTukar: true);
    if (!mounted) return;
    if (d != null) return _mulaiTukar(d);
    setState(() {});
    _fokuskan();
  }

  /// "Ubah transaksi": barang transaksi yang baru dibatalkan dimasukkan ke daftar belanja (harga sekarang).
  /// Belanjaan yang sedang di layar ditahan dulu supaya tidak hilang.
  void _isiUlang(IsiUlang isi) {
    if (_tukar != null) {
      tampilkanPesan(context, 'Selesaikan atau batalkan tukar barang dulu.', galat: true);
      return;
    }
    var hilang = 0;
    setState(() {
      _tutupKartuSelesai();
      if (!_keranjang.kosong) {
        _ditahan.add(_keranjang.salin());
        _keranjang.kosongkan();
      }
      for (final i in isi) {
        final b = app.katalog.untukKasir(i.barangId, app.cabang.id);
        if (b == null) {
          hilang++;
          continue;
        }
        _keranjang.tambah(b, qty: i.qty);
      }
      _barisDipilih = _keranjang.kosong ? null : _keranjang.barisTerakhir;
    });
    _simpanKeranjang();
    if (hilang > 0) {
      tampilkanPesan(context, '$hilang barang sudah tidak dijual di toko ini dan tidak dimasukkan.', galat: true);
    }
    _fokuskan();
  }

  /// Simpan isi keranjang ke database setiap kali berubah, supaya tidak hilang kalau listrik padam.
  void _simpanKeranjang() {
    final p = app.penggunaAktif;
    if (p == null) return;
    try {
      app.pemulihan.simpanKeranjang(kasirId: p.id, aktif: _keranjang, ditahan: _ditahan);
    } catch (e, st) {
      app.catatan?.tulis(e, st, konteks: 'simpan keranjang');
    }
  }

  /// Setelah aplikasi dibuka lagi (mis. sesudah listrik padam): tawarkan cetak struk yang tertunda
  /// dan lanjutkan belanjaan yang belum dibayar.
  Future<void> _pulihkan() async {
    final idStruk = app.pemulihan.strukBelumCetak();
    if (idStruk != null) {
      final struk = app.penjualan.struk(idStruk, app.cabang);
      if (struk != null && mounted) {
        final cetak = await konfirmasi(
          context,
          judul: 'Struk mungkin belum tercetak',
          isi: 'Transaksi ${struk.noTransaksi} (${formatRupiah(struk.total)}) sudah tersimpan, tapi aplikasi tertutup '
              'sebelum struknya selesai dicetak. Cetak struknya sekarang?',
          ya: 'Cetak struk',
          batal: 'Tidak perlu',
        );
        if (cetak) {
          final g = await app.cetakStrukTransaksi(struk, ulang: true);
          if (mounted && g != null) tampilkanPesan(context, g, galat: true);
        }
      }
      app.pemulihan.selesaiCetak();
    }

    final tj = app.pemulihan.muatTukar();
    if (tj != null && _tukar == null) {
      final d = app.penjualan.draftTukarDariJson(tj, app.cabang.id);
      if (d == null) {
        app.pemulihan.hapusTukar();
      } else if (mounted) {
        setState(() => _tukar = d);
        tampilkanPesan(context, 'Tukar barang dari ${d.noTransaksiAsal} belum dibayar dan dilanjutkan.');
      }
    }

    if (!_keranjang.kosong || !mounted) return;
    final t = app.pemulihan.muatKeranjang(app.cabang.id);
    if (t == null) return;
    if (t.kosong) {
      app.pemulihan.hapusKeranjang();
      return;
    }
    final lanjut = await konfirmasi(
      context,
      judul: 'Ada belanjaan yang belum dibayar',
      isi: 'Aplikasi tertutup saat ${t.namaKasir} sedang melayani (${formatJam(t.waktu)}): '
          '${t.aktif.jumlahJenis} jenis barang, ${formatRupiah(t.aktif.total)}'
          '${t.ditahan.isEmpty ? '' : ', dan ${t.ditahan.length} transaksi ditahan'}. '
          'Belum ada yang dibayar.${t.hilang > 0 ? ' (${t.hilang} barang sudah tidak dijual dan tidak dimuat.)' : ''}',
      ya: 'Lanjutkan belanjaan',
      batal: 'Buang',
      bahaya: false,
    );
    if (!mounted) return;
    if (lanjut) {
      setState(() {
        for (final b in t.aktif.baris) {
          _keranjang.tambah(b.barang, qty: b.qty);
        }
        _ditahan.addAll(t.ditahan);
        _barisDipilih = _keranjang.kosong ? null : _keranjang.barisTerakhir;
      });
      _simpanKeranjang();
    } else {
      app.pemulihan.hapusKeranjang();
    }
    _fokuskan();
  }

  bool _ditekan(KeyEvent e, LogicalKeyboardKey k) => (e is KeyDownEvent || e is KeyRepeatEvent) && e.logicalKey == k;

  void _keJumlah() {
    _fokusQty.requestFocus();
    _qty.selection = TextSelection(baseOffset: 0, extentOffset: _qty.text.length);
  }

  void _keBarcode() {
    _fokusScan.requestFocus();
    _scan.selection = TextSelection(baseOffset: 0, extentOffset: _scan.text.length);
  }

  /// Esc saat kartu kembalian tampil: tutup kartunya (pembeli mau cek harga, dll.).
  /// Kalau kartu tidak tampil, Esc diteruskan (SPV/Admin: kembali ke menu).
  bool _escTutupKartu(KeyEvent e) {
    if (!_ditekan(e, LogicalKeyboardKey.escape) || _selesai == null) return false;
    setState(_tutupKartuSelesai);
    _fokuskan();
    return true;
  }

  /// ↓ di kolom Barcode pindah ke Jumlah.
  KeyEventResult _tombolScan(FocusNode _, KeyEvent e) {
    if (_escTutupKartu(e)) return KeyEventResult.handled;
    if (_ditekan(e, LogicalKeyboardKey.arrowDown)) {
      _keJumlah();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// ↑ di kolom Jumlah kembali ke Barcode.
  KeyEventResult _tombolQty(FocusNode _, KeyEvent e) {
    if (_escTutupKartu(e)) return KeyEventResult.handled;
    if (_ditekan(e, LogicalKeyboardKey.arrowUp)) {
      _keBarcode();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _fokuskan() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fokusScan.requestFocus();
      });

  /// Jumlah yang dipakai untuk pratinjau harga (1 kalau isian belum wajar).
  int get _jumlahPratinjau => switch (cekJumlah(_qty.text)) {
        CekJumlah.wajar || CekJumlah.perluKonfirmasi => int.parse(_qty.text.trim()),
        _ => 1,
      };

  /// Barcode diketik: nama barang langsung muncul kalau kodenya cocok.
  void _barcodeBerubah(String teks) {
    final isi = teks.trim();
    setState(() {
      _tidakKetemu = false;
      _enterKosong = null;
      _pilih = isi.isEmpty ? null : app.katalog.untukKasirBarcode(isi, app.cabang.id);
    });
  }

  /// Barang dipilih (scan / cari): tampil di kotak input, kursor pindah ke Jumlah.
  void _pilihBarang(BarangJual b, {bool isiKolom = false}) {
    setState(() {
      _tutupKartuSelesai();
      _pilih = b;
      _tidakKetemu = false;
      if (isiKolom) _scan.text = b.barcode ?? b.nama;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _keJumlah();
    });
  }

  /// Enter di kolom Barcode.
  Future<void> _prosesScan() async {
    final isi = _scan.text.trim();
    if (isi.isEmpty) return _enterDiKolomKosong();
    _enterKosong = null;
    final b = app.katalog.untukKasirBarcode(isi, app.cabang.id);
    if (b != null) return _pilihBarang(b);
    // Barcode struk (bukan barang): buka tukar / kembalikan barang untuk struk itu.
    final trx = app.penjualan.idDariNomor(app.cabang.id, isi);
    if (trx != null) {
      _scan.clear();
      setState(() => _pilih = null);
      return _bukaRetur(trx);
    }
    final hasil = app.katalog.cari(isi, app.cabang.id, batas: 30).where((d) => d.untukDijual != null).toList();
    if (hasil.length == 1) return _pilihBarang(hasil.single.untukDijual!, isiKolom: true);
    if (hasil.isEmpty) {
      setState(() {
        _pilih = null;
        _tidakKetemu = true;
      });
      _keBarcode();
      return;
    }
    await _cari(awal: isi);
  }

  /// Enter di kolom Barcode yang kosong. Enter 2× berturut-turut = buka layar Bayar
  /// (hanya kalau daftar belanja tidak kosong). Scanner selalu mengirim barcode sebelum Enter,
  /// jadi scan tidak pernah memicu ini.
  void _enterDiKolomKosong() {
    final sekarang = DateTime.now();
    final pertama = _enterKosong;
    if (_keranjang.kosong) {
      setState(() => _enterKosong = null);
      return _fokuskan();
    }
    if (pertama != null && sekarang.difference(pertama) <= _jedaEnterBayar) {
      setState(() => _enterKosong = null);
      _bayar();
      return;
    }
    setState(() => _enterKosong = sekarang);
    _fokuskan();
    // Petunjuk "Enter sekali lagi" hilang sendiri kalau Enter kedua tidak datang.
    Timer(_jedaEnterBayar, () {
      if (mounted && _enterKosong == sekarang) setState(() => _enterKosong = null);
    });
  }

  Future<void> _cari({String awal = ''}) async {
    final b = await cariBarangDialog(context, awal: awal);
    if (b != null) {
      _pilihBarang(b, isiKolom: true);
    } else {
      _fokuskan();
    }
  }

  /// Enter di kolom Jumlah / tombol Tambah: masukkan barang yang tampil di kotak input ke daftar belanja.
  Future<void> _masukkan() async {
    final b = _pilih;
    if (b == null) {
      if (_scan.text.trim().isNotEmpty) return _prosesScan();
      return _fokuskan();
    }
    switch (cekJumlah(_qty.text)) {
      case CekJumlah.kosong:
        tampilkanPesan(context, 'Isi jumlah dulu (minimal 1).', galat: true);
        return _keJumlah();
      case CekJumlah.miripBarcode:
        // Kasir lupa Enter, lalu barcode barang berikutnya ter-scan ke kolom Jumlah.
        _qty.text = '1';
        tampilkanPesan(context, 'Angka di kolom Jumlah terlalu panjang, sepertinya barcode ter-scan ke kolom Jumlah. '
            '${b.nama} belum ditambahkan: cek jumlahnya lalu tekan Enter.', galat: true);
        setState(() {});
        return _keJumlah();
      case CekJumlah.perluKonfirmasi:
        final n = int.parse(_qty.text.trim());
        final ok = await konfirmasi(context,
            judul: 'Jumlahnya benar?', isi: '${formatAngka(n)} ${b.satuan} ${b.nama}. Jumlah sebesar ini jarang terjadi.', ya: 'Ya, benar', batal: 'Ubah jumlah');
        if (!mounted) return;
        if (!ok) return _keJumlah();
      case CekJumlah.wajar:
        break;
    }
    _tambahBarang(b, int.parse(_qty.text.trim()));
  }

  void _tambahBarang(BarangJual b, int qty) {
    setState(() {
      _tutupKartuSelesai();
      _keranjang.tambah(b, qty: qty);
      _barisDipilih = _keranjang.barisTerakhir;
      _pilih = null;
      _tidakKetemu = false;
      _enterKosong = null;
      _qty.text = '1';
      _scan.clear();
    });
    _simpanKeranjang();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_gulir.hasClients) {
        final tujuan = (_keranjang.barisTerakhir * 64.0).clamp(0.0, _gulir.position.maxScrollExtent);
        _gulir.animateTo(tujuan, duration: const Duration(milliseconds: 150), curve: Curves.easeOut);
      }
    });
    _fokuskan();
  }

  Future<void> _batalkanKeranjang() async {
    if (_keranjang.kosong) return;
    final ok = await konfirmasi(context,
        judul: 'Kosongkan belanja?', isi: 'Semua barang di layar akan dihapus. Belum ada yang tersimpan.', ya: 'Kosongkan', bahaya: true);
    if (ok) {
      setState(_keranjang.kosongkan);
      _simpanKeranjang();
    }
    _fokuskan();
  }

  void _tahan() {
    if (_keranjang.kosong) return;
    if (_tukar != null) {
      tampilkanPesan(context, 'Tukar barang tidak bisa ditahan. Selesaikan atau batalkan tukar dulu.', galat: true);
      return;
    }
    setState(() {
      _ditahan.add(_keranjang.salin());
      _keranjang.kosongkan();
      _barisDipilih = null;
    });
    _simpanKeranjang();
    tampilkanPesan(context, 'Transaksi ditahan. Ambil lagi lewat tombol "Ditahan".');
    _fokuskan();
  }

  Future<void> _ambilDitahan() async {
    if (_ditahan.isEmpty) return;
    if (_tukar != null) {
      tampilkanPesan(context, 'Selesaikan atau batalkan tukar barang dulu.', galat: true);
      return;
    }
    final i = await showDialog<int>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('Transaksi ditahan', style: TextStyle(fontWeight: FontWeight.w800)),
        children: [
          for (var i = 0; i < _ditahan.length; i++)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, i),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              child: Text(
                '${i + 1}. ${_ditahan[i].jumlahJenis} jenis · ${_ditahan[i].jumlahBarang} barang · ${formatRupiah(_ditahan[i].total)}',
                style: const TextStyle(fontSize: 18),
              ),
            ),
        ],
      ),
    );
    if (i == null) return _fokuskan();
    setState(() {
      _tutupKartuSelesai();
      final ambil = _ditahan.removeAt(i);
      if (!_keranjang.kosong) _ditahan.add(_keranjang.salin());
      _keranjang.kosongkan();
      for (final b in ambil.baris) {
        _keranjang.tambah(b.barang, qty: b.qty);
      }
    });
    _simpanKeranjang();
    _fokuskan();
  }

  Future<void> _bayar() async {
    _enterKosong = null;
    if (_keranjang.kosong) return;
    final shift = app.shiftAktif;
    if (shift == null) return _pastikanShift();
    final hasil = await showDialog<HasilSimpanTransaksi>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DialogBayar(keranjang: _keranjang, shift: shift, tukar: _tukar),
    );
    if (hasil == null) return _fokuskan();
    _tukar = null; // retur sudah tersimpan bersama transaksi
    final otomatis = app.cetakOtomatis;
    // Kembalian langsung tampil di tengah layar dan tetap ada sampai barang berikutnya di-scan.
    setState(() {
      _keranjang.kosongkan();
      _barisDipilih = null;
      _selesai = (hasil: hasil, mencetak: otomatis, galatCetak: null);
    });
    _fokuskan();
    if (!otomatis) return; // tanda "struk belum cetak" dihapus saat kartu ditutup
    final g = await app.cetakStrukTransaksi(hasil.struk);
    if (g == null) app.pemulihan.selesaiCetak();
    if (!mounted) return;
    if (_selesai?.hasil == hasil) {
      setState(() => _selesai = (hasil: hasil, mencetak: false, galatCetak: g));
    } else if (g != null) {
      tampilkanPesan(context, 'Struk ${hasil.noTransaksi} belum tercetak: $g', galat: true);
    }
  }

  /// Cetak (ulang) struk transaksi yang kembaliannya sedang tampil.
  Future<void> _cetakUlangSelesai() async {
    final s = _selesai;
    if (s == null || s.mencetak) return;
    setState(() => _selesai = (hasil: s.hasil, mencetak: true, galatCetak: null));
    final g = await app.cetakStrukTransaksi(s.hasil.struk, ulang: true);
    if (g == null) app.pemulihan.selesaiCetak();
    if (!mounted) return;
    if (_selesai?.hasil == s.hasil) setState(() => _selesai = (hasil: s.hasil, mencetak: false, galatCetak: g));
    _fokuskan();
  }

  /// Kartu kembalian ditutup (barang berikutnya di-scan / keluar). Kasir sudah melihat hasilnya.
  void _tutupKartuSelesai() {
    if (_selesai == null) return;
    _selesai = null;
    app.pemulihan.selesaiCetak();
  }

  Future<void> _transaksiTerakhir() async {
    final isi = await showDialog<KeTransaksi>(context: context, builder: (_) => const DialogTransaksiTerakhir());
    if (!mounted) return;
    if (isi != null) return _lanjut(isi);
    _fokuskan();
  }

  Future<void> _tutupShift() async {
    if (!_keranjang.kosong || _ditahan.isNotEmpty || _tukar != null) {
      tampilkanPesan(context, 'Selesaikan atau kosongkan belanja dan transaksi ditahan dulu.', galat: true);
      return;
    }
    final selesai = await tutupShiftDialog(context);
    if (selesai == true && mounted) {
      // Kasir: shift selesai = keluar. SPV/Admin: kembali ke menu.
      if (widget.onKembaliKeMenu != null && app.penggunaAktif?.peran != Peran.kasir) {
        app.aturShift(null);
        widget.onKembaliKeMenu!();
      } else {
        app.keluar();
      }
    } else {
      _fokuskan();
    }
  }

  /// Kas keluar/masuk (bayar titipan, beli dari sales, tambah uang kecil, ...).
  Future<void> _kas() async {
    if (app.shiftAktif == null) return _pastikanShift();
    await kasDialog(context);
    _fokuskan();
  }

  Future<void> _bukaPengaturan() async {
    if (widget.onBukaPengaturan == null) return;
    if (app.akses(Izin.aturPrinter) != Akses.ya) {
      final p = await mintaPinSpv(context, alasan: 'Pengaturan printer hanya untuk SPV atau Admin.');
      if (p == null) return _fokuskan();
    }
    widget.onBukaPengaturan!();
  }

  void _hapusBaris(int i) {
    setState(() {
      _keranjang.hapus(i);
      _barisDipilih = _keranjang.kosong ? null : _keranjang.barisTerakhir;
    });
    _simpanKeranjang();
    _fokuskan();
  }

  // ------------------------------------------------------------ kotak input barang

  static const _gayaIsian = TextStyle(fontSize: 17, fontWeight: FontWeight.w600);

  InputDecoration _hiasIsian({String? petunjuk}) => InputDecoration(
        hintText: petunjuk,
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        enabledBorder: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(7)), borderSide: BorderSide(color: Warna.garis, width: 1.5)),
        focusedBorder: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(7)), borderSide: BorderSide(color: Warna.utama, width: 2.5)),
      );

  Widget _barisInput(String label, Widget isi) => Row(children: [
        SizedBox(width: 112, child: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Warna.teks2))),
        Expanded(child: isi),
      ]);

  /// Kotak isian yang hanya ditampilkan (nama, harga, subtotal).
  Widget _kotakBaca({required Widget isi, Color latar = Warna.abuMuda, Color garis = Warna.garisTipis, Key? key}) => Container(
        key: key,
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(color: latar, borderRadius: BorderRadius.circular(7), border: Border.all(color: garis, width: 1.5)),
        alignment: Alignment.centerLeft,
        child: isi,
      );

  Widget _kotakInput() {
    final b = _pilih;
    final teks = _scan.text.trim();
    final Widget nama;
    if (b != null) {
      nama = _kotakBaca(
        key: const ValueKey('nama-barang'),
        latar: Warna.suksesMuda,
        garis: const Color(0xFF8FD3AC),
        isi: Row(children: [
          Flexible(child: Text(b.nama, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
          const SizedBox(width: 8),
          const Icon(Icons.check, size: 20, color: Warna.suksesTua),
        ]),
      );
    } else if (_tidakKetemu) {
      nama = _kotakBaca(
        key: const ValueKey('nama-barang'),
        latar: Warna.merahMuda,
        garis: Warna.merahGaris,
        isi: const Text.rich(
          TextSpan(children: [
            TextSpan(text: 'Barang tidak ditemukan', style: TextStyle(fontWeight: FontWeight.w800)),
            TextSpan(text: ' · F2 untuk cari nama'),
          ]),
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 16, color: Warna.merah),
        ),
      );
    } else if (_enterKosong != null && teks.isEmpty) {
      nama = _kotakBaca(
        key: const ValueKey('nama-barang'),
        latar: Warna.suksesMuda,
        garis: const Color(0xFF8FD3AC),
        isi: const Row(children: [
          Icon(Icons.payments, size: 20, color: Warna.suksesTua),
          SizedBox(width: 8),
          Flexible(
            child: Text('Tekan Enter sekali lagi untuk BAYAR',
                overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Warna.suksesTua)),
          ),
        ]),
      );
    } else {
      nama = _kotakBaca(
        key: const ValueKey('nama-barang'),
        latar: Colors.white,
        garis: Warna.garis,
        isi: Text(
          teks.isEmpty ? 'Muncul otomatis setelah barcode diketik' : 'Tekan Enter untuk mencari "$teks"',
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15.5, color: Warna.teksPudar),
        ),
      );
    }

    final h = b == null ? null : hitungHargaBaris(b.harga, _jumlahPratinjau);
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), boxShadow: Warna.bayangan),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Warna.garis, width: 1.5)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Row(children: [
            Expanded(child: Text('INPUT BARANG', style: _gayaLabel)),
            Text('↓ ↑ pindah kolom · Enter lanjut', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Warna.teksPudar)),
          ]),
          _barisInput(
            'Barcode',
            TextField(
              key: const ValueKey('scan'),
              controller: _scan,
              focusNode: _fokusScan,
              autofocus: true,
              style: const TextStyle(fontFamily: fontMono, fontSize: 17, fontWeight: FontWeight.w700),
              decoration: _hiasIsian(petunjuk: 'Scan atau ketik barcode / nama barang'),
              onChanged: _barcodeBerubah,
              // Fokus tetap di kolom ini setelah Enter (diatur sendiri oleh _prosesScan).
              onEditingComplete: () {},
              onSubmitted: (_) => _prosesScan(),
            ),
          ),
          _barisInput('Nama barang', nama),
          _barisInput(
            'Jumlah',
            Row(children: [
              SizedBox(
                width: 110,
                child: TextField(
                  key: const ValueKey('jumlah'),
                  controller: _qty,
                  focusNode: _fokusQty,
                  textAlign: TextAlign.right,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(14)],
                  style: _gayaIsian.copyWith(fontWeight: FontWeight.w800),
                  decoration: _hiasIsian(),
                  onChanged: (_) => setState(() {}),
                  onEditingComplete: () {},
                  onSubmitted: (_) => _masukkan(),
                ),
              ),
              const SizedBox(width: 14),
              const Text('Harga', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Warna.teks2)),
              const SizedBox(width: 10),
              Expanded(
                child: _kotakBaca(
                  isi: Row(children: [
                    Expanded(child: Text(h == null ? '–' : formatRupiah(h.hargaSatuan), style: _gayaIsian.copyWith(fontWeight: FontWeight.w800))),
                    if (h != null && h.isGrosir) const Lencana('GROSIR', latar: Warna.oranyeMuda, warna: Warna.oranye),
                  ]),
                ),
              ),
            ]),
          ),
          _barisInput(
            'Subtotal',
            _kotakBaca(
              isi: Row(children: [
                Expanded(
                  child: Text(h == null ? '' : '${formatAngka(h.qty)} × ${formatRupiah(h.hargaSatuan)}',
                      overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14.5, color: Warna.teksPudar)),
                ),
                Text(h == null ? '–' : formatRupiah(h.subtotal),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Warna.utamaTua)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cabang = app.cabang;
    final p = app.penggunaAktif!;
    final noBerikut = app.penjualan.nomorBerikutnya(cabang);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f2): () => _cari(),
        const SingleActivator(LogicalKeyboardKey.f6): _kas,
        const SingleActivator(LogicalKeyboardKey.f8): _tahan,
        const SingleActivator(LogicalKeyboardKey.f9): _transaksiTerakhir,
        const SingleActivator(LogicalKeyboardKey.f10): () => _bukaRetur(),
        const SingleActivator(LogicalKeyboardKey.f12): _bayar,
        const SingleActivator(LogicalKeyboardKey.delete): () {
          if (_barisDipilih != null && _barisDipilih! < _keranjang.jumlahJenis) _hapusBaris(_barisDipilih!);
        },
      },
      child: Scaffold(
        backgroundColor: Warna.latar,
        body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // ------------------------------------------------ atas: info + total
          Container(
            decoration: const BoxDecoration(gradient: Warna.gradasiKepala, boxShadow: Warna.bayanganKuat),
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
            child: IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(
                  flex: 7,
                  child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    _KotakInfo('Toko · cabang', '${cabang.namaToko} · ${cabang.nama}', flex: 4),
                    _KotakInfo('Tanggal', formatLayar(_sekarang), flex: 4),
                    _KotakInfo('No. transaksi', noBerikut, flex: 5, satuBaris: true),
                    _KotakInfo('Kasir', '${p.nama} (${p.peran.label})', flex: 4),
                  ]),
                ),
                const SizedBox(width: 4),
                Expanded(
                  flex: 4,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: Warna.bayanganKuat,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Container(width: 8, color: Warna.sukses),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 22, 8),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: MainAxisAlignment.center, children: [
                            Text(_tukar == null ? 'TOTAL BELANJA' : 'TOTAL BAYAR (TUKAR)',
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: Warna.suksesTua)),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                  formatRupiah(_tukar == null
                                      ? _keranjang.total
                                      : hitungTukar(nilaiRetur: _tukar!.nilai, totalBelanja: _keranjang.total).bayar),
                                  key: const ValueKey('total-belanja'),
                                  // Saat tukar ada baris rincian di bawahnya: angka sedikit lebih kecil supaya tinggi kotak tetap.
                                  style: TextStyle(fontSize: _tukar == null ? 60 : 46, fontWeight: FontWeight.w800, height: 1.1, color: Warna.utamaTua)),
                            ),
                            if (_tukar != null)
                              Text('belanja ${formatRupiah(_keranjang.total)} − barang kembali ${formatRupiah(_tukar!.nilai)}',
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Warna.teks2)),
                          ]),
                        ),
                      ),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
          // ------------------------------------------------ tengah: daftar belanja / kartu kembalian
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
              child: _keranjang.kosong && _selesai != null
                  ? Container(
                      decoration: BoxDecoration(
                        color: Warna.latarTerang,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Warna.garis, width: 1.5),
                      ),
                      alignment: Alignment.center,
                      padding: const EdgeInsets.all(10),
                      // Kartu dikecilkan kalau tinggi layar tidak cukup, supaya tombol Tutup tidak terpotong.
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: KartuKembalian(
                          key: const ValueKey('kartu-kembalian'),
                          hasil: _selesai!.hasil,
                          mencetak: _selesai!.mencetak,
                          galatCetak: _selesai!.galatCetak,
                          onCetak: _cetakUlangSelesai,
                          onTutup: () {
                            setState(_tutupKartuSelesai);
                            _fokuskan();
                          },
                        ),
                      ),
                    )
                  : DecoratedBox(
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), boxShadow: Warna.bayangan),
                      child: Container(
                        decoration: BoxDecoration(
                            color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Warna.garis, width: 1.5)),
                        clipBehavior: Clip.antiAlias,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          if (_tukar != null) _BannerTukar(tukar: _tukar!, totalBelanja: _keranjang.total, onBatal: _batalTukar),
                          const _KepalaKeranjang(),
                          Expanded(
                            child: _keranjang.kosong
                                ? const Center(
                                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                                      Icon(Icons.qr_code_scanner, size: 56, color: Warna.utamaGarisMuda),
                                      SizedBox(height: 10),
                                      Text('Scan barcode barang untuk mulai',
                                          style: TextStyle(fontSize: 22, color: Warna.teksPudar, fontWeight: FontWeight.w600)),
                                      SizedBox(height: 6),
                                      Text('Tukar / kembalikan barang: scan barcode di struk, atau tekan F10',
                                          style: TextStyle(fontSize: 16, color: Warna.teksPudar)),
                                    ]),
                                  )
                                : ListView.builder(
                                    controller: _gulir,
                                    itemCount: _keranjang.jumlahJenis,
                                    itemExtent: 64,
                                    itemBuilder: (_, i) => _BarisKeranjang(
                                      no: i + 1,
                                      baris: _keranjang.baris[i],
                                      terakhir: i == _keranjang.barisTerakhir,
                                      dipilih: i == _barisDipilih,
                                      selang: i.isOdd,
                                      onPilih: () => setState(() => _barisDipilih = i),
                                      onQty: (q) {
                                        setState(() => _keranjang.ubahQty(i, q));
                                        _simpanKeranjang();
                                        _fokuskan();
                                      },
                                      onHapus: () => _hapusBaris(i),
                                    ),
                                  ),
                          ),
                          Container(
                            decoration: const BoxDecoration(
                                color: Warna.utamaMuda, border: Border(top: BorderSide(color: Warna.utamaGarisMuda, width: 1.5))),
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                            child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                              Text.rich(TextSpan(style: const TextStyle(fontSize: 18, color: Warna.teks2), children: [
                                const TextSpan(text: 'Jenis barang: '),
                                TextSpan(text: '${_keranjang.jumlahJenis}', style: const TextStyle(fontWeight: FontWeight.w800, color: Warna.utamaTua)),
                                const TextSpan(text: '      Jumlah barang: '),
                                TextSpan(text: '${_keranjang.jumlahBarang}', style: const TextStyle(fontWeight: FontWeight.w800, color: Warna.utamaTua)),
                              ])),
                            ]),
                          ),
                        ]),
                      ),
                    ),
            ),
          ),
          // ------------------------------------------------ bawah: input barang + tombol
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: SizedBox(
              height: 214,
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(flex: 9, child: _kotakInput()),
                const SizedBox(width: 14),
                Expanded(
                  flex: 11,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Expanded(
                      flex: 4,
                      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Expanded(
                          child: _TombolWarna(
                            label: 'Tambah (Enter)',
                            ikon: Icons.add,
                            latar: Warna.utamaMuda,
                            garis: Warna.utama,
                            warna: Warna.utamaGelap,
                            onTap: _masukkan,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _TombolWarna(
                            label: 'Kosongkan',
                            latar: Warna.merahMuda,
                            garis: Warna.merahGaris,
                            warna: Warna.merah,
                            onTap: _keranjang.kosong ? null : _batalkanKeranjang,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _TombolWarna(
                            label: 'Tahan (F8)',
                            ikon: Icons.pause,
                            latar: Warna.ambarTombol,
                            garis: Warna.oranyeGaris,
                            warna: Warna.oranyeTua,
                            onTap: _keranjang.kosong ? null : _tahan,
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      flex: 5,
                      child: FilledButton.icon(
                        onPressed: _keranjang.kosong ? null : _bayar,
                        style: FilledButton.styleFrom(
                          backgroundColor: Warna.sukses,
                          disabledBackgroundColor: Warna.abuMuda,
                          disabledForegroundColor: Warna.teksPudar,
                          elevation: _keranjang.kosong ? 0 : 3,
                          shadowColor: Warna.suksesTua,
                        ),
                        icon: const Icon(Icons.payments, size: 32),
                        label: const Text('BAYAR (F12)', style: TextStyle(fontSize: 26)),
                      ),
                    ),
                  ]),
                ),
              ]),
            ),
          ),
          // ------------------------------------------------ paling bawah: pintasan & menu
          Container(
            color: Warna.utamaTua,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(children: [
              const Expanded(
                child: Wrap(spacing: 14, runSpacing: 4, children: [
                  _Pintasan('F2', 'Cari'),
                  _Pintasan('↓ ↑', 'Pindah kolom'),
                  _Pintasan('Enter 2×', 'Bayar'),
                  _Pintasan('Del', 'Hapus baris'),
                ]),
              ),
              _TombolKecil('Ditahan (${_ditahan.length})', _ditahan.isEmpty ? null : _ambilDitahan),
              _TombolKecil('Terakhir (F9)', _transaksiTerakhir),
              _TombolKecil('Kas keluar/masuk (F6)', _kas),
              if (widget.onBukaUbahHarga != null) _TombolKecil('Ubah harga', widget.onBukaUbahHarga),
              if (widget.onBukaBarangMasuk != null) _TombolKecil('Barang masuk', widget.onBukaBarangMasuk),
              if (widget.onBukaPengaturan != null) _TombolKecil('Pengaturan', _bukaPengaturan),
              _TombolKecil('Tutup shift', _tutupShift),
              if (widget.onKembaliKeMenu != null)
                _TombolKecil('← Menu', () {
                  if (!_keranjang.kosong || _ditahan.isNotEmpty || _tukar != null) {
                    tampilkanPesan(context, 'Selesaikan atau kosongkan belanja dulu.', galat: true);
                    return;
                  }
                  _tutupKartuSelesai();
                  widget.onKembaliKeMenu!();
                }, putih: true)
              else
                _TombolKecil('Keluar', () {
                  if (!_keranjang.kosong || _ditahan.isNotEmpty || _tukar != null) {
                    tampilkanPesan(context, 'Selesaikan atau kosongkan belanja dulu.', galat: true);
                    return;
                  }
                  _tutupKartuSelesai();
                  app.keluar();
                }, putih: true),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _KotakInfo extends StatelessWidget {
  const _KotakInfo(this.label, this.nilai, {this.flex = 1, this.satuBaris = false});
  final String label;
  final String nilai;
  final int flex;

  /// Nilai yang tidak boleh terpotong (no. transaksi): dikecilkan supaya muat satu baris.
  final bool satuBaris;
  @override
  Widget build(BuildContext context) => Expanded(
        flex: flex,
        child: Container(
          margin: const EdgeInsets.only(right: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
              color: Warna.utamaPanel, borderRadius: BorderRadius.circular(8), border: Border.all(color: Warna.utamaGaris)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(label.toUpperCase(),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: Warna.utamaTeksTerang)),
            const SizedBox(height: 4),
            if (satuBaris)
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(nilai, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: Colors.white)),
              )
            else
              Text(nilai,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: Colors.white)),
          ]),
        ),
      );
}

const _flex = [1, 7, 3, 3, 3, 1];

class _KepalaKeranjang extends StatelessWidget {
  const _KepalaKeranjang();
  @override
  Widget build(BuildContext context) {
    const gaya = TextStyle(fontSize: 14, letterSpacing: 0.6, fontWeight: FontWeight.w800, color: Warna.utamaTua);
    return Container(
      decoration: const BoxDecoration(color: Warna.utamaMuda, border: Border(bottom: BorderSide(color: Warna.utamaGarisMuda, width: 1.5))),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: const Row(children: [
        Expanded(flex: 1, child: Text('NO', style: gaya)),
        Expanded(flex: 7, child: Text('NAMA BARANG', style: gaya)),
        Expanded(flex: 3, child: Text('HARGA', textAlign: TextAlign.right, style: gaya)),
        Expanded(flex: 3, child: Text('JUMLAH', textAlign: TextAlign.center, style: gaya)),
        Expanded(flex: 3, child: Text('SUBTOTAL', textAlign: TextAlign.right, style: gaya)),
        Expanded(flex: 1, child: SizedBox()),
      ]),
    );
  }
}

class _BarisKeranjang extends StatelessWidget {
  const _BarisKeranjang({
    required this.no,
    required this.baris,
    required this.terakhir,
    required this.dipilih,
    required this.selang,
    required this.onPilih,
    required this.onQty,
    required this.onHapus,
  });

  final int no;
  final BarisKeranjang baris;
  final bool terakhir;
  final bool dipilih;
  final bool selang;
  final VoidCallback onPilih;
  final ValueChanged<int> onQty;
  final VoidCallback onHapus;

  @override
  Widget build(BuildContext context) {
    final h = baris.harga;
    return Material(
      color: terakhir ? Warna.utamaSorot : (selang ? Warna.baris2 : Colors.white),
      child: InkWell(
        onTap: onPilih,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              top: const BorderSide(color: Warna.garisTipis),
              left: BorderSide(color: dipilih ? Warna.utama : Colors.transparent, width: 5),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(children: [
            Expanded(flex: _flex[0], child: Text('$no', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Warna.teks2))),
            Expanded(
              flex: _flex[1],
              child: Row(children: [
                Flexible(
                  child: Text(baris.barang.nama,
                      overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
                ),
                if (h.isGrosir) ...[const SizedBox(width: 10), const Lencana('GROSIR', latar: Warna.oranyeMuda, warna: Warna.oranye)],
              ]),
            ),
            Expanded(flex: _flex[2], child: Text(formatRupiah(h.hargaSatuan), textAlign: TextAlign.right, style: const TextStyle(fontSize: 19))),
            Expanded(flex: _flex[3], child: Center(child: PengaturJumlah(nilai: baris.qty, onUbah: onQty))),
            Expanded(
              flex: _flex[4],
              child: Text(formatRupiah(h.subtotal), textAlign: TextAlign.right, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            ),
            Expanded(
              flex: _flex[5],
              child: Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  onPressed: onHapus,
                  tooltip: 'Hapus barang',
                  style: IconButton.styleFrom(
                    foregroundColor: Warna.merah,
                    side: const BorderSide(color: Color(0xFFE8C4BE), width: 2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.delete_outline),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

const _gayaLabel = TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, letterSpacing: 0.4, color: Warna.utamaTua);

class _Pintasan extends StatelessWidget {
  const _Pintasan(this.tombol, this.arti);
  final String tombol;
  final String arti;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(5)),
          child: Text(tombol, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Warna.utamaTua)),
        ),
        const SizedBox(width: 6),
        Text(arti, style: const TextStyle(fontSize: 14.5, color: Warna.utamaTeksTerang)),
      ]);
}

/// Tombol di bilah paling bawah (latar biru tua). [putih] untuk Keluar / ← Menu.
class _TombolKecil extends StatelessWidget {
  const _TombolKecil(this.label, this.onTap, {this.putih = false});
  final String label;
  final VoidCallback? onTap;
  final bool putih;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 8),
        child: putih
            ? FilledButton(
                onPressed: onTap,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Warna.utamaTua,
                  minimumSize: const Size(44, 42),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  textStyle: const TextStyle(fontFamily: fontUtama, fontSize: 15, fontWeight: FontWeight.w800),
                ),
                child: Text(label),
              )
            : OutlinedButton(
                onPressed: onTap,
                style: OutlinedButton.styleFrom(
                  backgroundColor: Warna.utamaPanel,
                  foregroundColor: Colors.white,
                  disabledForegroundColor: Warna.utamaGarisMuda,
                  minimumSize: const Size(44, 42),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  side: const BorderSide(color: Warna.utamaGaris, width: 1.5),
                  textStyle: const TextStyle(fontFamily: fontUtama, fontSize: 15, fontWeight: FontWeight.w700),
                ),
                child: Text(label),
              ),
      );
}

/// Tombol besar berwarna di bilah scan (Tambah / Kosongkan / Tahan).
class _TombolWarna extends StatelessWidget {
  const _TombolWarna({required this.label, this.ikon, required this.latar, required this.garis, required this.warna, required this.onTap});
  final String label;
  final IconData? ikon;
  final Color latar;
  final Color garis;
  final Color warna;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final aktif = onTap != null;
    final gaya = OutlinedButton.styleFrom(
      backgroundColor: aktif ? latar : Warna.abuMuda,
      foregroundColor: warna,
      disabledForegroundColor: Warna.teksPudar,
      side: BorderSide(color: aktif ? garis : Warna.garis, width: 2.5),
      padding: const EdgeInsets.symmetric(horizontal: 18),
    );
    return SizedBox(
      height: double.infinity,
      child: ikon == null
          ? OutlinedButton(onPressed: onTap, style: gaya, child: Text(label))
          : OutlinedButton.icon(onPressed: onTap, style: gaya, icon: Icon(ikon, size: 24), label: Text(label)),
    );
  }
}

// ============================================================================ dialog pembayaran

class DialogBayar extends StatefulWidget {
  const DialogBayar({super.key, required this.keranjang, required this.shift, this.tukar});
  final Keranjang keranjang;
  final Shift shift;

  /// Tukar barang (revisi F): nilai barang kembali memotong total, pembeli membayar selisihnya.
  final DraftTukar? tukar;
  @override
  State<DialogBayar> createState() => _DialogBayarState();
}

class _DialogBayarState extends State<DialogBayar> {
  MetodeBayar _metode = MetodeBayar.tunai;
  final _uang = TextEditingController();
  final _ref = TextEditingController();
  final _fokusUang = FocusNode();
  int _diterima = 0;
  bool _sibuk = false;
  String? _galat;

  HitungTukar get _hitung => hitungTukar(nilaiRetur: widget.tukar?.nilai ?? 0, totalBelanja: widget.keranjang.total);

  /// Yang harus dibayar pembeli (setelah potongan tukar).
  int get _total => _hitung.bayar;

  /// Belanja lunas dengan barang tukaran: tidak ada uang yang dibayar.
  bool get _lunasTukar => widget.tukar != null && _total == 0;

  HasilPembayaran get _cek => cekPembayaran(
      metode: _lunasTukar ? MetodeBayar.tunai : _metode, total: _total, uangDiterima: _diterima, noReferensi: _ref.text);

  @override
  void dispose() {
    _uang.dispose();
    _ref.dispose();
    _fokusUang.dispose();
    super.dispose();
  }

  void _selesai() {
    if (!_cek.boleh || _sibuk) return;
    setState(() => _sibuk = true);
    final app = context.app;
    try {
      final h = app.penjualan.simpan(
        cabang: app.cabang,
        kasir: app.penggunaAktif!,
        shift: widget.shift,
        keranjang: widget.keranjang,
        metode: _lunasTukar ? MetodeBayar.tunai : _metode,
        uangDiterima: _lunasTukar ? 0 : _diterima,
        noReferensi: !_lunasTukar && _metode.perluReferensi ? _ref.text : null,
        tukar: widget.tukar,
      );
      Navigator.pop(context, h);
    } catch (e) {
      setState(() {
        _sibuk = false;
        _galat = 'Transaksi tidak tersimpan: ${pesanGalat(e)}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cek = _cek;
    final tunai = _metode == MetodeBayar.tunai || _lunasTukar;
    final sisaTukar = _hitung.sisaDikembalikan;
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.pop(context)},
      child: Dialog(
        insetPadding: const EdgeInsets.all(40),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 820,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              decoration: const BoxDecoration(gradient: Warna.gradasiKepala),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(children: [
                const Icon(Icons.payments, color: Colors.white, size: 30),
                const SizedBox(width: 12),
                Expanded(
                    child: Text(widget.tukar == null ? 'Pembayaran' : 'Pembayaran tukar barang',
                        style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800))),
                Text('${widget.keranjang.jumlahBarang} BARANG',
                    style: const TextStyle(color: Warna.utamaTeksTerang, fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (widget.tukar != null) ...[
                  KotakPesan(
                    'Belanja ${formatRupiah(widget.keranjang.total)} − barang kembali ${formatRupiah(widget.tukar!.nilai)} '
                    '(${widget.tukar!.jumlahBarang} barang dari ${widget.tukar!.noTransaksiAsal})'
                    '${sisaTukar > 0 ? '. Sisa ${formatRupiah(sisaTukar)} dikembalikan tunai ke pembeli.' : '.'}',
                    jenis: JenisPesan.info,
                  ),
                  const SizedBox(height: 14),
                ],
                IntrinsicHeight(
                  child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Expanded(child: _KotakBesar(
                          label: 'TOTAL BAYAR', nilai: formatRupiah(_total), latar: Colors.white, garis: Warna.utamaGarisMuda, aksen: Warna.utama, warna: Warna.utamaTua)),
                    const SizedBox(width: 14),
                    Expanded(
                      child: !tunai
                          ? const _KotakTeks('Pastikan pembayaran sudah berhasil di mesin EDC, QRIS, atau aplikasi bank sebelum menekan Selesai.')
                          : cek.boleh
                              ? _KotakBesar(
                                  label: sisaTukar > 0 ? 'KEMBALIKAN TUNAI' : 'KEMBALIAN',
                                  nilai: formatRupiah(cek.kembalian + sisaTukar),
                                  latar: Warna.oranyeMuda,
                                  garis: Warna.oranyeGaris,
                                  aksen: Warna.oranyeTegas,
                                  warna: Warna.oranyeTua)
                              : _KotakBesar(
                                  label: 'UANG KURANG', nilai: formatRupiah(cek.kurang), latar: Warna.merahMuda, garis: Warna.merahGaris, aksen: Warna.merah, warna: Warna.merahTua),
                    ),
                  ]),
                ),
                const SizedBox(height: 20),
                if (_lunasTukar)
                  const _KotakTeks('Belanja lunas dengan barang tukaran. Tidak ada uang yang dibayar pembeli.')
                else
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: DropdownButtonFormField<MetodeBayar>(
                      initialValue: _metode,
                      decoration: const InputDecoration(labelText: 'Cara bayar'),
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Warna.teks, fontFamily: fontUtama),
                      items: [for (final m in MetodeBayar.values) DropdownMenuItem(value: m, child: Text(m.label))],
                      onChanged: (m) => setState(() {
                        _metode = m!;
                        _galat = null;
                        if (_metode == MetodeBayar.tunai) _fokusUang.requestFocus();
                      }),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: tunai
                        ? InputRupiah(
                            controller: _uang,
                            focusNode: _fokusUang,
                            autofocus: true,
                            label: 'Uang diterima dari pembeli',
                            besar: true,
                            onChanged: (n) => setState(() => _diterima = n),
                            onSubmitted: (_) => _selesai(),
                          )
                        : _metode.perluReferensi
                            ? TextField(
                                controller: _ref,
                                autofocus: true,
                                style: const TextStyle(fontSize: 24),
                                decoration: const InputDecoration(labelText: 'Nomor referensi (struk EDC / bukti transfer)', hintText: 'contoh: 004521'),
                                onChanged: (_) => setState(() {}),
                                onSubmitted: (_) => _selesai(),
                              )
                            : const _KotakTeks('Minta pembeli scan QRIS toko. Tunggu tulisan Berhasil di layar pembeli.'),
                  ),
                ]),
                if (_galat != null) ...[const SizedBox(height: 14), KotakPesan(_galat!, jenis: JenisPesan.galat)],
                const SizedBox(height: 20),
                Row(children: [
                  Expanded(
                    child: SizedBox(height: 68, child: OutlinedButton(onPressed: _sibuk ? null : () => Navigator.pop(context), child: const Text('Kembali (Esc)'))),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: SizedBox(
                      height: 68,
                      child: FilledButton.icon(
                        key: const ValueKey('selesai-bayar'),
                        autofocus: _lunasTukar,
                        onPressed: cek.boleh && !_sibuk ? _selesai : null,
                        style: FilledButton.styleFrom(
                          backgroundColor: Warna.sukses,
                          disabledBackgroundColor: Warna.abuMuda,
                          elevation: cek.boleh ? 3 : 0,
                          shadowColor: Warna.suksesTua,
                        ),
                        icon: const Icon(Icons.print, size: 28),
                        label: Text(_sibuk ? 'Menyimpan…' : 'Selesai & cetak struk (Enter)', style: const TextStyle(fontSize: 21)),
                      ),
                    ),
                  ),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _KotakBesar extends StatelessWidget {
  const _KotakBesar({
    required this.label,
    required this.nilai,
    required this.latar,
    required this.garis,
    required this.aksen,
    required this.warna,
    this.besar = false,
    this.lencana,
  });
  final String label;
  final String nilai;
  final Color latar;
  final Color garis;

  /// Garis tebal di kiri kotak.
  final Color aksen;
  final Color warna;

  /// Ukuran kartu kembalian (angka lebih besar, rata tengah).
  final bool besar;
  final String? lencana;
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(color: latar, borderRadius: BorderRadius.circular(12), border: Border.all(color: garis, width: 2)),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(width: 8, color: aksen),
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: besar ? 8 : 12),
                child: Column(crossAxisAlignment: besar ? CrossAxisAlignment.center : CrossAxisAlignment.start, children: [
                  Row(mainAxisAlignment: besar ? MainAxisAlignment.center : MainAxisAlignment.start, children: [
                    Text(label, style: TextStyle(fontSize: besar ? 20 : 15, fontWeight: FontWeight.w800, letterSpacing: besar ? 2 : 0.6, color: warna)),
                    if (lencana != null) ...[
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(color: warna, borderRadius: BorderRadius.circular(20)),
                        child: Text(lencana!, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: latar)),
                      ),
                    ],
                  ]),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: besar ? Alignment.center : Alignment.centerLeft,
                    child: Text(nilai, style: TextStyle(fontSize: besar ? 72 : 48, fontWeight: FontWeight.w800, color: warna, height: 1.1)),
                  ),
                ]),
              ),
            ),
          ]),
        ),
      );
}

class _KotakTeks extends StatelessWidget {
  const _KotakTeks(this.teks);
  final String teks;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Warna.abuMuda, borderRadius: BorderRadius.circular(12), border: Border.all(color: Warna.garis, width: 2)),
        alignment: Alignment.centerLeft,
        child: Text(teks, style: const TextStyle(fontSize: 17.5, height: 1.45)),
      );
}

/// Setelah bayar: kartu kembalian besar di tengah layar kasir. Tetap tampil sampai barang berikutnya
/// di-scan, supaya kasir masih bisa melihat kembalian sambil mengambil struk. Kembalian 0 tetap ditampilkan.
class KartuKembalian extends StatelessWidget {
  const KartuKembalian({super.key, required this.hasil, this.mencetak = false, this.galatCetak, this.onCetak, this.onTutup});
  final HasilSimpanTransaksi hasil;
  final bool mencetak;
  final String? galatCetak;
  final VoidCallback? onCetak;

  /// Tombol Tutup (Esc). Kartu juga tertutup sendiri saat barang berikutnya di-scan.
  final VoidCallback? onTutup;

  @override
  Widget build(BuildContext context) {
    final s = hasil.struk;
    final tunai = s.metode == MetodeBayar.tunai;
    final otomatis = context.app.cetakOtomatis;
    final sisaTukar = s.tukar?.sisaDikembalikan ?? 0;
    final Widget statusCetak;
    if (mencetak) {
      statusCetak = const _Pil(ikon: Icons.print, teks: 'Struk sedang dicetak', latar: Warna.utamaMuda, warna: Warna.utamaTua);
    } else if (galatCetak != null) {
      statusCetak = Expanded(child: KotakPesan('Struk belum tercetak: $galatCetak', jenis: JenisPesan.galat));
    } else {
      statusCetak = otomatis
          ? const _Pil(ikon: Icons.check, teks: 'Struk sudah dicetak', latar: Warna.suksesMuda, warna: Warna.suksesTua)
          : const _Pil(ikon: Icons.info_outline, teks: 'Cetak otomatis mati', latar: Warna.abuMuda, warna: Warna.teks2);
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 820),
      child: DecoratedBox(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), boxShadow: Warna.bayanganKuat),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Warna.utamaGarisMuda, width: 1.5),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              decoration: const BoxDecoration(gradient: LinearGradient(colors: [Warna.suksesTua, Warna.sukses])),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              child: Row(children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 30),
                const SizedBox(width: 12),
                Expanded(
                    child: Text(s.tukar == null ? 'Transaksi selesai' : 'Tukar barang selesai',
                        style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800))),
                Text(hasil.noTransaksi, style: const TextStyle(fontFamily: fontMono, color: Color(0xFFDDF5E6), fontSize: 16, fontWeight: FontWeight.w700)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (tunai)
                  _KotakBesar(
                    label: sisaTukar > 0 ? 'KEMBALIKAN TUNAI' : 'KEMBALIAN',
                    nilai: formatRupiah(s.kembalian + sisaTukar),
                    latar: Warna.oranyeMuda,
                    garis: Warna.oranyeGaris,
                    aksen: Warna.oranyeTegas,
                    warna: Warna.oranyeTua,
                    besar: true,
                    lencana: s.kembalian + sisaTukar == 0 ? 'UANG PAS' : (sisaTukar > 0 ? 'TERMASUK SISA TUKAR' : null),
                  )
                else
                  _KotakBesar(
                    label: 'DIBAYAR ${s.metode.label.toUpperCase()}',
                    nilai: formatRupiah(s.totalBayar),
                    latar: Warna.utamaMuda,
                    garis: Warna.utamaGarisMuda,
                    aksen: Warna.utama,
                    warna: Warna.utamaTua,
                    besar: true,
                    lencana: 'TANPA KEMBALIAN',
                  ),
                const SizedBox(height: 16),
                Row(children: [
                  statusCetak,
                  const SizedBox(width: 12),
                  if (!mencetak && onCetak != null)
                    OutlinedButton.icon(
                      onPressed: onCetak,
                      icon: const Icon(Icons.print),
                      label: Text(galatCetak == null && otomatis ? 'Cetak lagi' : 'Cetak struk'),
                    ),
                  if (galatCetak == null) const Spacer() else const SizedBox(width: 12),
                  if (onTutup != null)
                    OutlinedButton.icon(
                      key: const ValueKey('tutup-kembalian'),
                      onPressed: onTutup,
                      icon: const Icon(Icons.close),
                      label: const Text('Tutup (Esc)'),
                    ),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Pita di atas daftar belanja selama tukar barang: barang yang dikembalikan dan nilainya.
class _BannerTukar extends StatelessWidget {
  const _BannerTukar({required this.tukar, required this.totalBelanja, required this.onBatal});
  final DraftTukar tukar;
  final int totalBelanja;
  final VoidCallback onBatal;

  @override
  Widget build(BuildContext context) {
    final h = hitungTukar(nilaiRetur: tukar.nilai, totalBelanja: totalBelanja);
    final barang = tukar.item.map((i) => '${i.nama} ×${i.qty}${i.rusak ? ' (rusak)' : ''}').join(', ');
    return Container(
      key: const ValueKey('banner-tukar'),
      color: Warna.oranyeMuda,
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      child: Row(children: [
        const Icon(Icons.swap_horiz, color: Warna.oranyeTua, size: 30),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('TUKAR BARANG · barang kembali dari ${tukar.noTransaksiAsal} · ${formatRupiah(tukar.nilai)}',
                style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800, color: Warna.oranyeTua)),
            Text(
              totalBelanja == 0
                  ? '$barang · scan barang penggantinya'
                  : h.sisaDikembalikan > 0
                      ? '$barang · sisa ${formatRupiah(h.sisaDikembalikan)} dikembalikan tunai'
                      : '$barang · pembeli bayar selisih ${formatRupiah(h.bayar)}',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, color: Warna.teks2, fontWeight: FontWeight.w600),
            ),
          ]),
        ),
        const SizedBox(width: 10),
        OutlinedButton(
          key: const ValueKey('batal-tukar'),
          onPressed: onBatal,
          style: OutlinedButton.styleFrom(foregroundColor: Warna.merah, side: const BorderSide(color: Warna.merahGaris, width: 2)),
          child: const Text('Batalkan tukar'),
        ),
      ]),
    );
  }
}

class _Pil extends StatelessWidget {
  const _Pil({required this.ikon, required this.teks, required this.latar, required this.warna});
  final IconData ikon;
  final String teks;
  final Color latar;
  final Color warna;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(color: latar, borderRadius: BorderRadius.circular(30)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(ikon, color: warna, size: 22),
          const SizedBox(width: 8),
          Text(teks, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: warna)),
        ]),
      );
}

// ============================================================================ cari barang

Future<BarangJual?> cariBarangDialog(BuildContext context, {String awal = ''}) =>
    showDialog<BarangJual>(context: context, builder: (_) => _DialogCari(awal: awal));

class _DialogCari extends StatefulWidget {
  const _DialogCari({required this.awal});
  final String awal;
  @override
  State<_DialogCari> createState() => _DialogCariState();
}

class _DialogCariState extends State<_DialogCari> {
  late final _kata = TextEditingController(text: widget.awal);
  List<DetailBarang> _hasil = [];

  @override
  void initState() {
    super.initState();
    _cari();
  }

  void _cari() {
    final app = context.app;
    setState(() => _hasil = app.katalog.cari(_kata.text, app.cabang.id, batas: 40).where((d) => d.untukDijual != null).toList());
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Cari barang', style: TextStyle(fontWeight: FontWeight.w800)),
        content: SizedBox(
          width: 720,
          height: 520,
          child: Column(children: [
            TextField(
              controller: _kata,
              autofocus: true,
              style: const TextStyle(fontSize: 21),
              decoration: const InputDecoration(hintText: 'Ketik nama atau barcode', prefixIcon: Icon(Icons.search)),
              onChanged: (_) => _cari(),
              onSubmitted: (_) {
                if (_hasil.isNotEmpty) Navigator.pop(context, _hasil.first.untukDijual);
              },
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _hasil.isEmpty
                  ? const Center(child: Text('Tidak ada barang yang cocok', style: TextStyle(fontSize: 18, color: Warna.teksPudar)))
                  : ListView.separated(
                      itemCount: _hasil.length,
                      separatorBuilder: (_, _) => const Divider(),
                      itemBuilder: (_, i) {
                        final d = _hasil[i];
                        return ListTile(
                          onTap: () => Navigator.pop(context, d.untukDijual),
                          title: Text(d.nama, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
                          subtitle: Text('${d.barcode ?? 'tanpa barcode'} · stok ${d.stok} ${d.satuan}', style: const TextStyle(fontSize: 15)),
                          trailing: Text(formatRupiah(d.harga!.eceran), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                        );
                      },
                    ),
            ),
          ]),
        ),
        actions: [OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Tutup'))],
      );
}
