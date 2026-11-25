import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pos_core/pos_core.dart';

import '../data/repo/order_repo.dart';

/// Data kepala surat pesanan (dari info toko).
class KepalaDokumen {
  const KepalaDokumen({required this.namaToko, required this.namaCabang, required this.kodeCabang, required this.alamat, this.latihan = false});
  final String namaToko;
  final String namaCabang;
  final String kodeCabang;
  final String alamat;

  /// Dibuat di mode latihan: dokumen diberi tulisan [teksDokumenLatihan].
  final bool latihan;
}

/// Tulisan di surat pesanan / Excel yang dibuat di mode latihan.
const teksDokumenLatihan = 'LATIHAN - BUKAN PESANAN ASLI';

/// Huruf PDF. Tanpa huruf (null) dipakai Helvetica bawaan PDF, yang hanya mendukung huruf Latin dasar,
/// jadi aplikasi memuat Plus Jakarta Sans dari assets.
class HurufPdf {
  const HurufPdf({required this.biasa, required this.tebal});
  final pw.Font biasa;
  final pw.Font tebal;

  static HurufPdf dariByte(ByteData biasa, ByteData tebal) => HurufPdf(biasa: pw.Font.ttf(biasa), tebal: pw.Font.ttf(tebal));
}

String _waktu(DateTime t) => '${formatTanggal(t)}, ${formatJam(t)} WIB';

// ==================================================================== surat pesanan (PDF)

