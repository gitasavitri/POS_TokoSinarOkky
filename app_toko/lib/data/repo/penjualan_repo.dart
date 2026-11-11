import 'package:pos_core/pos_core.dart';

import '../database.dart';
import '../model.dart';
import 'pemulihan_repo.dart';

class HasilSimpanTransaksi {
  const HasilSimpanTransaksi({required this.transaksiId, required this.noTransaksi, required this.struk});
  final String transaksiId;
  final String noTransaksi;
  final DataStruk struk;
}

/// Shift kasir, simpan transaksi, pembatalan, retur, struk ulang.
/// Jam komputer lebih awal dari transaksi terakhir (biasanya baterai BIOS habis setelah listrik padam).
/// Penjualan ditahan supaya nomor struk dan laporan tidak kacau.
class JamMundur implements Exception {
  const JamMundur(this.terakhir, this.sekarang);
  final DateTime terakhir;
  final DateTime sekarang;
  String get pesan =>
      'Jam komputer mundur: sekarang ${formatLayar(sekarang)}, padahal transaksi terakhir ${formatLayar(terakhir)}. '
      'Betulkan tanggal & jam Windows dulu (klik kanan jam di pojok kanan bawah → Adjust date/time).';
  @override
  String toString() => pesan;
}

/// Toleransi selisih jam (koreksi otomatis Windows bisa memundurkan jam beberapa detik/menit).
const toleransiJamMundur = Duration(minutes: 10);

class PenjualanRepo {
  PenjualanRepo(this._db);
  final DatabaseToko _db;

  // ---------------------------------------------------------------- shift

  Shift? shiftAktif(String kasirId) {
    final r = _db.satu(
      'SELECT s.* FROM shift s LEFT JOIN shift_tutup t ON t.shift_id = s.id'
      ' LEFT JOIN shift_belum_dihitung b ON b.shift_id = s.id'
      ' WHERE s.kasir_id = ? AND t.shift_id IS NULL AND b.shift_id IS NULL ORDER BY s.dibuka_pada DESC LIMIT 1',
      [kasirId],
    );
    return r == null ? null : _shift(r);
  }

  Shift _shift(Map<String, Object?> r) => Shift(
        id: r['id']! as String,
        kasirId: r['kasir_id']! as String,
        modalAwal: r['modal_awal']! as int,
        dibukaPada: DateTime.parse(r['dibuka_pada']! as String),
      );

  Shift bukaShift({required String cabangId, required String kasirId, required int modalAwal}) {
    if (modalAwal < 0) throw ArgumentError('Modal awal tidak boleh minus');
    final ada = shiftAktif(kasirId);
    if (ada != null) return ada;
    final id = buatId();
    final t = _db.sekarangIso();
    _db.transaksi(() {
      _db.jalankan('INSERT INTO shift (id, cabang_id, kasir_id, modal_awal, dibuka_pada) VALUES (?,?,?,?,?)',
          [id, cabangId, kasirId, modalAwal, t]);
      _db.outbox('shift', id);
      _db.log(cabangId: cabangId, penggunaId: kasirId, aksi: 'buka_shift', detail: {'modal_awal': modalAwal});
    });
    return shiftAktif(kasirId)!;
  }

  RingkasanShift ringkasanShift(String shiftId) {
    final s = _shift(_db.satu('SELECT * FROM shift WHERE id = ?', [shiftId])!);
    final r = _db.satu(
      "SELECT COUNT(*) AS n,"
      " IFNULL(SUM(CASE WHEN p.metode = 'tunai' THEN t.total ELSE 0 END), 0) AS tunai,"
      " IFNULL(SUM(CASE WHEN p.metode <> 'tunai' THEN t.total ELSE 0 END), 0) AS non_tunai"
      ' FROM transaksi t JOIN pembayaran p ON p.transaksi_id = t.id'
      ' LEFT JOIN pembatalan b ON b.transaksi_id = t.id'
      ' WHERE t.shift_id = ? AND b.transaksi_id IS NULL',
      [shiftId],
    )!;
    // Retur dibayar tunai dari laci kasir, dicatat di shift yang aktif saat retur (lewat waktu & cabang).
    final cabangId = _db.satu('SELECT cabang_id FROM shift WHERE id = ?', [shiftId])!['cabang_id'];
    // Shift "Belum dihitung": batas waktunya saat kasir menutup, bukan saat amplop dihitung SPV/Admin.
    final ditutup = _db.satu('SELECT ditutup_pada FROM shift_belum_dihitung WHERE shift_id = ?', [shiftId])?['ditutup_pada'] ??
        _db.satu('SELECT ditutup_pada FROM shift_tutup WHERE shift_id = ?', [shiftId])?['ditutup_pada'];
    final retur = _db.satu(
      'SELECT IFNULL(SUM(r.total_kembali), 0) AS n FROM retur r JOIN transaksi t ON t.id = r.transaksi_id'
      ' WHERE t.cabang_id = ? AND r.created_at >= ? AND r.created_at <= ?',
      [cabangId, isoUtc(s.dibukaPada), ditutup ?? '9999'],
    )!;
    final kas = _db.satu(
      "SELECT IFNULL(SUM(CASE WHEN jenis = 'masuk' THEN jumlah ELSE 0 END), 0) AS masuk,"
      " IFNULL(SUM(CASE WHEN jenis = 'keluar' THEN jumlah ELSE 0 END), 0) AS keluar"
      ' FROM kas_shift WHERE shift_id = ?',
      [shiftId],
    )!;
    return RingkasanShift(
      shift: s,
      jumlahTransaksi: r['n']! as int,
      penjualanTunai: r['tunai']! as int,
      penjualanNonTunai: r['non_tunai']! as int,
      returTunai: retur['n']! as int,
      kasMasuk: kas['masuk']! as int,
      kasKeluar: kas['keluar']! as int,
    );
  }

