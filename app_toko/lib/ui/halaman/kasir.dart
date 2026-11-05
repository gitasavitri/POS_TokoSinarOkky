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
import 'shift.dart';
import 'transaksi.dart';

/// Layar kasir: fokus penjualan. Pembayaran muncul di atas layar ini.
class HalamanKasir extends StatefulWidget {
  const HalamanKasir({super.key, this.onKembaliKeMenu, this.onBukaBarangMasuk, this.onBukaUbahHarga, this.onBukaPengaturan});

  /// Untuk SPV/Admin: kembali ke menu. null untuk kasir.
  final VoidCallback? onKembaliKeMenu;
  final VoidCallback? onBukaBarangMasuk;
  final VoidCallback? onBukaUbahHarga;
  final VoidCallback? onBukaPengaturan;

  @override
  State<HalamanKasir> createState() => _HalamanKasirState();
}

class _HalamanKasirState extends State<HalamanKasir> {
  final _keranjang = Keranjang();
  final _ditahan = <Keranjang>[];
  final _scan = TextEditingController();
  final _qty = TextEditingController(text: '1');
  final _fokusScan = FocusNode();
  final _gulir = ScrollController();
  int? _barisDipilih;
  Timer? _jam;

  /// Transaksi yang baru selesai: kembaliannya tampil sampai barang berikutnya di-scan.
  ({HasilSimpanTransaksi hasil, bool mencetak, String? galatCetak})? _selesai;
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
    _gulir.dispose();
    super.dispose();
  }

  Aplikasi get app => context.app;

  Future<void> _pastikanShift() async {
    if (app.shiftAktif != null) return _pulihkan();
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

  void _fokuskan() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fokusScan.requestFocus();
      });

  int get _jumlahInput {
    final n = bacaAngka(_qty.text);
    return n <= 0 ? 1 : n;
  }

  void _tambahBarang(BarangJual b) {
    setState(() {
      _tutupKartuSelesai();
      _keranjang.tambah(b, qty: _jumlahInput);
      _barisDipilih = _keranjang.barisTerakhir;
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

  Future<void> _prosesScan() async {
    final isi = _scan.text.trim();
    if (isi.isEmpty) return;
    final b = app.katalog.untukKasirBarcode(isi, app.cabang.id);
    if (b != null) {
      _tambahBarang(b);
      return;
    }
    final hasil = app.katalog.cari(isi, app.cabang.id, batas: 30).where((d) => d.untukDijual != null).toList();
    if (hasil.length == 1) {
      _tambahBarang(hasil.single.untukDijual!);
      return;
    }
    if (hasil.isEmpty) {
      tampilkanPesan(context, 'Barang "$isi" tidak ditemukan di toko ini.', galat: true);
      _scan.selection = TextSelection(baseOffset: 0, extentOffset: _scan.text.length);
      _fokuskan();
      return;
    }
    await _cari(awal: isi);
  }

  Future<void> _cari({String awal = ''}) async {
    final b = await cariBarangDialog(context, awal: awal);
    if (b != null) {
      _tambahBarang(b);
    } else {
      _fokuskan();
    }
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
    if (_keranjang.kosong) return;
    final shift = app.shiftAktif;
    if (shift == null) return _pastikanShift();
    final hasil = await showDialog<HasilSimpanTransaksi>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DialogBayar(keranjang: _keranjang, shift: shift),
    );
    if (hasil == null) return _fokuskan();
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
    await showDialog<void>(context: context, builder: (_) => const DialogTransaksiTerakhir());
    _fokuskan();
  }

  Future<void> _tutupShift() async {
    if (!_keranjang.kosong || _ditahan.isNotEmpty) {
      tampilkanPesan(context, 'Selesaikan atau kosongkan belanja dan transaksi ditahan dulu.', galat: true);
      return;
    }
    final selesai = await tutupShiftDialog(context);
    if (selesai == true && mounted) {
      if (widget.onKembaliKeMenu != null) {
        app.aturShift(null);
        widget.onKembaliKeMenu!();
      } else {
        app.keluar();
      }
    } else {
      _fokuskan();
    }
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

  @override
  Widget build(BuildContext context) {
    final cabang = app.cabang;
    final p = app.penggunaAktif!;
    final noBerikut = app.penjualan.nomorBerikutnya(cabang);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f2): () => _cari(),
        const SingleActivator(LogicalKeyboardKey.f8): _tahan,
        const SingleActivator(LogicalKeyboardKey.f9): _transaksiTerakhir,
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
                            const Text('TOTAL BELANJA',
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: Warna.suksesTua)),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(formatRupiah(_keranjang.total),
                                  style: const TextStyle(fontSize: 60, fontWeight: FontWeight.w800, height: 1.1, color: Warna.utamaTua)),
                            ),
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
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
              child: _keranjang.kosong && _selesai != null
                  ? Container(
                      decoration: BoxDecoration(
                        color: Warna.latarTerang,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Warna.garis, width: 1.5),
                      ),
                      alignment: Alignment.center,
                      padding: const EdgeInsets.all(16),
                      child: SingleChildScrollView(
                        child: KartuKembalian(
                          key: const ValueKey('kartu-kembalian'),
                          hasil: _selesai!.hasil,
                          mencetak: _selesai!.mencetak,
                          galatCetak: _selesai!.galatCetak,
                          onCetak: _cetakUlangSelesai,
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
                          const _KepalaKeranjang(),
                          Expanded(
                            child: _keranjang.kosong
                                ? const Center(
                                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                                      Icon(Icons.qr_code_scanner, size: 56, color: Warna.utamaGarisMuda),
                                      SizedBox(height: 10),
                                      Text('Scan barcode barang untuk mulai',
                                          style: TextStyle(fontSize: 22, color: Warna.teksPudar, fontWeight: FontWeight.w600)),
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
          // ------------------------------------------------ bawah: scan + tombol
          Container(
            decoration: const BoxDecoration(
              color: Warna.latarTerang,
              border: Border(top: BorderSide(color: Warna.garis, width: 1.5)),
              boxShadow: [BoxShadow(color: Color(0x1A0D47A1), blurRadius: 10, offset: Offset(0, -3))],
            ),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                flex: 5,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('SCAN BARCODE / KETIK NAMA BARANG', style: _gayaLabel),
                  const SizedBox(height: 6),
                  TextField(
                    key: const ValueKey('scan'),
                    controller: _scan,
                    focusNode: _fokusScan,
                    autofocus: true,
                    style: const TextStyle(fontSize: 24),
                    decoration: const InputDecoration(
                      hintText: 'Arahkan scanner ke barcode…',
                      filled: true,
                      fillColor: Colors.white,
                      prefixIcon: Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Icon(Icons.qr_code_scanner, size: 32, color: Warna.utama)),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(10)), borderSide: BorderSide(color: Warna.utama, width: 3)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(10)), borderSide: BorderSide(color: Warna.utamaTua, width: 3.5)),
                    ),
                    onSubmitted: (_) => _prosesScan(),
                  ),
                ]),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 120,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('JUMLAH', style: _gayaLabel),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _qty,
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(5)],
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
                    decoration: const InputDecoration(filled: true, fillColor: Colors.white),
                    onSubmitted: (_) => _fokuskan(),
                  ),
                ]),
              ),
              const SizedBox(width: 12),
              _TombolWarna(
                label: 'Tambah (Enter)',
                ikon: Icons.add,
                latar: Warna.utamaMuda,
                garis: Warna.utama,
                warna: Warna.utamaGelap,
                onTap: _prosesScan,
              ),
              const SizedBox(width: 12),
              _TombolWarna(
                label: 'Kosongkan',
                latar: Warna.merahMuda,
                garis: Warna.merahGaris,
                warna: Warna.merah,
                onTap: _keranjang.kosong ? null : _batalkanKeranjang,
              ),
              const SizedBox(width: 10),
              _TombolWarna(
                label: 'Tahan (F8)',
                ikon: Icons.pause,
                latar: Warna.ambarTombol,
                garis: Warna.oranyeGaris,
                warna: Warna.oranyeTua,
                onTap: _keranjang.kosong ? null : _tahan,
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 64,
                width: 250,
                child: FilledButton.icon(
                  onPressed: _keranjang.kosong ? null : _bayar,
                  style: FilledButton.styleFrom(
                    backgroundColor: Warna.sukses,
                    disabledBackgroundColor: Warna.abuMuda,
                    disabledForegroundColor: Warna.teksPudar,
                    elevation: _keranjang.kosong ? 0 : 3,
                    shadowColor: Warna.suksesTua,
                  ),
                  icon: const Icon(Icons.payments, size: 30),
                  label: const Text('BAYAR (F12)', style: TextStyle(fontSize: 24)),
                ),
              ),
            ]),
          ),
          // ------------------------------------------------ paling bawah: pintasan & menu
          Container(
            color: Warna.utamaTua,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(children: [
              const Expanded(
                child: Wrap(spacing: 14, runSpacing: 4, children: [
                  _Pintasan('F2', 'Cari'),
                  _Pintasan('F8', 'Tahan'),
                  _Pintasan('F9', 'Terakhir'),
                  _Pintasan('Del', 'Hapus baris'),
                ]),
              ),
              _TombolKecil('Ditahan (${_ditahan.length})', _ditahan.isEmpty ? null : _ambilDitahan),
              _TombolKecil('Transaksi terakhir', _transaksiTerakhir),
              if (widget.onBukaUbahHarga != null) _TombolKecil('Ubah harga', widget.onBukaUbahHarga),
              if (widget.onBukaBarangMasuk != null) _TombolKecil('Barang masuk', widget.onBukaBarangMasuk),
              if (widget.onBukaPengaturan != null) _TombolKecil('Pengaturan', _bukaPengaturan),
              _TombolKecil('Tutup shift', _tutupShift),
              if (widget.onKembaliKeMenu != null)
                _TombolKecil('← Menu', () {
                  if (!_keranjang.kosong || _ditahan.isNotEmpty) {
                    tampilkanPesan(context, 'Selesaikan atau kosongkan belanja dulu.', galat: true);
                    return;
                  }
                  _tutupKartuSelesai();
                  widget.onKembaliKeMenu!();
                }, putih: true)
              else
                _TombolKecil('Keluar', () {
                  if (!_keranjang.kosong || _ditahan.isNotEmpty) {
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
      height: 64,
      child: ikon == null
          ? OutlinedButton(onPressed: onTap, style: gaya, child: Text(label))
          : OutlinedButton.icon(onPressed: onTap, style: gaya, icon: Icon(ikon, size: 24), label: Text(label)),
    );
  }
}

// ============================================================================ dialog pembayaran

class DialogBayar extends StatefulWidget {
  const DialogBayar({super.key, required this.keranjang, required this.shift});
  final Keranjang keranjang;
  final Shift shift;
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

  int get _total => widget.keranjang.total;

  HasilPembayaran get _cek => cekPembayaran(metode: _metode, total: _total, uangDiterima: _diterima, noReferensi: _ref.text);

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
        metode: _metode,
        uangDiterima: _diterima,
        noReferensi: _metode.perluReferensi ? _ref.text : null,
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
    final tunai = _metode == MetodeBayar.tunai;
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
                const Expanded(child: Text('Pembayaran', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800))),
                Text('${widget.keranjang.jumlahBarang} BARANG',
                    style: const TextStyle(color: Warna.utamaTeksTerang, fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
                                  label: 'KEMBALIAN',
                                  nilai: formatRupiah(cek.kembalian),
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
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: besar ? 16 : 12),
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
                    child: Text(nilai, style: TextStyle(fontSize: besar ? 84 : 48, fontWeight: FontWeight.w800, color: warna, height: 1.15)),
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
  const KartuKembalian({super.key, required this.hasil, this.mencetak = false, this.galatCetak, this.onCetak});
  final HasilSimpanTransaksi hasil;
  final bool mencetak;
  final String? galatCetak;
  final VoidCallback? onCetak;

  @override
  Widget build(BuildContext context) {
    final s = hasil.struk;
    final tunai = s.metode == MetodeBayar.tunai;
    final otomatis = context.app.cetakOtomatis;
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
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              child: Row(children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 30),
                const SizedBox(width: 12),
                const Expanded(
                    child: Text('Transaksi selesai', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800))),
                Text(hasil.noTransaksi, style: const TextStyle(fontFamily: fontMono, color: Color(0xFFDDF5E6), fontSize: 16, fontWeight: FontWeight.w700)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (tunai)
                  _KotakBesar(
                    label: 'KEMBALIAN',
                    nilai: formatRupiah(s.kembalian),
                    latar: Warna.oranyeMuda,
                    garis: Warna.oranyeGaris,
                    aksen: Warna.oranyeTegas,
                    warna: Warna.oranyeTua,
                    besar: true,
                    lencana: s.kembalian == 0 ? 'UANG PAS' : null,
                  )
                else
                  _KotakBesar(
                    label: 'DIBAYAR ${s.metode.label.toUpperCase()}',
                    nilai: formatRupiah(s.total),
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
                  if (galatCetak == null) ...[
                    const Spacer(),
                    const Flexible(
                      flex: 3,
                      child: Text('Tetap tampil sampai barang berikutnya di-scan',
                          textAlign: TextAlign.right, style: TextStyle(fontSize: 15.5, color: Warna.teksPudar)),
                    ),
                  ],
                ]),
              ]),
            ),
          ]),
        ),
      ),
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