/// PDF "Surat Pesanan Barang" ukuran A4: kepala toko, no. order, tanggal, pembuat, tujuan, catatan,
/// tabel barang dengan kolom Diterima (diisi tangan saat barang datang), dan tanda tangan.
Future<Uint8List> pdfSuratPesanan(OrderTersimpan o, KepalaDokumen k, {HurufPdf? huruf}) async {
  final tema = huruf == null ? pw.ThemeData.base() : pw.ThemeData.withFont(base: huruf.biasa, bold: huruf.tebal);
  final doc = pw.Document(title: 'Surat Pesanan Barang ${o.noOrder}', author: k.namaToko, creator: 'POS Toko', theme: tema);
  const abu = PdfColor.fromInt(0xFF5B6675);
  const garis = PdfColor.fromInt(0xFFB8C2CF);
  pw.TextStyle gaya(double ukuran, {bool tebal = false, PdfColor? warna}) =>
      pw.TextStyle(fontSize: ukuran, fontWeight: tebal ? pw.FontWeight.bold : pw.FontWeight.normal, color: warna);

  pw.Widget info(String label, String isi) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 3),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.SizedBox(width: 78, child: pw.Text(label, style: gaya(10, warna: abu))),
          pw.Expanded(child: pw.Text(isi, style: gaya(10.5, tebal: true))),
        ]),
      );

  pw.Widget tandaTangan(String judul, String nama) => pw.Expanded(
        child: pw.Column(children: [
          pw.Text(judul, style: gaya(10)),
          pw.SizedBox(height: 52),
          pw.Container(height: 0.8, color: PdfColors.black, margin: const pw.EdgeInsets.symmetric(horizontal: 18)),
          pw.SizedBox(height: 3),
          pw.Text(nama.isEmpty ? '(nama jelas)' : nama, style: gaya(9.5, warna: nama.isEmpty ? abu : null)),
        ]),
      );

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(40, 36, 40, 36),
    header: (c) => c.pageNumber == 1
        ? pw.SizedBox()
        : pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 8),
            child: pw.Text('Surat Pesanan Barang ${o.noOrder} (lanjutan)', style: gaya(9, warna: abu)),
          ),
    footer: (c) => pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
      pw.Text('${o.noOrder} · dicetak dari POS Toko', style: gaya(8, warna: abu)),
      pw.Text('Halaman ${c.pageNumber} dari ${c.pagesCount}', style: gaya(8, warna: abu)),
    ]),
    build: (c) => [
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(k.namaToko, style: gaya(17, tebal: true)),
            pw.Text('Cabang ${k.namaCabang} (${k.kodeCabang})', style: gaya(10.5)),
            if (k.alamat.isNotEmpty) pw.Text(k.alamat, style: gaya(9.5, warna: abu)),
          ]),
        ),
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          pw.Text('SURAT PESANAN BARANG', style: gaya(15, tebal: true)),
          pw.Text(o.noOrder, style: gaya(11.5, tebal: true)),
        ]),
      ]),
      if (k.latihan)
        pw.Container(
          margin: const pw.EdgeInsets.only(top: 8),
          padding: const pw.EdgeInsets.all(6),
          color: const PdfColor.fromInt(0xFFC2410C),
          child: pw.Center(child: pw.Text(teksDokumenLatihan, style: gaya(13, tebal: true, warna: PdfColors.white))),
        ),
      pw.SizedBox(height: 10),
      pw.Container(height: 1.2, color: PdfColors.black),
      pw.SizedBox(height: 10),
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(
          child: pw.Column(children: [
            info('Kepada', '${o.tujuan}${o.tujuanTokoUtama ? ' (toko utama)' : ''}'),
            info('Tanggal', _waktu(o.waktu)),
          ]),
        ),
        pw.SizedBox(width: 20),
        pw.Expanded(
          child: pw.Column(children: [
            info('Dibuat oleh', '${o.dibuatOleh} (${o.peranPembuat})'),
            info('Jumlah', '${o.jumlahJenis} jenis barang · ${formatAngka(o.totalJumlah)} total'),
          ]),
        ),
      ]),
      if (o.catatan.isNotEmpty) ...[pw.SizedBox(height: 4), info('Catatan', o.catatan)],
      pw.SizedBox(height: 12),
      pw.TableHelper.fromTextArray(
        headers: ['No', 'Barcode', 'Nama barang', 'Satuan', 'Jumlah', 'Diterima'],
        data: [
          for (var i = 0; i < o.baris.length; i++)
            ['${i + 1}', o.baris[i].barcode ?? '-', o.baris[i].nama, o.baris[i].satuan, formatAngka(o.baris[i].jumlah), ''],
        ],
        border: pw.TableBorder.all(color: garis, width: 0.6),
        headerStyle: gaya(9.5, tebal: true),
        headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFE8F0FA)),
        cellStyle: gaya(10),
        cellHeight: 22,
        cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
        columnWidths: {
          0: const pw.FixedColumnWidth(26),
          1: const pw.FixedColumnWidth(92),
          2: const pw.FlexColumnWidth(),
          3: const pw.FixedColumnWidth(48),
          4: const pw.FixedColumnWidth(50),
          5: const pw.FixedColumnWidth(58),
        },
        cellAlignments: {0: pw.Alignment.centerRight, 4: pw.Alignment.centerRight},
      ),
      pw.SizedBox(height: 6),
      pw.Text('Kolom "Diterima" diisi saat barang datang. Selisih dicatat di Barang masuk.', style: gaya(8.5, warna: abu)),
      pw.SizedBox(height: 26),
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        tandaTangan('Dibuat oleh', o.dibuatOleh),
        tandaTangan('Disetujui oleh', ''),
        tandaTangan('Diterima oleh', ''),
      ]),
    ],
  ));
  return doc.save();
}

// ==================================================================== Excel

final _gayaJudul = CellStyle(bold: true, fontSize: 14);
final _gayaKepala = CellStyle(bold: true, backgroundColorHex: ExcelColor.fromHexString('#FFE8F0FA'));
final _gayaTebal = CellStyle(bold: true);
final _gayaTeks = CellStyle(numberFormat: NumFormat.standard_49); // format Teks ('@')
final _gayaKepalaTeks = CellStyle(bold: true, backgroundColorHex: ExcelColor.fromHexString('#FFE8F0FA'), numberFormat: NumFormat.standard_49);

void _tulis(Sheet s, int kolom, int baris, CellValue? nilai, [CellStyle? gaya]) =>
    s.updateCell(CellIndex.indexByColumnRow(columnIndex: kolom, rowIndex: baris), nilai, cellStyle: gaya);

