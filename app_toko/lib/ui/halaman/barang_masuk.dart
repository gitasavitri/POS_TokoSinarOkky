import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pos_core/pos_core.dart';

import '../../data/model.dart';
import '../../data/repo/barang_masuk_repo.dart';
import '../../layanan/aplikasi.dart';
import '../komponen/umum.dart';
import '../tema.dart';

const daftarSatuan = ['pcs', 'pak', 'pouch', 'botol', 'kaleng', 'renceng', 'bungkus', 'kg', 'liter', 'sak', 'dus', 'karton', 'lusin'];

/// Barang masuk: ubah satu per satu → konfirmasi → kirim & kunci.
class IsiBarangMasuk extends StatefulWidget {
  const IsiBarangMasuk({super.key});
  @override
  State<IsiBarangMasuk> createState() => _IsiBarangMasukState();
}

class _IsiBarangMasukState extends State<IsiBarangMasuk> {
  late DraftBarangMasuk _draft;
  late List<Kategori> _kategori;
  late List<Supplier> _supplier;
  int _pilih = 0;
  bool _konfirmasi = false;
  final _scan = TextEditingController();
  final _faktur = TextEditingController();

  Aplikasi get app => context.app;

  @override
  void initState() {
    super.initState();
    _kategori = app.katalog.kategori();
    _supplier = app.katalog.supplier();
    _draft = app.barangMasuk.muatDraft(app.cabang.id) ?? DraftBarangMasuk();
    _draft.supplierId ??= _supplier.isEmpty ? null : _supplier.first.id;
    _faktur.text = _draft.noFaktur;
  }

  void _simpanDraft() => app.barangMasuk.simpanDraft(_draft);

  void _ubah(VoidCallback f) {
    setState(f);
    _simpanDraft();
  }

  void _tambahDariScan() {
    final isi = _scan.text.trim();
    if (isi.isEmpty) return;
    final ada = app.katalog.cariBarcode(isi, app.cabang.id);
    _scan.clear();
    if (ada != null) {
      _tambahBarangLama(ada);
    } else {
      _ubah(() {
        _draft.item.add(DraftItemMasuk(barcode: isi, kategoriId: _kategori.isEmpty ? '' : _kategori.first.id));
        _pilih = _draft.item.length - 1;
      });
      tampilkanPesan(context, 'Barcode $isi belum ada di sistem. Isi data barang baru.');
    }
  }

  void _tambahBarangLama(DetailBarang b) {
    final i = _draft.item.indexWhere((x) => x.barangId == b.id);
    if (i >= 0) {
      setState(() => _pilih = i);
      tampilkanPesan(context, '${b.nama} sudah ada di daftar.');
      return;
    }
    _ubah(() {
      _draft.item.add(app.barangMasuk.itemDariBarang(b));
      _pilih = _draft.item.length - 1;
    });
  }

  Future<void> _cariBarangLama() async {
    final b = await showDialog<DetailBarang>(context: context, builder: (_) => const _DialogCariSemua());
    if (b != null) _tambahBarangLama(b);
  }

  void _barangBaru() => _ubah(() {
        _draft.item.add(DraftItemMasuk(kategoriId: _kategori.isEmpty ? '' : _kategori.first.id));
        _pilih = _draft.item.length - 1;
      });

  Future<void> _tambahSupplier() async {
    final nama = await _mintaTeks(context, judul: 'Tambah supplier', label: 'Nama supplier');
    if (nama == null) return;
    try {
      final id = app.katalog.tambahSupplier(nama, cabangId: app.cabang.id, olehId: app.penggunaAktif!.id);
      _ubah(() {
        _supplier = app.katalog.supplier();
        _draft.supplierId = id;
      });
    } catch (e) {
      if (mounted) tampilkanPesan(context, pesanGalat(e), galat: true);
    }
  }

  Future<void> _tambahKategori() async {
    final nama = await _mintaTeks(context, judul: 'Tambah kategori', label: 'Nama kategori');
    if (nama == null) return;
    try {
      final id = app.katalog.tambahKategori(nama, cabangId: app.cabang.id, olehId: app.penggunaAktif!.id);
      _ubah(() {
        _kategori = app.katalog.kategori();
        _draft.item[_pilih].kategoriId = id;
      });
    } catch (e) {
      if (mounted) tampilkanPesan(context, pesanGalat(e), galat: true);
    }
  }

