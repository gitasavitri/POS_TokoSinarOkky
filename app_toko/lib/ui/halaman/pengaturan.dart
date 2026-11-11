import 'package:flutter/material.dart';
import 'package:pos_core/pos_core.dart';

import '../../data/repo/pengaturan_repo.dart';
import '../../layanan/aplikasi.dart';
import '../../layanan/sinkron.dart';
import '../komponen/umum.dart';
import '../tema.dart';
import 'transaksi.dart';

/// Pengaturan printer (per PC), info toko, kategori & supplier, cadangan data.
class IsiPengaturan extends StatefulWidget {
  const IsiPengaturan({super.key, this.hanyaPrinter = false});
  final bool hanyaPrinter;
  @override
  State<IsiPengaturan> createState() => _IsiPengaturanState();
}

class _IsiPengaturanState extends State<IsiPengaturan> {
  List<String> _printer = [];
  String? _pilih;
  String? _galatDaftar;

  Aplikasi get app => context.app;

  @override
  void initState() {
    super.initState();
    _cariPrinter();
  }

  void _cariPrinter() {
    try {
      _printer = app.printer.daftarPrinter();
      _galatDaftar = null;
    } catch (e) {
      _printer = [];
      _galatDaftar = 'Gagal membaca daftar printer: ${pesanGalat(e)}';
    }
    _pilih = app.namaPrinter;
    if (_pilih != null && !_printer.contains(_pilih)) _printer = [_pilih!, ..._printer];
    setState(() {});
  }

  Future<void> _tesCetak() async {
    final galat = await app.kirimKePrinter(cetakTes(namaToko: app.cabang.namaToko, namaCabang: app.cabang.nama, potongKertas: app.potongKertas));
    if (mounted) tampilkanPesan(context, galat ?? 'Tes cetak terkirim. Cek baris angka 1–32 muat satu baris.', galat: galat != null);
  }

