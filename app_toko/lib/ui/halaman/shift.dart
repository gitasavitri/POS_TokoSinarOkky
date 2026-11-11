import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pos_core/pos_core.dart';

import '../../data/model.dart';
import '../../layanan/aplikasi.dart';
import '../komponen/pin.dart';
import '../komponen/umum.dart';
import '../tema.dart';

/// Folder cadangan otomatis: Documents\POS-Cadangan.
Future<String> folderCadangan() async {
  final d = await getApplicationDocumentsDirectory();
  return '${d.path}${Platform.pathSeparator}POS-Cadangan';
}

/// Buka shift: kasir mengisi uang modal di laci/dompet kasir.
Future<Shift?> bukaShiftDialog(BuildContext context) => showDialog<Shift>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _DialogBukaShift(),
    );

class _DialogBukaShift extends StatefulWidget {
  const _DialogBukaShift();
  @override
  State<_DialogBukaShift> createState() => _DialogBukaShiftState();
}

class _DialogBukaShiftState extends State<_DialogBukaShift> {
  // Modal tetap toko (revisi P) jadi isian awal; kasir tetap menghitung dan boleh mengubahnya.
  late int _nilai = context.app.pengaturan.modalTetap;
  late final _modal = TextEditingController(text: _nilai == 0 ? '' : formatAngka(_nilai));

  @override
  void dispose() {
    _modal.dispose();
    super.dispose();
  }

  void _buka() {
    final app = context.app;
    final s = app.penjualan.bukaShift(cabangId: app.cabang.id, kasirId: app.penggunaAktif!.id, modalAwal: _nilai);
    Navigator.pop(context, s);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Buka shift', style: TextStyle(fontWeight: FontWeight.w800)),
        content: SizedBox(
          width: 480,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Halo, ${context.app.penggunaAktif!.nama}. Hitung uang modal (uang kembalian) sebelum mulai berjualan.',
                style: const TextStyle(fontSize: 17, height: 1.5)),
            const SizedBox(height: 18),
            InputRupiah(
              controller: _modal,
              autofocus: true,
              besar: true,
              label: 'Uang modal awal',
              onChanged: (n) => setState(() => _nilai = n),
              onSubmitted: (_) => _buka(),
            ),
          ]),
        ),
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          FilledButton(onPressed: _buka, child: const Text('Mulai shift')),
        ],
      );
}

/// Tutup shift dengan hitung buta: kasir mengetik uang yang dihitung tanpa tahu "uang tunai seharusnya".
/// Selisih baru tampil setelah hitungan disimpan. Kasir boleh hitung ulang [maksHitungUlangKasir] kali,
/// sesudahnya perlu PIN SPV. Semua hitungan tercatat.
Future<bool?> tutupShiftDialog(BuildContext context) =>
    showDialog<bool>(context: context, barrierDismissible: false, builder: (_) => const DialogTutupShift());

class DialogTutupShift extends StatefulWidget {
  const DialogTutupShift({super.key});
  @override
  State<DialogTutupShift> createState() => _DialogTutupShiftState();
}

class _DialogTutupShiftState extends State<DialogTutupShift> {
  final _kas = TextEditingController();
  int? _dihitung;
  late RingkasanShift _r;
  late List<HitunganShift> _hitungan;

  /// Hitungan yang masih berlaku (belum ada transaksi baru sesudahnya).
  int _berlaku = 0;

  /// true = sedang mengisi hitungan (selisih disembunyikan).
  bool _mengisi = true;
  bool _sibuk = false;
  String? _galat;

  String get _shiftId => context.app.shiftAktif!.id;

  @override
  void initState() {
    super.initState();
    _muat();
    // Sudah pernah dihitung dan masih berlaku (mis. tadi menekan Batal): langsung tampilkan hasilnya.
    _mengisi = _berlaku == 0;
  }

  @override
  void dispose() {
    _kas.dispose();
    super.dispose();
  }

