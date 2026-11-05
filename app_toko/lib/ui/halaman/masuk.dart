import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/model.dart';
import '../../layanan/aplikasi.dart';
import '../komponen/pin.dart';
import '../komponen/umum.dart';
import '../tema.dart';

/// Layar Masuk: Kasir/SPV dengan PIN, Admin dengan sandi + kode verifikasi.
class HalamanMasuk extends StatefulWidget {
  const HalamanMasuk({super.key});
  @override
  State<HalamanMasuk> createState() => _HalamanMasukState();
}

class _HalamanMasukState extends State<HalamanMasuk> {
  bool _admin = false;
  List<Pengguna> _daftar = [];
  Pengguna? _pilih;
  String _pin = '';
  String? _galat;
  bool _sibuk = false;
  final _user = TextEditingController();
  final _sandi = TextEditingController();
  final _kode = TextEditingController();

  @override
  void initState() {
    super.initState();
    final app = context.app;
    _daftar = app.pengguna.daftarLoginPin(app.cabang.id);
    _pilih = _daftar.where((p) => !p.terkunci).firstOrNull ?? _daftar.firstOrNull;
  }

  Future<void> _masukPin() async {
    if (_pilih == null || _pin.length != 6 || _sibuk) return;
    setState(() => _sibuk = true);
    final app = context.app;
    final h = await app.pengguna.masukPin(_pilih!.id, _pin);
    if (!mounted) return;
    if (h.berhasil) {
      app.masuk(h.pengguna!);
    } else {
      setState(() {
        _sibuk = false;
        _pin = '';
        _galat = h.pesan;
        _daftar = app.pengguna.daftarLoginPin(app.cabang.id);
        _pilih = _daftar.firstWhere((p) => p.id == _pilih!.id, orElse: () => _daftar.first);
      });
    }
  }

  Future<void> _masukAdmin() async {
    if (_sibuk) return;
    setState(() => _sibuk = true);
    final app = context.app;
    final h = await app.pengguna.masukAdmin(_user.text, _sandi.text, _kode.text);
    if (!mounted) return;
    if (h.berhasil) {
      app.masuk(h.pengguna!);
    } else {
      setState(() {
        _sibuk = false;
        _galat = h.pesan;
        _kode.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final cabang = app.cabang;
    return Scaffold(
      body: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          width: 460,
          color: Warna.hijauTua,
          padding: const EdgeInsets.fromLTRB(48, 56, 48, 40),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: Warna.hijauMuda, borderRadius: BorderRadius.circular(16)),
              child: const Icon(Icons.shopping_cart_outlined, size: 36, color: Warna.hijauTua),
            ),
            const SizedBox(height: 20),
            Text(cabang.namaToko, style: const TextStyle(color: Colors.white, fontSize: 38, fontWeight: FontWeight.w800, height: 1.1)),
            const SizedBox(height: 8),
            const Text('Kasir minimarket & grosir', style: TextStyle(color: Color(0xFFCFE3DA), fontSize: 20)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(color: Warna.hijauPanel, borderRadius: BorderRadius.circular(10), border: Border.all(color: Warna.hijauGaris)),
              child: Text('Cabang ${cabang.nama} · ${cabang.kode}',
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
            ),
            const Spacer(),
            const Text('Keamanan akun', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            for (final t in const [
              'Keluar otomatis setelah 10 menit tidak dipakai',
              'Salah PIN 5 kali: akun dikunci, Admin diberi tahu',
              'Setiap masuk, keluar, dan pembatalan tercatat di log',
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                      margin: const EdgeInsets.only(top: 8, right: 12),
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(color: Color(0xFF7FD1AE), shape: BoxShape.circle)),
                  Expanded(child: Text(t, style: const TextStyle(color: Color(0xFFE6F0EB), fontSize: 17.5, height: 1.45))),
                ]),
              ),
          ]),
        ),
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Container(
                width: 520,
                padding: const EdgeInsets.all(40),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: const [
                  BoxShadow(color: Color(0x14000000), blurRadius: 24, offset: Offset(0, 8)),
                ]),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Text('Masuk', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 24),
                  Row(children: [
                    Expanded(child: _tombolPeran('Kasir / SPV', !_admin, () => setState(() {
                          _admin = false;
                          _galat = null;
                        }))),
                    const SizedBox(width: 12),
                    Expanded(child: _tombolPeran('Admin', _admin, () => setState(() {
                          _admin = true;
                          _galat = null;
                        }))),
                  ]),
                  const SizedBox(height: 24),
                  if (_admin) _formAdmin() else _formPin(),
                  if (_galat != null) ...[const SizedBox(height: 16), KotakPesan(_galat!, jenis: JenisPesan.galat)],
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _tombolPeran(String label, bool aktif, VoidCallback onTap) => SizedBox(
        height: 64,
        child: aktif
            ? FilledButton(onPressed: onTap, child: Text(label, style: const TextStyle(fontSize: 21)))
            : OutlinedButton(onPressed: onTap, child: Text(label, style: const TextStyle(fontSize: 21))),
      );