  void _lanjut() {
    if (_draft.item.isEmpty) return tampilkanPesan(context, 'Belum ada barang di daftar.', galat: true);
    if (_draft.noFaktur.trim().isEmpty) return tampilkanPesan(context, 'Isi nomor faktur / surat jalan dulu.', galat: true);
    final salah = app.barangMasuk.periksa(_draft);
    if (salah.isNotEmpty) {
      final i = salah.keys.first;
      setState(() => _pilih = i);
      return tampilkanPesan(context, 'Barang no. ${i + 1}: ${salah[i]!.first}', galat: true);
    }
    setState(() => _konfirmasi = true);
  }

  void _kirim() {
    try {
      app.barangMasuk.kirim(cabang: app.cabang, oleh: app.penggunaAktif!, draft: _draft);
      app.barangMasuk.hapusDraft();
      tampilkanPesan(context, 'Barang masuk tersimpan dan terkunci. Stok sudah bertambah.');
      setState(() {
        _draft = DraftBarangMasuk(supplierId: _draft.supplierId);
        _faktur.clear();
        _pilih = 0;
        _konfirmasi = false;
      });
    } catch (e) {
      tampilkanPesan(context, pesanGalat(e), galat: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_konfirmasi) {
      return _Konfirmasi(
        draft: _draft,
        kategori: {for (final k in _kategori) k.id: k.nama},
        supplier: _supplier.firstWhere((s) => s.id == _draft.supplierId, orElse: () => const Supplier('', '-', 'luar')).nama,
        onKembali: () => setState(() => _konfirmasi = false),
        onKirim: _kirim,
      );
    }
    final p = app.penggunaAktif!;
    final jumlah = (baru: _draft.item.where((i) => i.barangBaru).length, ubah: _draft.item.where((i) => i.status == 'Data diubah').length);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Warna.garis, width: 2)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            flex: 3,
            child: DropdownButtonFormField<String>(
              initialValue: _draft.supplierId,
              decoration: const InputDecoration(labelText: 'Supplier'),
              style: const TextStyle(fontSize: 18, color: Warna.teks, fontFamily: fontUtama),
              items: [
                for (final s in _supplier) DropdownMenuItem(value: s.id, child: Text(s.jenis == 'toko_utama' ? '${s.nama} (toko utama)' : s.nama)),
              ],
              onChanged: (v) => _ubah(() => _draft.supplierId = v),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(height: 56, child: OutlinedButton(onPressed: _tambahSupplier, child: const Text('+ Supplier'))),
          const SizedBox(width: 16),
          Expanded(
            flex: 3,
            child: TextField(
              controller: _faktur,
              style: const TextStyle(fontSize: 18),
              decoration: const InputDecoration(labelText: 'No. faktur / surat jalan', hintText: 'Lihat di kertas dari supplier'),
              onChanged: (v) {
                _draft.noFaktur = v;
                _simpanDraft();
              },
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(height: 56, child: OutlinedButton.icon(onPressed: () => _riwayat(context), icon: const Icon(Icons.history), label: const Text('Riwayat & minta koreksi'))),
        ]),
      ),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 380,
              child: Container(
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Warna.garis, width: 2)),
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    const Expanded(child: Text('Daftar barang', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
                    Text('${_draft.item.length} barang', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Warna.teks2)),
                  ]),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _scan,
                    autofocus: true,
                    style: const TextStyle(fontSize: 18),
                    decoration: const InputDecoration(
                      hintText: 'Scan barcode barang yang datang',
                      prefixIcon: Icon(Icons.qr_code_scanner, color: Warna.hijau),
                      enabledBorder:
                          OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10)), borderSide: BorderSide(color: Warna.hijau, width: 3)),
                    ),
                    onSubmitted: (_) => _tambahDariScan(),
                  ),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: OutlinedButton(onPressed: _cariBarangLama, child: const Text('Cari barang lama'))),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _barangBaru,
                        style: OutlinedButton.styleFrom(
                            backgroundColor: const Color(0xFFF2F8F5), foregroundColor: Warna.hijauGelap, side: const BorderSide(color: Warna.hijau, width: 2)),
                        child: const Text('+ Barang baru'),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ListView.separated(
                      itemCount: _draft.item.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final it = _draft.item[i];
                        final dipilih = i == _pilih;
                        return InkWell(
                          onTap: () => setState(() => _pilih = i),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: dipilih ? Warna.hijauMuda : Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: dipilih ? Warna.hijau : Warna.kepalaTabel, width: dipilih ? 3 : 2),
                            ),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Expanded(
                                  child: Text('${i + 1}. ${it.nama.isEmpty ? '(nama belum diisi)' : it.nama}',
                                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                                ),
                                Text('+${formatAngka(it.jumlah)} ${it.satuan}',
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Warna.hijauGelap)),
                              ]),
                              const SizedBox(height: 6),
                              Lencana.status(it.status),
                            ]),
                          ),
                        );
                      },
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _draft.item.isEmpty
                  ? const Panel(
                      child: Padding(
                        padding: EdgeInsets.all(30),
                        child: Text(
                          'Scan barang yang datang, cari barang lama, atau tekan "+ Barang baru" untuk barang yang belum ada di sistem.',
                          style: TextStyle(fontSize: 19, color: Warna.teksPudar, height: 1.5),
                        ),
                      ),
                    )
                  : _FormItem(
                      key: ObjectKey(_draft.item[_pilih.clamp(0, _draft.item.length - 1)]),
                      item: _draft.item[_pilih.clamp(0, _draft.item.length - 1)],
                      nomor: _pilih + 1,
                      kategori: _kategori,
                      bolehTambahKategori: p.peran == Peran.admin,
                      onTambahKategori: _tambahKategori,
                      onUbah: () => _ubah(() {}),
                      onHapus: () => _ubah(() {
                        _draft.item.removeAt(_pilih);
                        _pilih = (_pilih - 1).clamp(0, 1 << 20);
                      }),
                      onBerikutnya: () => setState(() => _pilih = (_pilih + 1) % _draft.item.length),
                    ),
            ),
          ]),
        ),
      ),
      Container(
        decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Warna.hijau, width: 4))),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(children: [
          Expanded(
            child: Text.rich(TextSpan(style: const TextStyle(fontSize: 17), children: [
              const TextSpan(text: 'Barang baru: '),
              TextSpan(text: '${jumlah.baru}', style: const TextStyle(fontWeight: FontWeight.w800)),
              const TextSpan(text: '     Data diubah: '),
              TextSpan(text: '${jumlah.ubah}', style: const TextStyle(fontWeight: FontWeight.w800)),
              const TextSpan(text: '     Stok masuk saja: '),
              TextSpan(text: '${_draft.item.length - jumlah.baru - jumlah.ubah}', style: const TextStyle(fontWeight: FontWeight.w800)),
              const TextSpan(text: '     · Draft tersimpan otomatis di PC ini', style: TextStyle(color: Warna.teksPudar, fontSize: 15)),
            ])),
          ),
          if (_draft.item.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: OutlinedButton(
                onPressed: () async {
                  if (await konfirmasi(context, judul: 'Buang draft?', isi: 'Semua barang di daftar ini akan dihapus.', ya: 'Buang', bahaya: true)) {
                    app.barangMasuk.hapusDraft();
                    setState(() {
                      _draft = DraftBarangMasuk(supplierId: _draft.supplierId);
                      _faktur.clear();
                      _pilih = 0;
                    });
                  }
                },
                child: const Text('Buang draft'),
              ),
            ),
          SizedBox(height: 64, child: FilledButton(onPressed: _draft.item.isEmpty ? null : _lanjut, child: const Text('Lanjut ke konfirmasi →'))),
        ]),
      ),
    ]);
  }
}

