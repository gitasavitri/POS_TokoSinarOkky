import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pos_core/pos_core.dart';

import '../../data/model.dart';
import '../../data/repo/order_repo.dart';
import '../../layanan/aplikasi.dart';
import '../../layanan/dokumen.dart';
import '../../layanan/sistem.dart';
import '../komponen/umum.dart';
import '../tema.dart';

/// Tempat menyimpan file surat pesanan. Bisa diganti di test.
typedef SimpanDokumen = Future<String> Function(String namaFile, Uint8List isi);

/// Bawaan: simpan ke Documents\POS-Order.
Future<String> simpanDiFolderOrder(String namaFile, Uint8List isi) async {
  final folder = await folderDokumen('POS-Order');
  final f = File('$folder${Platform.pathSeparator}$namaFile');
  await f.writeAsBytes(isi, flush: true);
  return f.path;
}

/// Cara menyimpan & membuka file order. Diganti di uji tampilan (tanpa menulis ke Documents).
@visibleForTesting
SimpanDokumen simpanDokumenOrder = simpanDiFolderOrder;
@visibleForTesting
Future<String?> Function(String path) bukaFileOrder = bukaDenganProgramBawaan;

/// Huruf PDF dari assets aplikasi (supaya semua huruf nama barang tercetak).
Future<HurufPdf?> muatHurufPdf() async {
  try {
    return HurufPdf.dariByte(
      await rootBundle.load('assets/fonts/PlusJakartaSans_400Regular.ttf'),
      await rootBundle.load('assets/fonts/PlusJakartaSans_700Bold.ttf'),
    );
  } catch (_) {
    return null;
  }
}

KepalaDokumen kepalaDokumen(Aplikasi app) => KepalaDokumen(
  namaToko: app.cabang.namaToko,
  namaCabang: app.cabang.nama,
  kodeCabang: app.cabang.kode,
  alamat: app.cabang.alamat,
  latihan: app.latihan,
);

/// Buat PDF + Excel untuk order tersimpan. Mengembalikan (path PDF, path Excel).
Future<(String, String)> buatDokumenOrder(Aplikasi app, OrderTersimpan o, {SimpanDokumen simpan = simpanDiFolderOrder}) async {
  final k = kepalaDokumen(app);
  final nama = '${app.latihan ? 'LATIHAN-' : ''}${o.noOrder}';
  final pdf = await pdfSuratPesanan(o, k, huruf: await muatHurufPdf());
  final pathPdf = await simpan('$nama.pdf', pdf);
  final pathExcel = await simpan('$nama.xlsx', excelOrder(o, k));
  return (pathPdf, pathExcel);
}

/// Order barang (revisi G): kiri daftar barang toko + stok + saran + tombol (+); kanan daftar order.
/// Hasilnya PDF "Surat Pesanan Barang" + Excel di Documents\POS-Order. Kirim order ke pusat menyusul.
class IsiOrderBarang extends StatefulWidget {
  const IsiOrderBarang({super.key});
  SimpanDokumen get simpan => simpanDokumenOrder;
  Future<String?> Function(String path) get bukaFile => bukaFileOrder;

  @override
  State<IsiOrderBarang> createState() => _IsiOrderBarangState();
}

class _IsiOrderBarangState extends State<IsiOrderBarang> {
  final _kata = TextEditingController();
  final _fokusCari = FocusNode();
  final _catatan = TextEditingController();
  List<BarangOrder> _semua = [];
  bool _hanyaPerlu = false;
  late DaftarOrder _order;
  List<Supplier> _tujuan = [];
  bool _sibuk = false;

  @override
  void initState() {
    super.initState();
    final app = context.app;
    _tujuan = app.katalog.supplier();
    _order = app.order.muatDraft() ?? DaftarOrder();
    // Tujuan yang sudah tidak ada dikosongkan; order baru langsung ke toko utama kalau ada.
    if (_order.supplierId != null && !_tujuan.any((t) => t.id == _order.supplierId)) _order.supplierId = null;
    _order.supplierId ??= _tujuan.where((t) => t.jenis == 'toko_utama').firstOrNull?.id;
    _catatan.text = _order.catatan;
    // Belum ada yang perlu diorder → tampilkan semua; ada → langsung saring "Perlu order saja".
    _hanyaPerlu = app.order.daftarBarang(app.cabang.id, hanyaPerlu: true).isNotEmpty;
    _muat();
  }

  @override
  void dispose() {
    _kata.dispose();
    _fokusCari.dispose();
    _catatan.dispose();
    super.dispose();
  }