  /// Sudah ditutup: dihitung (shift_tutup) atau "Belum dihitung" (menunggu amplop dihitung).
  bool _shiftDitutup(String shiftId) =>
      _db.satu('SELECT 1 FROM shift_tutup WHERE shift_id = ?', [shiftId]) != null ||
      _db.satu('SELECT 1 FROM shift_belum_dihitung WHERE shift_id = ?', [shiftId]) != null;

  /// Transaksi di satu shift, terbaru dulu (Penjualan shift saya, revisi D).
  List<BarisTransaksi> transaksiShift(String shiftId) => _db
      .pilih(
        'SELECT t.id, t.no_transaksi, t.created_at, t.jumlah_barang, t.total, p.metode, u.nama AS kasir,'
        ' (x.transaksi_id IS NOT NULL) AS batal, EXISTS(SELECT 1 FROM retur r WHERE r.transaksi_id = t.id) AS retur'
        ' FROM transaksi t JOIN pembayaran p ON p.transaksi_id = t.id JOIN pengguna u ON u.id = t.kasir_id'
        ' LEFT JOIN pembatalan x ON x.transaksi_id = t.id'
        ' WHERE t.shift_id = ? ORDER BY t.created_at DESC, t.no_transaksi DESC',
        [shiftId],
      )
      .map((r) => BarisTransaksi(
            id: r['id'] as String,
            noTransaksi: r['no_transaksi'] as String,
            waktu: DateTime.parse(r['created_at'] as String),
            kasir: r['kasir'] as String,
            jumlahBarang: r['jumlah_barang'] as int,
            total: r['total'] as int,
            metode: MetodeBayar.dariKode(r['metode'] as String),
            dibatalkan: r['batal'] == 1,
            adaRetur: r['retur'] == 1,
          ))
      .toList();

  // ---------------------------------------------------------------- kas keluar / masuk

  List<KasShift> daftarKas(String shiftId) => _db
      .pilih(
        'SELECT k.*, p.nama AS pembuat, s.nama AS penyetuju FROM kas_shift k'
        ' JOIN pengguna p ON p.id = k.dibuat_oleh LEFT JOIN pengguna s ON s.id = k.disetujui_oleh'
        ' WHERE k.shift_id = ? ORDER BY k.created_at, k.rowid',
        [shiftId],
      )
      .map((r) => KasShift(
            id: r['id'] as String,
            jenis: JenisKas.dariKode(r['jenis'] as String),
            jumlah: r['jumlah'] as int,
            keterangan: r['keterangan'] as String,
            namaPembuat: r['pembuat'] as String,
            namaPenyetuju: r['penyetuju'] as String?,
            waktu: DateTime.parse(r['created_at'] as String),
          ))
      .toList();

  /// Catat kas keluar/masuk di shift [shiftId]. Kasir dengan jumlah ≥ [batasKasTanpaPin] wajib [disetujuiOleh] (SPV/Admin).
  String catatKas({
    required String shiftId,
    required JenisKas jenis,
    required int jumlah,
    required String keterangan,
    required Pengguna oleh,
    Pengguna? disetujuiOleh,
  }) {
    final galat = cekKas(jumlah: jumlah, keterangan: keterangan);
    if (galat != null) throw ArgumentError(galat);
    if (aksesKas(oleh.peran, jumlah) == Akses.pinSpv && (disetujuiOleh == null || !bolehMenyetujui(disetujuiOleh.peran))) {
      throw StateError('${jenis.label} mulai ${formatRupiah(batasKasTanpaPin)} perlu PIN SPV.');
    }
    final shift = _db.satu('SELECT cabang_id FROM shift WHERE id = ?', [shiftId]);
    if (shift == null) throw ArgumentError('Shift tidak ditemukan');
    if (_shiftDitutup(shiftId)) throw StateError('Shift sudah ditutup');
    final cabangId = shift['cabang_id'] as String;
    final id = buatId();
    _db.transaksi(() {
      _db.jalankan(
        'INSERT INTO kas_shift (id, cabang_id, shift_id, jenis, jumlah, keterangan, dibuat_oleh, disetujui_oleh, created_at)'
        ' VALUES (?,?,?,?,?,?,?,?,?)',
        [id, cabangId, shiftId, jenis.kode, jumlah, keterangan.trim(), oleh.id, disetujuiOleh?.id, _db.sekarangIso()],
      );
      _db.outbox('kas_shift', id);
      _db.log(
        cabangId: cabangId,
        penggunaId: oleh.id,
        disetujuiOleh: disetujuiOleh?.id,
        aksi: 'kas_${jenis.kode}',
        detail: {'shift_id': shiftId, 'jumlah': jumlah, 'keterangan': keterangan.trim()},
      );
    });
    return id;
  }