// ============================================================================ form satu barang

class _FormItem extends StatefulWidget {
  const _FormItem({
    super.key,
    required this.item,
    required this.nomor,
    required this.kategori,
    required this.bolehTambahKategori,
    required this.onTambahKategori,
    required this.onUbah,
    required this.onHapus,
    required this.onBerikutnya,
  });

  final DraftItemMasuk item;
  final int nomor;
  final List<Kategori> kategori;
  final bool bolehTambahKategori;
  final VoidCallback onTambahKategori;
  final VoidCallback onUbah;
  final VoidCallback onHapus;
  final VoidCallback onBerikutnya;

  @override
  State<_FormItem> createState() => _FormItemState();
}

class _FormItemState extends State<_FormItem> {
  DraftItemMasuk get it => widget.item;
  late final _barcode = TextEditingController(text: it.barcode);
  late final _nama = TextEditingController(text: it.nama);
  late final _jumlah = TextEditingController(text: it.jumlah == 0 ? '' : formatAngka(it.jumlah));
  late final _hpp = TextEditingController(text: it.hpp == 0 ? '' : formatAngka(it.hpp));
  late final _jual = TextEditingController(text: it.hargaJual == 0 ? '' : formatAngka(it.hargaJual));
  late final List<(TextEditingController, TextEditingController)> _grosir = [
    for (final g in it.grosir) (TextEditingController(text: '${g.minQty}'), TextEditingController(text: formatAngka(g.harga))),
  ];

