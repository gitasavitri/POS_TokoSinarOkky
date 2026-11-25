import 'package:pos_core/pos_core.dart';
import 'package:test/test.dart';

void main() {
  group('saran order (revisi G)', () {
    test('stok minimum diatur: isi sampai 2x stok minimum kalau stok <= minimum', () {
      expect(saranOrder(stok: 3, stokMinimum: 10), 17);
      expect(saranOrder(stok: 10, stokMinimum: 10), 10);
      expect(saranOrder(stok: 0, stokMinimum: 5), 10);
      expect(saranOrder(stok: -2, stokMinimum: 5), 12);
      expect(saranOrder(stok: 11, stokMinimum: 10), 0, reason: 'stok masih di atas minimum');
    });

    test('stok minimum belum diatur: hanya menutup stok minus', () {
      expect(saranOrder(stok: 0, stokMinimum: 0), 0);
      expect(saranOrder(stok: 5, stokMinimum: 0), 0);
      expect(saranOrder(stok: -3, stokMinimum: 0), 3);
    });

    test('perlu order = habis atau hampir habis', () {
      expect(perluOrder(stok: 0, stokMinimum: 0), isTrue);
      expect(perluOrder(stok: 4, stokMinimum: 5), isTrue);
      expect(perluOrder(stok: 6, stokMinimum: 5), isFalse);
      expect(perluOrder(stok: 6, stokMinimum: 0), isFalse);
    });

    test('tombol (+): pakai saran, kalau tidak ada 1', () {
      expect(jumlahAwalOrder(stok: 2, stokMinimum: 6), 10);
      expect(jumlahAwalOrder(stok: 0, stokMinimum: 0), 1);
      expect(jumlahAwalOrder(stok: 50, stokMinimum: 6), 1);
    });
  });

  group('nomor order', () {
    test('ORD-<kode>-<YYMMDD WIB>-<urut 4 digit>', () {
      // 11 Nov 2026 20.00 UTC = 12 Nov 2026 03.00 WIB
      final w = DateTime.utc(2026, 11, 11, 20);
      expect(nomorOrder(kodeCabang: 'A01', waktu: w, urut: 7), 'ORD-A01-261112-0007');
      expect(awalanNomorOrder('A01', w), 'ORD-A01-261112-');
      expect(() => nomorOrder(kodeCabang: 'A01', waktu: w, urut: 0), throwsRangeError);
      expect(() => nomorOrder(kodeCabang: 'A01', waktu: w, urut: 10000), throwsRangeError);
    });
  });

  group('daftar order', () {
    BarisOrder b(String id, int n) => BarisOrder(barangId: id, nama: 'Barang $id', satuan: 'pcs', jumlah: n);

    test('tambah barang yang sama menambah jumlah; jumlah <= 0 menghapus', () {
      final d = DaftarOrder()
        ..tambah(b('x', 5))
        ..tambah(b('y', 2))
        ..tambah(b('x', 3));
      expect(d.jumlahJenis, 2);
      expect(d.cari('x')!.jumlah, 8);
      expect(d.totalJumlah, 10);
      d.aturJumlah('y', 0);
      expect(d.cari('y'), isNull);
      d.aturJumlah('x', maksJumlahOrder + 50);
      expect(d.cari('x')!.jumlah, maksJumlahOrder);
    });

    test('periksa: kosong / belum pilih tujuan ditolak', () {
      final d = DaftarOrder();
      expect(d.periksa(), contains('kosong'));
      d.tambah(b('x', 1));
      expect(d.periksa(), contains('Order ke'));
      d.supplierId = 's1';
      expect(d.periksa(), isNull);
    });

    test('simpan & muat ulang draft (JSON)', () {
      final d = DaftarOrder(supplierId: 's1', catatan: 'kirim Senin')..tambah(BarisOrder(barangId: 'x', nama: 'Gula', satuan: 'pak', barcode: '899', jumlah: 4, stok: 1, stokMinimum: 3));
      final e = DaftarOrder.dariJson(d.keJson());
      expect(e.supplierId, 's1');
      expect(e.catatan, 'kirim Senin');
      expect(e.baris.single.barcode, '899');
      expect(e.baris.single.jumlah, 4);
      expect(e.baris.single.stokMinimum, 3);
    });
  });

  group('impor stok awal: baca sel (revisi J)', () {
    test('angka: angka Excel, teks biasa, format rupiah', () {
      expect(bacaBilanganBulat(17500).nilai, 17500);
      expect(bacaBilanganBulat(17500.0).nilai, 17500);
      expect(bacaBilanganBulat('17500').nilai, 17500);
      expect(bacaBilanganBulat('17.500').nilai, 17500);
      expect(bacaBilanganBulat('Rp 1.250.000').nilai, 1250000);
      expect(bacaBilanganBulat('Rp17.500,00').nilai, 17500);
      expect(bacaBilanganBulat(' 12 ').nilai, 12);
      expect(bacaBilanganBulat(null).kosong, isTrue);
      expect(bacaBilanganBulat('').kosong, isTrue);
    });

    test('angka: pecahan dan teks ditolak', () {
      expect(bacaBilanganBulat(1.5).salah, isNotNull);
      expect(bacaBilanganBulat('17,5').salah, isNotNull);
      expect(bacaBilanganBulat('17.50').salah, isNotNull, reason: 'titik bukan pemisah ribuan yang benar');
      expect(bacaBilanganBulat('dua').salah, isNotNull);
    });

    test('barcode: angka Excel diubah jadi teks; notasi E ditolak', () {
      expect(bacaBarcode(8991234567890.0).$1, '8991234567890');
      expect(bacaBarcode(8991234567890).$1, '8991234567890');
      expect(bacaBarcode(' 0089 ').$1, '0089');
      expect(bacaBarcode('8.99123E+12').$2, isNotNull);
      expect(bacaBarcode(null).$1, '');
    });

    test('baris lengkap terbaca; satuan huruf kecil; baris kosong dilewati', () {
      final b = bacaBarisImporStok(2, ['899', ' Gula  Pasir 1 kg ', 'Sembako', 'PAK', 20, '16.200', 17500])!;
      expect(b.salah, isEmpty);
      expect(b.nama, 'Gula Pasir 1 kg');
      expect(b.satuan, 'pak');
      expect((b.jumlah, b.hpp, b.hargaJual), (20, 16200, 17500));
      expect(bacaBarisImporStok(3, [null, '', ' ', null]), isNull);
    });

    test('baris salah ditandai: jumlah 0, HPP minus, harga <= HPP, kolom kosong', () {
      expect(bacaBarisImporStok(2, ['', 'A', 'K', 'pcs', 0, 100, 200])!.salah.single, contains('Jumlah'));
      expect(bacaBarisImporStok(2, ['', 'A', 'K', 'pcs', 1, -1, 200])!.salah.single, contains('HPP'));
      expect(bacaBarisImporStok(2, ['', 'A', 'K', 'pcs', 1, 200, 200])!.salah.single, contains('lebih besar dari HPP'));
      expect(bacaBarisImporStok(2, ['', 'A', 'K', 'pcs', 1])!.salah, hasLength(2));
    });

    test('sheet: baris judul dicari otomatis, nomor baris sesuai Excel', () {
      final sheet = <List<Object?>>[
        ['STOK AWAL TOKO'],
        kolomImporStok,
        ['1', 'A', 'K', 'pcs', 1, 1, 2],
        [],
        ['2', 'B', 'K', 'pcs', 1, 1, 2],
      ];
      final hasil = bacaSheetImporStok(sheet);
      expect(hasil.map((b) => b.nomorBaris), [3, 5]);
      expect(bacaSheetImporStok([['1', 'A', 'K', 'pcs', 1, 1, 2]]).single.nomorBaris, 1, reason: 'tanpa baris judul');
    });
  });

  group('akses tahap 4', () {
    test('order: semua peran; impor stok awal & mode latihan: SPV/Admin', () {
      for (final p in Peran.values) {
        expect(aksesUntuk(p, Izin.buatOrder), Akses.ya);
      }
      expect(aksesUntuk(Peran.kasir, Izin.imporStokAwal), Akses.tidak);
      expect(aksesUntuk(Peran.spv, Izin.imporStokAwal), Akses.ya);
      expect(aksesUntuk(Peran.admin, Izin.imporStokAwal), Akses.ya);
      expect(aksesUntuk(Peran.kasir, Izin.nyalakanLatihan), Akses.tidak);
      expect(aksesUntuk(Peran.spv, Izin.nyalakanLatihan), Akses.ya);
    });
  });

  group('struk mode latihan', () {
    final d = DataStruk(
      namaToko: 'Toko Contoh',
      namaCabang: 'Contoh',
      alamat: '',
      noTransaksi: 'TRX-A01-261111-0001',
      waktu: DateTime.utc(2026, 11, 11, 3),
      namaKasir: 'Kasir Contoh',
      item: const [ItemStruk(nama: 'Barang contoh', qty: 1, hargaSatuan: 1000, isGrosir: false)],
      metode: MetodeBayar.tunai,
      diterima: 1000,
      kembalian: 0,
    );

    test('tulisan LATIHAN di atas & bawah, muat 32 karakter', () {
      final b = tandaiLatihan(susunStruk(d));
      expect(b.first.teks, teksStrukLatihan);
      expect(b.last.teks, teksStrukLatihan);
      expect(teksStrukLatihan.length, lessThanOrEqualTo(lebarStruk));
    });

    test('struk latihan tanpa barcode (supaya tidak bisa di-scan untuk retur di data asli)', () {
      final asli = cetakStruk(d);
      final latihan = cetakStruk(d, latihan: true);
      bool adaBarcode(List<int> b) {
        for (var i = 0; i + 1 < b.length; i++) {
          if (b[i] == 0x1D && b[i + 1] == 0x6B) return true; // GS k
        }
        return false;
      }

      expect(adaBarcode(asli), isTrue);
      expect(adaBarcode(latihan), isFalse);
      expect(String.fromCharCodes(latihan), contains(teksStrukLatihan));
    });
  });
}