  // ---------------------------------------------------------------- tutup shift (hitung buta)

  List<HitunganShift> hitunganShift(String shiftId) => _db
      .pilih('SELECT * FROM shift_hitung WHERE shift_id = ? ORDER BY ke', [shiftId])
      .map((r) => HitunganShift(
            ke: r['ke'] as int,
            kasDihitung: r['kas_dihitung'] as int,
            kasSistem: r['kas_sistem'] as int,
            selisih: r['selisih'] as int,
            disetujuiOleh: r['disetujui_oleh'] as String?,
            waktu: DateTime.parse(r['created_at'] as String),
          ))
      .toList();

  /// Jumlah hitungan yang masih berlaku: dibuat setelah transaksi/kas terakhir (uang seharusnya belum berubah).
  /// Kalau sesudah menghitung kasir membatalkan tutup shift lalu berjualan lagi, hitungan lama tidak berlaku
  /// dan tidak menghabiskan jatah hitung ulang.
  int hitunganBerlaku(String shiftId, {List<HitunganShift>? semua, RingkasanShift? ring}) {
    final kas = (ring ?? ringkasanShift(shiftId)).kasSistem;
    final daftar = semua ?? hitunganShift(shiftId);
    var n = 0;
    for (final h in daftar.reversed) {
      if (h.kasSistem != kas) break;
      n++;
    }
    return n;
  }

  /// Simpan hitungan uang kasir (hitung buta). Semua hitungan tercatat. Kasir boleh hitung ulang
  /// [maksHitungUlangKasir] kali; sesudahnya wajib [disetujuiOleh] (SPV/Admin).
  HitunganShift simpanHitungan({required String shiftId, required int kasDihitung, required Pengguna oleh, Pengguna? disetujuiOleh}) {
    if (kasDihitung < 0) throw ArgumentError('Jumlah uang tidak boleh minus');
    if (_shiftDitutup(shiftId)) throw StateError('Shift sudah ditutup');
    final ring = ringkasanShift(shiftId);
    final semua = hitunganShift(shiftId);
    final sebelumnya = semua.length;
    if (aksesHitungUang(oleh.peran, hitunganBerlaku(shiftId, semua: semua, ring: ring)) == Akses.pinSpv &&
        (disetujuiOleh == null || !bolehMenyetujui(disetujuiOleh.peran))) {
      throw StateError('Sudah dihitung ulang $maksHitungUlangKasir kali. Hitung ulang berikutnya perlu PIN SPV.');
    }
    final cabangId = _db.satu('SELECT cabang_id FROM shift WHERE id = ?', [shiftId])!['cabang_id'] as String;
    final ke = sebelumnya + 1;
    final selisih = kasDihitung - ring.kasSistem;
    final id = buatId();
    _db.transaksi(() {
      _db.jalankan(
        'INSERT INTO shift_hitung (id, cabang_id, shift_id, ke, kas_dihitung, kas_sistem, selisih, dihitung_oleh, disetujui_oleh, created_at)'
        ' VALUES (?,?,?,?,?,?,?,?,?,?)',
        [id, cabangId, shiftId, ke, kasDihitung, ring.kasSistem, selisih, oleh.id, disetujuiOleh?.id, _db.sekarangIso()],
      );
      _db.outbox('shift_hitung', id);
      _db.log(
        cabangId: cabangId,
        penggunaId: oleh.id,
        disetujuiOleh: disetujuiOleh?.id,
        aksi: ke == 1 ? 'hitung_uang_shift' : 'hitung_ulang_shift',
        detail: {'shift_id': shiftId, 'ke': ke, 'kas_dihitung': kasDihitung, 'kas_sistem': ring.kasSistem, 'selisih': selisih},
      );
    });
    return hitunganShift(shiftId).last;
  }

