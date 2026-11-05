import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pos_core/pos_core.dart';
import 'package:pos_ui/pos_ui.dart';

import '../data/model.dart';
import '../layanan/sesi.dart';
import 'halaman/barang.dart';
import 'halaman/karyawan.dart';
import 'halaman/log.dart';
import 'halaman/ringkasan.dart';
import 'halaman/stok.dart';
import 'halaman/toko.dart';
import 'halaman/transaksi.dart';
import 'komponen.dart';

class AplikasiPusat extends StatefulWidget {
  const AplikasiPusat({super.key, required this.sesi});
  final Sesi sesi;
  @override
  State<AplikasiPusat> createState() => _AplikasiPusatState();
}

class _AplikasiPusatState extends State<AplikasiPusat> {
  bool _tombol(KeyEvent _) {
    widget.sesi.adaAktivitas();
    return false;
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_tombol);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_tombol);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SesiScope(
        sesi: widget.sesi,
        child: MaterialApp(
          title: 'POS Pusat',
          debugShowCheckedModeBanner: false,
          theme: buatTema(),
          builder: (context, child) => Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => widget.sesi.adaAktivitas(),
            child: child,
          ),
          home: const _Akar(),
        ),
      );
}

class _Akar extends StatelessWidget {
  const _Akar();
  @override
  Widget build(BuildContext context) {
    final s = SesiScope.of(context, dengar: true);
    if (s.server == null) return const HalamanServer();
    if (s.admin == null) return const HalamanMasuk(key: ValueKey('masuk'));
    return const HalamanUtama();
  }
}

/// Kerangka layar masuk: panel hijau kiri + kartu putih kanan.
class _LayarDepan extends StatelessWidget {
  const _LayarDepan({required this.judul, required this.child});
  final String judul;
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            width: 460,
            decoration: const BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Warna.utamaTua, Warna.utama, Warna.utamaTerang]),
            ),
            padding: const EdgeInsets.all(48),
            child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.store_mall_directory_outlined, color: Colors.white, size: 56),
              SizedBox(height: 18),
              Text('Kantor Pusat', style: TextStyle(color: Colors.white, fontSize: 38, fontWeight: FontWeight.w800, height: 1.1)),
              SizedBox(height: 8),
              Text('Laporan semua toko, harga, dan perangkat', style: TextStyle(color: Warna.utamaTeksTerang, fontSize: 19)),
              Spacer(),
              Text('Aplikasi ini tidak dipakai untuk berjualan.\nData berasal dari PC kasir di setiap toko.',
                  style: TextStyle(color: Warna.utamaTeksTerang, fontSize: 16, height: 1.5)),
            ]),
          ),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Container(
                  width: 520,
                  padding: const EdgeInsets.all(36),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                    Text(judul, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 22),
                    child,
                  ]),
                ),
              ),
            ),
          ),
        ]),
      );
}

class HalamanServer extends StatefulWidget {
  const HalamanServer({super.key});
  @override
  State<HalamanServer> createState() => _HalamanServerState();
}

class _HalamanServerState extends State<HalamanServer> {
  final _alamat = TextEditingController(text: 'https://');
  String? _galat;
  bool _sibuk = false;

  Future<void> _simpan() async {
    setState(() {
      _sibuk = true;
      _galat = null;
    });
    try {
      await context.sesi.aturServer(_alamat.text);
    } on GalatServer catch (e) {
      setState(() => _galat = e.pesan);
    } finally {
      if (mounted) setState(() => _sibuk = false);
    }
  }

  @override
  Widget build(BuildContext context) => _LayarDepan(
        judul: 'Alamat Server Pusat',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Diisi sekali saja. Minta alamatnya ke orang yang memasang server (VPS).', style: TextStyle(fontSize: 17, color: Warna.teksPudar)),
          const SizedBox(height: 18),
          TextField(
            controller: _alamat,
            autofocus: true,
            style: const TextStyle(fontSize: 20),
            decoration: const InputDecoration(labelText: 'Alamat server', hintText: 'https://pos.tokoanda.com'),
            onSubmitted: (_) => _simpan(),
          ),
          if (_galat != null) ...[const SizedBox(height: 14), KotakPesan(_galat!, jenis: JenisPesan.galat)],
          const SizedBox(height: 22),
          FilledButton(onPressed: _sibuk ? null : _simpan, child: Text(_sibuk ? 'Memeriksa…' : 'Simpan & periksa')),
        ]),
      );
}