  void _ubah(VoidCallback f) {
    setState(f);
    widget.onUbah();
  }

  void _simpanGrosir() {
    it.grosir = [for (final (m, h) in _grosir) TingkatGrosir(minQty: bacaAngka(m.text), harga: bacaAngka(h.text))];
    widget.onUbah();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final asal = it.asal;
    final stok = asal?.stok ?? 0;
    final jualBerubah = asal?.harga != null && asal!.harga!.eceran != it.hargaJual && it.hargaJual > 0;
    final untung = it.hargaJual - it.hpp;
    final salahGrosir = periksaTingkatGrosir(eceran: it.hargaJual, hpp: it.hpp, tingkat: it.grosir);

    Widget bagian(String judul, List<Widget> isi, {String? catatan}) => Container(
          padding: const EdgeInsets.only(top: 16, bottom: 4),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: Warna.abuMuda, width: 2))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              LabelKecil(judul, warna: Warna.hijauGelap),
              if (catatan != null) ...[const SizedBox(width: 10), Text(catatan, style: const TextStyle(fontSize: 15, color: Warna.teksPudar))],
            ]),
            const SizedBox(height: 12),
            ...isi,
          ]),
        );

    final kategoriAda = widget.kategori.any((k) => k.id == it.kategoriId);
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Warna.garis, width: 2)),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          color: Warna.kepalaTabel,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(children: [
            Expanded(
              child: Text('${widget.nomor}. ${it.barangBaru ? 'Barang baru' : 'Ubah data barang'}',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            ),
            Lencana.status(it.status),
          ]),
        ),
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 20), children: [
            const LabelKecil('Data barang', warna: Warna.hijauGelap),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _barcode,
                  style: const TextStyle(fontSize: 19),
                  decoration: const InputDecoration(labelText: 'Barcode', hintText: 'Scan barcode di kemasan (boleh kosong)'),
                  onChanged: (v) => _ubah(() => it.barcode = v.trim()),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _nama,
                  style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
                  decoration: const InputDecoration(labelText: 'Nama barang', hintText: 'contoh: Gula Pasir 1 kg'),
                  onChanged: (v) => _ubah(() => it.nama = v),
                ),
              ),
            ]),
            const SizedBox(height: 16),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                flex: 2,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  DropdownButtonFormField<String>(
                    initialValue: kategoriAda ? it.kategoriId : null,
                    decoration: const InputDecoration(labelText: 'Kategori'),
                    style: const TextStyle(fontSize: 19, color: Warna.teks, fontFamily: fontUtama),
                    items: [for (final k in widget.kategori) DropdownMenuItem(value: k.id, child: Text(k.nama))],
                    onChanged: (v) => _ubah(() => it.kategoriId = v ?? ''),
                  ),
                  if (widget.bolehTambahKategori)
                    TextButton(onPressed: widget.onTambahKategori, child: const Text('+ Tambah kategori baru'))
                  else
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text('Kategori baru hanya bisa ditambah Admin.', style: TextStyle(fontSize: 14, color: Warna.teksPudar)),
                    ),
                ]),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: daftarSatuan.contains(it.satuan) ? it.satuan : null,
                  decoration: const InputDecoration(labelText: 'Satuan'),
                  style: const TextStyle(fontSize: 19, color: Warna.teks, fontFamily: fontUtama),
                  items: [for (final s in daftarSatuan) DropdownMenuItem(value: s, child: Text(s))],
                  onChanged: (v) => _ubah(() => it.satuan = v ?? 'pcs'),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            bagian('Stok', [
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Expanded(child: _Nilai('Stok sekarang', '${formatAngka(stok)} ${it.satuan}')),
                const SizedBox(width: 14),
                Expanded(
                  child: TextField(
                    controller: _jumlah,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FormatRibuan()],
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                    decoration: const InputDecoration(labelText: 'Jumlah masuk', hintText: '0'),
                    onChanged: (v) => _ubah(() => it.jumlah = bacaAngka(v)),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(child: _Nilai('Stok setelah masuk', '${formatAngka(stok + it.jumlah)} ${it.satuan}', sorot: true)),
              ]),
            ]),
            const SizedBox(height: 8),
            bagian('Harga', [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: InputRupiah(
                    controller: _hpp,
                    label: 'HPP / harga modal per ${it.satuan}',
                    onChanged: (n) => _ubah(() => it.hpp = n),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    InputRupiah(
                      controller: _jual,
                      label: 'Harga jual eceran per ${it.satuan}',
                      tegas: jualBerubah,
                      onChanged: (n) => _ubah(() => it.hargaJual = n),
                    ),
                    const SizedBox(height: 6),
                    if (it.hargaJual > 0)
                      Text(
                        '${jualBerubah ? 'Sebelumnya ${formatRupiah(asal.harga!.eceran)} · ' : ''}'
                        '${untung > 0 ? 'Untung ${formatRupiah(untung)}' : 'Rugi ${formatRupiah(-untung)}'} per ${it.satuan}',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700, color: untung <= 0 ? Warna.merah : (jualBerubah ? Warna.oranye : const Color(0xFF0A6B44))),
                      ),
                  ]),
                ),
              ]),
            ]),
            const SizedBox(height: 8),
            bagian('Harga grosir', catatan: 'opsional · harga per ${it.satuan} kalau beli banyak', [
              if (_grosir.isEmpty)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: const Color(0xFFF2F5F3), borderRadius: BorderRadius.circular(8)),
                  child: const Text('Belum ada harga grosir. Barang ini dijual dengan harga eceran saja.', style: TextStyle(fontSize: 16, color: Warna.teks2)),
                ),
              for (var i = 0; i < _grosir.length; i++)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: const Color(0xFFFAFBFA), borderRadius: BorderRadius.circular(8), border: Border.all(color: Warna.garisTipis, width: 2)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      SizedBox(width: 90, child: Text('Tingkat ${i + 1}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Warna.teks2))),
                      const Text('Beli minimal  ', style: TextStyle(fontSize: 17)),
                      SizedBox(
                        width: 100,
                        child: TextField(
                          controller: _grosir[i].$1,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                          onChanged: (_) => _simpanGrosir(),
                        ),
                      ),
                      Text('  ${it.satuan}  →  harga  ', style: const TextStyle(fontSize: 17)),
                      SizedBox(width: 190, child: InputRupiah(controller: _grosir[i].$2, onChanged: (_) => _simpanGrosir())),
                      const Spacer(),
                      OutlinedButton(
                        onPressed: () {
                          _grosir.removeAt(i);
                          _simpanGrosir();
                        },
                        style: OutlinedButton.styleFrom(foregroundColor: Warna.merah, side: const BorderSide(color: Color(0xFFE8C4BE), width: 2)),
                        child: const Text('Hapus'),
                      ),
                    ]),
                    if (salahGrosir[i] != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(salahGrosir[i]!, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Warna.merah)),
                      ),
                  ]),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton(
                  onPressed: () {
                    _grosir.add((TextEditingController(), TextEditingController()));
                    _simpanGrosir();
                  },
                  style: OutlinedButton.styleFrom(foregroundColor: Warna.hijauGelap, side: const BorderSide(color: Warna.hijau, width: 2)),
                  child: const Text('+ Tambah tingkat harga'),
                ),
              ),
            ]),
            const SizedBox(height: 18),
            Row(children: [
              OutlinedButton(
                onPressed: widget.onHapus,
                style: OutlinedButton.styleFrom(foregroundColor: Warna.merah, side: const BorderSide(color: Warna.merahGaris, width: 2)),
                child: const Text('Hapus dari daftar'),
              ),
              const Spacer(),
              FilledButton(onPressed: widget.onBerikutnya, child: const Text('Barang berikutnya')),
            ]),
          ]),
        ),
      ]),
    );
  }
}