Uint8List _simpan(Excel e) {
  final b = e.encode();
  if (b == null) throw StateError('Gagal membuat file Excel');
  return Uint8List.fromList(b);
}

/// Excel order: kepala (toko, no. order, tanggal, pembuat, tujuan, catatan) lalu tabel barang.
Uint8List excelOrder(OrderTersimpan o, KepalaDokumen k) {
  final e = Excel.createExcel();
  final awal = e.getDefaultSheet()!;
  e.rename(awal, 'Order');
  final s = e['Order'];
  var r = 0;
  _tulis(s, 0, r++, TextCellValue('SURAT PESANAN BARANG'), _gayaJudul);
  if (k.latihan) _tulis(s, 0, r++, TextCellValue(teksDokumenLatihan), _gayaJudul);
  for (final (l, v) in [
    ('Toko', '${k.namaToko} · Cabang ${k.namaCabang} (${k.kodeCabang})'),
    ('No. order', o.noOrder),
    ('Tanggal', _waktu(o.waktu)),
    ('Dibuat oleh', '${o.dibuatOleh} (${o.peranPembuat})'),
    ('Kepada', '${o.tujuan}${o.tujuanTokoUtama ? ' (toko utama)' : ''}'),
    if (o.catatan.isNotEmpty) ('Catatan', o.catatan),
  ]) {
    _tulis(s, 0, r, TextCellValue(l), _gayaTebal);
    _tulis(s, 1, r++, TextCellValue(v));
  }
  r++;
  const kepala = ['No', 'Barcode', 'Nama barang', 'Satuan', 'Jumlah', 'Diterima', 'Stok saat order'];
  for (var i = 0; i < kepala.length; i++) {
    _tulis(s, i, r, TextCellValue(kepala[i]), _gayaKepala);
  }
  r++;
  for (var i = 0; i < o.baris.length; i++) {
    final b = o.baris[i];
    _tulis(s, 0, r, IntCellValue(i + 1));
    _tulis(s, 1, r, TextCellValue(b.barcode ?? ''), _gayaTeks);
    _tulis(s, 2, r, TextCellValue(b.nama));
    _tulis(s, 3, r, TextCellValue(b.satuan));
    _tulis(s, 4, r, IntCellValue(b.jumlah));
    _tulis(s, 6, r++, IntCellValue(b.stok));
  }
  _tulis(s, 2, r, TextCellValue('Total'), _gayaTebal);
  _tulis(s, 4, r, IntCellValue(o.totalJumlah), _gayaTebal);
  for (final (i, w) in [(0, 6.0), (1, 18.0), (2, 42.0), (3, 10.0), (4, 10.0), (5, 11.0), (6, 15.0)]) {
    s.setColumnWidth(i, w);
  }
  return _simpan(e);
}