  void _muat() {
    final app = context.app;
    setState(() => _semua = app.order.daftarBarang(app.cabang.id, kata: _kata.text));
  }

  void _simpanDraft() {
    _order.catatan = _catatan.text;
    context.app.order.simpanDraft(_order);
  }

  void _tambah(BarangOrder b) {
    setState(() => _order.tambah(b.keBaris()));
    _simpanDraft();
  }

  /// Enter di kotak cari: barcode yang cocok langsung ditambahkan.
  void _enterCari() {
    final app = context.app;
    final b = app.order.cariBarcode(app.cabang.id, _kata.text);
    if (b != null) {
      _tambah(b);
      _kata.clear();
      _muat();
    } else {
      _muat();
    }
    _fokusCari.requestFocus();
  }

  void _aturJumlah(BarisOrder b, int n) {
    setState(() => _order.aturJumlah(b.barangId, n));
    _simpanDraft();
  }

  Future<void> _ketikJumlah(BarisOrder b) async {
    final c = TextEditingController(text: '${b.jumlah}');
    final n = await showDialog<int>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(b.nama, style: const TextStyle(fontWeight: FontWeight.w800)),
        content: SizedBox(
          width: 360,
          child: TextField(
            controller: c,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(5)],
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
            decoration: InputDecoration(labelText: 'Jumlah order (${b.satuan})'),
            onSubmitted: (v) => Navigator.pop(d, int.tryParse(v)),
          ),
        ),
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(d), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(d, int.tryParse(c.text)), child: const Text('Simpan')),
        ],
      ),
    );
    if (n != null) _aturJumlah(b, n);
  }

  Future<void> _kosongkan() async {
    final ok = await konfirmasi(
      context,
      judul: 'Kosongkan daftar order?',
      isi: 'Semua barang di daftar order dihapus.',
      ya: 'Kosongkan',
      bahaya: true,
    );
    if (!ok) return;
    setState(() {
      _order.baris.clear();
      _catatan.clear();
    });
    _simpanDraft();
  }

  Future<void> _simpan() async {
    _order.catatan = _catatan.text;
    final salah = _order.periksa();
    if (salah != null) return tampilkanPesan(context, salah, galat: true);
    final app = context.app;
    setState(() => _sibuk = true);
    try {
      final o = app.order.simpan(cabang: app.cabang, oleh: app.penggunaAktif!, order: _order);
      String? pathPdf, pathExcel, galatFile;
      try {
        (pathPdf, pathExcel) = await buatDokumenOrder(app, o, simpan: widget.simpan);
      } catch (e) {
        galatFile = pesanGalat(e);
      }
      if (!mounted) return;
      setState(() {
        _order = DaftarOrder(supplierId: _order.supplierId);
        _catatan.clear();
        _sibuk = false;
      });
      _muat();
      await tampilkanHasilOrder(context, o, pathPdf: pathPdf, pathExcel: pathExcel, galat: galatFile, bukaFile: widget.bukaFile);
    } catch (e) {
      if (!mounted) return;
      setState(() => _sibuk = false);
      tampilkanPesan(context, pesanGalat(e), galat: true);
    }
  }

  Future<void> _riwayat() => showDialog<void>(
    context: context,
    builder: (_) => _DialogRiwayatOrder(simpan: widget.simpan, bukaFile: widget.bukaFile),
  );

  @override
  Widget build(BuildContext context) {
    final perlu = _semua.where((b) => b.perlu).length;
    final daftar = _hanyaPerlu ? _semua.where((b) => b.perlu).toList() : _semua;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const ValueKey('cari-order'),
                        controller: _kata,
                        focusNode: _fokusCari,
                        autofocus: true,
                        style: const TextStyle(fontSize: 19),
                        decoration: const InputDecoration(
                          hintText: 'Scan barcode atau ketik nama barang',
                          prefixIcon: Icon(Icons.search),
                        ),
                        onChanged: (_) => _muat(),
                        onSubmitted: (_) => _enterCari(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilterChip(
                      key: const ValueKey('filter-perlu-order'),
                      label: Text('Perlu order saja ($perlu)', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      selected: _hanyaPerlu,
                      padding: const EdgeInsets.all(10),
                      onSelected: (v) => setState(() => _hanyaPerlu = v),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      key: const ValueKey('riwayat-order'),
                      onPressed: _riwayat,
                      icon: const Icon(Icons.history),
                      label: const Text('Riwayat order'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '${daftar.length} barang · Saran = isi sampai $kaliStokMinimum× stok minimum. Stok minimum diatur SPV/Admin di Produk & stok.',
                  style: const TextStyle(fontSize: 15, color: Warna.teksPudar),
                ),
                const SizedBox(height: 10),
                Expanded(child: _tabelBarang(daftar)),
              ],
            ),
          ),
          const SizedBox(width: 18),
          SizedBox(width: 470, child: _panelOrder()),
        ],
      ),
    );
  }

  Widget _tabelBarang(List<BarangOrder> daftar) {
    const lebar = [7, 3, 2, 2, 2];
    Widget sel(int i, Widget w, {bool kanan = false}) => Expanded(
      flex: lebar[i],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Align(alignment: kanan ? Alignment.centerRight : Alignment.centerLeft, child: w),
      ),
    );
    const gayaKepala = TextStyle(fontSize: 13.5, letterSpacing: 0.5, fontWeight: FontWeight.w800, color: Warna.utamaTua);
    return _KotakPenuh(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: const BoxDecoration(
              color: Warna.utamaMuda,
              border: Border(bottom: BorderSide(color: Warna.utamaGarisMuda, width: 2)),
            ),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                sel(0, const Text('BARANG', style: gayaKepala)),
                sel(1, const Text('STOK', style: gayaKepala), kanan: true),
                sel(2, const Text('MIN.', style: gayaKepala), kanan: true),
                sel(3, const Text('SARAN', style: gayaKepala), kanan: true),
                const SizedBox(width: 64),
              ],
            ),
          ),
          Expanded(
            child: daftar.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _hanyaPerlu
                          ? 'Tidak ada barang yang perlu diorder. Matikan saringan "Perlu order saja" untuk melihat semua.'
                          : 'Tidak ada barang yang cocok.',
                      style: const TextStyle(fontSize: 17, color: Warna.teksPudar),
                    ),
                  )
                : ListView.builder(
                    itemCount: daftar.length,
                    itemBuilder: (context, r) {
                      final b = daftar[r];
                      final diOrder = _order.cari(b.id);
                      final warnaStok = switch (b.status) {
                        StatusStok.habis => Warna.merah,
                        StatusStok.hampirHabis => Warna.oranye,
                        StatusStok.aman => Warna.teks,
                      };
                      return Material(
                        color: diOrder != null ? Warna.utamaSorot : (r.isOdd ? Warna.baris2 : Colors.white),
                        child: InkWell(
                          onTap: () => _tambah(b),
                          child: Container(
                            constraints: const BoxConstraints(minHeight: 58),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                            decoration: const BoxDecoration(
                              border: Border(top: BorderSide(color: Warna.garisTipis)),
                            ),
                            child: Row(
                              children: [
                                sel(
                                  0,
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(b.nama, style: gayaSelTebal),
                                      Text(
                                        b.barcode ?? 'tanpa barcode',
                                        style: const TextStyle(fontSize: 14, fontFamily: fontMono, color: Warna.teksPudar),
                                      ),
                                    ],
                                  ),
                                ),
                                sel(
                                  1,
                                  Text(
                                    '${formatAngka(b.stok)} ${b.satuan}',
                                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: warnaStok),
                                  ),
                                  kanan: true,
                                ),
                                sel(2, Text(b.stokMinimum == 0 ? '-' : formatAngka(b.stokMinimum), style: gayaSel), kanan: true),
                                sel(3, Text(b.saran == 0 ? '-' : formatAngka(b.saran), style: gayaSelTebal), kanan: true),
                                SizedBox(
                                  width: 64,
                                  child: Align(
                                    alignment: Alignment.centerRight,
                                    child: diOrder != null
                                        ? Tooltip(
                                            message: 'Sudah di daftar order (${diOrder.jumlah}). Klik untuk menambah lagi.',
                                            child: FilledButton(
                                              key: ValueKey('tambah-order-${b.id}'),
                                              onPressed: () => _tambah(b),
                                              style: FilledButton.styleFrom(
                                                backgroundColor: Warna.sukses,
                                                minimumSize: const Size(52, 46),
                                                padding: EdgeInsets.zero,
                                              ),
                                              child: const Icon(Icons.check, size: 26, semanticLabel: 'Sudah di daftar order'),
                                            ),
                                          )
                                        : FilledButton(
                                            key: ValueKey('tambah-order-${b.id}'),
                                            onPressed: () => _tambah(b),
                                            style: FilledButton.styleFrom(minimumSize: const Size(52, 46), padding: EdgeInsets.zero),
                                            child: const Icon(Icons.add, size: 28, semanticLabel: 'Tambah ke daftar order'),
                                          ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _panelOrder() {
    final siap = _order.periksa() == null;
    return _KotakPenuh(
      judul: 'Daftar order',
      aksi: _order.kosong ? null : TextButton(onPressed: _kosongkan, child: const Text('Kosongkan')),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: DropdownButtonFormField<String>(
              key: const ValueKey('order-ke'),
              initialValue: _order.supplierId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Order ke'),
              style: const TextStyle(fontSize: 18, color: Warna.teks, fontFamily: fontUtama),
              items: [
                for (final t in _tujuan)
                  DropdownMenuItem(
                    value: t.id,
                    child: Text(t.jenis == 'toko_utama' ? '${t.nama} (toko utama)' : t.nama, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) {
                setState(() => _order.supplierId = v);
                _simpanDraft();
              },
            ),
          ),
          Expanded(
            child: _order.kosong
                ? const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      'Belum ada barang. Klik (+) di daftar kiri, atau scan barcode di kotak cari.',
                      style: TextStyle(fontSize: 16.5, color: Warna.teksPudar, height: 1.4),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _order.baris.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final b = _order.baris[i];
                      return Padding(
                        key: ValueKey('baris-order-${b.barangId}'),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(b.nama, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700)),
                                  Text('Stok ${formatAngka(b.stok)} · ${b.satuan}', style: const TextStyle(fontSize: 14, color: Warna.teksPudar)),
                                ],
                              ),
                            ),
                            _TombolKecil(ikon: Icons.remove, label: 'Kurangi', onTap: b.jumlah > 1 ? () => _aturJumlah(b, b.jumlah - 1) : null),
                            InkWell(
                              onTap: () => _ketikJumlah(b),
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                width: 64,
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                child: Text(
                                  formatAngka(b.jumlah),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                                ),
                              ),
                            ),
                            _TombolKecil(ikon: Icons.add, label: 'Tambah', onTap: () => _aturJumlah(b, b.jumlah + 1)),
                            const SizedBox(width: 4),
                            IconButton(
                              tooltip: 'Hapus dari daftar',
                              onPressed: () => _aturJumlah(b, 0),
                              icon: const Icon(Icons.delete_outline, color: Warna.merah),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: TextField(
              key: const ValueKey('catatan-order'),
              controller: _catatan,
              maxLines: 2,
              minLines: 1,
              maxLength: 300,
              style: const TextStyle(fontSize: 16.5),
              decoration: const InputDecoration(labelText: 'Catatan (boleh kosong)', hintText: 'mis. kirim sebelum Sabtu', counterText: ''),
              onChanged: (_) => _simpanDraft(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text('${_order.jumlahJenis} jenis barang', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                    const Spacer(),
                    Text('Total ${formatAngka(_order.totalJumlah)}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 60,
                  child: FilledButton.icon(
                    key: const ValueKey('simpan-order'),
                    onPressed: siap && !_sibuk ? _simpan : null,
                    icon: const Icon(Icons.picture_as_pdf),
                    label: Text(_sibuk ? 'Menyimpan…' : 'Simpan & buat surat pesanan', style: const TextStyle(fontSize: 18)),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Hasil: PDF "Surat Pesanan Barang" + Excel. Kirim order ke pusat lewat aplikasi menyusul.',
                  style: TextStyle(fontSize: 13.5, color: Warna.teksPudar),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Seperti [Panel], tapi isinya mengisi seluruh tinggi (untuk daftar yang bisa digulir).
class _KotakPenuh extends StatelessWidget {
  const _KotakPenuh({this.judul, this.aksi, required this.child});
  final String? judul;
  final Widget? aksi;
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), boxShadow: Warna.bayangan),
    child: Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: Warna.garis, width: 1.5),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (judul != null)
            Container(
              decoration: const BoxDecoration(
                color: Warna.utamaMuda,
                border: Border(bottom: BorderSide(color: Warna.utamaGarisMuda, width: 2)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      judul!,
                      style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: Warna.utamaTua),
                    ),
                  ),
                  ?aksi,
                ],
              ),
            ),
          Expanded(child: child),
        ],
      ),
    ),
  );
}

class _TombolKecil extends StatelessWidget {
  const _TombolKecil({required this.ikon, required this.label, required this.onTap});
  final IconData ikon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 44,
    height: 44,
    child: OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(44, 44)),
      child: Icon(ikon, size: 22, semanticLabel: label),
    ),
  );
}

