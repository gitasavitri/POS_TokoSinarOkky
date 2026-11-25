import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pos_core/pos_core.dart';

import '../../data/model.dart';
import '../../layanan/aplikasi.dart';
import '../komponen/pin.dart';
import '../komponen/umum.dart';
import '../tema.dart';
import 'transaksi.dart';

/// Tukar / kembalikan barang (revisi F). Kasir boleh sendiri sampai 3 hari dari tanggal struk;
/// lewat dari itu PIN SPV. Scan barcode struk → pilih barang (+ tandai rusak) → isi alasan →
/// "Kembalikan uang tunai" (struk RTR dicetak) atau "Tukar barang" (dibawa ke layar Transaksi).
///
/// Menu Kasir & SPV/Admin. SPV/Admin juga melihat riwayat retur hari ini di bawahnya.
class IsiRetur extends StatelessWidget {
  const IsiRetur({super.key, this.onTukar});

  /// Null = tombol Tukar barang tidak ditampilkan.
  final ValueChanged<DraftTukar>? onTukar;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final spv = app.penggunaAktif?.peran != Peran.kasir;
    return ListView(padding: const EdgeInsets.all(24), children: [
      PanelRetur(onTukar: onTukar, tinggiPratinjau: 600),
      if (spv) ...[const SizedBox(height: 20), const RiwayatReturHariIni()],
    ]);
  }
}

/// Dialog tukar/kembalikan barang untuk satu struk (dari detail transaksi atau scan struk di layar kasir).
/// [transaksiId] null = mulai dengan kolom scan struk.
/// Mengembalikan [DraftTukar] kalau kasir memilih Tukar barang.
Future<DraftTukar?> bukaDialogRetur(BuildContext context, String? transaksiId, {bool bisaTukar = false}) => showDialog<DraftTukar>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        titlePadding: const EdgeInsets.fromLTRB(24, 18, 12, 0),
        title: Row(children: [
          const Icon(Icons.assignment_return, color: Warna.merahIkon),
          const SizedBox(width: 10),
          const Expanded(child: Text('Tukar / kembalikan barang', style: TextStyle(fontWeight: FontWeight.w800))),
          IconButton(onPressed: () => Navigator.pop(c), icon: const Icon(Icons.close), tooltip: 'Tutup (Esc)'),
        ]),
        contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        content: CallbackShortcuts(
          bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.pop(c)},
          child: SizedBox(
            width: 1180,
            height: 640,
            child: SingleChildScrollView(
              child: PanelRetur(
                transaksiIdAwal: transaksiId,
                onTukar: bisaTukar ? (d) => Navigator.pop(c, d) : null,
                onSelesai: () => Navigator.pop(c),
                tinggiPratinjau: 600,
              ),
            ),
          ),
        ),
      ),
    );

class PanelRetur extends StatefulWidget {
  const PanelRetur({super.key, this.transaksiIdAwal, this.onTukar, this.onSelesai, this.tinggiPratinjau = 560});

  /// Struk yang langsung dibuka (tanpa scan).
  final String? transaksiIdAwal;
  final ValueChanged<DraftTukar>? onTukar;

  /// Dipanggil setelah kasir menutup kartu hasil retur (dialog: tutup dialog).
  final VoidCallback? onSelesai;
  final double tinggiPratinjau;

  @override
  State<PanelRetur> createState() => _PanelReturState();
}

class _PanelReturState extends State<PanelRetur> {
  final _scan = TextEditingController();
  final _alasan = TextEditingController();
  StrukUntukRetur? _struk;
  DataStruk? _dataStruk;
  final _qty = <String, int>{};
  final _rusak = <String>{};
  String? _galat;
  bool _sibuk = false;

  /// Retur uang yang baru selesai (kartu hasil).
  ({HasilRetur hasil, bool mencetak, String? galatCetak})? _hasil;

  Aplikasi get app => context.app;

  @override
  void initState() {
    super.initState();
    if (widget.transaksiIdAwal != null) WidgetsBinding.instance.addPostFrameCallback((_) => _muat(widget.transaksiIdAwal!));
  }

  @override
  void dispose() {
    _scan.dispose();
    _alasan.dispose();
    super.dispose();
  }