  void _muat() {
    final j = context.app.penjualan;
    _r = j.ringkasanShift(_shiftId);
    _hitungan = j.hitunganShift(_shiftId);
    _berlaku = j.hitunganBerlaku(_shiftId, semua: _hitungan, ring: _r);
  }

  HitunganShift? get _terakhir => _berlaku == 0 ? null : _hitungan.last;

  Future<void> _simpanHitungan() async {
    if (_dihitung == null || _sibuk) return;
    final app = context.app;
    final p = app.penggunaAktif!;
    Pengguna? spv;
    if (aksesHitungUang(p.peran, _berlaku) == Akses.pinSpv) {
      spv = await mintaPinSpv(context,
          alasan: 'Uang sudah dihitung ulang $maksHitungUlangKasir kali. Hitung ulang berikutnya perlu persetujuan SPV.');
      if (spv == null || !mounted) return;
    }
    setState(() => _sibuk = true);
    try {
      app.penjualan.simpanHitungan(shiftId: _shiftId, kasDihitung: _dihitung!, oleh: p, disetujuiOleh: spv);
      setState(() {
        _muat();
        _mengisi = false;
        _galat = null;
      });
    } catch (e) {
      setState(() => _galat = pesanGalat(e));
    } finally {
      if (mounted) setState(() => _sibuk = false);
    }
  }

  void _hitungUlang() => setState(() {
        _mengisi = true;
        _kas.clear();
        _dihitung = null;
        _galat = null;
      });

  Future<void> _tutup() async {
    final h = _terakhir;
    if (h == null || _sibuk) return;
    setState(() => _sibuk = true);
    final app = context.app;
    final p = app.penggunaAktif!;
    try {
      app.penjualan.tutupShift(shiftId: _r.shift.id, olehId: p.id);
    } catch (e) {
      setState(() {
        _sibuk = false;
        _galat = pesanGalat(e);
        _muat();
        _mengisi = _berlaku == 0;
      });
      return;
    }
    String pesan = 'Shift ditutup.';
    try {
      final f = app.cadangkan();
      pesan += ' Data dicadangkan ke $f';
    } catch (e) {
      pesan += ' Cadangan otomatis gagal: ${pesanGalat(e)}';
    }
    final kas = app.penjualan.daftarKas(_r.shift.id);
    final baris = <BarisStruk>[
      BarisStruk(app.cabang.namaToko, rata: Rata.tengah, tebal: true),
      BarisStruk('TUTUP SHIFT', rata: Rata.tengah, tebal: true),
      BarisStruk(garis()),
      BarisStruk(kiriKanan('Kasir', p.nama)),
      BarisStruk(kiriKanan('Dibuka', formatStruk(_r.shift.dibukaPada))),
      BarisStruk(kiriKanan('Ditutup', formatStruk(DateTime.now()))),
      BarisStruk(kiriKanan('Transaksi', '${_r.jumlahTransaksi}')),
      BarisStruk(kiriKanan('Modal awal', formatAngka(_r.shift.modalAwal))),
      BarisStruk(kiriKanan('Penjualan tunai', formatAngka(_r.penjualanTunai))),
      BarisStruk(kiriKanan('Non-tunai', formatAngka(_r.penjualanNonTunai))),
      BarisStruk(kiriKanan('Retur tunai', formatAngka(_r.returTunai))),
      if (_r.kasMasuk > 0) BarisStruk(kiriKanan('Kas masuk', formatAngka(_r.kasMasuk))),
      if (_r.kasKeluar > 0) BarisStruk(kiriKanan('Kas keluar', formatAngka(_r.kasKeluar))),
      for (final k in kas) BarisStruk(kiriKanan(' ${k.jenis == JenisKas.keluar ? '-' : '+'} ${k.keterangan}', formatAngka(k.jumlah))),
      BarisStruk(kiriKanan('Kas seharusnya', formatAngka(_r.kasSistem)), tebal: true),
      BarisStruk(kiriKanan('Kas dihitung', formatAngka(h.kasDihitung)), tebal: true),
      BarisStruk(kiriKanan('Selisih', formatAngka(h.kasDihitung - _r.kasSistem)), tebal: true),
      if (_hitungan.length > 1) BarisStruk(kiriKanan('Jumlah hitungan', '${_hitungan.length} kali')),
    ];
    await app.kirimKePrinter(cetakBaris(baris, potongKertas: app.potongKertas));
    if (!mounted) return;
    tampilkanPesan(context, pesan);
    Navigator.pop(context, true);
  }

