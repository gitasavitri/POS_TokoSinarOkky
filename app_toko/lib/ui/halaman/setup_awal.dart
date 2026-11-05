import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pos_core/pos_core.dart';

import '../../layanan/aplikasi.dart';
import '../komponen/umum.dart';
import '../tema.dart';

/// Pertama kali aplikasi dibuka di PC toko: isi data toko dan buat akun Admin.
class HalamanSetupAwal extends StatefulWidget {
  const HalamanSetupAwal({super.key});
  @override
  State<HalamanSetupAwal> createState() => _HalamanSetupAwalState();
}

class _HalamanSetupAwalState extends State<HalamanSetupAwal> {
  final _form = GlobalKey<FormState>();
  final _namaToko = TextEditingController(text: 'Toko Sinar Okky');
  final _kode = TextEditingController();
  final _namaCabang = TextEditingController();
  final _alamat = TextEditingController();
  final _pesan = TextEditingController(text: 'Barang yang sudah dibeli tidak dapat dikembalikan');
  final _namaAdmin = TextEditingController();
  final _user = TextEditingController();
  final _sandi = TextEditingController();
  final _sandi2 = TextEditingController();
  final _pin = TextEditingController();
  final _kodeTotp = TextEditingController();
  final String _rahasia = buatRahasiaTotp();
  String? _galat;
  bool _sibuk = false;

  String get _rahasiaBerkelompok => [
        for (var i = 0; i < _rahasia.length; i += 4) _rahasia.substring(i, i + 4 > _rahasia.length ? _rahasia.length : i + 4),
      ].join(' ');

  Future<void> _simpan() async {
    setState(() => _galat = null);
    if (!_form.currentState!.validate()) return;
    if (!await cocokkanTotp(_rahasia, _kodeTotp.text, DateTime.now())) {
      setState(() => _galat = 'Kode verifikasi salah. Pastikan kode di aplikasi autentikator sudah ditambahkan dan jam HP benar.');
      return;
    }
    setState(() => _sibuk = true);
    try {
      if (!mounted) return;
      final app = context.app;
      await app.setup.siapkan(
        namaToko: _namaToko.text,
        kodeCabang: _kode.text,
        namaCabang: _namaCabang.text,
        alamat: _alamat.text,
        pesanStruk: _pesan.text,
        namaAdmin: _namaAdmin.text,
        namaPenggunaAdmin: _user.text,
        sandiAdmin: _sandi.text,
        rahasiaTotp: _rahasia,
        pinAdmin: _pin.text,
      );
      app.segarkan();
    } catch (e) {
      setState(() {
        _galat = pesanGalat(e);
        _sibuk = false;
      });
    }
  }

  String? _wajib(String? v) => (v ?? '').trim().isEmpty ? 'Wajib diisi' : null;

  @override
  Widget build(BuildContext context) {
    Widget isian(String label, TextEditingController c,
            {String? Function(String?)? cek, bool sandi = false, String? hint, int? maks, TextInputType? tipe, List<TextInputFormatter>? format}) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: TextFormField(
            controller: c,
            obscureText: sandi,
            maxLength: maks,
            keyboardType: tipe,
            inputFormatters: format,
            style: const TextStyle(fontSize: 19),
            decoration: InputDecoration(labelText: label, hintText: hint, counterText: ''),
            validator: cek ?? _wajib,
          ),
        );

    return Scaffold(
      backgroundColor: Warna.latarTerang,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: Form(
              key: _form,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('Penyiapan pertama', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                const Text('Isi sekali saja di PC toko ini. Setelah itu kasir bisa langsung masuk.',
                    style: TextStyle(fontSize: 18, color: Warna.teksPudar)),
                const SizedBox(height: 24),
                Wrap(spacing: 20, runSpacing: 20, children: [
                  SizedBox(
                    width: 470,
                    child: Panel(
                      judul: '1. Data toko',
                      child: Column(children: [
                        isian('Nama toko (tercetak di struk)', _namaToko),
                        isian('Kode cabang (2–6 huruf/angka)', _kode,
                            hint: 'contoh: A01',
                            maks: 6,
                            format: [FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9]'))],
                            cek: (v) => RegExp(r'^[A-Za-z0-9]{2,6}$').hasMatch(v ?? '') ? null : '2–6 huruf/angka, contoh A01'),
                        isian('Nama cabang', _namaCabang, hint: 'contoh: Buah Batu'),
                        isian('Alamat', _alamat, cek: (_) => null),
                        isian('Pesan di bawah struk', _pesan, cek: (_) => null),
                      ]),
                    ),
                  ),
                  SizedBox(
                    width: 470,
                    child: Panel(
                      judul: '2. Akun Admin',
                      child: Column(children: [
                        isian('Nama Admin', _namaAdmin),
                        isian('Nama pengguna (untuk login)', _user, hint: 'contoh: admin.okky'),
                        isian('Kata sandi (min. 10 karakter)', _sandi, sandi: true, cek: (v) => periksaKataSandi(v ?? '')),
                        isian('Ulangi kata sandi', _sandi2, sandi: true, cek: (v) => v == _sandi.text ? null : 'Tidak sama'),
                        isian('PIN Admin 6 angka (untuk menyetujui di kasir)', _pin,
                            sandi: true,
                            maks: 6,
                            tipe: TextInputType.number,
                            format: [FilteringTextInputFormatter.digitsOnly],
                            cek: (v) => periksaPin(v ?? '')),
                      ]),
                    ),
                  ),
                ]),
                const SizedBox(height: 20),
                Panel(
                  judul: '3. Verifikasi dua langkah untuk Admin',
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text(
                      'Buka aplikasi autentikator di HP Admin (misalnya Google Authenticator), pilih tambah akun → '
                      '"Masukkan kunci penyiapan", lalu ketik kunci di bawah ini (jenis: berbasis waktu).',
                      style: TextStyle(fontSize: 17, height: 1.5),
                    ),
                    const SizedBox(height: 14),
                    Row(children: [
                      Expanded(
                        child: SelectableText(_rahasiaBerkelompok,
                            style: const TextStyle(fontFamily: fontMono, fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: 1)),
                      ),
                      OutlinedButton.icon(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: _rahasia));
                          tampilkanPesan(context, 'Kunci disalin');
                        },
                        icon: const Icon(Icons.copy),
                        label: const Text('Salin'),
                      ),
                    ]),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: 320,
                      child: isian('Kode 6 angka dari aplikasi', _kodeTotp,
                          tipe: TextInputType.number,
                          maks: 6,
                          format: [FilteringTextInputFormatter.digitsOnly],
                          cek: (v) => (v ?? '').length == 6 ? null : 'Isi 6 angka'),
                    ),
                    const KotakPesan(
                      'Simpan kunci ini di tempat aman. Kalau HP Admin hilang, kunci ini dibutuhkan untuk memasang ulang kode verifikasi.',
                      jenis: JenisPesan.info,
                    ),
                  ]),
                ),
                if (_galat != null) ...[const SizedBox(height: 16), KotakPesan(_galat!, jenis: JenisPesan.galat)],
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: _sibuk ? null : _simpan,
                    child: Text(_sibuk ? 'Menyimpan…' : 'Simpan & mulai'),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
