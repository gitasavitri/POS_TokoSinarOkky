import { buatApp } from './app.js';
import { config, pastikanDatabaseUrl } from './config.js';
import { buatPool } from './db.js';
import { jalankanMigrasi } from './migrasi.js';

const pool = buatPool(pastikanDatabaseUrl());
await jalankanMigrasi(pool, { cetak: console.log });
const app = buatApp(pool, { trustProxy: config.trustProxy, jedaSinkronDetik: config.jedaSinkronDetik });
const server = app.listen(config.port, config.host, () => {
  console.log(`Server Pusat jalan di http://${config.host}:${config.port} (pasang HTTPS di depannya, lihat README)`);
});

const berhenti = async () => {
  server.close();
  await pool.end();
  process.exit(0);
};
process.on('SIGINT', berhenti);
process.on('SIGTERM', berhenti);