  Widget _formPin() {
    if (_daftar.isEmpty) {
      return const KotakPesan(
        'Belum ada akun kasir atau SPV. Masuk sebagai Admin, lalu tambahkan karyawan di menu Karyawan.',
        jenis: JenisPesan.info,
      );
    }
    return PenangkapKetikanPin(
      pin: _pin,
      onUbah: (p) => setState(() {
        _pin = p;
        _galat = null;
      }),
      onEnter: _masukPin,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        DropdownButtonFormField<Pengguna>(
          initialValue: _pilih,
          decoration: const InputDecoration(labelText: 'Nama'),
          style: const TextStyle(fontSize: 20, color: Warna.teks, fontFamily: fontUtama),
          items: [
            for (final p in _daftar)
              DropdownMenuItem(value: p, child: Text('${p.nama} (${p.peran.label})${p.terkunci ? ' · terkunci' : ''}')),
          ],
          onChanged: (p) => setState(() {
            _pilih = p;
            _pin = '';
            _galat = null;
          }),
        ),
        const SizedBox(height: 18),
        const Text('PIN (6 angka)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        PapanPin(pin: _pin, onUbah: (p) => setState(() {
          _pin = p;
          _galat = null;
        })),
        const SizedBox(height: 22),
        SizedBox(
          height: 68,
          child: FilledButton(
            onPressed: _pin.length == 6 && !_sibuk ? _masukPin : null,
            child: Text(_sibuk ? 'Memeriksa…' : 'Masuk', style: const TextStyle(fontSize: 22)),
          ),
        ),
      ]),
    );
  }

  Widget _formAdmin() => AutofillGroup(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
            controller: _user,
            autofocus: true,
            style: const TextStyle(fontSize: 20),
            decoration: const InputDecoration(labelText: 'Nama pengguna'),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _sandi,
            obscureText: true,
            style: const TextStyle(fontSize: 20),
            decoration: const InputDecoration(labelText: 'Kata sandi'),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _kode,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(fontSize: 22, letterSpacing: 4, fontWeight: FontWeight.w700),
            decoration: const InputDecoration(labelText: 'Kode verifikasi', hintText: '6 angka dari aplikasi autentikator', counterText: ''),
            onSubmitted: (_) => _masukAdmin(),
          ),
          const SizedBox(height: 8),
          const Text('Akun Admin wajib verifikasi dua langkah karena bisa melihat semua laporan dan mengubah data.',
              style: TextStyle(fontSize: 15.5, color: Warna.teksPudar, height: 1.5)),
          const SizedBox(height: 22),
          SizedBox(
            height: 68,
            child: FilledButton(
              onPressed: _sibuk ? null : _masukAdmin,
              child: Text(_sibuk ? 'Memeriksa…' : 'Masuk sebagai Admin', style: const TextStyle(fontSize: 22)),
            ),
          ),
        ]),
      );
}