/// Dialog setelah order disimpan: nomor order + tombol buka PDF / Excel / folder.
Future<void> tampilkanHasilOrder(
  BuildContext context,
  OrderTersimpan o, {
  String? pathPdf,
  String? pathExcel,
  String? galat,
  required Future<String?> Function(String path) bukaFile,
}) => showDialog<void>(
  context: context,
  builder: (d) {
    Future<void> buka(String path) async {
      final g = await bukaFile(path);
      if (g != null && d.mounted) tampilkanPesan(d, g, galat: true);
    }

    return AlertDialog(
      title: Text('Order ${o.noOrder} tersimpan', style: const TextStyle(fontWeight: FontWeight.w800)),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('${o.jumlahJenis} jenis barang · total ${formatAngka(o.totalJumlah)} · ke ${o.tujuan}', style: const TextStyle(fontSize: 17)),
            const SizedBox(height: 14),
            if (galat != null)
              KotakPesan('Order tersimpan, tapi file belum dibuat: $galat. Buat ulang dari Riwayat order.', jenis: JenisPesan.galat)
            else ...[
              const Text('Disimpan di:', style: TextStyle(fontSize: 15.5, color: Warna.teksPudar)),
              SelectableText(pathPdf ?? '', style: const TextStyle(fontSize: 15, fontFamily: fontMono)),
              SelectableText(pathExcel ?? '', style: const TextStyle(fontSize: 15, fontFamily: fontMono)),
              const SizedBox(height: 10),
              const KotakPesan('Buka PDF lalu cetak (Ctrl+P), atau kirim file PDF/Excel ke toko utama / supplier.'),
            ],
          ],
        ),
      ),
      actions: [
        if (pathPdf != null)
          OutlinedButton.icon(
            onPressed: () => buka(File(pathPdf).parent.path),
            icon: const Icon(Icons.folder_open),
            label: const Text('Buka folder'),
          ),
        if (pathExcel != null)
          OutlinedButton.icon(onPressed: () => buka(pathExcel), icon: const Icon(Icons.table_chart), label: const Text('Buka Excel')),
        if (pathPdf != null) FilledButton.icon(onPressed: () => buka(pathPdf), icon: const Icon(Icons.picture_as_pdf), label: const Text('Buka PDF')),
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('Selesai')),
      ],
    );
  },
);

