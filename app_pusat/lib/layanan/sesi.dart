import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:pos_core/pos_core.dart';

import '../data/api.dart';
import '../data/model.dart';

/// Pengaturan PC pusat (hanya alamat server), disimpan sebagai file JSON di folder data aplikasi.
class PengaturanLokal {
  PengaturanLokal(this._berkas);

  /// Untuk test: tidak menulis ke disk.
  PengaturanLokal.memori() : _berkas = null;

  final File? _berkas;
  Map<String, Object?> _isi = {};

  Future<void> muat() async {
    final b = _berkas;
    if (b == null || !b.existsSync()) return;
    try {
      _isi = Map<String, Object?>.from(jsonDecode(await b.readAsString()) as Map);
    } on FormatException {
      _isi = {};
    }
  }

  String? get alamatServer => _isi['server'] as String?;

  Future<void> simpanAlamatServer(String? alamat) async {
    _isi['server'] = alamat;
    final b = _berkas;
    if (b != null) {
      await b.parent.create(recursive: true);
      await b.writeAsString(jsonEncode(_isi));
    }
  }
}

/// Keluar otomatis setelah tidak dipakai selama ini (sama dengan aturan Aplikasi Toko).
const batasDiam = Duration(minutes: 10);

/// Sesi Admin pusat: alamat server, login, keluar otomatis.
class Sesi extends ChangeNotifier {
  Sesi({required this.lokal, ApiPusat Function(Uri)? buatApi}) : _buatApi = buatApi ?? ApiHttp.new;

  final PengaturanLokal lokal;
  final ApiPusat Function(Uri) _buatApi;

  ApiPusat? _api;
  AdminPusat? _admin;
  Timer? _timerDiam;

  /// Pesan untuk layar masuk (mis. "Keluar otomatis karena 10 menit tidak dipakai").
  String? pesanMasuk;

  AdminPusat? get admin => _admin;
  ApiPusat get api => _api!;
  Uri? get server => lokal.alamatServer == null ? null : Uri.parse(lokal.alamatServer!);

  Future<void> aturServer(String alamat, {Future<void> Function(Uri)? cek}) async {
    final u = KlienServer.periksaAlamat(alamat);
    await (cek ?? ApiHttp.cekServer)(u);
    await lokal.simpanAlamatServer(u.toString());
    notifyListeners();
  }

  Future<void> gantiServer() async {
    await keluar();
    await lokal.simpanAlamatServer(null);
    notifyListeners();
  }

  Future<void> masuk(String namaPengguna, String sandi, String kode) async {
    final api = _buatApi(server!);
    _admin = await api.masuk(namaPengguna.trim(), sandi, kode.trim());
    _api = api;
    pesanMasuk = null;
    adaAktivitas();
    notifyListeners();
  }

  Future<void> keluar({String? alasan}) async {
    _timerDiam?.cancel();
    final api = _api;
    _api = null;
    _admin = null;
    pesanMasuk = alasan;
    notifyListeners();
    await api?.keluar();
  }

  void adaAktivitas() {
    if (_admin == null) return;
    _timerDiam?.cancel();
    _timerDiam = Timer(batasDiam, () => keluar(alasan: 'Keluar otomatis karena 10 menit tidak dipakai.'));
  }

  /// Jalankan permintaan ke server. Kalau sesi di server sudah habis, kembali ke layar masuk.
  Future<T> pakai<T>(Future<T> Function(ApiPusat api) kerja) async {
    final api = _api;
    if (api == null) throw const GalatServer('Belum masuk');
    try {
      return await kerja(api);
    } on GalatServer catch (e) {
      if (e.status == 401) unawaited(keluar(alasan: e.pesan));
      rethrow;
    }
  }

  @override
  void dispose() {
    _timerDiam?.cancel();
    super.dispose();
  }
}

class SesiScope extends InheritedNotifier<Sesi> {
  const SesiScope({super.key, required Sesi sesi, required super.child}) : super(notifier: sesi);

  static Sesi of(BuildContext context, {bool dengar = false}) => dengar
      ? context.dependOnInheritedWidgetOfExactType<SesiScope>()!.notifier!
      : context.getInheritedWidgetOfExactType<SesiScope>()!.notifier!;
}

extension SesiContext on BuildContext {
  Sesi get sesi => SesiScope.of(this);
}
