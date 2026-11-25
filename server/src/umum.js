// Fungsi kecil yang dipakai di banyak tempat: waktu, validasi, galat HTTP.
import { randomUUID } from 'node:crypto';

/** Waktu sebagai teks ISO 8601 UTC tanpa milidetik, sama seperti Aplikasi Toko: 2026-11-05T06:09:00Z */
export function isoUtc(waktu = new Date()) {
  return waktu.toISOString().replace(/\.\d{3}Z$/, 'Z');
}

export function tambahDetik(waktu, detik) {
  return new Date(waktu.getTime() + detik * 1000);
}

export const buatId = () => randomUUID();

const POLA_UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export const adalahUuid = (s) => typeof s === 'string' && POLA_UUID.test(s);

const POLA_ISO = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/;
export const adalahIso = (s) => typeof s === 'string' && POLA_ISO.test(s);

/** Galat yang aman ditampilkan ke pengguna; `status` = kode HTTP. */
export class GalatPengguna extends Error {
  constructor(pesan, status = 400) {
    super(pesan);
    this.status = status;
  }
}

export function wajib(kondisi, pesan, status = 400) {
  if (!kondisi) throw new GalatPengguna(pesan, status);
}

/** Bilangan bulat rupiah/jumlah. Menolak pecahan, teks, dan angka di luar batas aman. */
export function bulat(nilai, nama, { min = Number.MIN_SAFE_INTEGER, max = Number.MAX_SAFE_INTEGER } = {}) {
  wajib(Number.isSafeInteger(nilai), `${nama} harus bilangan bulat`);
  wajib(nilai >= min && nilai <= max, `${nama} harus antara ${min} dan ${max}`);
  return nilai;
}

export function teks(nilai, nama, { min = 1, max = 200 } = {}) {
  wajib(typeof nilai === 'string', `${nama} wajib diisi`);
  const t = nilai.trim();
  wajib(t.length >= min, `${nama} wajib diisi`);
  wajib(t.length <= max, `${nama} terlalu panjang (maks. ${max} huruf)`);
  return t;
}

/** Waktu untuk updated_at baru: sekarang, atau 1 detik sesudah versi lama kalau jam pengirim lama lebih maju.
 *  Perlu karena versi yang menang ditentukan oleh updated_at yang lebih besar. */
export function waktuSesudah(lamaIso, sekarang = new Date()) {
  const t = isoUtc(sekarang);
  if (!lamaIso || lamaIso < t) return t;
  return isoUtc(tambahDetik(new Date(lamaIso), 1));
}
