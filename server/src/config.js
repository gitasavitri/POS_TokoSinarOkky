// Baca pengaturan dari variabel lingkungan (file .env di folder server, kalau ada).
import { existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const fileEnv = fileURLToPath(new URL('../.env', import.meta.url));
if (existsSync(fileEnv)) process.loadEnvFile(fileEnv);

export const config = {
  port: Number(process.env.PORT ?? 3000),
  // Default hanya bisa diakses dari VPS itu sendiri; HTTPS dipasang lewat Caddy/Nginx di depannya.
  host: process.env.HOST ?? '127.0.0.1',
  databaseUrl: process.env.DATABASE_URL,
  trustProxy: process.env.TRUST_PROXY === '1',
  // Hanya untuk uji coba: jeda sebelum perubahan dikirim ke toko (bawaan 30 detik).
  jedaSinkronDetik: process.env.SINKRON_JEDA_DETIK == null ? undefined : Number(process.env.SINKRON_JEDA_DETIK),
};

export function pastikanDatabaseUrl() {
  if (!config.databaseUrl) {
    console.error('DATABASE_URL belum diisi. Salin .env.contoh menjadi .env lalu isi alamat MySQL.');
    process.exit(1);
  }
  return config.databaseUrl;
}