class _Nilai extends StatelessWidget {
  const _Nilai(this.label, this.nilai, {this.sorot = false});
  final String label;
  final String nilai;
  final bool sorot;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: Warna.teks2)),
        const SizedBox(height: 6),
        Container(
          height: 58,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(color: sorot ? Warna.hijauMuda : Warna.abuMuda, borderRadius: BorderRadius.circular(10)),
          child: Text(nilai, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: sorot ? Warna.hijauGelap : Warna.teks)),
        ),
      ]);
}

// ============================================================================ konfirmasi

class _Konfirmasi extends StatefulWidget {
  const _Konfirmasi({required this.draft, required this.kategori, required this.supplier, required this.onKembali, required this.onKirim});
  final DraftBarangMasuk draft;
  final Map<String, String> kategori;
  final String supplier;
  final VoidCallback onKembali;
  final VoidCallback onKirim;
  @override
  State<_Konfirmasi> createState() => _KonfirmasiState();
}

class _KonfirmasiState extends State<_Konfirmasi> {
  bool _cocok = false;

  String _grosirTeks(List<TingkatGrosir> g, String satuan) =>
      g.isEmpty ? '-' : g.map((t) => 'min ${t.minQty} $satuan: ${formatRupiah(t.harga)}').join('\n');

  @override
  Widget build(BuildContext context) {
    final d = widget.draft;
    final baru = d.item.where((i) => i.barangBaru).toList();
    final ubah = d.item.where((i) => i.status == 'Data diubah').toList();
    final stokSaja = d.item.where((i) => i.status == 'Stok masuk saja').toList();
    final total = d.item.fold<int>(0, (s, i) => s + i.jumlah);
    const kepala = TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, letterSpacing: 0.4, color: Warna.teks2);

