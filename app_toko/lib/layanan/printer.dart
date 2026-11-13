import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// Kirim byte ESC/POS mentah ke printer struk.
abstract class LayananPrinter {
  /// Nama printer yang terpasang di komputer.
  List<String> daftarPrinter();

  /// Printer bawaan Windows (null kalau tidak ada).
  String? printerBawaan();

  /// Kirim [data] apa adanya (RAW) ke printer [nama]. Melempar [PrinterGagal] kalau gagal.
  Future<void> cetak(String nama, Uint8List data, {String judul = 'Struk POS'});

  static LayananPrinter untukSistemIni() => Platform.isWindows ? PrinterWindows() : PrinterBerkas();
}

class PrinterGagal implements Exception {
  PrinterGagal(this.pesan);
  final String pesan;
  @override
  String toString() => pesan;
}

// ---------------------------------------------------------------------------- Windows (winspool.drv)

final class _DocInfo1 extends Struct {
  external Pointer<Utf16> pDocName;
  external Pointer<Utf16> pOutputFile;
  external Pointer<Utf16> pDatatype;
}

final class _PrinterInfo4 extends Struct {
  external Pointer<Utf16> pPrinterName;
  external Pointer<Utf16> pServerName;
  @Uint32()
  external int attributes;
}

typedef _OpenPrinterC = Int32 Function(Pointer<Utf16>, Pointer<Pointer<Void>>, Pointer<Void>);
typedef _OpenPrinterD = int Function(Pointer<Utf16>, Pointer<Pointer<Void>>, Pointer<Void>);
typedef _StartDocC = Uint32 Function(Pointer<Void>, Uint32, Pointer<_DocInfo1>);
typedef _StartDocD = int Function(Pointer<Void>, int, Pointer<_DocInfo1>);
typedef _HandleC = Int32 Function(Pointer<Void>);
typedef _HandleD = int Function(Pointer<Void>);
typedef _WriteC = Int32 Function(Pointer<Void>, Pointer<Uint8>, Uint32, Pointer<Uint32>);
typedef _WriteD = int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Uint32>);
typedef _EnumC = Int32 Function(Uint32, Pointer<Utf16>, Uint32, Pointer<Uint8>, Uint32, Pointer<Uint32>, Pointer<Uint32>);
typedef _EnumD = int Function(int, Pointer<Utf16>, int, Pointer<Uint8>, int, Pointer<Uint32>, Pointer<Uint32>);
typedef _DefaultC = Int32 Function(Pointer<Utf16>, Pointer<Uint32>);
typedef _DefaultD = int Function(Pointer<Utf16>, Pointer<Uint32>);

const _printerEnumLocal = 0x2;
const _printerEnumConnections = 0x4;

class PrinterWindows implements LayananPrinter {
  static DynamicLibrary get _lib => DynamicLibrary.open('winspool.drv');

  @override
  List<String> daftarPrinter() {
    final enumPrinters = _lib.lookupFunction<_EnumC, _EnumD>('EnumPrintersW');
    final perlu = calloc<Uint32>();
    final jumlah = calloc<Uint32>();
    try {
      const flags = _printerEnumLocal | _printerEnumConnections;
      enumPrinters(flags, nullptr, 4, nullptr, 0, perlu, jumlah);
      if (perlu.value == 0) return [];
      final buf = calloc<Uint8>(perlu.value);
      try {
        if (enumPrinters(flags, nullptr, 4, buf, perlu.value, perlu, jumlah) == 0) return [];
        final info = buf.cast<_PrinterInfo4>();
        return [
          for (var i = 0; i < jumlah.value; i++) (info + i).ref.pPrinterName.toDartString(),
        ]..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      } finally {
        calloc.free(buf);
      }
    } finally {
      calloc.free(perlu);
      calloc.free(jumlah);
    }
  }