  /// Revisi P: tidak sempat menghitung uang saat ganti shift. Uang (kecuali modal tetap) masuk amplop berlabel,
  /// shift menunggu dihitung SPV/Admin. Kasir tetap tidak melihat uang seharusnya.
  Future<void> _belumDihitung() async {
    if (_sibuk) return;
    final app = context.app;
    final p = app.penggunaAktif!;
    final modalTetap = app.pengaturan.modalTetap;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _DialogPetunjukAmplop(namaKasir: p.nama, modalTetap: modalTetap),
    );
    if (ok != true || !mounted) return;
    setState(() => _sibuk = true);
    final ShiftMenunggu m;
    try {
      m = app.penjualan.tutupShiftBelumDihitung(shiftId: _shiftId, oleh: p, modalTetap: modalTetap);
    } catch (e) {
      setState(() {
        _sibuk = false;
        _galat = pesanGalat(e);
      });
      return;
    }
    String pesan = 'Shift ditutup, menunggu dihitung SPV/Admin.';
    try {
      app.cadangkan();
    } catch (e) {
      pesan += ' Cadangan otomatis gagal: ${pesanGalat(e)}';
    }
    final g = await app.kirimKePrinter(cetakBaris(barisLabelAmplop(app.cabang.namaToko, m, modalTetap), potongKertas: app.potongKertas));
    if (g != null) pesan += ' Label amplop belum tercetak ($g): tulis label di amplop dengan tangan.';
    if (!mounted) return;
    tampilkanPesan(context, pesan, galat: g != null);
    Navigator.pop(context, true);
  }

  Widget _baris(String a, String b, {bool tebal = false, Color? warna}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Expanded(child: Text(a, style: TextStyle(fontSize: 18, fontWeight: tebal ? FontWeight.w800 : FontWeight.w500, color: warna))),
          Text(b, style: TextStyle(fontSize: 18, fontWeight: tebal ? FontWeight.w800 : FontWeight.w600, color: warna)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    // Setelah shift ditutup pengguna langsung keluar; dialog masih dibangun ulang selama animasi menutup.
    final p = context.app.penggunaAktif;
    if (p == null) return const SizedBox.shrink();
    final h = _terakhir;
    final kasir = p.peran == Peran.kasir;
    final sisa = sisaHitungUlang(_berlaku);
    final List<Widget> isi;
    final List<Widget> tombol;

    if (_mengisi || h == null) {
      isi = [
        const Text('Hitung semua uang tunai di kasir, termasuk uang modal awal, lalu ketik jumlahnya.',
            style: TextStyle(fontSize: 17, height: 1.45)),
        const SizedBox(height: 16),
        InputRupiah(
          key: const ValueKey('uang-dihitung'),
          controller: _kas,
          autofocus: true,
          besar: true,
          label: _berlaku == 0 ? 'Uang tunai yang dihitung' : 'Hitung ulang: uang tunai yang dihitung',
          onChanged: (n) => setState(() => _dihitung = _kas.text.isEmpty ? null : n),
          onSubmitted: (_) => _simpanHitungan(),
        ),
        if (_berlaku > 0 && kasir) ...[
          const SizedBox(height: 12),
          KotakPesan(
            aksesHitungUang(p.peran, _berlaku) == Akses.pinSpv
                ? 'Jatah hitung ulang sudah habis. Menyimpan hitungan ini perlu PIN SPV.'
                : 'Sisa hitung ulang tanpa PIN SPV: $sisa kali (termasuk yang ini).',
            jenis: JenisPesan.info,
          ),
        ],
      ];
      tombol = [
        OutlinedButton(onPressed: _sibuk ? null : () => Navigator.pop(context, false), child: const Text('Batal')),
        if (_berlaku == 0)
          OutlinedButton.icon(
            key: const ValueKey('belum-dihitung'),
            onPressed: _sibuk ? null : _belumDihitung,
            icon: const Icon(Icons.mail_outline),
            label: const Text('Belum dihitung'),
          ),
        if (h != null) OutlinedButton(onPressed: _sibuk ? null : () => setState(() => _mengisi = false), child: const Text('Kembali ke hasil')),
        FilledButton(
          key: const ValueKey('simpan-hitungan'),
          onPressed: _dihitung == null || _sibuk ? null : _simpanHitungan,
          child: Text(_sibuk ? 'Menyimpan…' : 'Simpan hitungan'),
        ),
      ];
    } else {
      final selisih = h.selisih;
      final bolehUlangTanpaPin = aksesHitungUang(p.peran, _berlaku) == Akses.ya;
      isi = [
        _baris('Uang tunai yang dihitung', formatRupiah(h.kasDihitung), tebal: true),
        const SizedBox(height: 10),
        KotakPesan(
          key: const ValueKey('hasil-selisih'),
          selisih == 0
              ? 'Uang pas, tidak ada selisih.'
              : selisih < 0
                  ? 'Uang KURANG ${formatRupiah(-selisih)}. Coba hitung ulang dulu. Selisih akan tercatat dan dilihat Admin.'
                  : 'Uang LEBIH ${formatRupiah(selisih)}. Coba hitung ulang dulu. Selisih akan tercatat dan dilihat Admin.',
          jenis: selisih == 0 ? JenisPesan.berhasil : JenisPesan.perhatian,
        ),
        if (_berlaku > 1) ...[
          const SizedBox(height: 12),
          const Text('Hitungan sebelumnya (tercatat)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Warna.teksPudar)),
          for (final x in _hitungan.skip(_hitungan.length - _berlaku).take(_berlaku - 1))
            _baris('Hitungan ${x.ke}', '${formatRupiah(x.kasDihitung)}  (selisih ${formatRupiah(x.selisih)})', warna: Warna.teksPudar),
        ],
      ];
      tombol = [
        OutlinedButton(onPressed: _sibuk ? null : () => Navigator.pop(context, false), child: const Text('Batal')),
        if (selisih != 0 || !kasir)
          OutlinedButton(
            key: const ValueKey('hitung-ulang'),
            onPressed: _sibuk ? null : _hitungUlang,
            child: Text(kasir ? (bolehUlangTanpaPin ? 'Hitung ulang (sisa $sisa)' : 'Hitung ulang (PIN SPV)') : 'Hitung ulang'),
          ),
        FilledButton(
          key: const ValueKey('tutup-shift'),
          onPressed: _sibuk ? null : _tutup,
          child: Text(_sibuk ? 'Menutup…' : 'Tutup shift & keluar'),
        ),
      ];
    }

    return AlertDialog(
      title: const Text('Tutup shift', style: TextStyle(fontWeight: FontWeight.w800)),
      content: SizedBox(
        width: 540,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Dibuka ${formatLayar(_r.shift.dibukaPada)}', style: const TextStyle(fontSize: 16, color: Warna.teksPudar)),
          const SizedBox(height: 8),
          // Hitung buta: kasir hanya melihat jumlah transaksi dan total penjualan, bukan uang tunai seharusnya.
          _baris('Jumlah transaksi', '${_r.jumlahTransaksi}'),
          _baris('Total penjualan', formatRupiah(_r.penjualan)),
          const Divider(height: 22),
          ...isi,
          if (_galat != null) ...[const SizedBox(height: 12), KotakPesan(_galat!, jenis: JenisPesan.galat)],
        ]),
      ),
      actions: tombol,
    );
  }
}