    Widget bagian(String judul, Color latar, Color warna, Widget isi) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Container(
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Warna.garis, width: 2)),
            clipBehavior: Clip.antiAlias,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                  color: latar,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  child: Text(judul, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: warna))),
              isi,
            ]),
          ),
        );

    List<(String, String, String)> perubahan(DraftItemMasuk i) {
      final a = i.asal!;
      final r = <(String, String, String)>[];
      if (a.nama != i.nama) r.add(('Nama', a.nama, i.nama));
      if ((a.barcode ?? '') != i.barcode) r.add(('Barcode', a.barcode ?? '-', i.barcode.isEmpty ? '-' : i.barcode));
      if (a.kategoriId != i.kategoriId) r.add(('Kategori', a.kategoriNama, widget.kategori[i.kategoriId] ?? '-'));
      if (a.satuan != i.satuan) r.add(('Satuan', a.satuan, i.satuan));
      final h = a.harga;
      if (h == null || h.eceran != i.hargaJual) {
        r.add(('Harga jual', h == null ? '-' : formatRupiah(h.eceran), '${formatRupiah(i.hargaJual)}  ${h == null ? '' : '(${teksPerubahanPersen(h.eceran, i.hargaJual)})'}'));
      }
      final gLama = h?.grosir ?? const <TingkatGrosir>[];
      if (gLama.length != i.grosir.length || [for (var k = 0; k < gLama.length; k++) gLama[k] != i.grosir[k]].any((x) => x)) {
        r.add(('Harga grosir', _grosirTeks(gLama, a.satuan), _grosirTeks(i.grosir, i.satuan)));
      }
      r.add(('Stok', '${a.stok} ${a.satuan}', '${a.stok + i.jumlah} ${i.satuan} (+${i.jumlah})'));
      return r;
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(
        child: ListView(padding: const EdgeInsets.all(20), children: [
          Panel(
            child: Wrap(spacing: 50, runSpacing: 12, children: [
              _Nilai('Supplier', widget.supplier),
              _Nilai('No. faktur', d.noFaktur),
              _Nilai('Dicatat oleh', context.app.penggunaAktif!.nama),
              _Nilai('Total satuan masuk', formatAngka(total), sorot: true),
            ]),
          ),
          const SizedBox(height: 16),
          if (baru.isNotEmpty)
            bagian(
              'Barang baru (${baru.length}) · akan ditambahkan ke daftar barang toko ini',
              Warna.biruMuda,
              Warna.biru,
              Table(
                columnWidths: const {0: FlexColumnWidth(4), 1: FlexColumnWidth(2), 2: FlexColumnWidth(2), 3: FlexColumnWidth(2), 4: FlexColumnWidth(2), 5: FlexColumnWidth(3)},
                children: [
                  TableRow(
                    decoration: const BoxDecoration(color: Color(0xFFF2F5F3)),
                    children: [for (final k in ['NAMA BARANG', 'KATEGORI', 'MASUK', 'HPP', 'HARGA JUAL', 'HARGA GROSIR']) _sel(Text(k, style: kepala))],
                  ),
                  for (final i in baru)
                    TableRow(children: [
                      _sel(Text(i.nama, style: gayaTebal)),
                      _sel(Text(widget.kategori[i.kategoriId] ?? '-', style: gaya)),
                      _sel(Text('${formatAngka(i.jumlah)} ${i.satuan}', style: gaya)),
                      _sel(Text(formatRupiah(i.hpp), style: gaya)),
                      _sel(Text(formatRupiah(i.hargaJual), style: gayaTebal)),
                      _sel(Text(_grosirTeks(i.grosir, i.satuan), style: gaya)),
                    ]),
                ],
              ),
            ),
          if (ubah.isNotEmpty)
            bagian(
              'Perubahan data (${ubah.length}) · harga baru langsung berlaku di kasir setelah dikirim',
              Warna.oranyeMuda,
              Warna.oranye,
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (final i in ubah) ...[
                  Padding(padding: const EdgeInsets.fromLTRB(18, 14, 18, 6), child: Text(i.asal!.nama, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800))),
                  Table(
                    columnWidths: const {0: FlexColumnWidth(2), 1: FlexColumnWidth(4), 2: FlexColumnWidth(4)},
                    children: [
                      TableRow(
                          decoration: const BoxDecoration(color: Color(0xFFF2F5F3)),
                          children: [for (final k in ['DATA', 'SEBELUM', 'SESUDAH']) _sel(Text(k, style: kepala))]),
                      for (final (a, b, c) in perubahan(i))
                        TableRow(children: [
                          _sel(Text(a, style: gayaTebal)),
                          _sel(Text(b, style: const TextStyle(fontSize: 17, color: Color(0xFF5E6A65), decoration: TextDecoration.lineThrough))),
                          _sel(Text(c, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Warna.oranye))),
                        ]),
                    ],
                  ),
                ],
              ]),
            ),
          if (stokSaja.isNotEmpty)
            bagian(
              'Stok masuk saja (${stokSaja.length})',
              Warna.abuMuda,
              Warna.teks,
              Column(children: [
                for (final i in stokSaja)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    child: Row(children: [
                      Expanded(child: Text(i.nama, style: gayaTebal)),
                      Text('${i.asal!.stok} → ', style: gaya),
                      Text('${i.asal!.stok + i.jumlah} ${i.satuan} (+${i.jumlah})',
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Warna.hijauGelap)),
                    ]),
                  ),
              ]),
            ),
        ]),
      ),
      Container(
        decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Warna.hijau, width: 4))),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          CheckboxListTile(
            value: _cocok,
            onChanged: (v) => setState(() => _cocok = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: Text('Saya sudah mencocokkan semua barang dan harga dengan faktur ${d.noFaktur}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            subtitle: const Text(
                'Setelah dikirim: stok bertambah, harga baru berlaku di kasir, dan data terkunci. Koreksi hanya lewat SPV atau Admin.',
                style: TextStyle(fontSize: 15.5)),
          ),
          const SizedBox(height: 10),
          Row(children: [
            SizedBox(height: 64, child: OutlinedButton(onPressed: widget.onKembali, child: const Text('← Kembali & ubah'))),
            const Spacer(),
            SizedBox(height: 64, child: FilledButton(onPressed: _cocok ? widget.onKirim : null, child: const Text('Kirim & kunci'))),
          ]),
        ]),
      ),
    ]);
  }
}

