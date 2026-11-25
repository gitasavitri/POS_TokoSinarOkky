import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/model.dart';
import '../../layanan/aplikasi.dart';
import '../tema.dart';
import 'umum.dart';

/// Papan angka PIN besar (bisa juga diketik dari keyboard).
class PapanPin extends StatelessWidget {
  const PapanPin({super.key, required this.pin, required this.onUbah, this.panjang = 6});

  final String pin;
  final ValueChanged<String> onUbah;
  final int panjang;

  @override
  Widget build(BuildContext context) {
    Widget tombol(String label, {String? aria, VoidCallback? aksi, bool perintah = false}) => SizedBox(
          height: 68,
          child: perintah
              ? OutlinedButton(
                  onPressed: aksi,
                  child: Text(label, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600), semanticsLabel: aria),
                )
              : FilledButton(
                  onPressed: aksi,
                  style: FilledButton.styleFrom(backgroundColor: Warna.abuMuda, foregroundColor: Warna.teks),
                  child: Text(label, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700), semanticsLabel: aria),
                ),
        );

    void ketik(String d) {
      if (pin.length < panjang) onUbah(pin + d);
    }

    return Column(mainAxisSize: MainAxisSize.min, children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < panjang; i++)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 7, vertical: 8),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < pin.length ? Warna.utama : Colors.white,
                border: Border.all(color: Warna.utama, width: 2),
              ),
            ),
        ],
      ),
      const SizedBox(height: 10),
      GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 2.2,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          for (final d in ['1', '2', '3', '4', '5', '6', '7', '8', '9']) tombol(d, aria: 'Angka $d', aksi: () => ketik(d)),
          tombol('Ulang', aria: 'Kosongkan PIN', perintah: true, aksi: () => onUbah('')),
          tombol('0', aria: 'Angka 0', aksi: () => ketik('0')),
          tombol('Hapus', aria: 'Hapus satu angka', perintah: true, aksi: pin.isEmpty ? null : () => onUbah(pin.substring(0, pin.length - 1))),
        ],
      ),
    ]);
  }
}

/// Tangkap ketikan angka dari keyboard fisik untuk [PapanPin].
class PenangkapKetikanPin extends StatelessWidget {
  const PenangkapKetikanPin({super.key, required this.pin, required this.onUbah, required this.onEnter, required this.child, this.panjang = 6});

  final String pin;
  final ValueChanged<String> onUbah;
  final VoidCallback onEnter;
  final Widget child;
  final int panjang;

  @override
  Widget build(BuildContext context) => Focus(
        autofocus: true,
        onKeyEvent: (node, e) {
          if (e is! KeyDownEvent) return KeyEventResult.ignored;
          final c = e.character;
          if (c != null && RegExp(r'^[0-9]$').hasMatch(c)) {
            if (pin.length < panjang) onUbah(pin + c);
            return KeyEventResult.handled;
          }
          if (e.logicalKey == LogicalKeyboardKey.backspace && pin.isNotEmpty) {
            onUbah(pin.substring(0, pin.length - 1));
            return KeyEventResult.handled;
          }
          if (e.logicalKey == LogicalKeyboardKey.enter || e.logicalKey == LogicalKeyboardKey.numpadEnter) {
            onEnter();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: child,
      );
}

/// Minta PIN SPV/Admin di layar yang sama. Mengembalikan penyetuju, atau null kalau dibatalkan.
Future<Pengguna?> mintaPinSpv(BuildContext context, {required String alasan}) =>
    showDialog<Pengguna>(context: context, builder: (_) => _DialogPinSpv(alasan: alasan));

class _DialogPinSpv extends StatefulWidget {
  const _DialogPinSpv({required this.alasan});
  final String alasan;
  @override
  State<_DialogPinSpv> createState() => _DialogPinSpvState();
}

class _DialogPinSpvState extends State<_DialogPinSpv> {
  late final List<Pengguna> _penyetuju;
  Pengguna? _pilih;
  String _pin = '';
  String? _galat;
  bool _sibuk = false;

  @override
  void initState() {
    super.initState();
    final app = context.app;
    _penyetuju = app.pengguna.daftarPenyetuju(app.cabang.id).where((p) => p.id != app.penggunaAktif?.id).toList();
    _pilih = _penyetuju.isEmpty ? null : _penyetuju.first;
  }

  Future<void> _setujui() async {
    if (_pilih == null || _pin.length < 6 || _sibuk) return;
    setState(() => _sibuk = true);
    final p = await context.app.pengguna.setujuiDenganPin(_pilih!.id, _pin);
    if (!mounted) return;
    if (p == null) {
      setState(() {
        _sibuk = false;
        _pin = '';
        _galat = 'PIN salah atau akun terkunci.';
      });
    } else {
      Navigator.pop(context, p);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Perlu persetujuan SPV', style: TextStyle(fontWeight: FontWeight.w800)),
        content: SizedBox(
          width: 420,
          child: PenangkapKetikanPin(
            pin: _pin,
            onUbah: (p) => setState(() {
              _pin = p;
              _galat = null;
            }),
            onEnter: _setujui,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              KotakPesan(widget.alasan),
              const SizedBox(height: 16),
              if (_penyetuju.isEmpty)
                const KotakPesan('Belum ada SPV atau Admin dengan PIN di toko ini.', jenis: JenisPesan.galat)
              else
                DropdownButtonFormField<Pengguna>(
                  initialValue: _pilih,
                  decoration: const InputDecoration(labelText: 'Nama SPV / Admin'),
                  style: const TextStyle(fontSize: 19, color: Warna.teks, fontFamily: fontUtama),
                  items: [for (final p in _penyetuju) DropdownMenuItem(value: p, child: Text('${p.nama} (${p.peran.label})'))],
                  onChanged: (p) => setState(() => _pilih = p),
                ),
              const SizedBox(height: 8),
              PapanPin(pin: _pin, onUbah: (p) => setState(() {
                _pin = p;
                _galat = null;
              })),
              if (_galat != null) ...[
                const SizedBox(height: 10),
                Text(_galat!, style: const TextStyle(color: Warna.merah, fontWeight: FontWeight.w700, fontSize: 16)),
              ],
            ]),
          ),
        ),
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          FilledButton(onPressed: _pin.length == 6 && _pilih != null && !_sibuk ? _setujui : null, child: const Text('Setujui')),
        ],
      );
}
