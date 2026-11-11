import 'package:flutter/material.dart';
import 'package:pos_core/pos_core.dart';

import '../../data/model.dart';
import '../../layanan/aplikasi.dart';
import '../komponen/pin.dart';
import '../komponen/umum.dart';
import '../tema.dart';

/// Barang dari transaksi yang dibatalkan untuk dibuat ulang di layar Transaksi ("ubah transaksi", revisi E).
typedef IsiUlang = List<({String barangId, int qty})>;

/// Daftar transaksi hari ini dari layar kasir (F9): klik untuk detail, cetak ulang, batalkan.
/// Mengembalikan [IsiUlang] kalau kasir memilih "Ubah transaksi".
class DialogTransaksiTerakhir extends StatefulWidget {
  const DialogTransaksiTerakhir({super.key});
  @override
  State<DialogTransaksiTerakhir> createState() => _DialogTransaksiTerakhirState();
}

class _DialogTransaksiTerakhirState extends State<DialogTransaksiTerakhir> {
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Transaksi hari ini', style: TextStyle(fontWeight: FontWeight.w800)),
    contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
    content: SizedBox(width: 960, height: 560, child: DaftarRiwayatTransaksi(bisaIsiUlang: true, onIsiUlang: (isi) => Navigator.pop(context, isi))),
    actions: [OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Tutup'))],
  );
}

/// Cari transaksi (scan barcode di struk / ketik nomor) + daftar transaksi hari ini di toko ini.
/// Dipakai di F9 layar kasir dan menu kasir "Cetak ulang struk".
class DaftarRiwayatTransaksi extends StatefulWidget {
  const DaftarRiwayatTransaksi({super.key, this.bisaIsiUlang = false, this.onIsiUlang});
  final bool bisaIsiUlang;
  final ValueChanged<IsiUlang>? onIsiUlang;
  @override
  State<DaftarRiwayatTransaksi> createState() => _DaftarRiwayatTransaksiState();
}

class _DaftarRiwayatTransaksiState extends State<DaftarRiwayatTransaksi> {
  final _cari = TextEditingController();
  List<BarisTransaksi> _daftar = [];
  String? _galat;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  @override
  void dispose() {
    _cari.dispose();
    super.dispose();
  }

  void _muat() {
    final app = context.app;
    final dari = awalHariWibUtc(DateTime.now());
    setState(() => _daftar = app.laporan.daftarTransaksi(app.cabang.id, dari, dari.add(const Duration(days: 1)), batas: 300));
  }

  Future<void> _buka(String id) async {
    final isi = await bukaDetailTransaksi(context, id, bisaIsiUlang: widget.bisaIsiUlang);
    if (!mounted) return;
    if (isi != null && widget.onIsiUlang != null) return widget.onIsiUlang!(isi);
    _muat();
  }

  Future<void> _cariNomor() async {
    final teks = _cari.text.trim();
    if (teks.isEmpty) return;
    final app = context.app;
    final id = app.penjualan.idDariNomor(app.cabang.id, teks);
    if (id == null) {
      setState(() => _galat = 'Transaksi "$teks" tidak ditemukan di toko ini.');
      return;
    }
    setState(() => _galat = null);
    _cari.clear();
    await _buka(id);
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        key: const ValueKey('cari-transaksi'),
        controller: _cari,
        autofocus: true,
        style: const TextStyle(fontFamily: fontMono, fontSize: 19, fontWeight: FontWeight.w700),
        decoration: InputDecoration(
          hintText: 'Scan barcode di struk atau ketik no. transaksi, lalu Enter',
          prefixIcon: const Icon(Icons.qr_code_scanner),
          errorText: _galat,
        ),
        onChanged: (_) {
          if (_galat != null) setState(() => _galat = null);
        },
        onSubmitted: (_) => _cariNomor(),
      ),
      const SizedBox(height: 12),
      Text(
        'Transaksi hari ini (${_daftar.length}) · klik untuk melihat isi, cetak ulang, atau batalkan',
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Warna.teksPudar),
      ),
      const SizedBox(height: 8),
      Expanded(
        child: _daftar.isEmpty
            ? const Center(
                child: Text('Belum ada transaksi hari ini.', style: TextStyle(fontSize: 18, color: Warna.teksPudar)),
              )
            : SingleChildScrollView(
                child: TabelSederhana(
                  kolom: const ['Jam', 'No. transaksi', 'Kasir', 'Bayar', 'Total', 'Status'],
                  lebar: const [2, 5, 3, 3, 3, 3],
                  rataKanan: const {4},
                  onTap: (i) => _buka(_daftar[i].id),
                  baris: [
                    for (final t in _daftar)
                      [
                        Text(formatJam(t.waktu), style: gayaSel),
                        Text(t.noTransaksi, style: gayaSelTebal),
                        Text(t.kasir, style: gayaSel),
                        Text(t.metode.label, style: gayaSel),
                        Text(formatRupiah(t.total), style: gayaSelTebal),
                        Lencana.status(t.status),
                      ],
                  ],
                ),
              ),
      ),
    ],
  );
}

