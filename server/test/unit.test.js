// Test tanpa database: keamanan (TOTP, Argon2 cocok dengan Aplikasi Toko), aturan harga grosir, migrasi.
import assert from 'node:assert/strict';
import { test } from 'node:test';

import { hargaUntukQty, periksaTingkatGrosir } from '../src/harga.js';
import {
  base32Decode,
  base32Encode,
  buatHashSandi,
  cocokSandi,
  cocokTotp,
  hashToken,
  kodePendaftaran,
  kodeTotp,
  normalKode,
  periksaSandiBaru,
} from '../src/keamanan.js';
import { pecahSql } from '../src/migrasi.js';
import { isoUtc, waktuSesudah } from '../src/umum.js';

test('TOTP sesuai contoh RFC 6238 (SHA-1)', () => {
  const rahasia = base32Encode(Buffer.from('12345678901234567890'));
  // RFC 6238: T=59 → 94287082, T=1111111109 → 07081804 (6 angka terakhir)
  assert.equal(kodeTotp(rahasia, new Date(59_000)), '287082');
  assert.equal(kodeTotp(rahasia, new Date(1_111_111_109_000)), '081804');
  assert.ok(cocokTotp(rahasia, '287082', new Date(59_000)));
  assert.ok(cocokTotp(rahasia, '287082', new Date(59_000 + 30_000)), 'langkah sebelumnya masih diterima');
  assert.ok(!cocokTotp(rahasia, '287082', new Date(59_000 + 90_000)), 'dua langkah lewat ditolak');
  assert.ok(!cocokTotp(rahasia, 'abc123', new Date(59_000)));
});

test('base32 bolak-balik', () => {
  const b = Buffer.from([0, 1, 2, 250, 251, 252, 253, 254, 255, 7]);
  assert.deepEqual(base32Decode(base32Encode(b)), b);
});

test('hash sandi buatan Aplikasi Toko (Dart) bisa dicek di server', async () => {
  // Dibuat dengan pos_core buatHash('sandi-panjang-1') dan buatHash('482913').
  const dariDart = '$argon2id$v=19$m=8192,t=3,p=1$298LgkoqGzqVA8wqruIJpg$5LXjAlGDzzF9h39L7/5MOns0Bj63c37EGZbNd3ysB4U';
  const pinDart = '$argon2id$v=19$m=8192,t=3,p=1$+CR8pSHekM79ZWw/O1YbGg$KA3Z0BnCdwmzoKXGF2jI0+QgYxzGY39sV4k/fGxW7xs';
  assert.ok(await cocokSandi('sandi-panjang-1', dariDart));
  assert.ok(!(await cocokSandi('sandi-panjang-2', dariDart)));
  assert.ok(await cocokSandi('482913', pinDart));
  assert.ok(!(await cocokSandi('482914', pinDart)));
});

test('hash sandi server: format PHC Argon2id, parameter sama dengan aplikasi', async () => {
  const h = await buatHashSandi('kata-sandi-baru');
  assert.match(h, /^\$argon2id\$v=19\$m=8192,t=3,p=1\$/);
  assert.ok(await cocokSandi('kata-sandi-baru', h));
  assert.ok(!(await cocokSandi('kata-sandi-lama', h)));
  assert.ok(!(await cocokSandi('apa saja', '!')), 'hash rusak/kosong selalu ditolak');
  assert.equal(periksaSandiBaru('pendek'), 'Kata sandi minimal 10 karakter');
  assert.equal(periksaSandiBaru('cukup-panjang'), null);
});

test('token dan kode pendaftaran', () => {
  assert.equal(hashToken('abc').length, 64);
  const k = kodePendaftaran();
  assert.match(k, /^[A-Z2-9]{5}-[A-Z2-9]{5}$/);
  assert.doesNotMatch(k, /[01OIL]/);
  assert.equal(normalKode(` ${k.toLowerCase()} `), k.replace('-', ''));
});

test('aturan tingkat grosir sama dengan pos_core', () => {
  const ok = periksaTingkatGrosir({ eceran: 17500, hpp: 16200, tingkat: [{ min_qty: 10, harga: 17000 }, { min_qty: 50, harga: 16800 }] });
  assert.deepEqual(ok, {});
  const salah = periksaTingkatGrosir({
    eceran: 17500,
    hpp: 16200,
    tingkat: [
      { min_qty: 1, harga: 17000 },
      { min_qty: 10, harga: 17500 },
      { min_qty: 20, harga: 16000 },
      { min_qty: 20, harga: 16900 },
    ],
  });
  assert.equal(salah[0], 'Jumlah minimal harus 2 atau lebih.');
  assert.equal(salah[1], 'Harga grosir harus lebih murah dari harga eceran.');
  assert.equal(salah[2], 'Rugi: harga grosir sama dengan atau di bawah HPP.');
  assert.equal(salah[3], 'Jumlah minimal harus lebih besar dari tingkat sebelumnya.');
  const naik = periksaTingkatGrosir({ eceran: 17500, hpp: null, tingkat: [{ min_qty: 10, harga: 16800 }, { min_qty: 50, harga: 17000 }] });
  assert.equal(naik[1], 'Harga tingkat ini lebih mahal dari tingkat sebelumnya.');
  const pecahan = periksaTingkatGrosir({ eceran: 17500, hpp: null, tingkat: [{ min_qty: 10, harga: 16999.5 }] });
  assert.equal(pecahan[0], 'Harga grosir harus diisi.', 'uang harus bilangan bulat');
});

test('harga grosir berlaku untuk seluruh jumlah di baris (contoh AGENTS.md)', () => {
  const tingkat = [{ min_qty: 10, harga: 17000 }];
  assert.deepEqual(hargaUntukQty(17500, tingkat, 9), { harga: 17500, grosir: false, subtotal: 157500 });
  assert.deepEqual(hargaUntukQty(17500, tingkat, 15), { harga: 17000, grosir: true, subtotal: 255000 });
});

test('waktu ISO tanpa milidetik, dan updated_at baru selalu lebih besar dari versi lama', () => {
  const sekarang = new Date(Date.UTC(2026, 10, 5, 6, 9, 0, 123));
  assert.equal(isoUtc(sekarang), '2026-11-05T06:09:00Z');
  assert.equal(waktuSesudah(null, sekarang), '2026-11-05T06:09:00Z');
  assert.equal(waktuSesudah('2026-11-05T06:00:00Z', sekarang), '2026-11-05T06:09:00Z');
  assert.equal(waktuSesudah('2026-11-05T07:00:00Z', sekarang), '2026-11-05T07:00:01Z', 'jam toko lebih maju');
});

test('pemecah file migrasi', () => {
  const p = pecahSql("-- komentar\nCREATE TABLE a (x INT);\nCREATE TRIGGER t BEFORE UPDATE ON a FOR EACH ROW SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'x; y';\n");
  assert.equal(p.length, 2);
  assert.match(p[1], /MESSAGE_TEXT = 'x; y'$/);
});