  /// Tutup shift memakai hitungan uang terakhir (lihat [simpanHitungan]). Wajib sudah dihitung minimal sekali.
  RingkasanShift tutupShift({required String shiftId, required String olehId}) {
    final hitungan = hitunganShift(shiftId);
    if (hitungan.isEmpty) throw StateError('Hitung uang tunai dulu sebelum menutup shift');
    final kasDihitung = hitungan.last.kasDihitung;
    final ring = ringkasanShift(shiftId);
    if (hitungan.last.kasSistem != ring.kasSistem) {
      throw StateError('Ada transaksi atau kas keluar/masuk baru setelah uang dihitung. Hitung ulang dulu.');
    }
    final selisih = kasDihitung - ring.kasSistem;
    final cabangId = _db.satu('SELECT cabang_id FROM shift WHERE id = ?', [shiftId])!['cabang_id'] as String;
    _db.transaksi(() {
      _db.jalankan(
        'INSERT INTO shift_tutup (shift_id, kas_dihitung, kas_sistem, selisih, ditutup_oleh, ditutup_pada)'
        ' VALUES (?,?,?,?,?,?)',
        [shiftId, kasDihitung, ring.kasSistem, selisih, olehId, _db.sekarangIso()],
      );
      _db.outbox('shift_tutup', shiftId, kolomKunci: 'shift_id');
      _db.log(cabangId: cabangId, penggunaId: olehId, aksi: 'tutup_shift', detail: {
        'kas_dihitung': kasDihitung,
        'kas_sistem': ring.kasSistem,
        'selisih': selisih,
        'jumlah_hitungan': hitungan.length,
      });
    });
    return ring;
  }

  // ---------------------------------------------------------------- tutup shift "Belum dihitung" (revisi P)

  /// Kasir menutup shift tanpa menghitung uang. Uang (kecuali [modalTetap]) dimasukkan ke amplop berlabel,
  /// shift berstatus "menunggu dihitung". Hanya boleh sebelum uang dihitung (kalau sudah dihitung, tutup biasa).
  ShiftMenunggu tutupShiftBelumDihitung({required String shiftId, required Pengguna oleh, required int modalTetap}) {
    if (modalTetap < 0) throw ArgumentError('Modal tetap tidak boleh minus');
    final sh = _db.satu('SELECT s.cabang_id, s.kasir_id, s.dibuka_pada, u.nama FROM shift s JOIN pengguna u ON u.id = s.kasir_id WHERE s.id = ?',
        [shiftId]);
    if (sh == null) throw ArgumentError('Shift tidak ditemukan');
    if (_shiftDitutup(shiftId)) throw StateError('Shift sudah ditutup');
    final ring = ringkasanShift(shiftId);
    if (hitunganBerlaku(shiftId, ring: ring) > 0) {
      throw StateError('Uang shift ini sudah dihitung. Tutup shift dengan hitungan itu.');
    }
    final cabangId = sh['cabang_id'] as String;
    final waktu = _db.sekarang();
    final modal = hitungModalDitinggal(modalTetap: modalTetap, kasSistem: ring.kasSistem);
    final label = labelAmplop(
      namaKasir: sh['nama'] as String,
      dibuka: formatLayar(DateTime.parse(sh['dibuka_pada'] as String)),
      ditutup: formatJam(waktu),
    );
    _db.transaksi(() {
      _db.jalankan(
        'INSERT INTO shift_belum_dihitung (shift_id, cabang_id, kas_sistem, modal_ditinggal, label_amplop, ditutup_oleh, ditutup_pada)'
        ' VALUES (?,?,?,?,?,?,?)',
        [shiftId, cabangId, ring.kasSistem, modal, label, oleh.id, isoUtc(waktu)],
      );
      _db.outbox('shift_belum_dihitung', shiftId, kolomKunci: 'shift_id');
      _db.log(cabangId: cabangId, penggunaId: oleh.id, aksi: 'tutup_shift_belum_dihitung', detail: {
        'shift_id': shiftId,
        'kasir_id': sh['kasir_id'],
        'kas_sistem': ring.kasSistem,
        'modal_ditinggal': modal,
        'jumlah_transaksi': ring.jumlahTransaksi,
      });
    });
    return shiftMenungguDihitung(cabangId).firstWhere((m) => m.shiftId == shiftId);
  }

