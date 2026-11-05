import 'package:flutter/material.dart';
import 'package:pos_core/pos_core.dart';

import '../../layanan/aplikasi.dart';
import '../komponen/kerangka.dart';
import '../komponen/umum.dart';
import '../tema.dart';

/// Menu ikon SPV/Admin (pengganti menu samping): ringkasan hari ini, ikon menu per kelompok, hal yang perlu dicek.
class MenuBeranda extends StatelessWidget {
  const MenuBeranda({super.key, required this.onMenu});
  final BukaMenu onMenu;

  @override
  Widget build(BuildContext context) {
    final app = AplikasiScope.of(context, dengar: true);
    final p = app.penggunaAktif!;
    final c = app.cabang;
    final (dari, sampai) = Periode.hariIni.rentang(DateTime.now());
    final r = app.laporan.ringkasan(c.id, dari, sampai);
    final cek = app.laporan.perluDicek(c.id, dari, sampai);
    final menipis = app.katalog.stokMenipis(c.id).length;
    final antreanLabel = app.harga.antreanLabel().length;

    Widget itemCek(String judul, String isi, {required bool penting, required MenuAdmin ke}) => InkWell(
          onTap: () => onMenu(ke),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Row(children: [
              Icon(penting ? Icons.error : Icons.info, color: penting ? Warna.merah : Warna.oranyeTegas, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(judul, style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800, color: penting ? Warna.merah : Warna.oranyeTua)),
                  Text(isi, style: const TextStyle(fontSize: 14.5, color: Warna.teksPudar)),
                ]),
              ),
              const Icon(Icons.chevron_right, color: Warna.teksPudar),
            ]),
          ),
        );

    final daftarCek = <Widget>[
      if (cek.batal > 0) itemCek('${cek.batal} transaksi dibatalkan', 'Lihat di Log aktivitas', penting: true, ke: MenuAdmin.log),
      if (cek.terkunci > 0 && MenuAdmin.karyawan.bolehUntuk(p.peran))
        itemCek('${cek.terkunci} akun terkunci', 'Salah PIN 5 kali · buka di Karyawan', penting: true, ke: MenuAdmin.karyawan),
      if (cek.koreksiMenunggu > 0) itemCek('${cek.koreksiMenunggu} koreksi barang masuk', 'Menunggu persetujuan', penting: false, ke: MenuAdmin.koreksi),
      if (menipis > 0) itemCek('$menipis barang stok hampir habis', 'Buka Produk & stok', penting: false, ke: MenuAdmin.produk),
      if (cek.selisihKas > 0) itemCek('${cek.selisihKas} shift dengan selisih kas', 'Lihat di Log aktivitas', penting: false, ke: MenuAdmin.log),
      if (antreanLabel > 0) itemCek('$antreanLabel label rak perlu dicetak ulang', 'Buka Ubah harga', penting: false, ke: MenuAdmin.ubahHarga),
    ];

    Widget ubin(MenuAdmin m, {String? lencana}) => UbinMenu(
          ikon: m.ikon,
          label: m.label,
          warna: m.warna,
          latar: m.latar,
          lencana: lencana,
          utama: m == MenuAdmin.penjualan,
          onTap: () => onMenu(m),
        );

    List<Widget> grup(GrupAdmin g) => [
          for (final m in MenuAdmin.values)
            if (m != MenuAdmin.beranda && m.grup == g && m.bolehUntuk(p.peran))
              ubin(m,
                  lencana: switch (m) {
                    MenuAdmin.koreksi when cek.koreksiMenunggu > 0 => '${cek.koreksiMenunggu}',
                    MenuAdmin.produk when menipis > 0 => '$menipis menipis',
                    MenuAdmin.ubahHarga when antreanLabel > 0 => '$antreanLabel label',
                    MenuAdmin.karyawan when cek.terkunci > 0 => '${cek.terkunci} terkunci',
                    _ => null,
                  }),
        ];

    return Scaffold(
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        BarKepala(
          judul: c.namaToko,
          sub: 'Cabang ${c.nama} · ${c.kode}',
          nama: '${p.nama} (${p.peran.label})',
          keterangan: formatLayar(DateTime.now()),
          onKeluar: app.keluar,
        ),
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(28, 18, 28, 24), children: [
            for (final w in app.peringatan) ...[KotakPesan(w, jenis: JenisPesan.perhatian), const SizedBox(height: 12)],
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: KartuAngka(label: 'Penjualan hari ini', nilai: formatRupiah(r.penjualanBersih), aksen: Warna.sukses, ikon: Icons.payments)),
              const SizedBox(width: 14),
              Expanded(child: KartuAngka(label: 'Transaksi', nilai: '${r.jumlahTransaksi}', aksen: Warna.utama, ikon: Icons.receipt_long)),
              const SizedBox(width: 14),
              Expanded(child: KartuAngka(label: 'Laba kotor', nilai: formatRupiah(r.labaKotor), aksen: Warna.ungu, ikon: Icons.trending_up)),
              const SizedBox(width: 14),
              Expanded(
                child: KartuAngka(
                  label: 'Perlu dicek',
                  nilai: daftarCek.isEmpty ? 'Tidak ada' : '${daftarCek.length} hal',
                  warna: daftarCek.isEmpty ? Warna.teks : Warna.lencanaOranye,
                  aksen: daftarCek.isEmpty ? Warna.abuIkon : Warna.lencanaOranye,
                  ikon: daftarCek.isEmpty ? Icons.check_circle_outline : Icons.warning_amber_rounded,
                ),
              ),
            ]),
            const SizedBox(height: 16),
            Wrap(spacing: 16, runSpacing: 16, crossAxisAlignment: WrapCrossAlignment.start, children: [
              GrupMenu(judul: 'PENJUALAN', warna: Warna.utama, latar: const Color(0xFFF2F8FF), ubin: grup(GrupAdmin.penjualan)),
              GrupMenu(judul: 'BARANG & HARGA', warna: Warna.toska, latar: const Color(0xFFF0FAFA), ubin: grup(GrupAdmin.barang)),
              GrupMenu(judul: 'LAPORAN & PENGATURAN', warna: Warna.abuIkon, latar: const Color(0xFFF5F7FA), ubin: grup(GrupAdmin.laporan)),
              if (daftarCek.isNotEmpty)
                SizedBox(
                  width: 420,
                  child: Panel(
                    judul: 'Perlu dicek',
                    warnaKepala: Warna.oranyeMuda,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: daftarCek),
                  ),
                ),
            ]),
          ]),
        ),
      ]),
    );
  }
}