/// Template Excel impor stok awal: sheet "Stok awal" (judul kolom saja, kolom Barcode berformat Teks)
/// + sheet "Petunjuk" berisi cara mengisi, contoh, dan daftar kategori yang sudah ada.
Uint8List templateImporStok({List<String> kategori = const [], List<String> satuan = const []}) {
  final e = Excel.createExcel();
  final awal = e.getDefaultSheet()!;
  e.rename(awal, 'Stok awal');
  final s = e['Stok awal'];
  for (var i = 0; i < kolomImporStok.length; i++) {
    _tulis(s, i, 0, TextCellValue(kolomImporStok[i]), i == 0 ? _gayaKepalaTeks : _gayaKepala);
  }
  // Kolom Barcode berformat Teks supaya angka 0 di depan dan barcode panjang tidak berubah.
  for (var r = 1; r <= 500; r++) {
    _tulis(s, 0, r, null, _gayaTeks);
  }
  for (final (i, w) in [(0, 18.0), (1, 40.0), (2, 18.0), (3, 10.0), (4, 10.0), (5, 18.0), (6, 14.0)]) {
    s.setColumnWidth(i, w);
  }

  final p = e['Petunjuk'];
  var r = 0;
  _tulis(p, 0, r++, TextCellValue('CARA MENGISI TEMPLATE STOK AWAL'), _gayaJudul);
  for (final t in [
    'Isi di sheet "Stok awal", mulai baris 2. Satu baris = satu barang. Jangan mengubah baris judul.',
    'Barcode: boleh kosong untuk barang tanpa barcode. Kalau barcode sudah ada di program, barang itu dipakai (nama, kategori, satuan tidak diubah).',
    'Nama barang, Kategori, Satuan: wajib untuk barang baru. Kategori harus sama dengan daftar di bawah, atau ditambahkan saat impor (SPV/Admin).',
    'Jumlah: stok yang ada sekarang, bilangan bulat lebih dari 0.',
    'HPP (harga beli) per satuan dan Harga jual: angka rupiah tanpa koma, mis. 17500 atau 17.500. Harga jual harus lebih besar dari HPP.',
    'Simpan file, lalu di program: Barang masuk → Impor stok awal → Pilih file. Periksa pratinjau sebelum menyimpan.',
  ]) {
    _tulis(p, 0, r++, TextCellValue('• $t'));
  }
  r++;
  _tulis(p, 0, r++, TextCellValue('Contoh isian (data contoh, jangan disalin):'), _gayaTebal);
  for (var i = 0; i < kolomImporStok.length; i++) {
    _tulis(p, i, r, TextCellValue(kolomImporStok[i]), _gayaKepala);
  }
  r++;
  for (final row in const [
    ['8990000000017', 'Contoh Barang A 1 kg', 'Contoh Kategori', 'pak', 20, 16000, 17500],
    ['', 'Contoh Barang B (tanpa barcode)', 'Contoh Kategori', 'pcs', 5, 2500, 3000],
  ]) {
    for (var i = 0; i < row.length; i++) {
      final v = row[i];
      _tulis(p, i, r, v is int ? IntCellValue(v) : TextCellValue('$v'), i == 0 ? _gayaTeks : null);
    }
    r++;
  }
  if (kategori.isNotEmpty) {
    r++;
    _tulis(p, 0, r++, TextCellValue('Kategori yang sudah ada:'), _gayaTebal);
    for (final k in kategori) {
      _tulis(p, 0, r++, TextCellValue(k));
    }
  }
  if (satuan.isNotEmpty) {
    r++;
    _tulis(p, 0, r++, TextCellValue('Satuan yang biasa dipakai: ${satuan.join(', ')}'), _gayaTebal);
  }
  p.setColumnWidth(0, 18);
  p.setColumnWidth(1, 36);
  e.setDefaultSheet('Stok awal');
  return _simpan(e);
}

/// Nilai polos sel Excel (teks, int, double, null) untuk dibaca pos_core.
Object? _nilaiSel(Data? d) {
  final v = d?.value;
  return switch (v) {
    null => null,
    TextCellValue() => v.value.toString(),
    IntCellValue() => v.value,
    DoubleCellValue() => v.value,
    BoolCellValue() => '${v.value}',
    FormulaCellValue() => v.formula, // rumus tidak dihitung; sel berisi rumus akan ditandai salah
    _ => v.toString(),
  };
}

/// Baca file Excel (.xlsx) impor stok awal. Memakai sheet "Stok awal" kalau ada, kalau tidak sheet pertama.
/// Melempar [FormatException] dengan pesan yang dimengerti pengguna kalau file tidak bisa dibaca.
List<BarisImporStok> bacaExcelImporStok(Uint8List byte) {
  final Excel e;
  try {
    e = Excel.decodeBytes(byte);
  } catch (_) {
    throw const FormatException('File tidak bisa dibaca. Pastikan file Excel berformat .xlsx (Simpan Sebagai → Excel Workbook).');
  }
  final nama = e.tables.keys.firstWhere((n) => n.toLowerCase() == 'stok awal', orElse: () => e.tables.keys.isEmpty ? '' : e.tables.keys.first);
  final sheet = e.tables[nama];
  if (sheet == null) throw const FormatException('File Excel kosong.');
  final baris = [for (final r in sheet.rows) [for (final d in r) _nilaiSel(d)]];
  return bacaSheetImporStok(baris);
}