  /// Shift yang amplopnya belum dihitung, terlama dulu (daftar untuk SPV/Admin).
  List<ShiftMenunggu> shiftMenungguDihitung(String cabangId) => _db
      .pilih(
        'SELECT b.*, s.kasir_id, s.modal_awal, s.dibuka_pada, u.nama AS kasir,'
        ' (SELECT COUNT(*) FROM transaksi t LEFT JOIN pembatalan x ON x.transaksi_id = t.id'
        '   WHERE t.shift_id = s.id AND x.transaksi_id IS NULL) AS n'
        ' FROM shift_belum_dihitung b JOIN shift s ON s.id = b.shift_id JOIN pengguna u ON u.id = s.kasir_id'
        ' LEFT JOIN shift_tutup t ON t.shift_id = b.shift_id'
        ' WHERE b.cabang_id = ? AND t.shift_id IS NULL ORDER BY b.ditutup_pada',
        [cabangId],
      )
      .map((r) => ShiftMenunggu(
            shiftId: r['shift_id'] as String,
            kasirId: r['kasir_id'] as String,
            namaKasir: r['kasir'] as String,
            modalAwal: r['modal_awal'] as int,
            dibukaPada: DateTime.parse(r['dibuka_pada'] as String),
            ditutupPada: DateTime.parse(r['ditutup_pada'] as String),
            kasSistem: r['kas_sistem'] as int,
            modalDitinggal: r['modal_ditinggal'] as int,
            labelAmplop: r['label_amplop'] as String,
            jumlahTransaksi: r['n'] as int,
          ))
      .toList();

  /// SPV/Admin mengisi hasil hitungan amplop. Sistem menulis hitungan + menutup shift; selisih tercatat
  /// ke kasir shift itu. Hanya sekali (setelah itu shift_tutup terkunci).
  HasilHitungAmplop hitungAmplop({required String shiftId, required int amplopDihitung, required Pengguna oleh}) {
    if (aksesUntuk(oleh.peran, Izin.hitungShiftMenunggu) != Akses.ya) {
      throw StateError('Hanya SPV atau Admin yang boleh menghitung amplop shift.');
    }
    if (amplopDihitung < 0) throw ArgumentError('Isi amplop tidak boleh minus');
    final b = _db.satu(
      'SELECT b.*, s.kasir_id FROM shift_belum_dihitung b JOIN shift s ON s.id = b.shift_id WHERE b.shift_id = ?',
      [shiftId],
    );
    if (b == null) throw StateError('Shift ini tidak menunggu dihitung');
    if (_db.satu('SELECT 1 FROM shift_tutup WHERE shift_id = ?', [shiftId]) != null) {
      throw StateError('Amplop shift ini sudah dihitung');
    }
    final cabangId = b['cabang_id'] as String;
    final kasSistem = b['kas_sistem'] as int;
    final modal = b['modal_ditinggal'] as int;
    final kas = hitungKasDariAmplop(amplopDihitung: amplopDihitung, modalDitinggal: modal);
    final selisih = hitungSelisihAmplop(amplopDihitung: amplopDihitung, modalDitinggal: modal, kasSistem: kasSistem);
    final ke = hitunganShift(shiftId).length + 1;
    final t = _db.sekarangIso();
    final hitungId = buatId();
    _db.transaksi(() {
      _db.jalankan(
        'INSERT INTO shift_hitung (id, cabang_id, shift_id, ke, kas_dihitung, kas_sistem, selisih, dihitung_oleh, disetujui_oleh, created_at)'
        ' VALUES (?,?,?,?,?,?,?,?,?,?)',
        [hitungId, cabangId, shiftId, ke, kas, kasSistem, selisih, oleh.id, null, t],
      );
      _db.outbox('shift_hitung', hitungId);
      _db.jalankan(
        'INSERT INTO shift_tutup (shift_id, kas_dihitung, kas_sistem, selisih, ditutup_oleh, ditutup_pada) VALUES (?,?,?,?,?,?)',
        [shiftId, kas, kasSistem, selisih, oleh.id, t],
      );
      _db.outbox('shift_tutup', shiftId, kolomKunci: 'shift_id');
      _db.log(cabangId: cabangId, penggunaId: oleh.id, aksi: 'hitung_amplop_shift', detail: {
        'shift_id': shiftId,
        'kasir_id': b['kasir_id'],
        'amplop_dihitung': amplopDihitung,
        'modal_ditinggal': modal,
        'kas_sistem': kasSistem,
        'selisih': selisih,
      });
    });
    return HasilHitungAmplop(amplopDihitung: amplopDihitung, modalDitinggal: modal, kasSistem: kasSistem, selisih: selisih);
  }

  // ---------------------------------------------------------------- transaksi

  /// Waktu transaksi terakhir di cabang ini (null kalau belum ada).
  DateTime? transaksiTerakhir(String cabangId) {
    final r = _db.satu('SELECT created_at FROM transaksi WHERE cabang_id = ? ORDER BY created_at DESC LIMIT 1', [cabangId]);
    return r == null ? null : DateTime.parse(r['created_at'] as String);
  }

  /// Lempar [JamMundur] kalau jam komputer jauh lebih awal dari transaksi terakhir.
  void cekJam(String cabangId, [DateTime? sekarang]) {
    final terakhir = transaksiTerakhir(cabangId);
    final s = sekarang ?? _db.sekarang();
    if (terakhir != null && s.isBefore(terakhir.subtract(toleransiJamMundur))) throw JamMundur(terakhir, s);
  }

