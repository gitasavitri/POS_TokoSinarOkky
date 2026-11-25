import { pastikanDatabaseUrl } from '../src/config.js';
import { buatPool } from '../src/db.js';
import { jalankanMigrasi } from '../src/migrasi.js';

const pool = buatPool(pastikanDatabaseUrl());
try {
  await jalankanMigrasi(pool, { cetak: console.log });
  console.log('Skema database sudah terbaru.');
} finally {
  await pool.end();
}