const gaya = TextStyle(fontSize: 17);
const gayaTebal = TextStyle(fontSize: 17, fontWeight: FontWeight.w800);
Widget _sel(Widget w) => Padding(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12), child: w);

// ============================================================================ riwayat & minta koreksi

Future<void> _riwayat(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _DialogRiwayat());

class _DialogRiwayat extends StatefulWidget {
  const _DialogRiwayat();
  @override
  State<_DialogRiwayat> createState() => _DialogRiwayatState();
}

class _DialogRiwayatState extends State<_DialogRiwayat> {
  late List<RiwayatMasuk> _r;

  @override
  void initState() {
    super.initState();
    _r = context.app.barangMasuk.riwayat(context.app.cabang.id);
  }

  Future<void> _minta(String itemId, String nama, int sekarang) async {
    final jumlah = TextEditingController();
    final alasan = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Minta koreksi: $nama', style: const TextStyle(fontWeight: FontWeight.w800)),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Tercatat sekarang: $sekarang', style: const TextStyle(fontSize: 17)),
            const SizedBox(height: 14),
            TextField(
              controller: jumlah,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              decoration: const InputDecoration(labelText: 'Jumlah yang benar'),
            ),
            const SizedBox(height: 14),
            TextField(controller: alasan, style: const TextStyle(fontSize: 18), decoration: const InputDecoration(labelText: 'Alasan', hintText: 'contoh: salah ketik')),
          ]),
        ),
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(d, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Kirim permintaan')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final app = context.app;
      app.barangMasuk.mintaKoreksi(itemId: itemId, jumlahBaru: bacaAngka(jumlah.text), alasan: alasan.text, oleh: app.penggunaAktif!);
      tampilkanPesan(context, 'Permintaan koreksi terkirim ke SPV/Admin.');
      setState(() => _r = app.barangMasuk.riwayat(app.cabang.id));
    } catch (e) {
      tampilkanPesan(context, pesanGalat(e), galat: true);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Riwayat barang masuk', style: TextStyle(fontWeight: FontWeight.w800)),
        content: SizedBox(
          width: 860,
          height: 600,
          child: _r.isEmpty
              ? const Center(child: Text('Belum ada barang masuk.', style: TextStyle(fontSize: 18, color: Warna.teksPudar)))
              : ListView(children: [
                  const KotakPesan('Data yang sudah dikirim terkunci. Kalau ada yang salah, tekan "Minta koreksi"; SPV atau Admin yang menyetujui.',
                      jenis: JenisPesan.info),
                  const SizedBox(height: 12),
                  for (final r in _r)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: Warna.garisTipis, width: 2)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Text('Faktur ${r.noFaktur} · ${r.supplier}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                        Text('${formatLayar(r.dikirimPada)} · ${r.oleh}', style: const TextStyle(fontSize: 15, color: Warna.teksPudar)),
                        const SizedBox(height: 8),
                        for (final i in r.item)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(children: [
                              Expanded(child: Text(i.nama, style: const TextStyle(fontSize: 17))),
                              Text(
                                  i.jumlahBerlaku != i.jumlah
                                      ? '${i.jumlah} → ${i.jumlahBerlaku} ${i.satuan}'
                                      : '${i.jumlah} ${i.satuan}',
                                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                              const SizedBox(width: 12),
                              if (i.statusKoreksi == 'menunggu')
                                Lencana.status('Menunggu')
                              else
                                TextButton(onPressed: () => _minta(i.itemId, i.nama, i.jumlahBerlaku), child: const Text('Minta koreksi')),
                            ]),
                          ),
                      ]),
                    ),
                ]),
        ),
        actions: [OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Tutup'))],
      );
}

