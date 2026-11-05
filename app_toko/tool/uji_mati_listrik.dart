// Uji "mati listrik": proses penulis dimatikan paksa (kill -9) di tengah penjualan, lalu database dicek.
//
//   dart run tool/uji_mati_listrik.dart tulis <file.db>   # jualan terus-menerus sampai dimatikan
//   dart run tool/uji_mati_listrik.dart cek <file.db>     # cek keutuhan; keluar kode 1 kalau ada yang rusak
//
// Catatan: kill -9 mematikan program, bukan listrik. Ketahanan terhadap listrik padam bergantung juga pada
// PRAGMA synchronous = FULL (data benar-benar ditulis ke disk sebelum transaksi dianggap selesai).
import 'dart:convert';
import 'dart:io';

import 'package:app_toko/data/database.dart';
import 'package:app_toko/data/model.dart';
import 'package:app_toko/data/repo/barang_masuk_repo.dart';
import 'package:app_toko/data/repo/katalog_repo.dart';
import 'package:app_toko/data/repo/pengaturan_repo.dart';
import 'package:app_toko/data/repo/pengguna_repo.dart';
import 'package:app_toko/data/repo/penjualan_repo.dart';
import 'package:app_toko/data/repo/setup_repo.dart';
import 'package:pos_core/pos_core.dart';

Future<void> main(List<String> arg) async {
  final db = DatabaseToko.buka(arg[1]);
  if (arg[0] == 'cek') exit(cek(db));

  if (!PengaturanRepo(db).sudahDisiapkan) {
    await SetupRepo(db).siapkan(
      namaToko: 'TOKO CONTOH', kodeCabang: 'U01', namaCabang: 'Uji', alamat: 'Jl. Contoh', pesanStruk: '',
      namaAdmin: 'Admin Uji', namaPenggunaAdmin: 'admin.uji', sandiAdmin: 'sandi-panjang-1',
      rahasiaTotp: base32Encode(ascii.encode('12345678901234567890')), pinAdmin: '908172',
    );
    final c = PengaturanRepo(db).infoCabang()!;
    final admin = PenggunaRepo(db).semua(c.id).first;
    BarangMasukRepo(db).kirim(cabang: c, oleh: admin, draft: DraftBarangMasuk(supplierId: idSupplierTokoUtama, noFaktur: 'F-UJI', item: [
      for (var i = 0; i < 5; i++)
        DraftItemMasuk(barcode: '89900$i', nama: 'Barang $i', kategoriId: kategoriAwal['Sembako']!, satuan: 'pcs', jumlah: 100000, hpp: 1000 + i, hargaJual: 1500 + i),
    ]));
  }
  final c = PengaturanRepo(db).infoCabang()!;
  final kasir = PenggunaRepo(db).semua(c.id).first;
  final jual = PenjualanRepo(db);
  final katalog = KatalogRepo(db);
  final shift = jual.shiftAktif(kasir.id) ?? jual.bukaShift(cabangId: c.id, kasirId: kasir.id, modalAwal: 0);
  for (var n = 0;; n++) {
    final k = Keranjang();
    for (var i = 0; i < 5; i++) {
      k.tambah(katalog.untukKasirBarcode('89900$i', c.id)!, qty: 1 + (n + i) % 12);
    }
    jual.simpan(cabang: c, kasir: kasir, shift: shift, keranjang: k, metode: MetodeBayar.tunai, uangDiterima: k.total);
  }
}

int cek(DatabaseToko db) {
  final masalah = <String>[];
  final integritas = db.pilih('PRAGMA integrity_check').map((r) => r.values.first).toList();
  if (integritas.length != 1 || integritas.first != 'ok') masalah.add('integrity_check: $integritas');
  final fk = db.pilih('PRAGMA foreign_key_check');
  if (fk.isNotEmpty) masalah.add('foreign_key_check: ${fk.length} baris');
  final trx = db.satu('SELECT COUNT(*) AS n FROM transaksi')!['n'] as int;
  final tanpaBayar = db.satu('SELECT COUNT(*) AS n FROM transaksi t WHERE NOT EXISTS (SELECT 1 FROM pembayaran p WHERE p.transaksi_id = t.id)')!['n'] as int;
  final totalSalah = db.satu(
      'SELECT COUNT(*) AS n FROM transaksi t WHERE t.total <> (SELECT IFNULL(SUM(subtotal),0) FROM transaksi_item i WHERE i.transaksi_id = t.id)')!['n'] as int;
  final stokSalah = db.satu(
      "SELECT COUNT(*) AS n FROM transaksi t WHERE (SELECT IFNULL(SUM(qty),0) FROM transaksi_item i WHERE i.transaksi_id = t.id) <> "
      "-(SELECT IFNULL(SUM(jumlah),0) FROM mutasi_stok m WHERE m.ref_id = t.id AND m.jenis = 'jual')")!['n'] as int;
  final outboxKurang = db.satu("SELECT COUNT(*) AS n FROM transaksi t WHERE NOT EXISTS (SELECT 1 FROM outbox o WHERE o.tabel = 'transaksi' AND o.baris_id = t.id)")!['n'] as int;
  final nomorKembar = db.satu('SELECT COUNT(*) - COUNT(DISTINCT no_transaksi) AS n FROM transaksi')!['n'] as int;
  if (tanpaBayar > 0) masalah.add('$tanpaBayar transaksi tanpa pembayaran');
  if (totalSalah > 0) masalah.add('$totalSalah transaksi total ≠ jumlah item');
  if (stokSalah > 0) masalah.add('$stokSalah transaksi stok tidak cocok');
  if (outboxKurang > 0) masalah.add('$outboxKurang transaksi tidak masuk antrean kirim');
  if (nomorKembar > 0) masalah.add('$nomorKembar nomor transaksi kembar');
  stdout.writeln(masalah.isEmpty ? 'UTUH: $trx transaksi, semua lengkap' : 'RUSAK: ${masalah.join('; ')}');
  db.tutup();
  return masalah.isEmpty ? 0 : 1;
}