// ============================================================================ "Belum dihitung" (revisi P)

/// Isi struk label amplop. Sengaja tanpa "uang seharusnya" (hitung buta).
List<BarisStruk> barisLabelAmplop(String namaToko, ShiftMenunggu m, int modalTetap) => [
      BarisStruk(namaToko, rata: Rata.tengah, tebal: true),
      BarisStruk('AMPLOP SHIFT', rata: Rata.tengah, tebal: true, besar: true),
      BarisStruk('BELUM DIHITUNG', rata: Rata.tengah, tebal: true),
      BarisStruk(garis()),
      BarisStruk(kiriKanan('Kasir', m.namaKasir), tebal: true),
      BarisStruk(kiriKanan('Dibuka', formatStruk(m.dibukaPada))),
      BarisStruk(kiriKanan('Ditutup', formatStruk(m.ditutupPada))),
      BarisStruk(kiriKanan('Transaksi', '${m.jumlahTransaksi}')),
      BarisStruk(kiriKanan('Modal di kasir', modalTetap == 0 ? '-' : formatAngka(modalTetap))),
      BarisStruk(garis()),
      const BarisStruk('Diisi SPV/Admin:'),
      const BarisStruk('Isi amplop  : ................'),
      const BarisStruk('Dihitung    : ................'),
      const BarisStruk('Tanggal     : ................'),
    ];