  void _cari() {
    final teks = _scan.text.trim();
    if (teks.isEmpty) return;
    final id = app.penjualan.idDariNomor(app.cabang.id, teks);
    if (id == null) {
      setState(() => _galat = 'Struk "$teks" tidak ditemukan di toko ini.');
      return;
    }
    _scan.clear();
    _muat(id);
  }

  void _muat(String id) {
    final s = app.penjualan.strukUntukRetur(id);
    setState(() {
      _hasil = null;
      _struk = s;
      _dataStruk = s == null ? null : app.penjualan.struk(id, app.cabang);
      _qty.clear();
      _rusak.clear();
      _alasan.clear();
      _galat = s == null
          ? 'Transaksi tidak ditemukan.'
          : s.dibatalkan
              ? 'Transaksi ${s.noTransaksi} sudah dibatalkan, tidak bisa diretur.'
              : s.habis
                  ? 'Semua barang di ${s.noTransaksi} sudah dikembalikan.'
                  : null;
    });
  }

  int get _nilai {
    final s = _struk;
    if (s == null) return 0;
    return s.item.fold(0, (n, i) => n + (_qty[i.itemId] ?? 0) * i.harga);
  }

  int get _jumlah => _qty.values.fold(0, (a, b) => a + b);

  Akses get _akses => app.penjualan.aksesReturStruk(_struk!.id, app.penggunaAktif!.peran);

  /// Cek isian + minta PIN SPV kalau struk lebih dari 3 hari. Null = batal.
  Future<({Pengguna? penyetuju})?> _siapkan() async {
    final s = _struk!;
    final galat = cekRetur(pilihan: _qty, sisa: {for (final i in s.item) i.itemId: i.sisa}, alasan: _alasan.text);
    if (galat != null) {
      setState(() => _galat = galat);
      return null;
    }
    if (_akses != Akses.pinSpv) return (penyetuju: null);
    final p = await mintaPinSpv(context,
        alasan: 'Struk ${s.noTransaksi} tanggal ${formatTanggal(s.waktu)} sudah lebih dari $batasHariReturKasir hari.');
    if (p == null) return null;
    return (penyetuju: p);
  }

  Future<void> _kembalikanUang() async {
    final s = _struk!;
    final shift = app.shiftAktif;
    if (app.penggunaAktif!.peran == Peran.kasir && shift == null) {
      return setState(() => _galat = 'Buka shift dulu (menu Transaksi). Uang retur diambil dari uang kasir.');
    }
    final siap = await _siapkan();
    if (siap == null || !mounted) return;
    final ok = await konfirmasi(
      context,
      judul: 'Kembalikan uang tunai?',
      isi: 'Kembalikan uang TUNAI ${formatRupiah(_nilai)} ke pembeli untuk $_jumlah barang dari ${s.noTransaksi}.'
          '${_rusak.isEmpty ? '' : ' Barang rusak tidak dimasukkan ke stok jual.'}',
      ya: 'Kembalikan uang',
    );
    if (!ok || !mounted) return;
    setState(() => _sibuk = true);
    final HasilRetur h;
    try {
      h = app.penjualan.retur(
        cabang: app.cabang,
        transaksiId: s.id,
        qtyPerItem: Map.of(_qty),
        rusak: Set.of(_rusak),
        alasan: _alasan.text,
        oleh: app.penggunaAktif!,
        disetujuiOleh: siap.penyetuju,
        shiftId: shift?.id,
      );
    } catch (e) {
      setState(() {
        _sibuk = false;
        _galat = pesanGalat(e);
      });
      return;
    }
    final otomatis = app.cetakOtomatis;
    setState(() {
      _sibuk = false;
      _hasil = (hasil: h, mencetak: otomatis, galatCetak: null);
      _struk = null;
    });
    if (otomatis) await _cetak(ulang: false);
  }

  Future<void> _cetak({required bool ulang}) async {
    final r = _hasil;
    if (r == null) return;
    setState(() => _hasil = (hasil: r.hasil, mencetak: true, galatCetak: null));
    final g = await app.cetakRetur(r.hasil.struk);
    if (!mounted || _hasil?.hasil != r.hasil) return;
    setState(() => _hasil = (hasil: r.hasil, mencetak: false, galatCetak: g));
  }