  @override
  Widget build(BuildContext context) {
    final p = app.pengaturan;
    final admin = app.penggunaAktif?.peran == Peran.admin;
    return ListView(padding: const EdgeInsets.all(24), children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          flex: 3,
          child: Panel(
            judul: 'Printer struk (khusus PC ini)',
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (_galatDaftar != null) ...[KotakPesan(_galatDaftar!, jenis: JenisPesan.galat), const SizedBox(height: 12)],
              DropdownButtonFormField<String>(
                initialValue: _pilih,
                decoration: const InputDecoration(labelText: 'Printer yang dipakai'),
                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: Warna.teks, fontFamily: fontUtama),
                items: [for (final n in _printer) DropdownMenuItem(value: n, child: Text(n))],
                onChanged: (v) => setState(() {
                  _pilih = v;
                  p.simpan(PengaturanRepo.kPrinter, v);
                }),
              ),
              const SizedBox(height: 6),
              const Text('Daftar ini diambil dari printer yang sudah terpasang di Windows. Printer baru: pasang drivernya dulu, lalu tekan Cari ulang.',
                  style: TextStyle(fontSize: 15, color: Warna.teksPudar)),
              const SizedBox(height: 14),
              SwitchListTile(
                value: app.cetakOtomatis,
                onChanged: (v) => setState(() => p.simpanBool(PengaturanRepo.kCetakOtomatis, v)),
                title: const Text('Cetak struk otomatis setelah bayar', style: TextStyle(fontSize: 17.5, fontWeight: FontWeight.w700)),
                subtitle: const Text('Kalau mati, kasir menekan tombol Cetak sendiri'),
              ),
              SwitchListTile(
                value: app.potongKertas,
                onChanged: (v) => setState(() => p.simpanBool(PengaturanRepo.kPotongKertas, v)),
                title: const Text('Potong kertas otomatis', style: TextStyle(fontSize: 17.5, fontWeight: FontWeight.w700)),
                subtitle: const Text('Hanya untuk printer yang punya pisau pemotong'),
              ),
              ListTile(
                title: const Text('Jumlah salinan struk', style: TextStyle(fontSize: 17.5, fontWeight: FontWeight.w700)),
                trailing: PengaturJumlah(
                  nilai: app.salinanStruk,
                  onUbah: (v) => setState(() => p.simpan(PengaturanRepo.kSalinanStruk, '${v.clamp(1, 3)}')),
                ),
              ),
              const SizedBox(height: 10),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                OutlinedButton(onPressed: _cariPrinter, child: const Text('Cari ulang printer')),
                const SizedBox(width: 10),
                FilledButton.icon(onPressed: _pilih == null ? null : _tesCetak, icon: const Icon(Icons.print), label: const Text('Tes cetak')),
              ]),
            ]),
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          flex: 2,
          child: Panel(
            judul: 'Contoh tes cetak',
            child: SizedBox(
              height: 330,
              child: PratinjauStruk(baris: [
                BarisStruk(app.cabang.namaToko, rata: Rata.tengah, tebal: true, besar: true),
                BarisStruk('Cabang ${app.cabang.nama}', rata: Rata.tengah),
                BarisStruk(garis()),
                const BarisStruk('TES CETAK', rata: Rata.tengah, tebal: true),
                BarisStruk(kiriKanan('Lebar kertas', '58 mm')),
                BarisStruk(kiriKanan('Huruf per baris', '32')),
                const BarisStruk('12345678901234567890123456789012'),
                BarisStruk(garis()),
              ]),
            ),
          ),
        ),
      ]),
      const SizedBox(height: 16),
      const KotakPesan(
        'Printer harus printer thermal 58 mm yang mendukung ESC/POS, tersambung USB, dan drivernya sudah terpasang di Windows. '
        'Scanner barcode USB langsung terbaca seperti keyboard, tidak perlu disetel.',
        jenis: JenisPesan.info,
      ),
      if (!widget.hanyaPrinter) ...[
        const SizedBox(height: 20),
        if (admin) _InfoToko(onSimpan: () => setState(() {})),
        if (admin) const SizedBox(height: 20),
        if (admin) const _ModalTetap(),
        if (admin) const SizedBox(height: 20),
        if (admin) const _KategoriSupplier(),
        if (admin) const SizedBox(height: 20),
        _KantorPusat(bolehAtur: admin),
        const SizedBox(height: 20),
        Panel(
          judul: 'Data & cadangan',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _Baris('Data penjualan tersimpan di', 'Komputer ini (tetap jalan tanpa internet)'),
            _Baris('Lokasi file database', app.lokasiDatabase ?? '-'),
            _Baris('Cadangan otomatis', 'Tiap 1 jam & setiap tutup shift → ${app.folderCadangan} (14 terbaru disimpan)'),
            _Baris('Cadangan terakhir', () {
              final t = DateTime.tryParse(app.pengaturan.ambil(PengaturanRepo.kCadanganTerakhir) ?? '');
              return t == null ? 'Belum ada' : '${formatJam(t)} · ${formatTanggal(t)}';
            }()),
            const SizedBox(height: 8),
            if (admin) const _FlashdiskCadangan(),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: () async {
                  try {
                    final f = app.cadangkan();
                    if (context.mounted) tampilkanPesan(context, 'Tersimpan: $f');
                    setState(() {});
                  } catch (e) {
                    if (context.mounted) tampilkanPesan(context, 'Gagal: ${pesanGalat(e)}', galat: true);
                  }
                },
                icon: const Icon(Icons.save_alt),
                label: const Text('Cadangkan sekarang'),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Kalau suatu saat database rusak (mis. hardisk bermasalah), aplikasi otomatis menawarkan pemulihan dari cadangan ini '
              'saat dibuka, dengan PIN SPV/Admin.',
              style: TextStyle(fontSize: 15, color: Warna.teksPudar),
            ),
          ]),
        ),
      ],
    ]);
  }
}

/// Admin: salin cadangan juga ke flashdisk (huruf drive).
class _FlashdiskCadangan extends StatefulWidget {
  const _FlashdiskCadangan();
  @override
  State<_FlashdiskCadangan> createState() => _FlashdiskCadanganState();
}

class _FlashdiskCadanganState extends State<_FlashdiskCadangan> {
  late final _drive = TextEditingController(text: context.app.pengaturan.ambil(PengaturanRepo.kFolderCadangan2) ?? '');

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
          child: TextField(
            controller: _drive,
            style: const TextStyle(fontSize: 18),
            decoration: const InputDecoration(
              labelText: 'Salin juga ke flashdisk (huruf drive, mis. E:) — boleh kosong',
              helperText: 'Kalau flashdisk tidak tercolok, cadangan tetap tersimpan di PC.',
            ),
          ),
        ),
        const SizedBox(width: 12),
        OutlinedButton(
          onPressed: () {
            final d = _drive.text.trim().toUpperCase().replaceAll(RegExp(r'[\\/]+$'), '');
            if (d.isNotEmpty && !RegExp(r'^[A-Z]:$').hasMatch(d)) {
              tampilkanPesan(context, 'Isi huruf drive saja, contoh E:', galat: true);
              return;
            }
            context.app.pengaturan.simpan(PengaturanRepo.kFolderCadangan2, d.isEmpty ? null : d);
            _drive.text = d;
            tampilkanPesan(context, d.isEmpty ? 'Salinan ke flashdisk dimatikan.' : 'Cadangan berikutnya juga disalin ke $d\\POS-Cadangan.');
          },
          child: const Text('Simpan'),
        ),
      ]);
}