class _DialogPetunjukAmplop extends StatelessWidget {
  const _DialogPetunjukAmplop({required this.namaKasir, required this.modalTetap});
  final String namaKasir;
  final int modalTetap;

  Widget _langkah(int no, String teks) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: Warna.utamaMuda, borderRadius: BorderRadius.circular(15)),
            child: Text('$no', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Warna.utamaTua)),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(teks, style: const TextStyle(fontSize: 17, height: 1.4))),
        ]),
      );

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Tutup shift: belum dihitung', style: TextStyle(fontWeight: FontWeight.w800)),
        content: SizedBox(
          width: 560,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Pakai ini kalau tidak sempat menghitung uang saat ganti shift.', style: TextStyle(fontSize: 16, color: Warna.teksPudar)),
            const SizedBox(height: 10),
            if (modalTetap > 0)
              _langkah(1, 'Sisakan uang modal ${formatRupiah(modalTetap)} di kasir untuk shift berikutnya '
                  '(kalau uangnya kurang dari itu, sisakan semua).')
            else
              _langkah(1, 'Ambil semua uang tunai dari kasir.'),
            _langkah(2, modalTetap > 0 ? 'Masukkan semua sisa uang tunai ke amplop.' : 'Masukkan semua uang tunai ke amplop.'),
            _langkah(3, 'Label amplop dicetak di printer struk. Tempel di amplop (atau tulis: nama $namaKasir, tanggal & jam).'),
            _langkah(4, 'Serahkan amplop ke SPV/Admin. Mereka yang menghitung, dan selisihnya tercatat atas nama $namaKasir.'),
            const SizedBox(height: 10),
            const KotakPesan('Setelah ini shift tidak bisa dipakai berjualan lagi.', jenis: JenisPesan.perhatian),
          ]),
        ),
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          FilledButton.icon(
            key: const ValueKey('konfirmasi-belum-dihitung'),
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.mail_outline),
            label: const Text('Tutup shift & cetak label'),
          ),
        ],
      );
}

/// SPV/Admin: daftar shift yang ditutup "Belum dihitung", klik untuk mengisi hasil hitungan amplop.
class IsiShiftMenunggu extends StatefulWidget {
  const IsiShiftMenunggu({super.key});
  @override
  State<IsiShiftMenunggu> createState() => _IsiShiftMenungguState();
}

class _IsiShiftMenungguState extends State<IsiShiftMenunggu> {
  late List<ShiftMenunggu> _daftar;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  void _muat() => setState(() => _daftar = context.app.penjualan.shiftMenungguDihitung(context.app.cabang.id));