  /// Nomor yang akan dipakai transaksi berikutnya (untuk ditampilkan di layar kasir).
  String nomorBerikutnya(InfoCabang cabang) => _nomorBerikutnya(cabang, _db.sekarang());

  String _nomorBerikutnya(InfoCabang cabang, DateTime waktu) {
    final awalan = awalanNomorTransaksi(cabang.kode, waktu);
    final r = _db.satu(
      'SELECT no_transaksi FROM transaksi WHERE cabang_id = ? AND no_transaksi LIKE ? ORDER BY no_transaksi DESC LIMIT 1',
      [cabang.id, '$awalan%'],
    );
    final urut = r == null ? 1 : int.parse((r['no_transaksi']! as String).substring(awalan.length)) + 1;
    return nomorTransaksi(kodeCabang: cabang.kode, waktu: waktu, urut: urut);
  }

  /// Simpan transaksi lengkap dalam SATU transaksi database: transaksi, item, pembayaran,
  /// mutasi stok, log, outbox. Gagal di tengah → tidak ada yang tersimpan.
  HasilSimpanTransaksi simpan({
    required InfoCabang cabang,
    required Pengguna kasir,
    required Shift shift,
    required Keranjang keranjang,
    required MetodeBayar metode,
    int uangDiterima = 0,
    String? noReferensi,
  }) {
    if (keranjang.kosong) throw ArgumentError('Keranjang kosong');
    final total = keranjang.total;
    final bayar = cekPembayaran(metode: metode, total: total, uangDiterima: uangDiterima, noReferensi: noReferensi);
    if (!bayar.boleh) throw ArgumentError(bayar.pesan);

    return _db.transaksi(() {
      final waktu = _db.sekarang();
      cekJam(cabang.id, waktu);
      final t = isoUtc(waktu);
      final id = buatId();
      final no = _nomorBerikutnya(cabang, waktu);
      // Ditulis di transaksi database yang sama: kalau listrik padam sesudah ini, belanjaan tidak
      // muncul lagi sebagai "belum dibayar" (mencegah dobel), dan aplikasi tahu struk mungkin belum tercetak.
      final pulih = PemulihanRepo(_db);
      pulih.hapusKeranjang();
      pulih.tandaiBelumCetak(id);
      _db.jalankan(
        'INSERT INTO transaksi (id, cabang_id, no_transaksi, shift_id, kasir_id, total, jumlah_barang, created_at)'
        ' VALUES (?,?,?,?,?,?,?,?)',
        [id, cabang.id, no, shift.id, kasir.id, total, keranjang.jumlahBarang, t],
      );
      _db.outbox('transaksi', id);
      final itemStruk = <ItemStruk>[];
      for (final b in keranjang.baris) {
        final h = b.harga;
        final itemId = buatId();
        _db.jalankan(
          'INSERT INTO transaksi_item (id, transaksi_id, barang_id, nama_barang, qty, harga_satuan, harga_grosir,'
          ' hpp_satuan, subtotal) VALUES (?,?,?,?,?,?,?,?,?)',
          [itemId, id, b.barang.id, b.barang.nama, b.qty, h.hargaSatuan, h.isGrosir ? 1 : 0, b.barang.hpp, h.subtotal],
        );
        _db.outbox('transaksi_item', itemId);
        final mutasiId = buatId();
        _db.jalankan(
          "INSERT INTO mutasi_stok (id, cabang_id, barang_id, jumlah, jenis, ref_id, dibuat_oleh, created_at)"
          " VALUES (?,?,?,?,'jual',?,?,?)",
          [mutasiId, cabang.id, b.barang.id, -b.qty, id, kasir.id, t],
        );
        _db.outbox('mutasi_stok', mutasiId);
        itemStruk.add(ItemStruk(nama: b.barang.nama, qty: b.qty, hargaSatuan: h.hargaSatuan, isGrosir: h.isGrosir));
      }
      final bayarId = buatId();
      _db.jalankan(
        'INSERT INTO pembayaran (id, transaksi_id, metode, jumlah_diterima, kembalian, no_referensi, created_at)'
        ' VALUES (?,?,?,?,?,?,?)',
        [bayarId, id, metode.kode, bayar.diterima, bayar.kembalian, noReferensi?.trim(), t],
      );
      _db.outbox('pembayaran', bayarId);
      return HasilSimpanTransaksi(
        transaksiId: id,
        noTransaksi: no,
        struk: DataStruk(
          namaToko: cabang.namaToko,
          namaCabang: cabang.nama,
          alamat: cabang.alamat,
          noTransaksi: no,
          waktu: waktu,
          namaKasir: kasir.nama,
          item: itemStruk,
          metode: metode,
          diterima: bayar.diterima,
          kembalian: bayar.kembalian,
          noReferensi: noReferensi?.trim(),
          pesanBawah: cabang.pesanStruk,
        ),
      );
    });
  }