  Future<void> _tukar() async {
    final s = _struk!;
    final siap = await _siapkan();
    if (siap == null || !mounted) return;
    try {
      final d = app.penjualan.siapkanTukar(
        transaksiId: s.id,
        qtyPerItem: Map.of(_qty),
        rusak: Set.of(_rusak),
        alasan: _alasan.text,
        oleh: app.penggunaAktif!,
        disetujuiOleh: siap.penyetuju,
        cabangId: app.cabang.id,
      );
      widget.onTukar!(d);
    } catch (e) {
      setState(() => _galat = pesanGalat(e));
    }
  }

  void _selesai() {
    setState(() => _hasil = null);
    widget.onSelesai?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasil != null) return _kartuHasil();
    final s = _struk;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (widget.transaksiIdAwal == null) ...[
        Panel(
          child: Row(children: [
            Expanded(
              child: TextField(
                key: const ValueKey('scan-struk-retur'),
                controller: _scan,
                autofocus: true,
                style: const TextStyle(fontFamily: fontMono, fontSize: 20, fontWeight: FontWeight.w700),
                decoration: const InputDecoration(
                  labelText: 'Scan barcode di struk atau ketik nomor transaksi',
                  hintText: 'contoh: TRX-A01-261105-0001',
                  prefixIcon: Icon(Icons.qr_code_scanner, color: Warna.utama),
                ),
                onChanged: (_) {
                  if (_galat != null && _struk == null) setState(() => _galat = null);
                },
                onSubmitted: (_) => _cari(),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(height: 58, child: FilledButton(onPressed: _cari, child: const Text('Cari'))),
          ]),
        ),
        const SizedBox(height: 16),
      ],
      if (s == null || s.dibatalkan || s.habis) ...[
        if (_galat != null) KotakPesan(_galat!, jenis: JenisPesan.galat),
        if (s == null && _galat == null)
          const KotakPesan(
            'Pembeli membawa barang + struk. Scan barcode di struk, pilih barang yang dikembalikan, lalu pilih '
            '"Kembalikan uang tunai" atau "Tukar barang". Uang retur selalu dikembalikan tunai.',
            jenis: JenisPesan.info,
          ),
      ] else
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 3, child: _panelPilih(s)),
          const SizedBox(width: 16),
          SizedBox(width: 380, height: widget.tinggiPratinjau, child: PratinjauStruk(baris: context.app.pratinjauStruk(susunStruk(_dataStruk!)))),
        ]),
    ]);
  }

  Widget _panelPilih(StrukUntukRetur s) {
    final hari = selisihHariWib(s.waktu, app.db.sekarang());
    final perluPin = _akses == Akses.pinSpv;
    final kasirTanpaShift = app.penggunaAktif!.peran == Peran.kasir && app.shiftAktif == null;
    final bisa = _jumlah > 0 && !_sibuk;
    return Panel(
      judul: 'Pilih barang yang dikembalikan · ${s.noTransaksi}',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(
          'Tanggal struk ${formatLayar(s.waktu)} · ${hari == 0 ? 'hari ini' : '$hari hari lalu'}',
          style: const TextStyle(fontSize: 15.5, color: Warna.teksPudar, fontWeight: FontWeight.w600),
        ),
        if (perluPin) ...[
          const SizedBox(height: 10),
          const KotakPesan('Struk lebih dari $batasHariReturKasir hari. Tukar / retur perlu PIN SPV.', jenis: JenisPesan.perhatian),
        ],
        const SizedBox(height: 6),
        for (final i in s.item) _barisItem(i),
        const Divider(height: 24),
        TextField(
          key: const ValueKey('alasan-retur'),
          controller: _alasan,
          style: const TextStyle(fontSize: 18),
          decoration: const InputDecoration(labelText: 'Alasan', hintText: 'contoh: kemasan bocor, salah beli, kedaluwarsa'),
          onChanged: (_) {
            if (_galat != null) setState(() => _galat = null);
          },
        ),
        if (_galat != null) ...[const SizedBox(height: 10), KotakPesan(_galat!, jenis: JenisPesan.galat)],
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('NILAI BARANG KEMBALI',
                  style: TextStyle(fontSize: 13.5, letterSpacing: 0.6, fontWeight: FontWeight.w800, color: Warna.teksPudar)),
              Text(formatRupiah(_nilai),
                  key: const ValueKey('nilai-retur'), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: Warna.merahTua)),
            ]),
          ),
          if (widget.onTukar != null) ...[
            SizedBox(
              height: 58,
              child: OutlinedButton.icon(
                key: const ValueKey('tombol-tukar'),
                onPressed: bisa ? _tukar : null,
                icon: const Icon(Icons.swap_horiz),
                label: const Text('Tukar barang'),
              ),
            ),
            const SizedBox(width: 10),
          ],
          SizedBox(
            height: 58,
            child: FilledButton.icon(
              key: const ValueKey('tombol-kembalikan-uang'),
              onPressed: bisa && !kasirTanpaShift ? _kembalikanUang : null,
              style: FilledButton.styleFrom(backgroundColor: Warna.oranyeTegas),
              icon: const Icon(Icons.payments),
              label: Text(perluPin ? 'Kembalikan uang tunai (PIN SPV)' : 'Kembalikan uang tunai'),
            ),
          ),
        ]),
        if (kasirTanpaShift)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Kembalikan uang butuh shift yang aktif. Buka shift lewat menu Transaksi.',
                style: TextStyle(fontSize: 14.5, color: Warna.teksPudar)),
          ),
        if (widget.onTukar != null)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Tukar barang: nilai barang kembali memotong belanja baru di layar Transaksi, pembeli membayar selisihnya.',
                style: TextStyle(fontSize: 14.5, color: Warna.teksPudar)),
          ),
      ]),
    );
  }

  Widget _barisItem(ItemRetur i) {
    final n = _qty[i.itemId] ?? 0;
    final rusak = _rusak.contains(i.itemId);
    return Container(
      key: ValueKey('retur-${i.itemId}'),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Warna.garisTipis))),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(i.nama, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            Text(
              'Dibeli ${formatAngka(i.qty)} × ${formatRupiah(i.harga)}${i.sudahRetur > 0 ? ' · sudah dikembalikan ${i.sudahRetur}' : ''}',
              style: const TextStyle(fontSize: 15.5, color: Warna.teksPudar),
            ),
          ]),
        ),
        if (i.sisa == 0)
          const Lencana('Sudah dikembalikan semua', latar: Warna.abuMuda, warna: Warna.teks2)
        else ...[
          Tooltip(
            message: 'Barang rusak / kedaluwarsa: tidak dimasukkan ke stok jual',
            child: OutlinedButton.icon(
              key: ValueKey('rusak-${i.itemId}'),
              onPressed: n == 0 ? null : () => setState(() => rusak ? _rusak.remove(i.itemId) : _rusak.add(i.itemId)),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(44, 46),
                backgroundColor: rusak ? Warna.merahMuda : null,
                foregroundColor: rusak ? Warna.merah : Warna.teks2,
                side: BorderSide(color: rusak ? Warna.merah : Warna.garis, width: rusak ? 2 : 1.5),
              ),
              icon: Icon(rusak ? Icons.check_box : Icons.check_box_outline_blank, size: 22),
              label: const Text('Rusak'),
            ),
          ),
          const SizedBox(width: 12),
          PengaturJumlah(
            nilai: n,
            min: 0,
            onUbah: (v) => setState(() {
              _galat = null;
              final baru = v.clamp(0, i.sisa);
              _qty[i.itemId] = baru;
              if (baru == 0) _rusak.remove(i.itemId);
            }),
          ),
        ],
      ]),
    );
  }

  Widget _kartuHasil() {
    final r = _hasil!;
    final h = r.hasil;
    final Widget status;
    if (r.mencetak) {
      status = const Lencana('Struk retur sedang dicetak', latar: Warna.utamaMuda, warna: Warna.utamaTua);
    } else if (r.galatCetak != null) {
      status = Flexible(child: KotakPesan('Struk retur belum tercetak: ${r.galatCetak}', jenis: JenisPesan.galat));
    } else {
      status = app.cetakOtomatis
          ? const Lencana('Struk retur sudah dicetak', latar: Warna.suksesMuda, warna: Warna.suksesTua)
          : const Lencana('Cetak otomatis mati', latar: Warna.abuMuda, warna: Warna.teks2);
    }
    return Center(
      child: ConstrainedBox(
        key: const ValueKey('hasil-retur'),
        constraints: const BoxConstraints(maxWidth: 760),
        child: Panel(
          judul: 'Retur selesai · ${h.noRetur}',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
              decoration: BoxDecoration(
                color: Warna.oranyeMuda,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Warna.oranyeGaris, width: 2),
              ),
              child: Column(children: [
                const Text('KEMBALIKAN UANG TUNAI',
                    style: TextStyle(fontSize: 18, letterSpacing: 2, fontWeight: FontWeight.w800, color: Warna.oranyeTua)),
                Text(formatRupiah(h.total), style: const TextStyle(fontSize: 64, fontWeight: FontWeight.w800, color: Warna.oranyeTua, height: 1.1)),
                Text('${h.struk.jumlahBarang} barang dari ${h.struk.noTransaksiAsal}',
                    style: const TextStyle(fontSize: 16, color: Warna.oranyeTua, fontWeight: FontWeight.w600)),
              ]),
            ),
            const SizedBox(height: 14),
            Row(children: [
              status,
              const Spacer(),
              if (!r.mencetak)
                OutlinedButton.icon(
                  onPressed: () => _cetak(ulang: true),
                  icon: const Icon(Icons.print),
                  label: Text(r.galatCetak == null && app.cetakOtomatis ? 'Cetak lagi' : 'Cetak struk retur'),
                ),
              const SizedBox(width: 10),
              FilledButton(key: const ValueKey('selesai-retur'), onPressed: _selesai, child: const Text('Selesai')),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// Riwayat retur hari ini (SPV/Admin): siapa memproses, tukar atau uang, barang rusak, PIN SPV.
class RiwayatReturHariIni extends StatefulWidget {
  const RiwayatReturHariIni({super.key});
  @override
  State<RiwayatReturHariIni> createState() => _RiwayatReturHariIniState();
}

class _RiwayatReturHariIniState extends State<RiwayatReturHariIni> {
  Future<void> _cetakUlang(BarisRetur r) async {
    final app = context.app;
    final d = app.penjualan.strukRetur(r.id, app.cabang);
    if (d == null) return;
    final g = await app.cetakRetur(d);
    if (mounted) tampilkanPesan(context, g ?? 'Struk ${r.noRetur} dicetak ulang', galat: g != null);
  }

  @override
  Widget build(BuildContext context) {
    final app = AplikasiScope.of(context, dengar: true);
    final dari = awalHariWibUtc(DateTime.now());
    final daftar = app.penjualan.daftarRetur(app.cabang.id, dari, dari.add(const Duration(days: 1)));
    return Panel(
      judul: 'Retur & tukar hari ini (${daftar.length})',
      padding: EdgeInsets.zero,
      child: daftar.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(20),
              child: Text('Belum ada retur hari ini.', style: TextStyle(fontSize: 17, color: Warna.teksPudar)),
            )
          : TabelSederhana(
              kolom: const ['Jam', 'No. retur', 'Struk asal', 'Oleh', 'Barang', 'Cara', 'Nilai', 'Alasan'],
              lebar: const [2, 5, 5, 3, 2, 4, 3, 5],
              rataKanan: const {4, 6},
              onTap: (i) => _cetakUlang(daftar[i]),
              baris: [
                for (final r in daftar)
                  [
                    Text(formatJam(r.waktu), style: gayaSel),
                    Text(r.noRetur, style: gayaSelTebal),
                    Text(r.noTransaksiAsal, style: gayaSel),
                    Row(children: [
                      Flexible(child: Text(r.oleh, overflow: TextOverflow.ellipsis, style: gayaSel)),
                      if (r.penyetuju != null) ...[const SizedBox(width: 6), const Lencana('PIN', latar: Warna.unguMuda, warna: Warna.ungu)],
                    ]),
                    Text('${r.jumlahBarang}${r.jumlahRusak > 0 ? ' (${r.jumlahRusak} rusak)' : ''}', style: gayaSel),
                    r.tukar
                        ? Lencana('Tukar · ${r.noTransaksiTukar!.split('-').last}', latar: Warna.biruMuda, warna: Warna.biru)
                        : const Lencana('Uang tunai', latar: Warna.oranyeMuda, warna: Warna.oranyeTua),
                    Text(formatRupiah(r.total), style: gayaSelTebal),
                    Text(r.alasan, overflow: TextOverflow.ellipsis, style: gayaSel),
                  ],
              ],
            ),
    );
  }
}