class HalamanMasuk extends StatefulWidget {
  const HalamanMasuk({super.key});
  @override
  State<HalamanMasuk> createState() => _HalamanMasukState();
}

class _HalamanMasukState extends State<HalamanMasuk> {
  final _nama = TextEditingController();
  final _sandi = TextEditingController();
  final _kode = TextEditingController();
  String? _galat;
  bool _sibuk = false;

  Future<void> _masuk() async {
    setState(() {
      _sibuk = true;
      _galat = null;
    });
    try {
      await context.sesi.masuk(_nama.text, _sandi.text, _kode.text);
    } on GalatServer catch (e) {
      if (mounted) {
        setState(() => _galat = e.pesan);
        _sandi.clear();
        _kode.clear();
      }
    } finally {
      if (mounted) setState(() => _sibuk = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.sesi;
    return _LayarDepan(
      judul: 'Masuk Admin pusat',
      child: AutofillGroup(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (s.pesanMasuk != null) ...[KotakPesan(s.pesanMasuk!, jenis: JenisPesan.info), const SizedBox(height: 16)],
          TextField(controller: _nama, autofocus: true, style: const TextStyle(fontSize: 19), decoration: const InputDecoration(labelText: 'Nama pengguna')),
          const SizedBox(height: 16),
          TextField(controller: _sandi, obscureText: true, style: const TextStyle(fontSize: 19), decoration: const InputDecoration(labelText: 'Kata sandi')),
          const SizedBox(height: 16),
          TextField(
            controller: _kode,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(fontSize: 26, letterSpacing: 8, fontWeight: FontWeight.w800),
            decoration: const InputDecoration(labelText: 'Kode 6 angka dari aplikasi Authenticator di HP', counterText: ''),
            onSubmitted: (_) => _masuk(),
          ),
          if (_galat != null) ...[const SizedBox(height: 14), KotakPesan(_galat!, jenis: JenisPesan.galat)],
          const SizedBox(height: 22),
          FilledButton(onPressed: _sibuk ? null : _masuk, child: Text(_sibuk ? 'Memeriksa…' : 'Masuk')),
          const SizedBox(height: 12),
          Text('Server: ${s.server}', style: const TextStyle(fontSize: 14, color: Warna.teksPudar)),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(onPressed: () => s.gantiServer(), child: const Text('Ganti alamat server')),
          ),
        ]),
      ),
    );
  }
}

enum GrupPusat { penjualan, barang, toko }

enum MenuPusat {
  ringkasan('Ringkasan semua toko', Icons.space_dashboard, GrupPusat.penjualan, Warna.utama, Color(0xFFDCEBFC)),
  transaksi('Transaksi', Icons.receipt_long, GrupPusat.penjualan, Warna.hijauIkon, Warna.hijauIkonMuda),
  barang('Barang & harga', Icons.sell, GrupPusat.barang, Warna.coklat, Warna.coklatMuda),
  stok('Stok per toko', Icons.inventory, GrupPusat.barang, Warna.hijauIkon, Warna.hijauIkonMuda),
  toko('Toko & perangkat', Icons.storefront, GrupPusat.toko, Warna.ungu, Warna.unguMuda),
  karyawan('Karyawan', Icons.badge, GrupPusat.toko, Warna.toska, Warna.toskaMuda),
  log('Log aktivitas', Icons.history, GrupPusat.toko, Warna.abuIkon, Warna.abuIkonMuda);

  const MenuPusat(this.label, this.ikon, this.grup, this.warna, this.latar);
  final String label;
  final IconData ikon;
  final GrupPusat grup;
  final Color warna;
  final Color latar;
}

/// Toko dianggap "mengirim data" kalau sinkron terakhir paling lama 10 menit lalu.
bool tokoAktif(CabangPusat c, DateTime sekarang) => c.terakhirSinkron != null && sekarang.difference(c.terakhirSinkron!).inMinutes <= 10;

class HalamanUtama extends StatefulWidget {
  const HalamanUtama({super.key});
  @override
  State<HalamanUtama> createState() => _HalamanUtamaState();
}

class _HalamanUtamaState extends State<HalamanUtama> {
  /// null = menu ikon.
  MenuPusat? _menu;

  void _buka(MenuPusat? m) => setState(() => _menu = m);