  Future<void> _hitung(ShiftMenunggu m) async {
    await showDialog<void>(context: context, barrierDismissible: false, builder: (_) => DialogHitungAmplop(shift: m));
    if (!mounted) return;
    _muat();
    context.app.segarkan();
  }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(24), children: [
        const KotakPesan(
          'Shift yang ditutup kasir tanpa menghitung uang. Hitung isi amplopnya, lalu klik shift untuk mengisi hasilnya. '
          'Selisih tercatat atas nama kasir shift itu.',
          jenis: JenisPesan.info,
        ),
        const SizedBox(height: 16),
        Panel(
          judul: 'Menunggu dihitung (${_daftar.length})',
          warnaKepala: _daftar.isEmpty ? null : Warna.oranyeMuda,
          padding: EdgeInsets.zero,
          child: _daftar.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Tidak ada shift yang menunggu dihitung.', style: TextStyle(fontSize: 17, color: Warna.teksPudar)),
                )
              : TabelSederhana(
                  kolom: const ['Kasir', 'Dibuka', 'Ditutup', 'Transaksi', 'Modal di kasir'],
                  lebar: const [3, 4, 4, 2, 3],
                  rataKanan: const {3, 4},
                  onTap: (i) => _hitung(_daftar[i]),
                  baris: [
                    for (final m in _daftar)
                      [
                        Text(m.namaKasir, style: gayaSelTebal),
                        Text(formatLayar(m.dibukaPada), style: gayaSel),
                        Text(formatLayar(m.ditutupPada), style: gayaSel),
                        Text('${m.jumlahTransaksi}', style: gayaSel),
                        Text(formatRupiah(m.modalDitinggal), style: gayaSel),
                      ],
                  ],
                ),
        ),
      ]);
}

/// SPV/Admin mengisi hasil hitungan amplop. Uang seharusnya dan selisih baru tampil setelah disimpan.
class DialogHitungAmplop extends StatefulWidget {
  const DialogHitungAmplop({super.key, required this.shift});
  final ShiftMenunggu shift;
  @override
  State<DialogHitungAmplop> createState() => _DialogHitungAmplopState();
}

class _DialogHitungAmplopState extends State<DialogHitungAmplop> {
  final _c = TextEditingController();
  int? _nilai;
  HasilHitungAmplop? _hasil;
  bool _sibuk = false;
  String? _galat;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _simpan() async {
    if (_nilai == null || _sibuk) return;
    final m = widget.shift;
    final ok = await konfirmasi(context,
        judul: 'Simpan hasil hitungan?',
        isi: 'Isi amplop ${m.namaKasir}: ${formatRupiah(_nilai!)}. Hasil ini tidak bisa diubah lagi.',
        ya: 'Simpan');
    if (!ok || !mounted) return;
    setState(() => _sibuk = true);
    try {
      final app = context.app;
      final h = app.penjualan.hitungAmplop(shiftId: m.shiftId, amplopDihitung: _nilai!, oleh: app.penggunaAktif!);
      setState(() {
        _hasil = h;
        _galat = null;
      });
    } catch (e) {
      setState(() => _galat = pesanGalat(e));
    } finally {
      if (mounted) setState(() => _sibuk = false);
    }
  }