class _DialogRiwayatOrder extends StatelessWidget {
  const _DialogRiwayatOrder({required this.simpan, required this.bukaFile});
  final SimpanDokumen simpan;
  final Future<String?> Function(String path) bukaFile;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final daftar = app.order.riwayat(app.cabang.id);
    Future<void> buatUlang(String id) async {
      final o = app.order.muat(id)!;
      try {
        final (pdf, excel) = await buatDokumenOrder(app, o, simpan: simpan);
        if (context.mounted) await tampilkanHasilOrder(context, o, pathPdf: pdf, pathExcel: excel, bukaFile: bukaFile);
      } catch (e) {
        if (context.mounted) tampilkanPesan(context, pesanGalat(e), galat: true);
      }
    }

    return AlertDialog(
      title: const Text('Riwayat order', style: TextStyle(fontWeight: FontWeight.w800)),
      content: SizedBox(
        width: 820,
        height: 480,
        child: daftar.isEmpty
            ? const Text('Belum ada order.', style: TextStyle(fontSize: 17, color: Warna.teksPudar))
            : SingleChildScrollView(
                child: TabelSederhana(
                  kolom: const ['No. order', 'Waktu', 'Ke', 'Oleh', 'Barang', ''],
                  lebar: const [5, 4, 4, 3, 2, 3],
                  rataKanan: const {4},
                  baris: [
                    for (final o in daftar)
                      [
                        Text(
                          o.noOrder,
                          style: const TextStyle(fontSize: 15.5, fontFamily: fontMono, fontWeight: FontWeight.w700),
                        ),
                        Text('${formatTanggal(o.waktu)} ${formatJam(o.waktu)}', style: const TextStyle(fontSize: 15.5)),
                        Text(o.tujuan, style: const TextStyle(fontSize: 15.5)),
                        Text(o.oleh, style: const TextStyle(fontSize: 15.5)),
                        Text('${o.jumlahJenis} jenis', style: const TextStyle(fontSize: 15.5)),
                        OutlinedButton(onPressed: () => buatUlang(o.id), child: const Text('PDF / Excel')),
                      ],
                  ],
                ),
              ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Tutup'))],
    );
  }
}