  String? idDariNomor(String cabangId, String noAtauBarcode) {
    final no = noAtauBarcode.toUpperCase().startsWith('TRX-') ? noAtauBarcode.trim().toUpperCase() : noTransaksiDariBarcode(noAtauBarcode);
    if (no == null) return null;
    return _db.satu('SELECT id FROM transaksi WHERE cabang_id = ? AND no_transaksi = ?', [cabangId, no])?['id'] as String?;
  }

  bool sudahDibatalkan(String transaksiId) =>
      _db.satu('SELECT 1 FROM pembatalan WHERE transaksi_id = ?', [transaksiId]) != null;

  /// Batalkan transaksi yang sudah dibayar. Transaksi asli tidak diubah; stok dikembalikan.
  void batalkan({
    required String transaksiId,
    required String alasan,
    required String dimintaOleh,
    required String disetujuiOleh,
  }) {
    if (alasan.trim().isEmpty) throw ArgumentError('Alasan wajib diisi');
    _db.transaksi(() {
      if (sudahDibatalkan(transaksiId)) throw StateError('Transaksi sudah dibatalkan');
      if (_db.satu('SELECT 1 FROM retur WHERE transaksi_id = ?', [transaksiId]) != null) {
        throw StateError('Transaksi sudah ada returnya, tidak bisa dibatalkan');
      }
      final tr = _db.satu('SELECT cabang_id, no_transaksi, total FROM transaksi WHERE id = ?', [transaksiId]);
      if (tr == null) throw StateError('Transaksi tidak ditemukan');
      final t = _db.sekarangIso();
      _db.jalankan(
        'INSERT INTO pembatalan (transaksi_id, alasan, diminta_oleh, disetujui_oleh, created_at) VALUES (?,?,?,?,?)',
        [transaksiId, alasan.trim(), dimintaOleh, disetujuiOleh, t],
      );
      _db.outbox('pembatalan', transaksiId, kolomKunci: 'transaksi_id');
      for (final i in _db.pilih('SELECT barang_id, qty FROM transaksi_item WHERE transaksi_id = ?', [transaksiId])) {
        final mid = buatId();
        _db.jalankan(
          "INSERT INTO mutasi_stok (id, cabang_id, barang_id, jumlah, jenis, ref_id, dibuat_oleh, created_at)"
          " VALUES (?,?,?,?,'batal_jual',?,?,?)",
          [mid, tr['cabang_id'], i['barang_id'], i['qty'], transaksiId, disetujuiOleh, t],
        );
        _db.outbox('mutasi_stok', mid);
      }
      _db.log(
        cabangId: tr['cabang_id'] as String,
        penggunaId: dimintaOleh,
        disetujuiOleh: disetujuiOleh,
        aksi: 'batal_transaksi',
        detail: {'no_transaksi': tr['no_transaksi'], 'total': tr['total'], 'alasan': alasan.trim()},
      );
    });
  }

  /// Data struk untuk cetak ulang.
  DataStruk? struk(String transaksiId, InfoCabang cabang) {
    final t = _db.satu(
      'SELECT t.*, p.metode, p.jumlah_diterima, p.kembalian, p.no_referensi, u.nama AS kasir'
      ' FROM transaksi t JOIN pembayaran p ON p.transaksi_id = t.id JOIN pengguna u ON u.id = t.kasir_id'
      ' WHERE t.id = ?',
      [transaksiId],
    );
    if (t == null) return null;
    final item = _db
        .pilih('SELECT nama_barang, qty, harga_satuan, harga_grosir FROM transaksi_item WHERE transaksi_id = ? ORDER BY rowid',
            [transaksiId])
        .map((r) => ItemStruk(
              nama: r['nama_barang'] as String,
              qty: r['qty'] as int,
              hargaSatuan: r['harga_satuan'] as int,
              isGrosir: r['harga_grosir'] == 1,
            ))
        .toList();
    return DataStruk(
      namaToko: cabang.namaToko,
      namaCabang: cabang.nama,
      alamat: cabang.alamat,
      noTransaksi: t['no_transaksi'] as String,
      waktu: DateTime.parse(t['created_at'] as String),
      namaKasir: t['kasir'] as String,
      item: item,
      metode: MetodeBayar.dariKode(t['metode'] as String),
      diterima: t['jumlah_diterima'] as int,
      kembalian: t['kembalian'] as int,
      noReferensi: t['no_referensi'] as String?,
      pesanBawah: cabang.pesanStruk,
      dibatalkan: sudahDibatalkan(transaksiId),
      cetakUlang: true,
    );
  }

