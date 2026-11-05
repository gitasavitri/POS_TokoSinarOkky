// Test dengan MySQL sungguhan (database sementara) lewat HTTP, seperti dipakai Aplikasi Toko & Aplikasi Pusat.
import assert from 'node:assert/strict';
import { after, before, describe, test } from 'node:test';

import { buatApp } from '../src/app.js';
import { kodeTotp } from '../src/keamanan.js';
import { ambilPerubahan } from '../src/sinkron.js';
import { buatAdminPusat, databaseUji, item, itemSetup, penjualanContoh, tokoContoh } from './bantu.js';

const db = await databaseUji();
const lewati = db.lewati ?? false;

describe('Server Pusat', { skip: lewati }, () => {
  let server, alamat, admin, tokenAdmin;
  const A = tokoContoh('A01');
  const B = tokoContoh('B02');
  const perangkat = {};

  async function minta(metode, jalur, { token, isi } = {}) {
    const r = await fetch(alamat + jalur, {
      method: metode,
      headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) },
      body: isi === undefined ? undefined : JSON.stringify(isi),
    });
    return { status: r.status, isi: await r.json() };
  }

  /** Perubahan untuk toko, dengan jam dimajukan supaya jeda aman 30 detik terlewati. */
  const ambil = (toko, sejak = 0) =>
    ambilPerubahan(db.pool, { id: perangkat[toko].perangkat_id, cabang_id: (toko === 'A' ? A : B).cabang.id }, sejak, 500, new Date(Date.now() + 60_000));

  before(async () => {
    const app = buatApp(db.pool, { catatGalat: () => {} });
    await new Promise((ok) => {
      server = app.listen(0, '127.0.0.1', ok);
    });
    alamat = `http://127.0.0.1:${server.address().port}`;
    admin = await buatAdminPusat(db.pool);
  });

  after(async () => {
    server?.close();
    await db.tutup();
  });

  test('sehat', async () => {
    const r = await minta('GET', '/api/sehat');
    assert.equal(r.status, 200);
    assert.equal(r.isi.ok, true);
  });

  test('Admin pusat: sandi + kode TOTP; satu pesan untuk semua kegagalan', async () => {
    const salahKode = await minta('POST', '/api/pusat/masuk', { isi: { nama_pengguna: admin.namaPengguna, sandi: admin.sandi, kode: '000000' } });
    assert.equal(salahKode.status, 401);
    const salahSandi = await minta('POST', '/api/pusat/masuk', { isi: { nama_pengguna: admin.namaPengguna, sandi: 'salah-sandinya', kode: kodeTotp(admin.rahasia) } });
    assert.equal(salahSandi.isi.galat, salahKode.isi.galat);
    const ok = await minta('POST', '/api/pusat/masuk', { isi: { nama_pengguna: admin.namaPengguna, sandi: admin.sandi, kode: kodeTotp(admin.rahasia) } });
    assert.equal(ok.status, 200, JSON.stringify(ok.isi));
    tokenAdmin = ok.isi.token;
    assert.equal((await minta('GET', '/api/pusat/saya', { token: tokenAdmin })).isi.nama, 'Admin Pusat');
    assert.equal((await minta('GET', '/api/pusat/saya')).status, 401, 'tanpa token ditolak');
  });

  test('daftarkan PC toko A dan B dengan kode sekali pakai', async () => {
    for (const [nama, d] of [['A', A], ['B', B]]) {
      const kode = (await minta('POST', '/api/pusat/kode-pendaftaran', { token: tokenAdmin })).isi.kode;
      const r = await minta('POST', '/api/perangkat/daftar', { isi: { kode, nama_perangkat: `PC ${nama}`, cabang: d.cabang } });
      assert.equal(r.status, 201, JSON.stringify(r.isi));
      perangkat[nama] = r.isi;
      const ulang = await minta('POST', '/api/perangkat/daftar', { isi: { kode, cabang: d.cabang } });
      assert.equal(ulang.status, 403, 'kode tidak bisa dipakai dua kali');
    }
    const kode = (await minta('POST', '/api/pusat/kode-pendaftaran', { token: tokenAdmin })).isi.kode;
    const kodeKembar = tokoContoh('A01');
    const r = await minta('POST', '/api/perangkat/daftar', { isi: { kode, cabang: kodeKembar.cabang } });
    assert.equal(r.status, 409, 'kode cabang A01 sudah dipakai toko lain');
  });

  test('kirim data setup + penjualan; kiriman ulang tidak dobel', async () => {
    const jual = penjualanContoh(A);
    const semua = [...itemSetup(A), ...jual.item];
    const r = await minta('POST', '/api/sinkron/kirim', { token: perangkat.A.token, isi: { item: semua } });
    assert.equal(r.status, 200);
    assert.deepEqual(r.isi.ditolak, []);
    assert.equal(r.isi.diterima.length, semua.length);

    const ulang = await minta('POST', '/api/sinkron/kirim', { token: perangkat.A.token, isi: { item: semua } });
    assert.equal(ulang.isi.diterima.length, semua.length);
    const [[{ n }]] = await db.pool.query('SELECT COUNT(*) AS n FROM transaksi');
    assert.equal(n, 1);
    const [[p]] = await db.pool.query('SELECT totp_secret FROM pengguna WHERE id = ?', [A.admin.id]);
    assert.equal(p.totp_secret, null, 'rahasia TOTP admin toko tidak disimpan di server');
  });

  test('toko B tidak bisa menulis data toko A, dan tidak bisa membuat harga untuk semua toko', async () => {
    await minta('POST', '/api/sinkron/kirim', { token: perangkat.B.token, isi: { item: itemSetup(B) } });
    const palsu = { ...penjualanContoh(A, { no: 99 }) };
    const hargaSemua = { ...B.harga, id: crypto.randomUUID(), cabang_id: null };
    const adminPusatPalsu = { ...B.admin, id: crypto.randomUUID(), cabang_id: null };
    const r = await minta('POST', '/api/sinkron/kirim', {
      token: perangkat.B.token,
      isi: { item: [palsu.item[1], item('harga_jual', hargaSemua), item('pengguna', adminPusatPalsu), item('transaksi_item', { ...palsu.ti, id: crypto.randomUUID(), transaksi_id: crypto.randomUUID() })] },
    });
    assert.equal(r.isi.diterima.length, 0);
    assert.equal(r.isi.ditolak.length, 4);
    assert.match(r.isi.ditolak[0].alasan, /bukan milik cabang/);
    assert.match(r.isi.ditolak[3].alasan, /induk belum ada/);
  });

  test('barang master: versi lebih baru menang, versi lama diabaikan', async () => {
    const baru = { ...A.barang, nama: 'Gula Pasir Premium 1 kg', updated_at: '2026-11-05T05:00:00Z' };
    const lama = { ...A.barang, nama: 'Nama Lama', updated_at: '2026-11-05T01:00:00Z' };
    await minta('POST', '/api/sinkron/kirim', { token: perangkat.A.token, isi: { item: [item('barang', baru), item('barang', lama)] } });
    const [[b]] = await db.pool.query('SELECT nama FROM barang WHERE id = ?', [A.barang.id]);
    assert.equal(b.nama, 'Gula Pasir Premium 1 kg');
  });

  test('ambil: toko B menerima barang A (katalog bersama) tapi bukan harga khusus toko A; tidak menerima kirimannya sendiri', async () => {
    const r = await ambil('B');
    const tabel = r.perubahan.map((p) => `${p.tabel}:${p.baris.id ?? p.baris.barang_id}`);
    assert.ok(tabel.includes(`barang:${A.barang.id}`));
    assert.ok(!tabel.includes(`harga_jual:${A.harga.id}`));
    assert.ok(!tabel.includes(`barang:${B.barang.id}`), 'barang kirimannya sendiri tidak dikirim balik');
    const barangA = r.perubahan.find((p) => p.baris.id === A.barang.id).baris;
    assert.equal(barangA.kategori_nama, 'Sembako', 'nama kategori ikut untuk dicocokkan di toko');
    const adminPusat = r.perubahan.find((p) => p.tabel === 'pengguna' && p.baris.id === admin.id);
    assert.ok(adminPusat, 'akun Admin pusat ikut (dibutuhkan sebagai pembuat harga pusat)');
    assert.equal(adminPusat.baris.sandi_hash, '!');
    assert.equal(adminPusat.baris.totp_secret, undefined);
    assert.ok(!r.perubahan.some((p) => p.tabel === 'pengguna' && p.baris.cabang_id === A.cabang.id), 'akun toko A tidak dikirim ke B');
    assert.equal(r.masih_ada, false);
    const lagi = await ambil('B', r.kursor);
    assert.equal(lagi.perubahan.length, 0, 'kursor maju; tidak ada yang dikirim dua kali');
  });

  test('perubahan yang lebih muda dari 30 detik belum dikirim', async () => {
    const r = await ambilPerubahan(db.pool, { id: perangkat.B.perangkat_id, cabang_id: B.cabang.id }, 0, 500, new Date());
    assert.equal(r.perubahan.length, 0);
  });

  test('harga pusat: dicek aturan grosir, lalu dikirim ke semua toko', async () => {
    const salah = await minta('POST', '/api/pusat/harga', {
      token: tokenAdmin,
      isi: { barang_id: A.barang.id, harga: 18000, grosir: [{ min_qty: 10, harga: 16000 }], alasan: 'Harga supplier naik' },
    });
    assert.equal(salah.status, 400);
    assert.match(salah.isi.galat, /HPP/);

    const { kursor } = await ambil('A');
    const ok = await minta('POST', '/api/pusat/harga', {
      token: tokenAdmin,
      isi: { barang_id: A.barang.id, harga: 18000, grosir: [{ min_qty: 10, harga: 17500 }, { min_qty: 50, harga: 17200 }], alasan: 'Harga supplier naik' },
    });
    assert.equal(ok.status, 201, JSON.stringify(ok.isi));
    for (const toko of ['A', 'B']) {
      const r = await ambil(toko, toko === 'A' ? kursor : 0);
      const hj = r.perubahan.find((p) => p.tabel === 'harga_jual' && p.baris.id === ok.isi.harga_jual_id);
      assert.ok(hj, `toko ${toko} menerima harga pusat`);
      assert.equal(hj.baris.cabang_id, null);
      assert.equal(hj.baris.sumber, 'pusat');
      const g = r.perubahan.filter((p) => p.tabel === 'harga_grosir' && p.baris.harga_jual_id === ok.isi.harga_jual_id);
      assert.deepEqual(g.map((x) => x.baris.min_qty), [10, 50]);
      const iHarga = r.perubahan.indexOf(hj);
      assert.ok(r.perubahan.indexOf(g[0]) > iHarga, 'grosir datang sesudah harga induknya');
    }
  });

  test('laporan gabungan: per cabang + total, transaksi batal tidak dihitung', async () => {
    const jualB = penjualanContoh(B, { qty: 2, harga: 17500, waktu: '2026-11-05T04:00:00Z' });
    const batalB = penjualanContoh(B, { qty: 3, harga: 17500, waktu: '2026-11-05T04:10:00Z', no: 2 });
    const pembatalan = { transaksi_id: batalB.trx.id, alasan: 'Salah input', diminta_oleh: B.kasir.id, disetujui_oleh: B.admin.id, created_at: '2026-11-05T04:11:00Z' };
    const r = await minta('POST', '/api/sinkron/kirim', {
      token: perangkat.B.token,
      isi: { item: [...jualB.item, ...batalB.item, item('pembatalan', pembatalan, batalB.trx.id)] },
    });
    assert.deepEqual(r.isi.ditolak, []);

    const q = '?dari=2026-11-04T17:00:00Z&sampai=2026-11-05T17:00:00Z';
    const s = (await minta('GET', `/api/pusat/ringkasan${q}`, { token: tokenAdmin })).isi;
    const a = s.per_cabang.find((c) => c.kode === 'A01');
    const b = s.per_cabang.find((c) => c.kode === 'B02');
    assert.equal(a.penjualan_bersih, 15 * 17000);
    assert.equal(a.laba_kotor, 15 * (17000 - 16200));
    assert.equal(b.penjualan_bersih, 2 * 17500);
    assert.equal(b.jumlah_transaksi, 1);
    assert.equal(b.jumlah_batal, 1);
    assert.equal(s.total.penjualan_bersih, 15 * 17000 + 2 * 17500);
    assert.ok(Number.isInteger(s.total.penjualan_bersih), 'uang dikembalikan sebagai bilangan bulat');

    const harian = (await minta('GET', `/api/pusat/penjualan-harian${q}`, { token: tokenAdmin })).isi;
    assert.deepEqual(harian, [{ tanggal: '2026-11-05', total: 15 * 17000 + 2 * 17500, transaksi: 2 }]);
    const stok = (await minta('GET', `/api/pusat/stok?cabang_id=${A.cabang.id}`, { token: tokenAdmin })).isi;
    assert.equal(stok[0].stok, -15);
    const trx = (await minta('GET', `/api/pusat/transaksi${q}&cabang_id=${B.cabang.id}`, { token: tokenAdmin })).isi;
    assert.equal(trx.length, 2);
    assert.equal(trx.filter((t) => t.batal).length, 1);
    const salahRentang = await minta('GET', '/api/pusat/ringkasan?dari=kemarin&sampai=hari-ini', { token: tokenAdmin });
    assert.equal(salahRentang.status, 400);
  });

  test('riwayat di server juga tidak bisa diubah', async () => {
    await assert.rejects(db.pool.query("UPDATE transaksi SET total = 1"), /tidak boleh diubah/);
    await assert.rejects(db.pool.query('DELETE FROM mutasi_stok'), /tidak boleh dihapus/);
  });

  test('koreksi barang masuk: hanya berubah dari menunggu ke keputusan', async () => {
    const bm = { id: crypto.randomUUID(), cabang_id: A.cabang.id, supplier_id: A.supplier.id, no_faktur: 'F-1', status: 'terkirim', dibuat_oleh: A.kasir.id, dikirim_pada: '2026-11-05T02:30:00Z', created_at: '2026-11-05T02:20:00Z' };
    const bmi = { id: crypto.randomUUID(), barang_masuk_id: bm.id, barang_id: A.barang.id, jumlah: 40, hpp_satuan: 3100, harga_jual_baru: null, created_at: bm.created_at };
    const k = { id: crypto.randomUUID(), barang_masuk_item_id: bmi.id, jumlah_baru: 36, hpp_baru: null, alasan: 'Salah hitung', diminta_oleh: A.kasir.id, status: 'menunggu', diputuskan_oleh: null, diputuskan_pada: null, created_at: '2026-11-05T03:00:00Z' };
    const setuju = { ...k, status: 'disetujui', diputuskan_oleh: A.admin.id, diputuskan_pada: '2026-11-05T03:05:00Z' };
    const ubahLagi = { ...k, status: 'ditolak' };
    const draftLagi = { ...bm, no_faktur: 'F-UBAH', status: 'draft' };
    const r = await minta('POST', '/api/sinkron/kirim', {
      token: perangkat.A.token,
      isi: { item: [item('barang_masuk', bm), item('barang_masuk_item', bmi), item('koreksi_barang_masuk', k), item('koreksi_barang_masuk', setuju), item('koreksi_barang_masuk', ubahLagi), item('barang_masuk', draftLagi)] },
    });
    assert.deepEqual(r.isi.ditolak, []);
    const [[kk]] = await db.pool.query('SELECT status FROM koreksi_barang_masuk WHERE id = ?', [k.id]);
    assert.equal(kk.status, 'disetujui');
    const [[b]] = await db.pool.query('SELECT no_faktur, status FROM barang_masuk WHERE id = ?', [bm.id]);
    assert.deepEqual(b, { no_faktur: 'F-1', status: 'terkirim' }, 'barang masuk terkirim tetap terkunci');
  });

  test('perangkat yang dicabut tidak bisa sinkron lagi', async () => {
    const r = await minta('POST', `/api/pusat/perangkat/${perangkat.B.perangkat_id}/cabut`, { token: tokenAdmin });
    assert.equal(r.status, 200);
    const k = await minta('GET', '/api/sinkron/ambil?sejak=0', { token: perangkat.B.token });
    assert.equal(k.status, 401);
  });

  test('Admin pusat terkunci setelah 5 kali salah', async () => {
    const lain = await buatAdminPusat(db.pool, { namaPengguna: 'admin.kedua' });
    for (let i = 0; i < 4; i++) {
      assert.equal((await minta('POST', '/api/pusat/masuk', { isi: { nama_pengguna: lain.namaPengguna, sandi: 'salah-terus-1', kode: '123456' } })).status, 401);
    }
    assert.equal((await minta('POST', '/api/pusat/masuk', { isi: { nama_pengguna: lain.namaPengguna, sandi: 'salah-terus-1', kode: '123456' } })).status, 423);
    const benar = await minta('POST', '/api/pusat/masuk', { isi: { nama_pengguna: lain.namaPengguna, sandi: lain.sandi, kode: kodeTotp(lain.rahasia) } });
    assert.equal(benar.status, 423, 'sandi benar pun ditolak sampai dibuka');
  });

  test('isi bukan JSON dan alamat tidak dikenal', async () => {
    const r = await fetch(`${alamat}/api/pusat/masuk`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: '{rusak' });
    assert.equal(r.status, 400);
    assert.equal((await minta('GET', '/api/tidak-ada')).status, 404);
  });
});