/// Admin: modal tetap toko (revisi P). Dipakai saat shift ditutup "Belum dihitung" dan sebagai isian awal buka shift.
class _ModalTetap extends StatefulWidget {
  const _ModalTetap();
  @override
  State<_ModalTetap> createState() => _ModalTetapState();
}

class _ModalTetapState extends State<_ModalTetap> {
  late final _c = TextEditingController(text: context.app.pengaturan.modalTetap == 0 ? '' : formatAngka(context.app.pengaturan.modalTetap));
  late int _nilai = context.app.pengaturan.modalTetap;

  void _simpan() {
    final app = context.app;
    try {
      app.pengaturan.aturModalTetap(_nilai, cabangId: app.cabang.id, oleh: app.penggunaAktif!);
      tampilkanPesan(context, _nilai == 0 ? 'Modal tetap dimatikan: semua uang masuk amplop.' : 'Modal tetap ${formatRupiah(_nilai)} tersimpan.');
    } catch (e) {
      tampilkanPesan(context, pesanGalat(e), galat: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Panel(
        judul: 'Modal tetap kasir (Admin)',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text(
            'Uang modal yang selalu tetap di kasir. Kalau shift ditutup "Belum dihitung", uang sebesar ini ditinggal di kasir '
            'untuk shift berikutnya dan sisanya dimasukkan ke amplop. Juga jadi isian awal saat buka shift. Kosongkan kalau tidak dipakai.',
            style: TextStyle(fontSize: 15.5, color: Warna.teksPudar, height: 1.4),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: InputRupiah(
                key: const ValueKey('modal-tetap'),
                controller: _c,
                label: 'Modal tetap',
                onChanged: (n) => _nilai = n,
                onSubmitted: (_) => _simpan(),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton(onPressed: _simpan, child: const Text('Simpan')),
          ]),
        ]),
      );
}

class _Baris extends StatelessWidget {
  const _Baris(this.a, this.b);
  final String a;
  final String b;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 280, child: Text(a, style: const TextStyle(fontSize: 17))),
          Expanded(child: SelectableText(b, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
        ]),
      );
}

class _InfoToko extends StatefulWidget {
  const _InfoToko({required this.onSimpan});
  final VoidCallback onSimpan;
  @override
  State<_InfoToko> createState() => _InfoTokoState();
}

class _InfoTokoState extends State<_InfoToko> {
  late final c = context.app.cabang;
  late final _toko = TextEditingController(text: c.namaToko);
  late final _nama = TextEditingController(text: c.nama);
  late final _alamat = TextEditingController(text: c.alamat);
  late final _pesan = TextEditingController(text: c.pesanStruk);

  @override
  Widget build(BuildContext context) => Panel(
        judul: 'Info toko di struk (Admin)',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: TextField(controller: _toko, style: const TextStyle(fontSize: 18), decoration: const InputDecoration(labelText: 'Nama toko'))),
            const SizedBox(width: 14),
            Expanded(child: TextField(controller: _nama, style: const TextStyle(fontSize: 18), decoration: const InputDecoration(labelText: 'Nama cabang'))),
            const SizedBox(width: 14),
            SizedBox(width: 140, child: InputDecorator(decoration: const InputDecoration(labelText: 'Kode cabang'), child: Text(c.kode, style: const TextStyle(fontSize: 18)))),
          ]),
          const SizedBox(height: 14),
          TextField(controller: _alamat, style: const TextStyle(fontSize: 18), decoration: const InputDecoration(labelText: 'Alamat')),
          const SizedBox(height: 14),
          TextField(controller: _pesan, style: const TextStyle(fontSize: 18), decoration: const InputDecoration(labelText: 'Pesan di bawah struk')),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: () {
                final app = context.app;
                final galat = cekPesanStruk(_pesan.text);
                if (galat != null) return tampilkanPesan(context, galat, galat: true);
                app.pengaturan.ubahInfoCabang(
                  cabangId: c.id,
                  nama: _nama.text,
                  alamat: _alamat.text,
                  pesanStruk: _pesan.text,
                  namaToko: _toko.text,
                  olehId: app.penggunaAktif!.id,
                );
                tampilkanPesan(context, 'Info toko disimpan.');
                app.segarkan();
                widget.onSimpan();
              },
              child: const Text('Simpan info toko'),
            ),
          ),
        ]),
      );
}

