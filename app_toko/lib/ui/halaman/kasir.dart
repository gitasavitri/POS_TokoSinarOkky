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
    setState(() {
      _keranjang.kosongkan();
      _barisDipilih = null;
    });
    String? galatCetak;
    if (app.cetakOtomatis) galatCetak = await app.cetakStrukTransaksi(hasil.struk);
    if (app.cetakOtomatis && galatCetak == null) app.pemulihan.selesaiCetak();
    if (!mounted) return;
    await showDialog<void>(context: context, builder: (_) => DialogSelesai(hasil: hasil, galatCetak: galatCetak));
    app.pemulihan.selesaiCetak(); // kasir sudah melihat hasilnya (dan bisa cetak ulang dari dialog)
    _fokuskan();
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
        body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // ------------------------------------------------ atas: info + total
          Container(
            color: Warna.hijauTua,
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
                const SizedBox(width: 14),
                Expanded(
                  flex: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
                    decoration: BoxDecoration(
                        color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFF7FD1AE), width: 3)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Text('TOTAL BELANJA',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: Warna.hijauTua)),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(formatRupiah(_keranjang.total),
                            style: const TextStyle(fontSize: 60, fontWeight: FontWeight.w800, height: 1.1, color: Warna.hijauTua)),
                      ),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
          // ------------------------------------------------ tengah: daftar belanja
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(20, 14, 20, 14),
              decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Warna.garis, width: 2)),
              clipBehavior: Clip.antiAlias,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const _KepalaKeranjang(),
                Expanded(
                  child: _keranjang.kosong
                      ? const Center(
                          child: Text('Scan barcode barang untuk mulai',
                              style: TextStyle(fontSize: 22, color: Warna.teksPudar, fontWeight: FontWeight.w600)))
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
                  color: const Color(0xFFF2F5F3),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    Text.rich(TextSpan(style: const TextStyle(fontSize: 18), children: [
                      const TextSpan(text: 'Jenis barang: '),
                      TextSpan(text: '${_keranjang.jumlahJenis}', style: const TextStyle(fontWeight: FontWeight.w800)),
                      const TextSpan(text: '      Jumlah barang: '),
                      TextSpan(text: '${_keranjang.jumlahBarang}', style: const TextStyle(fontWeight: FontWeight.w800)),
                    ])),
                  ]),
                ),
              ]),
            ),
          ),
          // ------------------------------------------------ bawah: scan + tombol
          Container(
            decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Warna.hijau, width: 4))),
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                flex: 5,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const LabelKecil('Scan barcode / ketik nama barang'),
                  const SizedBox(height: 6),
                  TextField(
                    key: const ValueKey('scan'),
                    controller: _scan,
                    focusNode: _fokusScan,
                    autofocus: true,
                    style: const TextStyle(fontSize: 24),
                    decoration: const InputDecoration(
                      hintText: 'Arahkan scanner ke barcode…',
                      prefixIcon: Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Icon(Icons.qr_code_scanner, size: 32, color: Warna.hijau)),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(10)), borderSide: BorderSide(color: Warna.hijau, width: 3)),
                    ),
                    onSubmitted: (_) => _prosesScan(),
                  ),
                ]),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 120,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const LabelKecil('Jumlah'),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _qty,
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(5)],
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
                    onSubmitted: (_) => _fokuskan(),
                  ),
                ]),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 64,
                child: OutlinedButton(
                  onPressed: _prosesScan,
                  style: OutlinedButton.styleFrom(
                      backgroundColor: Warna.hijauMuda, foregroundColor: Warna.hijauGelap, side: const BorderSide(color: Warna.hijau, width: 3)),
                  child: const Text('Tambah (Enter)'),
                ),
              ),
              const SizedBox(width: 20),
              SizedBox(
                height: 64,
                child: OutlinedButton(
                  onPressed: _keranjang.kosong ? null : _batalkanKeranjang,
                  style: OutlinedButton.styleFrom(foregroundColor: Warna.merah, side: const BorderSide(color: Warna.merahGaris, width: 2)),
                  child: const Text('Kosongkan'),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(height: 64, child: OutlinedButton(onPressed: _keranjang.kosong ? null : _tahan, child: const Text('Tahan (F8)'))),
              const SizedBox(width: 10),
              SizedBox(
                height: 64,
                width: 240,
                child: FilledButton(
                  onPressed: _keranjang.kosong ? null : _bayar,
                  child: const Text('BAYAR (F12)', style: TextStyle(fontSize: 24)),
                ),
              ),
            ]),
          ),
          // ------------------------------------------------ paling bawah: pintasan & menu
          Container(
            color: Warna.kepalaTabel,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(children: [
              const Expanded(
                child: Wrap(spacing: 18, children: [
                  _Pintasan('F2', 'Cari barang'),
                  _Pintasan('F8', 'Tahan'),
                  _Pintasan('F9', 'Transaksi terakhir'),
                  _Pintasan('Del', 'Hapus baris'),
                  _Pintasan('F12', 'Bayar'),
                ]),
              ),
              _TombolKecil('Ditahan (${_ditahan.length})', _ditahan.isEmpty ? null : _ambilDitahan),
              _TombolKecil('Transaksi terakhir', _transaksiTerakhir),
              if (widget.onBukaUbahHarga != null) _TombolKecil('Ubah harga', widget.onBukaUbahHarga),
              if (widget.onBukaBarangMasuk != null) _TombolKecil('Barang masuk', widget.onBukaBarangMasuk),
              if (widget.onBukaPengaturan != null) _TombolKecil('Pengaturan', _bukaPengaturan),
              _TombolKecil('Tutup shift', _tutupShift),
              if (widget.onKembaliKeMenu != null)
                _TombolKecil('Kembali ke menu', () {
                  if (!_keranjang.kosong || _ditahan.isNotEmpty) {
                    tampilkanPesan(context, 'Selesaikan atau kosongkan belanja dulu.', galat: true);
                    return;
                  }
                  widget.onKembaliKeMenu!();
                })
              else
                _TombolKecil('Keluar', () {
                  if (!_keranjang.kosong || _ditahan.isNotEmpty) {
                    tampilkanPesan(context, 'Selesaikan atau kosongkan belanja dulu.', galat: true);
                    return;
                  }
                  app.keluar();
                }),
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
              color: Warna.hijauPanel, borderRadius: BorderRadius.circular(8), border: Border.all(color: Warna.hijauGaris)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(label.toUpperCase(),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: Warna.hijauTeksTerang)),
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
    const gaya = TextStyle(fontSize: 14, letterSpacing: 0.6, fontWeight: FontWeight.w800, color: Warna.teks2);
    return Container(
      color: Warna.kepalaTabel,
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
      color: terakhir ? Warna.hijauSorot : (selang ? Warna.baris2 : Colors.white),
      child: InkWell(
        onTap: onPilih,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              top: const BorderSide(color: Warna.garisTipis),
              left: BorderSide(color: dipilih ? Warna.hijau : Colors.transparent, width: 5),
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

class _Pintasan extends StatelessWidget {
  const _Pintasan(this.tombol, this.arti);
  final String tombol;
  final String arti;
  @override
  Widget build(BuildContext context) => Text.rich(TextSpan(style: const TextStyle(fontSize: 14.5, color: Warna.teks2), children: [
        TextSpan(text: tombol, style: const TextStyle(fontWeight: FontWeight.w800)),
        TextSpan(text: ' $arti'),
      ]));
}

class _TombolKecil extends StatelessWidget {
  const _TombolKecil(this.label, this.onTap);
  final String label;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 8),
        child: OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(44, 44),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            side: const BorderSide(color: Color(0xFF9AA9A2), width: 2),
            textStyle: const TextStyle(fontFamily: fontUtama, fontSize: 15, fontWeight: FontWeight.w700),
          ),
          child: Text(label),
        ),
      );
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
              color: Warna.hijauTua,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(children: [
                const Expanded(child: Text('Pembayaran', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800))),
                Text('${widget.keranjang.jumlahBarang} BARANG',
                    style: const TextStyle(color: Warna.hijauTeksTerang, fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                IntrinsicHeight(
                  child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Expanded(child: _KotakBesar(label: 'TOTAL BAYAR', nilai: formatRupiah(_total), latar: Warna.hijauMuda, garis: const Color(0xFF9DCFB8), warna: Warna.hijauTua)),
                    const SizedBox(width: 14),
                    Expanded(
                      child: !tunai
                          ? const _KotakTeks('Pastikan pembayaran sudah berhasil di mesin EDC, QRIS, atau aplikasi bank sebelum menekan Selesai.')
                          : cek.boleh
                              ? _KotakBesar(label: 'KEMBALIAN', nilai: formatRupiah(cek.kembalian), latar: Warna.oranyeMuda, garis: Warna.oranyeGaris, warna: Warna.oranyeTua)
                              : _KotakBesar(
                                  label: 'UANG KURANG', nilai: formatRupiah(cek.kurang), latar: Warna.merahMuda, garis: const Color(0xFFE3A79F), warna: Warna.merahTua),
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
                      child: FilledButton(
                        onPressed: cek.boleh && !_sibuk ? _selesai : null,
                        child: Text(_sibuk ? 'Menyimpan…' : 'Selesai & cetak struk (Enter)', style: const TextStyle(fontSize: 21)),
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
  const _KotakBesar({required this.label, required this.nilai, required this.latar, required this.garis, required this.warna});
  final String label;
  final String nilai;
  final Color latar;
  final Color garis;
  final Color warna;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(color: latar, borderRadius: BorderRadius.circular(12), border: Border.all(color: garis, width: 2)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: warna)),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(nilai, style: TextStyle(fontSize: 48, fontWeight: FontWeight.w800, color: warna, height: 1.15)),
          ),
        ]),
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

/// Setelah bayar: tampilkan kembalian besar + cetak ulang.
class DialogSelesai extends StatelessWidget {
  const DialogSelesai({super.key, required this.hasil, this.galatCetak});
  final HasilSimpanTransaksi hasil;
  final String? galatCetak;

  @override
  Widget build(BuildContext context) {
    final s = hasil.struk;
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.enter): () => Navigator.pop(context)},
      child: Focus(
        autofocus: true,
        child: AlertDialog(
          title: Row(children: [
            const Icon(Icons.check_circle, color: Warna.hijau, size: 34),
            const SizedBox(width: 12),
            Expanded(child: Text('Transaksi tersimpan · ${hasil.noTransaksi}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 22))),
          ]),
          content: SizedBox(
            width: 560,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (s.metode == MetodeBayar.tunai)
                _KotakBesar(label: 'KEMBALIAN', nilai: formatRupiah(s.kembalian), latar: Warna.oranyeMuda, garis: Warna.oranyeGaris, warna: Warna.oranyeTua)
              else
                _KotakBesar(label: s.metode.label.toUpperCase(), nilai: formatRupiah(s.total), latar: Warna.hijauMuda, garis: const Color(0xFF9DCFB8), warna: Warna.hijauTua),
              if (galatCetak != null) ...[
                const SizedBox(height: 14),
                KotakPesan('Struk belum tercetak: $galatCetak', jenis: JenisPesan.galat),
              ],
            ]),
          ),
          actions: [
            OutlinedButton.icon(
              onPressed: () async {
                final g = await context.app.cetakStrukTransaksi(s);
                if (context.mounted) tampilkanPesan(context, g ?? 'Struk dicetak', galat: g != null);
              },
              icon: const Icon(Icons.print),
              label: Text(galatCetak == null && context.app.cetakOtomatis ? 'Cetak lagi' : 'Cetak struk'),
            ),
            FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Transaksi baru (Enter)')),
          ],
        ),
      ),
    );
  }
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
