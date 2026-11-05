// Rute HTTP Server Pusat.
import express from 'express';

import { buatKodePendaftaran, cekPerangkat, cekSesi, daftarPerangkat as daftarkanPerangkat, keluarAdmin, masukAdmin } from './akun.js';
import { satu, transaksi } from './db.js';
import * as pusat from './pusat.js';
import { MAKS_AMBIL, MAKS_KIRIM, ambilPerubahan, terimaKiriman } from './sinkron.js';
import { GalatPengguna, isoUtc, wajib } from './umum.js';

const VERSI_API = 1;

const tokenDari = (req) => {
  const h = req.get('authorization') ?? '';
  return h.startsWith('Bearer ') ? h.slice(7).trim() : null;
};

export function buatApp(pool, { trustProxy = false, catatGalat = console.error, jedaSinkronDetik } = {}) {
  const app = express();
  app.disable('x-powered-by');
  if (trustProxy) app.set('trust proxy', 1);
  app.use(express.json({ limit: '10mb' }));

  // ---------------------------------------------------------------- umum
  app.get('/api/sehat', async (_req, res) => {
    await satu(pool, 'SELECT 1 AS ok');
    res.json({ ok: true, versi_api: VERSI_API, waktu: isoUtc() });
  });

  // ---------------------------------------------------------------- perangkat toko
  app.post('/api/perangkat/daftar', async (req, res) => {
    res.status(201).json(await daftarkanPerangkat(pool, req.body ?? {}));
  });

  const wajibPerangkat = async (req, _res, next) => {
    const p = await cekPerangkat(pool, tokenDari(req));
    if (!p) throw new GalatPengguna('Perangkat belum terdaftar atau sudah dicabut', 401);
    req.perangkat = p;
    next();
  };

  app.get('/api/perangkat/status', wajibPerangkat, async (req, res) => {
    res.json({ perangkat_id: req.perangkat.id, cabang_id: req.perangkat.cabang_id, waktu: isoUtc() });
  });

  app.post('/api/sinkron/kirim', wajibPerangkat, async (req, res) => {
    const item = req.body?.item;
    wajib(Array.isArray(item), 'item harus berupa daftar');
    wajib(item.length <= MAKS_KIRIM, `Maksimal ${MAKS_KIRIM} item per kiriman`);
    res.json(await transaksi(pool, (kon) => terimaKiriman(kon, req.perangkat, item)));
  });

  app.get('/api/sinkron/ambil', wajibPerangkat, async (req, res) => {
    const sejak = Number(req.query.sejak ?? 0);
    wajib(Number.isSafeInteger(sejak) && sejak >= 0, 'sejak tidak valid');
    const batas = Math.min(Number(req.query.batas) || MAKS_AMBIL, MAKS_AMBIL);
    // waktu server ikut dikirim supaya PC toko bisa memperingatkan kalau jamnya salah.
    res.json({ ...(await ambilPerubahan(pool, req.perangkat, sejak, batas, new Date(), jedaSinkronDetik)), waktu: isoUtc() });
  });

  // ---------------------------------------------------------------- Admin pusat
  app.post('/api/pusat/masuk', async (req, res) => {
    res.json(await masukAdmin(pool, req.body ?? {}));
  });

  const r = express.Router();
  r.use(async (req, _res, next) => {
    const admin = await cekSesi(pool, tokenDari(req));
    if (!admin) throw new GalatPengguna('Sesi berakhir, silakan masuk lagi', 401);
    req.admin = admin;
    next();
  });

  r.post('/keluar', async (req, res) => {
    await keluarAdmin(pool, tokenDari(req));
    res.json({ ok: true });
  });
  r.get('/saya', (req, res) => res.json(req.admin));

  r.get('/cabang', async (_req, res) => res.json(await pusat.daftarCabang(pool)));
  r.get('/perangkat', async (_req, res) => res.json(await pusat.daftarPerangkat(pool)));
  r.post('/perangkat/:id/cabut', async (req, res) => {
    await pusat.cabutPerangkat(pool, req.params.id, req.admin.id);
    res.json({ ok: true });
  });
  r.post('/kode-pendaftaran', async (req, res) => res.status(201).json(await buatKodePendaftaran(pool, req.admin.id)));

  r.get('/kategori', async (_req, res) => {
    const [baris] = await pool.query('SELECT id, nama, aktif FROM kategori ORDER BY nama');
    res.json(baris);
  });
  r.post('/kategori', async (req, res) =>
    res.status(201).json(await transaksi(pool, (kon) => pusat.simpanKategori(kon, req.body ?? {}, req.admin.id))),
  );
  r.get('/barang', async (req, res) => res.json(await pusat.daftarBarang(pool, req.query)));
  r.post('/barang', async (req, res) => res.json(await transaksi(pool, (kon) => pusat.simpanBarang(kon, req.body ?? {}, req.admin.id))));
  r.get('/barang-ganda', async (_req, res) => res.json(await pusat.barangGanda(pool)));
  r.post('/barang-cabang', async (req, res) => {
    await transaksi(pool, (kon) => pusat.aturBarangCabang(kon, req.body ?? {}, req.admin.id));
    res.json({ ok: true });
  });
  r.post('/harga', async (req, res) => res.status(201).json(await pusat.ubahHargaPusatTransaksi(pool, req.body ?? {}, req.admin.id)));

  r.get('/ringkasan', async (req, res) => res.json(await pusat.ringkasan(pool, req.query)));
  r.get('/penjualan-harian', async (req, res) => res.json(await pusat.penjualanHarian(pool, req.query)));
  r.get('/terlaris', async (req, res) => res.json(await pusat.terlaris(pool, req.query)));
  r.get('/transaksi', async (req, res) => res.json(await pusat.daftarTransaksi(pool, req.query)));
  r.get('/stok', async (req, res) => res.json(await pusat.stokCabang(pool, req.query)));
  r.get('/karyawan', async (req, res) => res.json(await pusat.daftarKaryawan(pool, req.query)));
  r.get('/log', async (req, res) => res.json(await pusat.daftarLog(pool, req.query)));

  app.use('/api/pusat', r);

  // ---------------------------------------------------------------- galat
  app.use((_req, res) => res.status(404).json({ galat: 'Alamat tidak ditemukan' }));
  // eslint-disable-next-line no-unused-vars
  app.use((err, _req, res, _next) => {
    if (err instanceof GalatPengguna) return res.status(err.status).json({ galat: err.message });
    if (err?.type === 'entity.parse.failed') return res.status(400).json({ galat: 'Isi permintaan bukan JSON yang valid' });
    if (err?.type === 'entity.too.large') return res.status(413).json({ galat: 'Kiriman terlalu besar' });
    catatGalat(err);
    res.status(500).json({ galat: 'Terjadi galat di server' });
  });
  return app;
}