  @override
  String? printerBawaan() {
    final getDefault = _lib.lookupFunction<_DefaultC, _DefaultD>('GetDefaultPrinterW');
    final panjang = calloc<Uint32>();
    try {
      getDefault(nullptr, panjang);
      if (panjang.value == 0) return null;
      final buf = calloc<Uint16>(panjang.value).cast<Utf16>();
      try {
        return getDefault(buf, panjang) == 0 ? null : buf.toDartString();
      } finally {
        calloc.free(buf);
      }
    } finally {
      calloc.free(panjang);
    }
  }

  @override
  Future<void> cetak(String nama, Uint8List data, {String judul = 'Struk POS'}) async {
    final galat = await Isolate.run(() => _cetakRaw(nama, data, judul));
    if (galat != null) throw PrinterGagal(galat);
  }

  /// Dijalankan di isolate terpisah supaya layar tidak macet. Mengembalikan pesan galat atau null.
  static String? _cetakRaw(String nama, Uint8List data, String judul) {
    final lib = _lib;
    final openPrinter = lib.lookupFunction<_OpenPrinterC, _OpenPrinterD>('OpenPrinterW');
    final startDoc = lib.lookupFunction<_StartDocC, _StartDocD>('StartDocPrinterW');
    final startPage = lib.lookupFunction<_HandleC, _HandleD>('StartPagePrinter');
    final writePrinter = lib.lookupFunction<_WriteC, _WriteD>('WritePrinter');
    final endPage = lib.lookupFunction<_HandleC, _HandleD>('EndPagePrinter');
    final endDoc = lib.lookupFunction<_HandleC, _HandleD>('EndDocPrinter');
    final closePrinter = lib.lookupFunction<_HandleC, _HandleD>('ClosePrinter');

    final pNama = nama.toNativeUtf16();
    final pJudul = judul.toNativeUtf16();
    final pTipe = 'RAW'.toNativeUtf16();
    final pHandle = calloc<Pointer<Void>>();
    final doc = calloc<_DocInfo1>();
    final buf = calloc<Uint8>(data.length);
    final tertulis = calloc<Uint32>();
    try {
      if (openPrinter(pNama, pHandle, nullptr) == 0) return 'Printer "$nama" tidak ditemukan atau tidak bisa dibuka.';
      final h = pHandle.value;
      try {
        doc.ref
          ..pDocName = pJudul
          ..pOutputFile = nullptr
          ..pDatatype = pTipe;
        if (startDoc(h, 1, doc) == 0) return 'Printer menolak dokumen. Cek driver printer (harus mendukung RAW).';
        try {
          if (startPage(h) == 0) return 'Gagal memulai halaman cetak.';
          buf.asTypedList(data.length).setAll(0, data);
          final ok = writePrinter(h, buf, data.length, tertulis);
          endPage(h);
          if (ok == 0 || tertulis.value != data.length) return 'Data tidak terkirim penuh ke printer.';
        } finally {
          endDoc(h);
        }
      } finally {
        closePrinter(h);
      }
      return null;
    } finally {
      calloc
        ..free(pNama)
        ..free(pJudul)
        ..free(pTipe)
        ..free(pHandle)
        ..free(doc)
        ..free(buf)
        ..free(tertulis);
    }
  }
}

// ---------------------------------------------------------------------------- selain Windows

/// Untuk komputer pengembang selain Windows: struk disimpan sebagai file di folder sementara.
class PrinterBerkas implements LayananPrinter {
  String? terakhir;

  @override
  List<String> daftarPrinter() => const ['Simpan ke file (uji coba)'];

  @override
  String? printerBawaan() => daftarPrinter().first;

  @override
  Future<void> cetak(String nama, Uint8List data, {String judul = 'Struk POS'}) async {
    final f = File('${Directory.systemTemp.path}/struk-${DateTime.now().millisecondsSinceEpoch}.bin');
    await f.writeAsBytes(data);
    terakhir = f.path;
  }
}