/// Menu kasir "Cetak ulang struk": cari lewat barcode struk / nomor, atau pilih dari transaksi hari ini.
class IsiCetakUlang extends StatelessWidget {
  const IsiCetakUlang({super.key, this.onIsiUlang});
  final ValueChanged<IsiUlang>? onIsiUlang;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
    child: DaftarRiwayatTransaksi(bisaIsiUlang: onIsiUlang != null, onIsiUlang: onIsiUlang),
  );
}

/// Detail satu transaksi dalam bentuk daftar belanja seperti layar kasir (revisi E):
/// Cetak ulang, Tukar/kembalikan barang (menyusul, revisi F), Batalkan (PIN SPV), Ubah transaksi.
/// [bisaIsiUlang]: tampilkan "Ubah transaksi" (batalkan + barangnya dimasukkan lagi ke layar Transaksi).
Future<IsiUlang?> bukaDetailTransaksi(BuildContext context, String transaksiId, {bool bisaIsiUlang = false}) => showDialog<IsiUlang>(
  context: context,
  builder: (_) => DialogDetailTransaksi(transaksiId: transaksiId, bisaIsiUlang: bisaIsiUlang),
);

class DialogDetailTransaksi extends StatefulWidget {
  const DialogDetailTransaksi({super.key, required this.transaksiId, this.bisaIsiUlang = false});
  final String transaksiId;
  final bool bisaIsiUlang;
  @override
  State<DialogDetailTransaksi> createState() => _DialogDetailTransaksiState();
}

class _DialogDetailTransaksiState extends State<DialogDetailTransaksi> {
  DetailTransaksi? _d;
  bool _sibuk = false;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  void _muat() {
    final app = context.app;
    setState(() => _d = app.penjualan.detailTransaksi(widget.transaksiId, app.cabang));
  }

  /// Batalkan transaksi (kasir: PIN SPV). [isiUlang] = "ubah transaksi": barangnya dikembalikan ke pemanggil.
  Future<void> _batalkan({bool isiUlang = false}) async {
    final app = context.app;
    final d = _d!;
    if (isiUlang) {
      final ok = await konfirmasi(
        context,
        judul: 'Ubah transaksi?',
        isi:
            'Transaksi ${d.struk.noTransaksi} dibatalkan dulu, lalu semua barangnya dimasukkan ke layar Transaksi untuk diubah '
            'dan dibayar sebagai transaksi baru. Harga memakai harga sekarang. Kembalikan dulu uang transaksi lama ke pembeli.',
        ya: 'Lanjut',
      );
      if (!ok || !mounted) return;
    }
    final alasan = await _mintaAlasan(awal: isiUlang ? 'Ubah transaksi' : '');
    if (alasan == null || !mounted) return;
    var penyetuju = app.penggunaAktif!;
    final akses = app.akses(Izin.batalTransaksi);
    if (akses == Akses.tidak) return;
    if (akses == Akses.pinSpv) {
      final p = await mintaPinSpv(context, alasan: 'Membatalkan ${d.struk.noTransaksi} (${formatRupiah(d.struk.total)}).');
      if (p == null || !mounted) return;
      penyetuju = p;
    }
    setState(() => _sibuk = true);
    try {
      app.penjualan.batalkan(transaksiId: d.id, alasan: alasan, dimintaOleh: app.penggunaAktif!.id, disetujuiOleh: penyetuju.id);
    } catch (e) {
      if (mounted) {
        setState(() => _sibuk = false);
        tampilkanPesan(context, pesanGalat(e), galat: true);
      }
      return;
    }
    if (!mounted) return;
    if (isiUlang) {
      tampilkanPesan(context, 'Transaksi ${d.struk.noTransaksi} dibatalkan. Barangnya sudah di layar Transaksi.');
      Navigator.pop(context, [for (final i in d.item) (barangId: i.barangId, qty: i.qty)]);
      return;
    }
    tampilkanPesan(context, 'Transaksi dibatalkan. Stok sudah dikembalikan.');
    setState(() => _sibuk = false);
    _muat();
  }