// ============================================================================ cari semua barang

class _DialogCariSemua extends StatefulWidget {
  const _DialogCariSemua();
  @override
  State<_DialogCariSemua> createState() => _DialogCariSemuaState();
}

class _DialogCariSemuaState extends State<_DialogCariSemua> {
  final _kata = TextEditingController();
  List<DetailBarang> _hasil = [];

  @override
  void initState() {
    super.initState();
    _cari();
  }

  void _cari() {
    final app = context.app;
    setState(() => _hasil = app.katalog.cari(_kata.text, app.cabang.id, hanyaDiToko: false, batas: 60));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Cari barang lama', style: TextStyle(fontWeight: FontWeight.w800)),
        content: SizedBox(
          width: 720,
          height: 520,
          child: Column(children: [
            TextField(
              controller: _kata,
              autofocus: true,
              style: const TextStyle(fontSize: 20),
              decoration: const InputDecoration(hintText: 'Ketik nama atau barcode', prefixIcon: Icon(Icons.search)),
              onChanged: (_) => _cari(),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                itemCount: _hasil.length,
                separatorBuilder: (_, _) => const Divider(),
                itemBuilder: (_, i) {
                  final d = _hasil[i];
                  return ListTile(
                    onTap: () => Navigator.pop(context, d),
                    title: Text(d.nama, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    subtitle: Text('${d.barcode ?? 'tanpa barcode'} · ${d.kategoriNama}${d.dijualDiToko ? ' · stok ${d.stok} ${d.satuan}' : ' · belum dijual di toko ini'}'),
                    trailing: Text(d.harga == null ? '-' : formatRupiah(d.harga!.eceran), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  );
                },
              ),
            ),
          ]),
        ),
        actions: [OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Tutup'))],
      );
}

Future<String?> _mintaTeks(BuildContext context, {required String judul, required String label}) {
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(judul, style: const TextStyle(fontWeight: FontWeight.w800)),
      content: SizedBox(
        width: 440,
        child: TextField(
          controller: c,
          autofocus: true,
          style: const TextStyle(fontSize: 19),
          decoration: InputDecoration(labelText: label),
          onSubmitted: (v) => Navigator.pop(d, v.trim().isEmpty ? null : v.trim()),
        ),
      ),
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(d), child: const Text('Batal')),
        FilledButton(onPressed: () => Navigator.pop(d, c.text.trim().isEmpty ? null : c.text.trim()), child: const Text('Simpan')),
      ],
    ),
  );
}