  Widget _baris(String a, String b, {bool tebal = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(child: Text(a, style: TextStyle(fontSize: 17, fontWeight: tebal ? FontWeight.w800 : FontWeight.w500))),
          Text(b, style: TextStyle(fontSize: 17, fontWeight: tebal ? FontWeight.w800 : FontWeight.w600)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final m = widget.shift;
    final h = _hasil;
    return AlertDialog(
      title: Text('Hitung amplop: ${m.namaKasir}', style: const TextStyle(fontWeight: FontWeight.w800)),
      content: SizedBox(
        width: 540,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _baris('Shift', '${formatLayar(m.dibukaPada)} – ${formatJam(m.ditutupPada)}'),
          _baris('Jumlah transaksi', '${m.jumlahTransaksi}'),
          _baris('Modal ditinggal di kasir', formatRupiah(m.modalDitinggal)),
          const Divider(height: 22),
          if (h == null) ...[
            InputRupiah(
              key: const ValueKey('isi-amplop'),
              controller: _c,
              autofocus: true,
              besar: true,
              label: 'Uang di dalam amplop',
              onChanged: (n) => setState(() => _nilai = _c.text.isEmpty ? null : n),
              onSubmitted: (_) => _simpan(),
            ),
          ] else ...[
            _baris('Isi amplop dihitung', formatRupiah(h.amplopDihitung), tebal: true),
            _baris('Isi amplop seharusnya', formatRupiah(h.amplopSeharusnya)),
            const SizedBox(height: 10),
            KotakPesan(
              key: const ValueKey('hasil-amplop'),
              h.selisih == 0
                  ? 'Uang pas, tidak ada selisih.'
                  : '${h.selisih < 0 ? 'Uang KURANG' : 'Uang LEBIH'} ${formatRupiah(h.selisih.abs())}. Tercatat atas nama ${m.namaKasir}.',
              jenis: h.selisih == 0 ? JenisPesan.berhasil : JenisPesan.perhatian,
            ),
          ],
          if (_galat != null) ...[const SizedBox(height: 12), KotakPesan(_galat!, jenis: JenisPesan.galat)],
        ]),
      ),
      actions: h == null
          ? [
              OutlinedButton(onPressed: _sibuk ? null : () => Navigator.pop(context), child: const Text('Batal')),
              FilledButton(
                key: const ValueKey('simpan-amplop'),
                onPressed: _nilai == null || _sibuk ? null : _simpan,
                child: Text(_sibuk ? 'Menyimpan…' : 'Simpan hasil hitungan'),
              ),
            ]
          : [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Selesai'))],
    );
  }
}

// ============================================================================ kas keluar / masuk

/// Catat kas keluar/masuk dari layar kasir. Mengembalikan true kalau tersimpan.
Future<bool?> kasDialog(BuildContext context) =>
    showDialog<bool>(context: context, barrierDismissible: false, builder: (_) => const DialogKas());

class DialogKas extends StatefulWidget {
  const DialogKas({super.key});
  @override
  State<DialogKas> createState() => _DialogKasState();
}

class _DialogKasState extends State<DialogKas> {
  JenisKas _jenis = JenisKas.keluar;
  final _jumlah = TextEditingController();
  final _ket = TextEditingController();
  int _nilai = 0;
  bool _sibuk = false;
  String? _galat;
  late List<KasShift> _daftar;

  static const _contohKeluar = ['Bayar titipan', 'Beli barang dari sales', 'Beli keperluan toko'];
  static const _contohMasuk = ['Tambah uang kecil', 'Uang dari pemilik'];

  @override
  void initState() {
    super.initState();
    _daftar = context.app.penjualan.daftarKas(context.app.shiftAktif!.id);
  }

  @override
  void dispose() {
    _jumlah.dispose();
    _ket.dispose();
    super.dispose();
  }