class _KategoriSupplier extends StatefulWidget {
  const _KategoriSupplier();
  @override
  State<_KategoriSupplier> createState() => _KategoriSupplierState();
}

class _KategoriSupplierState extends State<_KategoriSupplier> {
  final _kat = TextEditingController();
  final _sup = TextEditingController();

  void _tambah(bool kategori) {
    final app = context.app;
    final c = kategori ? _kat : _sup;
    try {
      if (kategori) {
        app.katalog.tambahKategori(c.text, cabangId: app.cabang.id, olehId: app.penggunaAktif!.id);
      } else {
        app.katalog.tambahSupplier(c.text, cabangId: app.cabang.id, olehId: app.penggunaAktif!.id);
      }
      c.clear();
      setState(() {});
    } catch (e) {
      tampilkanPesan(context, pesanGalat(e), galat: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    Widget kolom(String judul, List<String> isi, TextEditingController c, bool kategori) => Expanded(
          child: Panel(
            judul: judul,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Wrap(spacing: 8, runSpacing: 8, children: [for (final n in isi) Chip(label: Text(n, style: const TextStyle(fontSize: 16)))]),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: c,
                    style: const TextStyle(fontSize: 18),
                    decoration: InputDecoration(hintText: kategori ? 'Nama kategori baru' : 'Nama supplier baru'),
                    onSubmitted: (_) => _tambah(kategori),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(height: 56, child: OutlinedButton(onPressed: () => _tambah(kategori), child: const Text('Tambah'))),
              ]),
            ]),
          ),
        );
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      kolom('Kategori barang', [for (final k in app.katalog.kategori()) k.nama], _kat, true),
      const SizedBox(width: 18),
      kolom('Supplier', [for (final s in app.katalog.supplier()) s.nama], _sup, false),
    ]);
  }
}

/// Status kirim data ke kantor pusat + pendaftaran PC ini (Admin).
class _KantorPusat extends StatefulWidget {
  const _KantorPusat({required this.bolehAtur});
  final bool bolehAtur;
  @override
  State<_KantorPusat> createState() => _KantorPusatState();
}

class _KantorPusatState extends State<_KantorPusat> {
  final _alamat = TextEditingController();
  final _kode = TextEditingController();
  final _nama = TextEditingController(text: 'PC kasir 1');
  bool _sibuk = false;

  Future<void> _daftar() async {
    final app = context.app;
    setState(() => _sibuk = true);
    try {
      await app.sinkron.daftar(alamat: _alamat.text, kode: _kode.text, namaPerangkat: _nama.text, olehId: app.penggunaAktif!.id);
      if (mounted) tampilkanPesan(context, 'PC ini sudah terdaftar. Data mulai dikirim ke kantor pusat.');
      _kode.clear();
    } on GalatSinkron catch (e) {
      if (mounted) tampilkanPesan(context, e.pesan, galat: true);
    } finally {
      if (mounted) setState(() => _sibuk = false);
    }
  }

