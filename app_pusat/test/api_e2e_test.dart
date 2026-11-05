// Uji ApiHttp melawan Server Pusat sungguhan. Hanya jalan kalau diisi:
//   POS_SERVER_UJI  mis. http://127.0.0.1:3999
//   POS_ADMIN_UJI   nama_pengguna:sandi:rahasia_totp  (akun Admin pusat KHUSUS UJI, bukan akun asli)

import 'dart:io';

import 'package:app_pusat/data/api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_core/pos_core.dart';

void main() {
  final server = Platform.environment['POS_SERVER_UJI'];
  final admin = Platform.environment['POS_ADMIN_UJI']?.split(':');

  test('Aplikasi Pusat ⇄ Server Pusat', () async {
    final dasar = KlienServer.periksaAlamat(server!);
    await ApiHttp.cekServer(dasar);
    final api = ApiHttp(dasar);

    await expectLater(api.masuk(admin![0], admin[1], '000000'), throwsA(isA<GalatServer>().having((e) => e.status, 'status', 401)));
    final a = await api.masuk(admin[0], admin[1], await kodeTotp(admin[2], DateTime.now()));
    expect(a.nama, isNotEmpty);

    final (dari, sampai) = (DateTime.now().subtract(const Duration(days: 30)), DateTime.now().add(const Duration(days: 1)));
    final r = await api.ringkasan(dari, sampai);
    expect(r.total.penjualanBersih, r.perCabang.fold<int>(0, (s, c) => s + c.penjualanBersih));
    final harian = await api.penjualanHarian(dari, sampai);
    expect(harian.values.fold<int>(0, (s, v) => s + v), r.total.penjualanBersih + r.total.totalRetur);
    expect(await api.transaksi(dari, sampai), hasLength(r.total.jumlahTransaksi + r.total.jumlahBatal));

    final cabang = await api.cabang();
    expect(cabang, isNotEmpty, reason: 'jalankan uji ujung-ke-ujung app_toko dulu supaya ada toko');
    await api.stok(cabang.first.id);
    await api.karyawan();
    await api.log(dari, sampai);
    await api.perangkat();
    final (kode, _) = await api.buatKodePendaftaran();
    expect(kode, matches(RegExp(r'^[A-Z2-9]{5}-[A-Z2-9]{5}$')));

    final barang = (await api.barang()).firstWhere((b) => b.hppTertinggi != null);
    final eceran = barang.hppTertinggi! + 2000;
    await expectLater(
      api.ubahHarga(barangId: barang.id, eceran: eceran, grosir: [TingkatGrosir(minQty: 10, harga: barang.hppTertinggi!)], alasan: 'uji'),
      throwsA(isA<GalatServer>().having((e) => e.pesan, 'pesan', contains('HPP'))),
    );
    await api.ubahHarga(barangId: barang.id, eceran: eceran, grosir: [TingkatGrosir(minQty: 10, harga: eceran - 500)], alasan: 'uji');
    final sesudah = (await api.barang(kata: barang.nama)).firstWhere((b) => b.id == barang.id);
    expect(sesudah.harga!.eceran, eceran);
    expect(sesudah.harga!.grosir.single, TingkatGrosir(minQty: 10, harga: eceran - 500));

    await api.keluar();
    await expectLater(api.cabang(), throwsA(isA<GalatServer>().having((e) => e.status, 'status', 401)));
  }, skip: server == null || admin == null || admin.length != 3 ? 'POS_SERVER_UJI / POS_ADMIN_UJI tidak diisi' : false);
}