  Future<String?> _mintaAlasan({String awal = ''}) {
    final c = TextEditingController(text: awal);
    // Controller tidak di-dispose di sini: dialog masih dipakai selama animasi menutup.
    return showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Alasan pembatalan', style: TextStyle(fontWeight: FontWeight.w800)),
        content: SizedBox(
          width: 460,
          child: TextField(
            key: const ValueKey('alasan-batal'),
            controller: c,
            autofocus: true,
            style: const TextStyle(fontSize: 19),
            decoration: const InputDecoration(hintText: 'contoh: salah input barang'),
            onSubmitted: (_) {
              if (c.text.trim().isNotEmpty) Navigator.pop(d, c.text.trim());
            },
          ),
        ),
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(d), child: const Text('Batal')),
          FilledButton(
            key: const ValueKey('lanjut-batal'),
            onPressed: () {
              if (c.text.trim().isNotEmpty) Navigator.pop(d, c.text.trim());
            },
            child: const Text('Lanjut'),
          ),
        ],
      ),
    );
  }

  Future<void> _cetakUlang() async {
    final app = context.app;
    final g = await app.cetakStrukTransaksi(_d!.struk, ulang: true);
    if (mounted) tampilkanPesan(context, g ?? 'Struk dicetak ulang', galat: g != null);
  }

  Widget _info(String label, String nilai, {bool tebal = false}) => Padding(
    padding: const EdgeInsets.only(right: 28),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(fontSize: 12.5, letterSpacing: 0.6, fontWeight: FontWeight.w700, color: Warna.teksPudar),
        ),
        const SizedBox(height: 2),
        Text(nilai, style: TextStyle(fontSize: 17, fontWeight: tebal ? FontWeight.w800 : FontWeight.w600)),
      ],
    ),
  );

  Widget _ringkas(String a, String b, {bool besar = false, Color? warna}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          a,
          style: TextStyle(fontSize: besar ? 19 : 16.5, fontWeight: FontWeight.w700, color: Warna.teks2),
        ),
        SizedBox(
          width: 210,
          child: Text(
            b,
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: besar ? 28 : 17.5, fontWeight: FontWeight.w800, color: warna ?? (besar ? Warna.utamaTua : Warna.teks)),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final d = _d;
    if (d == null) {
      return AlertDialog(
        content: const Text('Transaksi tidak ditemukan', style: TextStyle(fontSize: 18)),
        actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Tutup'))],
      );
    }
    final app = context.app;
    final s = d.struk;
    final aksesBatal = app.akses(Izin.batalTransaksi);
    final bolehBatal = !d.dibatalkan && !d.adaRetur && aksesBatal != Akses.tidak;
    final pin = aksesBatal == Akses.pinSpv ? ' (PIN SPV)' : '';
    const gayaKepala = TextStyle(fontSize: 13.5, letterSpacing: 0.6, fontWeight: FontWeight.w800, color: Warna.utamaTua);
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      title: Row(
        children: [
          Expanded(
            child: Text(
              s.noTransaksi,
              style: const TextStyle(fontWeight: FontWeight.w800, fontFamily: fontMono),
            ),
          ),
          Lencana.status(d.status),
        ],
      ),
      content: SizedBox(
        width: 1000,
        height: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _info('Tanggal', formatLayar(s.waktu)),
                _info('Kasir', s.namaKasir),
                _info('Cara bayar', s.metode.label),
                if (s.noReferensi != null && s.noReferensi!.isNotEmpty) _info('No. referensi', s.noReferensi!),
              ],
            ),
            const SizedBox(height: 12),
            if (d.dibatalkan) ...[
              const KotakPesan('Transaksi ini sudah dibatalkan. Stoknya sudah dikembalikan.', jenis: JenisPesan.galat),
              const SizedBox(height: 10),
            ],
            if (d.adaRetur) ...[
              const KotakPesan('Sebagian barang sudah diretur, jadi transaksi ini tidak bisa dibatalkan.', jenis: JenisPesan.perhatian),
              const SizedBox(height: 10),
            ],
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Warna.garis, width: 1.5),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      decoration: const BoxDecoration(
                        color: Warna.utamaMuda,
                        border: Border(bottom: BorderSide(color: Warna.utamaGarisMuda, width: 1.5)),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                      child: const Row(
                        children: [
                          Expanded(flex: 1, child: Text('NO', style: gayaKepala)),
                          Expanded(flex: 8, child: Text('NAMA BARANG', style: gayaKepala)),
                          Expanded(
                            flex: 3,
                            child: Text('HARGA', textAlign: TextAlign.right, style: gayaKepala),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text('JUMLAH', textAlign: TextAlign.center, style: gayaKepala),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text('SUBTOTAL', textAlign: TextAlign.right, style: gayaKepala),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: d.item.length,
                        itemBuilder: (_, i) {
                          final it = d.item[i];
                          return Container(
                            key: ValueKey('detail-baris-$i'),
                            color: i.isOdd ? Warna.baris2 : Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 1,
                                  child: Text('${i + 1}', style: const TextStyle(fontSize: 16, color: Warna.teksPudar)),
                                ),
                                Expanded(
                                  flex: 8,
                                  child: Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          it.nama,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 17.5, fontWeight: FontWeight.w700),
                                        ),
                                      ),
                                      if (it.isGrosir) ...[const SizedBox(width: 8), const Lencana('GROSIR', latar: Warna.oranyeMuda, warna: Warna.oranye)],
                                      if (it.sudahRetur > 0) ...[
                                        const SizedBox(width: 8),
                                        Lencana('diretur ${it.sudahRetur}', latar: Warna.merahMuda, warna: Warna.merah),
                                      ],
                                    ],
                                  ),
                                ),
                                Expanded(
                                  flex: 3,
                                  child: Text(formatRupiah(it.hargaSatuan), textAlign: TextAlign.right, style: const TextStyle(fontSize: 17)),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    formatAngka(it.qty),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontSize: 17.5, fontWeight: FontWeight.w800),
                                  ),
                                ),
                                Expanded(
                                  flex: 3,
                                  child: Text(
                                    formatRupiah(it.subtotal),
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(fontSize: 17.5, fontWeight: FontWeight.w800, color: Warna.utamaTua),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    Container(
                      decoration: const BoxDecoration(
                        color: Warna.utamaMuda,
                        border: Border(top: BorderSide(color: Warna.utamaGarisMuda, width: 1.5)),
                      ),
                      padding: const EdgeInsets.fromLTRB(18, 8, 18, 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'Jenis barang: ${d.item.length}      Jumlah barang: ${formatAngka(d.jumlahBarang)}',
                            style: const TextStyle(fontSize: 16.5, color: Warna.teks2),
                          ),
                          const Spacer(),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              _ringkas('TOTAL', formatRupiah(s.total), besar: true),
                              if (s.metode == MetodeBayar.tunai) ...[
                                _ringkas('Tunai diterima', formatRupiah(s.diterima)),
                                _ringkas('Kembali', formatRupiah(s.kembalian), warna: Warna.suksesTua),
                              ] else
                                _ringkas(s.metode.label, formatRupiah(s.diterima)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        SizedBox(
          width: 1000,
          child: Row(
            spacing: 10,
            children: [
              if (bolehBatal)
                OutlinedButton(
                  key: const ValueKey('batalkan-transaksi'),
                  onPressed: _sibuk ? null : () => _batalkan(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Warna.merah,
                    side: const BorderSide(color: Warna.merahGaris, width: 2),
                  ),
                  child: Text('Batalkan$pin'),
                ),
              if (bolehBatal && widget.bisaIsiUlang && app.shiftAktif != null)
                OutlinedButton(
                  key: const ValueKey('ubah-transaksi'),
                  onPressed: _sibuk ? null : () => _batalkan(isiUlang: true),
                  child: Text('Ubah transaksi$pin'),
                ),
              if (!d.dibatalkan)
                const Tooltip(
                  message: 'Fitur tukar / kembalikan barang menyusul (revisi F).',
                  child: OutlinedButton(onPressed: null, child: Text('Tukar / kembalikan')),
                ),
              const Spacer(),
              OutlinedButton.icon(
                key: const ValueKey('cetak-ulang'),
                onPressed: _sibuk ? null : _cetakUlang,
                icon: const Icon(Icons.print),
                label: const Text('Cetak ulang'),
              ),
              FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Tutup')),
            ],
          ),
        ),
      ],
    );
  }
}

/// Tampilan struk 58 mm di layar.
class PratinjauStruk extends StatelessWidget {
  const PratinjauStruk({super.key, required this.baris});
  final List<BarisStruk> baris;

  @override
  Widget build(BuildContext context) => Container(
    color: Warna.latar,
    alignment: Alignment.topCenter,
    padding: const EdgeInsets.all(14),
    child: SingleChildScrollView(
      child: Container(
        width: 380,
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final b in baris)
              Text(
                b.teks,
                textAlign: switch (b.rata) {
                  Rata.kiri => TextAlign.left,
                  Rata.tengah => TextAlign.center,
                  Rata.kanan => TextAlign.right,
                },
                style: TextStyle(
                  fontFamily: fontMono,
                  fontSize: b.besar ? 16 : 13.5,
                  height: 1.45,
                  fontWeight: b.tebal ? FontWeight.w700 : FontWeight.w400,
                  color: const Color(0xFF111111),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
