// Token, hash sandi (Argon2id, cocok dengan hash buatan Aplikasi Toko), dan TOTP.
import { createHash, createHmac, randomBytes, timingSafeEqual } from 'node:crypto';
import { argon2id, argon2Verify } from 'hash-wasm';

/** Token acak untuk perangkat/sesi. Yang disimpan di database hanya hash-nya. */
export const tokenAcak = (byte = 32) => randomBytes(byte).toString('base64url');
export const hashToken = (token) => createHash('sha256').update(token, 'utf8').digest('hex');

/** Kode pendaftaran perangkat: 10 huruf/angka tanpa yang mirip (0/O, 1/I/L). */
export function kodePendaftaran() {
  const huruf = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  const b = randomBytes(10);
  let k = '';
  for (const x of b) k += huruf[x % huruf.length];
  return `${k.slice(0, 5)}-${k.slice(5)}`;
}

export const normalKode = (k) => String(k ?? '').toUpperCase().replace(/[^A-Z0-9]/g, '');

/** Hash sandi dengan parameter yang sama seperti pos_core (m=8192 KiB, t=3, p=1). */
export async function buatHashSandi(sandi) {
  return argon2id({
    password: sandi,
    salt: randomBytes(16),
    parallelism: 1,
    iterations: 3,
    memorySize: 8192,
    hashLength: 32,
    outputType: 'encoded',
  });
}

export async function cocokSandi(sandi, hash) {
  if (typeof hash !== 'string' || !hash.startsWith('$argon2')) return false;
  try {
    return await argon2Verify({ password: sandi, hash });
  } catch {
    return false;
  }
}

export function periksaSandiBaru(sandi) {
  if (typeof sandi !== 'string' || sandi.length < 10) return 'Kata sandi minimal 10 karakter';
  return null;
}

// ------------------------------------------------------------------ TOTP (RFC 6238, SHA-1, 30 detik, 6 angka)

const ALFABET32 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

export function base32Encode(buf) {
  let bit = 0, nilai = 0, out = '';
  for (const b of buf) {
    nilai = (nilai << 8) | b;
    bit += 8;
    while (bit >= 5) {
      out += ALFABET32[(nilai >>> (bit - 5)) & 31];
      bit -= 5;
    }
  }
  if (bit > 0) out += ALFABET32[(nilai << (5 - bit)) & 31];
  return out;
}

export function base32Decode(s) {
  const bersih = String(s).toUpperCase().replace(/[^A-Z2-7]/g, '');
  let bit = 0, nilai = 0;
  const out = [];
  for (const c of bersih) {
    nilai = (nilai << 5) | ALFABET32.indexOf(c);
    bit += 5;
    if (bit >= 8) {
      out.push((nilai >>> (bit - 8)) & 255);
      bit -= 8;
    }
  }
  return Buffer.from(out);
}

export const buatRahasiaTotp = () => base32Encode(randomBytes(20));

export function kodeTotp(rahasia, waktu = new Date(), langkah = 0) {
  const counter = Math.floor(waktu.getTime() / 1000 / 30) + langkah;
  const buf = Buffer.alloc(8);
  buf.writeBigUInt64BE(BigInt(counter));
  const h = createHmac('sha1', base32Decode(rahasia)).update(buf).digest();
  const o = h[h.length - 1] & 15;
  const bin = ((h[o] & 127) << 24) | (h[o + 1] << 16) | (h[o + 2] << 8) | h[o + 3];
  return String(bin % 1_000_000).padStart(6, '0');
}

/** Terima kode langkah sekarang, sebelumnya, dan sesudahnya (jam HP boleh selisih ±30 detik). */
export function cocokTotp(rahasia, kode, waktu = new Date()) {
  const k = String(kode ?? '').replace(/\s/g, '');
  if (!/^\d{6}$/.test(k)) return false;
  for (const l of [-1, 0, 1]) {
    const a = Buffer.from(kodeTotp(rahasia, waktu, l));
    if (timingSafeEqual(a, Buffer.from(k))) return true;
  }
  return false;
}

export const tautanOtpAuth = (rahasia, akun, penerbit = 'POS Pusat') =>
  `otpauth://totp/${encodeURIComponent(penerbit)}:${encodeURIComponent(akun)}?secret=${rahasia}&issuer=${encodeURIComponent(penerbit)}&algorithm=SHA1&digits=6&period=30`;