  Future<void> _simpan() async {
    if (_sibuk) return;
    final g = cekKas(jumlah: _nilai, keterangan: _ket.text);
    if (g != null) return setState(() => _galat = g);
    final app = context.app;
    final p = app.penggunaAktif!;
    Pengguna? spv;
    if (aksesKas(p.peran, _nilai) == Akses.pinSpv) {
      spv = await mintaPinSpv(context, alasan: '${_jenis.label} ${formatRupiah(_nilai)}: mulai ${formatRupiah(batasKasTanpaPin)} perlu persetujuan SPV.');
      if (spv == null || !mounted) return;
    }
    setState(() => _sibuk = true);
    try {
      app.penjualan.catatKas(
        shiftId: app.shiftAktif!.id,
        jenis: _jenis,
        jumlah: _nilai,
        keterangan: _ket.text,
        oleh: p,
        disetujuiOleh: spv,
      );
      if (!mounted) return;
      tampilkanPesan(context, '${_jenis.label} ${formatRupiah(_nilai)} tercatat.');
      Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _sibuk = false;
        _galat = pesanGalat(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.app.penggunaAktif!;
    final perluPin = aksesKas(p.peran, _nilai) == Akses.pinSpv;
    final keluar = _jenis == JenisKas.keluar;
    return AlertDialog(
      title: const Text('Kas keluar / masuk', style: TextStyle(fontWeight: FontWeight.w800)),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SegmentedButton<JenisKas>(
              segments: const [
                ButtonSegment(value: JenisKas.keluar, label: Text('Kas keluar'), icon: Icon(Icons.north_east)),
                ButtonSegment(value: JenisKas.masuk, label: Text('Kas masuk'), icon: Icon(Icons.south_west)),
              ],
              selected: {_jenis},
              onSelectionChanged: (v) => setState(() {
                _jenis = v.first;
                _galat = null;
              }),
            ),
            const SizedBox(height: 8),
            Text(
              keluar ? 'Uang diambil dari uang kasir, mis. bayar orang yang titip jual atau beli barang dari sales.' : 'Uang ditambahkan ke uang kasir.',
              style: const TextStyle(fontSize: 15.5, color: Warna.teksPudar, height: 1.4),
            ),
            const SizedBox(height: 14),
            InputRupiah(
              key: const ValueKey('jumlah-kas'),
              controller: _jumlah,
              autofocus: true,
              besar: true,
              label: 'Jumlah uang',
              onChanged: (n) => setState(() {
                _nilai = n;
                _galat = null;
              }),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('keterangan-kas'),
              controller: _ket,
              maxLength: 100,
              style: const TextStyle(fontSize: 19),
              decoration: const InputDecoration(labelText: 'Keterangan (untuk apa)', hintText: 'contoh: bayar titipan kue Bu Ani'),
              onChanged: (_) => setState(() => _galat = null),
              onSubmitted: (_) => _simpan(),
            ),
            Wrap(spacing: 8, runSpacing: 6, children: [
              for (final c in keluar ? _contohKeluar : _contohMasuk)
                ActionChip(
                  label: Text(c),
                  onPressed: () => setState(() {
                    _ket.text = c;
                    _ket.selection = TextSelection.collapsed(offset: c.length);
                    _galat = null;
                  }),
                ),
            ]),
            if (perluPin) ...[
              const SizedBox(height: 12),
              KotakPesan('Mulai ${formatRupiah(batasKasTanpaPin)} perlu PIN SPV.', jenis: JenisPesan.perhatian),
            ],
            if (_galat != null) ...[const SizedBox(height: 12), KotakPesan(_galat!, jenis: JenisPesan.galat)],
            if (_daftar.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('Sudah dicatat di shift ini', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Warna.teksPudar)),
              for (final k in _daftar)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    SizedBox(width: 56, child: Text(formatJam(k.waktu), style: const TextStyle(fontSize: 15, color: Warna.teksPudar))),
                    Expanded(child: Text(k.keterangan, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15.5))),
                    Text('${k.jenis == JenisKas.keluar ? '−' : '+'} ${formatRupiah(k.jumlah)}',
                        style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: k.jenis == JenisKas.keluar ? Warna.merah : Warna.suksesTua)),
                  ]),
                ),
            ],
          ]),
        ),
      ),
      actions: [
        OutlinedButton(onPressed: _sibuk ? null : () => Navigator.pop(context, false), child: const Text('Batal (Esc)')),
        FilledButton(
          key: const ValueKey('simpan-kas'),
          onPressed: _sibuk ? null : _simpan,
          child: Text(_sibuk ? 'Menyimpan…' : (perluPin ? 'Simpan (PIN SPV)' : 'Simpan')),
        ),
      ],
    );
  }
}