  @override
  Widget build(BuildContext context) {
    final s = context.sesi;
    final nama = s.admin?.nama ?? '';
    final m = _menu;
    if (m == null) return _MenuUtama(nama: nama, onBuka: _buka, onKeluar: () => s.keluar());
    final isi = switch (m) {
      MenuPusat.ringkasan => const IsiRingkasan(),
      MenuPusat.transaksi => const IsiTransaksi(),
      MenuPusat.barang => const IsiBarang(),
      MenuPusat.stok => const IsiStok(),
      MenuPusat.toko => const IsiToko(),
      MenuPusat.karyawan => const IsiKaryawan(),
      MenuPusat.log => const IsiLog(),
    };
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => _buka(null)},
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: Warna.latar,
          body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            BarKepala(
              judul: m.label,
              onMenu: () => _buka(null),
              nama: nama,
              keterangan: 'Kantor pusat · semua toko',
              onKeluar: () => s.keluar(),
            ),
            Expanded(child: KeyedSubtree(key: ValueKey(m), child: isi)),
          ]),
        ),
      ),
    );
  }
}

/// Menu ikon Aplikasi Pusat: ringkasan hari ini + ikon per kelompok.
class _MenuUtama extends StatelessWidget {
  const _MenuUtama({required this.nama, required this.onBuka, required this.onKeluar});
  final String nama;
  final ValueChanged<MenuPusat> onBuka;
  final VoidCallback onKeluar;

  @override
  Widget build(BuildContext context) {
    final sekarang = DateTime.now();
    final (dari, sampai) = Periode.hariIni.rentang(sekarang);
    return Scaffold(
      backgroundColor: Warna.latar,
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        BarKepala(judul: 'KANTOR PUSAT', sub: 'Laporan semua toko', nama: nama, keterangan: formatLayar(sekarang), onKeluar: onKeluar),
        Expanded(
          child: Muat<(RingkasanPusat, List<CabangPusat>)>(
            ambil: (s) => s.pakai((api) async => (await api.ringkasan(dari, sampai), await api.cabang())),
            isi: (context, d, ulang) {
              final (r, cabang) = d;
              final aktif = cabang.where((c) => tokoAktif(c, sekarang)).length;
              final mati = cabang.length - aktif;
              Widget ubin(MenuPusat m) => UbinMenu(
                    ikon: m.ikon,
                    label: m.label,
                    warna: m.warna,
                    latar: m.latar,
                    utama: m == MenuPusat.ringkasan,
                    lencana: m == MenuPusat.toko && mati > 0 ? '$mati offline' : null,
                    onTap: () => onBuka(m),
                  );
              List<Widget> grup(GrupPusat g) => [for (final m in MenuPusat.values) if (m.grup == g) ubin(m)];
              return ListView(padding: const EdgeInsets.fromLTRB(28, 18, 28, 24), children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: KartuAngka(
                        label: 'Penjualan hari ini (semua toko)', nilai: formatRupiah(r.total.penjualanBersih), aksen: Warna.sukses, ikon: Icons.payments),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: KartuAngka(label: 'Transaksi', nilai: formatAngka(r.total.jumlahTransaksi), aksen: Warna.utama, ikon: Icons.receipt_long),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: KartuAngka(
                      label: 'Toko mengirim data',
                      nilai: cabang.isEmpty ? 'Belum ada toko' : '$aktif dari ${cabang.length}',
                      warna: mati > 0 ? Warna.lencanaOranye : Warna.suksesTua,
                      aksen: mati > 0 ? Warna.lencanaOranye : Warna.sukses,
                      ikon: Icons.storefront,
                      catatan: 'dalam 10 menit terakhir',
                    ),
                  ),
                ]),
                const SizedBox(height: 16),
                Wrap(spacing: 16, runSpacing: 16, children: [
                  GrupMenu(judul: 'PENJUALAN', warna: Warna.utama, latar: const Color(0xFFF2F8FF), ubin: grup(GrupPusat.penjualan)),
                  GrupMenu(judul: 'BARANG & HARGA', warna: Warna.toska, latar: const Color(0xFFF0FAFA), ubin: grup(GrupPusat.barang)),
                  GrupMenu(judul: 'TOKO & ORANG', warna: Warna.ungu, latar: const Color(0xFFF6F2FD), ubin: grup(GrupPusat.toko)),
                ]),
              ]);
            },
          ),
        ),
      ]),
    );
  }
}
