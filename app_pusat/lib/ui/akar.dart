import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pos_core/pos_core.dart';
import 'package:pos_ui/pos_ui.dart';

import '../layanan/sesi.dart';
import 'halaman/barang.dart';
import 'halaman/karyawan.dart';
import 'halaman/log.dart';
import 'halaman/ringkasan.dart';
import 'halaman/stok.dart';
import 'halaman/toko.dart';
import 'halaman/transaksi.dart';

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
            color: Warna.hijauTua,
            padding: const EdgeInsets.all(48),
            child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.store_mall_directory_outlined, color: Colors.white, size: 56),
              SizedBox(height: 18),
              Text('Kantor Pusat', style: TextStyle(color: Colors.white, fontSize: 38, fontWeight: FontWeight.w800, height: 1.1)),
              SizedBox(height: 8),
              Text('Laporan semua toko, harga, dan perangkat', style: TextStyle(color: Warna.hijauTeksTerang, fontSize: 19)),
              Spacer(),
              Text('Aplikasi ini tidak dipakai untuk berjualan.\nData berasal dari PC kasir di setiap toko.',
                  style: TextStyle(color: Warna.hijauTeksTerang, fontSize: 16, height: 1.5)),
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

enum MenuPusat {
  ringkasan('Ringkasan semua toko', Icons.space_dashboard_outlined),
  transaksi('Transaksi', Icons.receipt_long_outlined),
  barang('Barang & harga', Icons.sell_outlined),
  stok('Stok per toko', Icons.inventory_2_outlined),
  toko('Toko & perangkat', Icons.storefront_outlined),
  karyawan('Karyawan', Icons.badge_outlined),
  log('Log aktivitas', Icons.history);

  const MenuPusat(this.label, this.ikon);
  final String label;
  final IconData ikon;
}

class HalamanUtama extends StatefulWidget {
  const HalamanUtama({super.key});
  @override
  State<HalamanUtama> createState() => _HalamanUtamaState();
}

class _HalamanUtamaState extends State<HalamanUtama> {
  MenuPusat _menu = MenuPusat.ringkasan;

  @override
  Widget build(BuildContext context) {
    final s = context.sesi;
    final isi = switch (_menu) {
      MenuPusat.ringkasan => const IsiRingkasan(),
      MenuPusat.transaksi => const IsiTransaksi(),
      MenuPusat.barang => const IsiBarang(),
      MenuPusat.stok => const IsiStok(),
      MenuPusat.toko => const IsiToko(),
      MenuPusat.karyawan => const IsiKaryawan(),
      MenuPusat.log => const IsiLog(),
    };
    return Scaffold(
      body: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          width: 270,
          color: Warna.hijauTua,
          child: ListView(padding: const EdgeInsets.fromLTRB(14, 22, 14, 14), children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: Text('KANTOR PUSAT', style: TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w800)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 2, 10, 18),
              child: Text('Admin · ${s.admin?.nama ?? ''}', style: const TextStyle(color: Warna.hijauTeksTerang, fontSize: 15, height: 1.45)),
            ),
            for (final m in MenuPusat.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Material(
                  color: m == _menu ? const Color(0xFF1E5A45) : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => setState(() => _menu = m),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 50),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(children: [
                          Icon(m.ikon, color: Colors.white, size: 22),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(m.label,
                                style: TextStyle(color: Colors.white, fontSize: 16.5, fontWeight: m == _menu ? FontWeight.w800 : FontWeight.w500)),
                          ),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
          ]),
        ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(28, 18, 20, 18),
              child: Row(children: [
                Expanded(child: Text(_menu.label, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800))),
                OutlinedButton.icon(onPressed: () => s.keluar(), icon: const Icon(Icons.logout), label: const Text('Keluar')),
              ]),
            ),
            const Divider(height: 2, thickness: 2, color: Warna.garisTipis),
            Expanded(child: KeyedSubtree(key: ValueKey(_menu), child: isi)),
          ]),
        ),
      ]),
    );
  }
}