  /// Server sama, alamat berbeda (mis. PC kasir pindah ke komputer sendiri, atau pakai alamat https tunnel).
  Future<void> _gantiAlamat(LayananSinkron s) async {
    final isian = TextEditingController(text: s.alamatServer ?? '');
    String? galat;
    var sibuk = false;
    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, atur) => AlertDialog(
          title: const Text('Ganti alamat server', style: TextStyle(fontWeight: FontWeight.w800)),
          content: SizedBox(
            width: 520,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text(
                'Untuk server yang sama dengan alamat baru, tanpa kode pendaftaran baru. Contoh:\n'
                '• http://localhost:3000 (server di PC ini)\n'
                '• http://192.168.1.10:3000 (server di PC lain di toko)\n'
                '• https://pos.tokoanda.com (lewat internet)',
                style: TextStyle(fontSize: 15.5, height: 1.5, color: Warna.teksPudar),
              ),
              const SizedBox(height: 14),
              TextField(
                key: const ValueKey('alamat-server-baru'),
                controller: isian,
                autofocus: true,
                style: const TextStyle(fontSize: 18),
                decoration: InputDecoration(labelText: 'Alamat server baru', errorText: galat),
              ),
            ]),
          ),
          actions: [
            OutlinedButton(onPressed: sibuk ? null : () => Navigator.pop(c), child: const Text('Batal')),
            FilledButton(
              onPressed: sibuk
                  ? null
                  : () async {
                      atur(() {
                        sibuk = true;
                        galat = null;
                      });
                      try {
                        await s.gantiAlamat(alamat: isian.text, olehId: context.app.penggunaAktif!.id);
                        if (c.mounted) Navigator.pop(c);
                        if (mounted) tampilkanPesan(context, 'Alamat server diganti.');
                      } catch (e) {
                        atur(() {
                          sibuk = false;
                          galat = pesanGalat(e);
                        });
                      }
                    },
              child: Text(sibuk ? 'Mengecek…' : 'Simpan'),
            ),
          ],
        ),
      ),
    );
    // isian tidak di-dispose di sini: dialog masih memakainya selama animasi menutup.
  }

  @override
  Widget build(BuildContext context) {
    final s = context.app.sinkron;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final terakhir = s.terakhirBerhasil;
        final antrean = s.antrean;
        return Panel(
          judul: 'Kirim data ke kantor pusat',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (s.terdaftar) ...[
              _Baris('Server', s.alamatServer ?? '-'),
              _Baris('Terakhir berhasil', terakhir == null ? 'Belum pernah' : '${formatJam(terakhir)} · ${formatTanggal(terakhir)}'),
              _Baris('Menunggu dikirim', antrean == 0 ? 'Tidak ada, semua sudah terkirim' : '$antrean data (dikirim otomatis tiap menit)'),
              if (s.galatTerakhir != null) ...[const SizedBox(height: 8), KotakPesan(s.galatTerakhir!, jenis: JenisPesan.perhatian)],
              if (s.ditolakTerakhir.isNotEmpty) ...[
                const SizedBox(height: 8),
                KotakPesan('Ditolak server: ${s.ditolakTerakhir.take(3).join(' · ')}', jenis: JenisPesan.perhatian),
              ],
              if (s.masalahTerakhir.isNotEmpty) ...[
                const SizedBox(height: 8),
                KotakPesan('Perlu dicek: ${s.masalahTerakhir.take(3).join(' · ')}', jenis: JenisPesan.perhatian),
              ],
              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                if (widget.bolehAtur) ...[
                  OutlinedButton(
                    key: const ValueKey('ganti-alamat-server'),
                    onPressed: () => _gantiAlamat(s),
                    child: const Text('Ganti alamat'),
                  ),
                  const SizedBox(width: 10),
                ],
                if (widget.bolehAtur)
                  OutlinedButton(
                    onPressed: () async {
                      final ok = await konfirmasi(context,
                          judul: 'Putuskan dari kantor pusat?',
                          isi: 'PC ini berhenti mengirim data. Untuk menyambung lagi perlu kode pendaftaran baru dari Admin pusat.',
                          ya: 'Putuskan',
                          bahaya: true);
                      if (ok) s.lupakanServer();
                    },
                    child: const Text('Putuskan'),
                  ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: s.sedangJalan ? null : s.sinkronSekarang,
                  icon: const Icon(Icons.sync),
                  label: Text(s.sedangJalan ? 'Mengirim…' : 'Kirim sekarang'),
                ),
              ]),
            ] else if (!widget.bolehAtur)
              const Text('Belum tersambung ke kantor pusat. Minta Admin mendaftarkan PC ini.', style: TextStyle(fontSize: 17))
            else ...[
              const Text(
                'Belum tersambung. Minta kode pendaftaran ke Admin pusat (berlaku 24 jam, sekali pakai), lalu isi di sini. '
                'Penjualan tetap jalan walau internet putus.',
                style: TextStyle(fontSize: 16, color: Warna.teksPudar),
              ),
              const SizedBox(height: 14),
              TextField(controller: _alamat, style: const TextStyle(fontSize: 18), decoration: const InputDecoration(labelText: 'Alamat server', hintText: 'https://pos.tokoanda.com')),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: TextField(controller: _kode, style: const TextStyle(fontSize: 20, letterSpacing: 2), decoration: const InputDecoration(labelText: 'Kode pendaftaran', hintText: 'ABCDE-FGHJK'))),
                const SizedBox(width: 14),
                Expanded(child: TextField(controller: _nama, style: const TextStyle(fontSize: 18), decoration: const InputDecoration(labelText: 'Nama PC ini'))),
              ]),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(onPressed: _sibuk ? null : _daftar, child: Text(_sibuk ? 'Mendaftarkan…' : 'Daftarkan PC ini')),
              ),
            ],
          ]),
        );
      },
    );
  }
}