  /// Detail transaksi untuk layar riwayat (revisi E): barang per baris seperti daftar belanja kasir.
  DetailTransaksi? detailTransaksi(String transaksiId, InfoCabang cabang) {
    final s = struk(transaksiId, cabang);
    if (s == null) return null;
    final item = _db
        .pilih(
          'SELECT i.barang_id, i.nama_barang, i.qty, i.harga_satuan, i.harga_grosir, i.subtotal,'
          ' IFNULL((SELECT SUM(ri.qty) FROM retur_item ri WHERE ri.transaksi_item_id = i.id), 0) AS sudah'
          ' FROM transaksi_item i WHERE i.transaksi_id = ? ORDER BY i.rowid',
          [transaksiId],
        )
        .map((r) => ItemDetailTransaksi(
              barangId: r['barang_id'] as String,
              nama: r['nama_barang'] as String,
              qty: r['qty'] as int,
              hargaSatuan: r['harga_satuan'] as int,
              isGrosir: r['harga_grosir'] == 1,
              subtotal: r['subtotal'] as int,
              sudahRetur: r['sudah'] as int,
            ))
        .toList();
    final t = _db.satu('SELECT kasir_id FROM transaksi WHERE id = ?', [transaksiId])!;
    return DetailTransaksi(
      id: transaksiId,
      struk: s,
      item: item,
      adaRetur: item.any((i) => i.sudahRetur > 0),
      kasirId: t['kasir_id'] as String,
    );
  }

  /// Item transaksi untuk retur: (id item, nama, qty dibeli, harga, qty sudah diretur).
  List<({String itemId, String barangId, String nama, int qty, int harga, int sudahRetur})> itemUntukRetur(
          String transaksiId) =>
      _db
          .pilih(
            'SELECT i.id, i.barang_id, i.nama_barang, i.qty, i.harga_satuan,'
            ' IFNULL((SELECT SUM(ri.qty) FROM retur_item ri WHERE ri.transaksi_item_id = i.id), 0) AS sudah'
            ' FROM transaksi_item i WHERE i.transaksi_id = ? ORDER BY i.rowid',
            [transaksiId],
          )
          .map((r) => (
                itemId: r['id'] as String,
                barangId: r['barang_id'] as String,
                nama: r['nama_barang'] as String,
                qty: r['qty'] as int,
                harga: r['harga_satuan'] as int,
                sudahRetur: r['sudah'] as int,
              ))
          .toList();

  /// Retur (SPV/Admin). [qtyPerItem]: id item → jumlah diretur. Uang dikembalikan tunai.
  int retur({
    required String transaksiId,
    required Map<String, int> qtyPerItem,
    required bool kembaliKeStok,
    required String alasan,
    required String olehId,
  }) {
    if (alasan.trim().isEmpty) throw ArgumentError('Alasan wajib diisi');
    final dipilih = {for (final e in qtyPerItem.entries) if (e.value > 0) e.key: e.value};
    if (dipilih.isEmpty) throw ArgumentError('Pilih barang yang diretur');
    return _db.transaksi(() {
      if (sudahDibatalkan(transaksiId)) throw StateError('Transaksi sudah dibatalkan');
      final item = {for (final i in itemUntukRetur(transaksiId)) i.itemId: i};
      final cabangId = _db.satu('SELECT cabang_id FROM transaksi WHERE id = ?', [transaksiId])!['cabang_id'] as String;
      var total = 0;
      for (final e in dipilih.entries) {
        final i = item[e.key];
        if (i == null) throw ArgumentError('Barang tidak ada di transaksi ini');
        if (e.value > i.qty - i.sudahRetur) throw ArgumentError('Jumlah retur ${i.nama} melebihi yang dibeli');
        total += e.value * i.harga;
      }
      final id = buatId();
      final t = _db.sekarangIso();
      _db.jalankan(
        'INSERT INTO retur (id, transaksi_id, alasan, total_kembali, diproses_oleh, created_at) VALUES (?,?,?,?,?,?)',
        [id, transaksiId, alasan.trim(), total, olehId, t],
      );
      _db.outbox('retur', id);
      for (final e in dipilih.entries) {
        final rid = buatId();
        _db.jalankan(
          'INSERT INTO retur_item (id, retur_id, transaksi_item_id, qty, kembali_ke_stok) VALUES (?,?,?,?,?)',
          [rid, id, e.key, e.value, kembaliKeStok ? 1 : 0],
        );
        _db.outbox('retur_item', rid);
        if (kembaliKeStok) {
          final mid = buatId();
          _db.jalankan(
            "INSERT INTO mutasi_stok (id, cabang_id, barang_id, jumlah, jenis, ref_id, dibuat_oleh, created_at)"
            " VALUES (?,?,?,?,'retur',?,?,?)",
            [mid, cabangId, item[e.key]!.barangId, e.value, id, olehId, t],
          );
          _db.outbox('mutasi_stok', mid);
        }
      }
      _db.log(cabangId: cabangId, penggunaId: olehId, aksi: 'retur', detail: {
        'transaksi_id': transaksiId,
        'total_kembali': total,
        'kembali_ke_stok': kembaliKeStok,
        'alasan': alasan.trim(),
      });
      return total;
    });
  }
}
