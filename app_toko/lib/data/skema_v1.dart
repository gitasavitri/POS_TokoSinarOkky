// FILE INI DIBUAT OTOMATIS dari database/schema_toko.sql.
// Jangan diedit langsung. Ubah skema lewat file migrasi baru, lalu jalankan:
//   dart run tool/salin_skema.dart
// ignore_for_file: unnecessary_raw_strings

const skemaV1 = r'''
-- =====================================================================
-- Skema database Aplikasi Toko (SQLite)
-- Versi 1 · lihat AGENTS.md untuk aturan lengkap
--
-- Aturan inti:
--   * ID = UUID teks, bukan auto-increment
--   * Uang = INTEGER rupiah, jumlah barang = INTEGER
--   * Waktu = TEXT ISO 8601 UTC (contoh: 2026-11-05T06:09:00Z)
--   * Tabel transaksi & riwayat hanya boleh INSERT (dijaga trigger)
--   * Stok dihitung dari mutasi_stok, tidak disimpan sebagai angka
-- =====================================================================

PRAGMA foreign_keys = ON;

-- ---------------------------------------------------------------------
-- MASTER DATA (boleh diubah, perubahan penting dicatat di log_aktivitas)
-- ---------------------------------------------------------------------

CREATE TABLE cabang (
    id              TEXT PRIMARY KEY,
    kode            TEXT NOT NULL UNIQUE,          -- dipakai di nomor struk, mis. 'A01'
    nama            TEXT NOT NULL,
    alamat          TEXT NOT NULL DEFAULT '',
    pesan_struk     TEXT NOT NULL DEFAULT '',
    aktif           INTEGER NOT NULL DEFAULT 1 CHECK (aktif IN (0, 1)),
    created_at      TEXT NOT NULL,
    updated_at      TEXT NOT NULL
);

CREATE TABLE pengguna (
    id              TEXT PRIMARY KEY,
    cabang_id       TEXT REFERENCES cabang(id),     -- NULL = admin pusat (semua cabang)
    nama            TEXT NOT NULL,
    nama_pengguna   TEXT UNIQUE,                    -- untuk login admin
    peran           TEXT NOT NULL CHECK (peran IN ('kasir', 'spv', 'admin')),
    pin_hash        TEXT,                           -- kasir & spv
    sandi_hash      TEXT,                           -- admin
    totp_secret     TEXT,                           -- admin; simpan terenkripsi
    gagal_login     INTEGER NOT NULL DEFAULT 0,
    terkunci        INTEGER NOT NULL DEFAULT 0 CHECK (terkunci IN (0, 1)),
    aktif           INTEGER NOT NULL DEFAULT 1 CHECK (aktif IN (0, 1)),
    created_at      TEXT NOT NULL,
    updated_at      TEXT NOT NULL,
    CHECK (peran = 'admin' OR pin_hash IS NOT NULL),
    CHECK (peran <> 'admin' OR (sandi_hash IS NOT NULL AND nama_pengguna IS NOT NULL))
);

CREATE TABLE kategori (
    id              TEXT PRIMARY KEY,
    nama            TEXT NOT NULL UNIQUE COLLATE NOCASE,
    aktif           INTEGER NOT NULL DEFAULT 1 CHECK (aktif IN (0, 1)),
    created_at      TEXT NOT NULL
);

CREATE TABLE barang (
    id              TEXT PRIMARY KEY,
    barcode         TEXT UNIQUE,                    -- boleh NULL untuk barang tanpa barcode
    nama            TEXT NOT NULL,
    kategori_id     TEXT NOT NULL REFERENCES kategori(id),
    satuan          TEXT NOT NULL,                  -- pcs, pak, pouch, dus, kg, ...
    aktif           INTEGER NOT NULL DEFAULT 1 CHECK (aktif IN (0, 1)),
    created_at      TEXT NOT NULL,
    updated_at      TEXT NOT NULL
);
CREATE INDEX idx_barang_nama ON barang(nama);

-- Barang yang dijual di tiap toko. Tiap toko bisa punya daftar barang berbeda.
-- Barang hanya bisa dijual di toko yang punya baris aktif di sini.
CREATE TABLE barang_cabang (
    cabang_id       TEXT NOT NULL REFERENCES cabang(id),
    barang_id       TEXT NOT NULL REFERENCES barang(id),
    aktif           INTEGER NOT NULL DEFAULT 1 CHECK (aktif IN (0, 1)),
    stok_minimum    INTEGER NOT NULL DEFAULT 0 CHECK (stok_minimum >= 0),  -- untuk peringatan stok hampir habis
    created_at      TEXT NOT NULL,
    updated_at      TEXT NOT NULL,
    PRIMARY KEY (cabang_id, barang_id)
);

CREATE TABLE supplier (
    id              TEXT PRIMARY KEY,
    nama            TEXT NOT NULL,
    jenis           TEXT NOT NULL DEFAULT 'luar' CHECK (jenis IN ('luar', 'toko_utama')),
    telepon         TEXT NOT NULL DEFAULT '',
    aktif           INTEGER NOT NULL DEFAULT 1 CHECK (aktif IN (0, 1)),
    created_at      TEXT NOT NULL
);

-- ---------------------------------------------------------------------
-- HARGA & HPP (riwayat, hanya INSERT)
-- ---------------------------------------------------------------------

-- Setiap perubahan harga = baris baru. cabang_id NULL = berlaku semua cabang.
CREATE TABLE harga_jual (
    id              TEXT PRIMARY KEY,
    barang_id       TEXT NOT NULL REFERENCES barang(id),
    cabang_id       TEXT REFERENCES cabang(id),
    harga           INTEGER NOT NULL CHECK (harga > 0),
    sumber          TEXT NOT NULL CHECK (sumber IN ('barang_masuk', 'ubah_harga', 'pusat')),
    ref_id          TEXT,                           -- id barang_masuk jika sumber = barang_masuk
    alasan          TEXT NOT NULL DEFAULT '',
    dibuat_oleh     TEXT NOT NULL REFERENCES pengguna(id),
    disetujui_oleh  TEXT REFERENCES pengguna(id),   -- PIN SPV bila diperlukan
    berlaku_mulai   TEXT NOT NULL,
    created_at      TEXT NOT NULL
);
CREATE INDEX idx_harga_jual_barang ON harga_jual(barang_id, cabang_id, berlaku_mulai);

-- Tingkat harga grosir, melekat pada satu versi harga jual.
CREATE TABLE harga_grosir (
    id              TEXT PRIMARY KEY,
    harga_jual_id   TEXT NOT NULL REFERENCES harga_jual(id),
    min_qty         INTEGER NOT NULL CHECK (min_qty >= 2),
    harga           INTEGER NOT NULL CHECK (harga > 0),
    created_at      TEXT NOT NULL,
    UNIQUE (harga_jual_id, min_qty)
);

-- HPP rata-rata tertimbang per cabang; baris terbaru = HPP sekarang.
CREATE TABLE hpp_barang (
    id              TEXT PRIMARY KEY,
    cabang_id       TEXT NOT NULL REFERENCES cabang(id),
    barang_id       TEXT NOT NULL REFERENCES barang(id),
    hpp             INTEGER NOT NULL CHECK (hpp >= 0),
    ref_id          TEXT,                           -- id barang_masuk / koreksi
    created_at      TEXT NOT NULL
);
CREATE INDEX idx_hpp_barang ON hpp_barang(cabang_id, barang_id, created_at);

-- ---------------------------------------------------------------------
-- STOK (buku besar, hanya INSERT)
-- ---------------------------------------------------------------------

CREATE TABLE mutasi_stok (
    id              TEXT PRIMARY KEY,
    cabang_id       TEXT NOT NULL REFERENCES cabang(id),
    barang_id       TEXT NOT NULL REFERENCES barang(id),
    jumlah          INTEGER NOT NULL CHECK (jumlah <> 0),   -- + masuk, − keluar
    jenis           TEXT NOT NULL CHECK (jenis IN
                        ('masuk', 'jual', 'batal_jual', 'retur', 'koreksi', 'opname')),
    ref_id          TEXT,                           -- id dokumen sumber
    dibuat_oleh     TEXT NOT NULL REFERENCES pengguna(id),
    created_at      TEXT NOT NULL
);
CREATE INDEX idx_mutasi_stok ON mutasi_stok(cabang_id, barang_id);

-- ---------------------------------------------------------------------
-- BARANG MASUK (draft bebas diubah, terkirim = terkunci)
-- ---------------------------------------------------------------------

CREATE TABLE barang_masuk (
    id              TEXT PRIMARY KEY,
    cabang_id       TEXT NOT NULL REFERENCES cabang(id),
    supplier_id     TEXT NOT NULL REFERENCES supplier(id),
    no_faktur       TEXT NOT NULL,
    status          TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'terkirim')),
    dibuat_oleh     TEXT NOT NULL REFERENCES pengguna(id),
    dikirim_pada    TEXT,
    created_at      TEXT NOT NULL,
    CHECK (status = 'draft' OR (dikirim_pada IS NOT NULL AND no_faktur <> ''))
);

CREATE TABLE barang_masuk_item (
    id                  TEXT PRIMARY KEY,
    barang_masuk_id     TEXT NOT NULL REFERENCES barang_masuk(id),
    barang_id           TEXT NOT NULL REFERENCES barang(id),
    jumlah              INTEGER NOT NULL CHECK (jumlah > 0),
    hpp_satuan          INTEGER NOT NULL CHECK (hpp_satuan >= 0),
    harga_jual_baru     INTEGER CHECK (harga_jual_baru > 0),   -- NULL = harga tidak berubah
    created_at          TEXT NOT NULL,
    UNIQUE (barang_masuk_id, barang_id)
);

CREATE TABLE koreksi_barang_masuk (
    id                      TEXT PRIMARY KEY,
    barang_masuk_item_id    TEXT NOT NULL REFERENCES barang_masuk_item(id),
    jumlah_baru             INTEGER NOT NULL CHECK (jumlah_baru >= 0),
    hpp_baru                INTEGER CHECK (hpp_baru >= 0),
    alasan                  TEXT NOT NULL CHECK (alasan <> ''),
    diminta_oleh            TEXT NOT NULL REFERENCES pengguna(id),
    status                  TEXT NOT NULL DEFAULT 'menunggu'
                                CHECK (status IN ('menunggu', 'disetujui', 'ditolak')),
    diputuskan_oleh         TEXT REFERENCES pengguna(id),
    diputuskan_pada         TEXT,
    created_at              TEXT NOT NULL
);

-- ---------------------------------------------------------------------
-- PENJUALAN (hanya INSERT)
-- ---------------------------------------------------------------------

CREATE TABLE shift (
    id              TEXT PRIMARY KEY,
    cabang_id       TEXT NOT NULL REFERENCES cabang(id),
    kasir_id        TEXT NOT NULL REFERENCES pengguna(id),
    modal_awal      INTEGER NOT NULL CHECK (modal_awal >= 0),
    dibuka_pada     TEXT NOT NULL
);

CREATE TABLE shift_tutup (
    shift_id        TEXT PRIMARY KEY REFERENCES shift(id),
    kas_dihitung    INTEGER NOT NULL CHECK (kas_dihitung >= 0),
    kas_sistem      INTEGER NOT NULL,
    selisih         INTEGER NOT NULL,
    ditutup_oleh    TEXT NOT NULL REFERENCES pengguna(id),
    ditutup_pada    TEXT NOT NULL,
    CHECK (selisih = kas_dihitung - kas_sistem)
);

CREATE TABLE transaksi (
    id              TEXT PRIMARY KEY,
    cabang_id       TEXT NOT NULL REFERENCES cabang(id),
    no_transaksi    TEXT NOT NULL,                  -- TRX-A01-261105-0001
    shift_id        TEXT NOT NULL REFERENCES shift(id),
    kasir_id        TEXT NOT NULL REFERENCES pengguna(id),
    total           INTEGER NOT NULL CHECK (total >= 0),
    jumlah_barang   INTEGER NOT NULL CHECK (jumlah_barang > 0),
    created_at      TEXT NOT NULL,
    UNIQUE (cabang_id, no_transaksi)
);
CREATE INDEX idx_transaksi_waktu ON transaksi(cabang_id, created_at);

CREATE TABLE transaksi_item (
    id              TEXT PRIMARY KEY,
    transaksi_id    TEXT NOT NULL REFERENCES transaksi(id),
    barang_id       TEXT NOT NULL REFERENCES barang(id),
    nama_barang     TEXT NOT NULL,                  -- salinan nama saat dijual
    qty             INTEGER NOT NULL CHECK (qty > 0),
    harga_satuan    INTEGER NOT NULL CHECK (harga_satuan > 0),
    harga_grosir    INTEGER NOT NULL DEFAULT 0 CHECK (harga_grosir IN (0, 1)),
    hpp_satuan      INTEGER NOT NULL CHECK (hpp_satuan >= 0),  -- untuk laporan laba
    subtotal        INTEGER NOT NULL,
    CHECK (subtotal = qty * harga_satuan)
);

CREATE TABLE pembayaran (
    id              TEXT PRIMARY KEY,
    transaksi_id    TEXT NOT NULL UNIQUE REFERENCES transaksi(id),
    metode          TEXT NOT NULL CHECK (metode IN ('tunai', 'qris', 'kartu', 'transfer')),
    jumlah_diterima INTEGER NOT NULL CHECK (jumlah_diterima >= 0),
    kembalian       INTEGER NOT NULL CHECK (kembalian >= 0),
    no_referensi    TEXT,
    created_at      TEXT NOT NULL,
    CHECK (metode IN ('qris', 'tunai') OR (no_referensi IS NOT NULL AND no_referensi <> ''))
);

CREATE TABLE pembatalan (
    transaksi_id    TEXT PRIMARY KEY REFERENCES transaksi(id),
    alasan          TEXT NOT NULL CHECK (alasan <> ''),
    diminta_oleh    TEXT NOT NULL REFERENCES pengguna(id),
    disetujui_oleh  TEXT NOT NULL REFERENCES pengguna(id),
    created_at      TEXT NOT NULL
);

CREATE TABLE retur (
    id              TEXT PRIMARY KEY,
    transaksi_id    TEXT NOT NULL REFERENCES transaksi(id),
    alasan          TEXT NOT NULL CHECK (alasan <> ''),
    total_kembali   INTEGER NOT NULL CHECK (total_kembali >= 0),
    diproses_oleh   TEXT NOT NULL REFERENCES pengguna(id),
    created_at      TEXT NOT NULL
);

CREATE TABLE retur_item (
    id                  TEXT PRIMARY KEY,
    retur_id            TEXT NOT NULL REFERENCES retur(id),
    transaksi_item_id   TEXT NOT NULL REFERENCES transaksi_item(id),
    qty                 INTEGER NOT NULL CHECK (qty > 0),
    kembali_ke_stok     INTEGER NOT NULL CHECK (kembali_ke_stok IN (0, 1))  -- 0 = barang rusak
);

-- ---------------------------------------------------------------------
-- LOG & SINKRONISASI
-- ---------------------------------------------------------------------

CREATE TABLE log_aktivitas (
    id              TEXT PRIMARY KEY,
    cabang_id       TEXT REFERENCES cabang(id),
    pengguna_id     TEXT REFERENCES pengguna(id),
    disetujui_oleh  TEXT REFERENCES pengguna(id),
    aksi            TEXT NOT NULL,                  -- mis. 'login_gagal', 'ubah_harga', 'batal_transaksi'
    detail          TEXT NOT NULL DEFAULT '{}',     -- JSON, tanpa PIN/sandi
    created_at      TEXT NOT NULL
);
CREATE INDEX idx_log_waktu ON log_aktivitas(cabang_id, created_at);

-- Antrean data yang harus dikirim ke Server Pusat.
CREATE TABLE outbox (
    id              TEXT PRIMARY KEY,
    tabel           TEXT NOT NULL,
    baris_id        TEXT NOT NULL,
    payload         TEXT NOT NULL,                  -- JSON baris lengkap
    created_at      TEXT NOT NULL,
    terkirim_pada   TEXT,                           -- NULL = belum terkirim
    percobaan       INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX idx_outbox_belum ON outbox(terkirim_pada, created_at);

-- Pengaturan khusus PC ini (printer, laci, dll.)
CREATE TABLE pengaturan_perangkat (
    kunci           TEXT PRIMARY KEY,
    nilai           TEXT NOT NULL
);

-- ---------------------------------------------------------------------
-- TRIGGER: tabel riwayat hanya boleh INSERT
-- ---------------------------------------------------------------------

CREATE TRIGGER no_update_transaksi BEFORE UPDATE ON transaksi BEGIN SELECT RAISE(ABORT, 'transaksi tidak boleh diubah'); END;
CREATE TRIGGER no_delete_transaksi BEFORE DELETE ON transaksi BEGIN SELECT RAISE(ABORT, 'transaksi tidak boleh dihapus'); END;
CREATE TRIGGER no_update_transaksi_item BEFORE UPDATE ON transaksi_item BEGIN SELECT RAISE(ABORT, 'transaksi_item tidak boleh diubah'); END;
CREATE TRIGGER no_delete_transaksi_item BEFORE DELETE ON transaksi_item BEGIN SELECT RAISE(ABORT, 'transaksi_item tidak boleh dihapus'); END;
CREATE TRIGGER no_update_pembayaran BEFORE UPDATE ON pembayaran BEGIN SELECT RAISE(ABORT, 'pembayaran tidak boleh diubah'); END;
CREATE TRIGGER no_delete_pembayaran BEFORE DELETE ON pembayaran BEGIN SELECT RAISE(ABORT, 'pembayaran tidak boleh dihapus'); END;
CREATE TRIGGER no_update_pembatalan BEFORE UPDATE ON pembatalan BEGIN SELECT RAISE(ABORT, 'pembatalan tidak boleh diubah'); END;
CREATE TRIGGER no_delete_pembatalan BEFORE DELETE ON pembatalan BEGIN SELECT RAISE(ABORT, 'pembatalan tidak boleh dihapus'); END;
CREATE TRIGGER no_update_retur BEFORE UPDATE ON retur BEGIN SELECT RAISE(ABORT, 'retur tidak boleh diubah'); END;
CREATE TRIGGER no_delete_retur BEFORE DELETE ON retur BEGIN SELECT RAISE(ABORT, 'retur tidak boleh dihapus'); END;
CREATE TRIGGER no_update_retur_item BEFORE UPDATE ON retur_item BEGIN SELECT RAISE(ABORT, 'retur_item tidak boleh diubah'); END;
CREATE TRIGGER no_delete_retur_item BEFORE DELETE ON retur_item BEGIN SELECT RAISE(ABORT, 'retur_item tidak boleh dihapus'); END;
CREATE TRIGGER no_update_mutasi_stok BEFORE UPDATE ON mutasi_stok BEGIN SELECT RAISE(ABORT, 'mutasi_stok tidak boleh diubah'); END;
CREATE TRIGGER no_delete_mutasi_stok BEFORE DELETE ON mutasi_stok BEGIN SELECT RAISE(ABORT, 'mutasi_stok tidak boleh dihapus'); END;
CREATE TRIGGER no_update_harga_jual BEFORE UPDATE ON harga_jual BEGIN SELECT RAISE(ABORT, 'harga_jual tidak boleh diubah, tambahkan versi baru'); END;
CREATE TRIGGER no_delete_harga_jual BEFORE DELETE ON harga_jual BEGIN SELECT RAISE(ABORT, 'harga_jual tidak boleh dihapus'); END;
CREATE TRIGGER no_update_harga_grosir BEFORE UPDATE ON harga_grosir BEGIN SELECT RAISE(ABORT, 'harga_grosir tidak boleh diubah, tambahkan versi baru'); END;
CREATE TRIGGER no_delete_harga_grosir BEFORE DELETE ON harga_grosir BEGIN SELECT RAISE(ABORT, 'harga_grosir tidak boleh dihapus'); END;
CREATE TRIGGER no_update_hpp_barang BEFORE UPDATE ON hpp_barang BEGIN SELECT RAISE(ABORT, 'hpp_barang tidak boleh diubah'); END;
CREATE TRIGGER no_delete_hpp_barang BEFORE DELETE ON hpp_barang BEGIN SELECT RAISE(ABORT, 'hpp_barang tidak boleh dihapus'); END;
CREATE TRIGGER no_update_shift_tutup BEFORE UPDATE ON shift_tutup BEGIN SELECT RAISE(ABORT, 'shift_tutup tidak boleh diubah'); END;
CREATE TRIGGER no_delete_shift_tutup BEFORE DELETE ON shift_tutup BEGIN SELECT RAISE(ABORT, 'shift_tutup tidak boleh dihapus'); END;
CREATE TRIGGER no_update_log BEFORE UPDATE ON log_aktivitas BEGIN SELECT RAISE(ABORT, 'log_aktivitas tidak boleh diubah'); END;
CREATE TRIGGER no_delete_log BEFORE DELETE ON log_aktivitas BEGIN SELECT RAISE(ABORT, 'log_aktivitas tidak boleh dihapus'); END;

-- Harga grosir hanya boleh ditambahkan pada versi harga jual yang baru dibuat
-- dan harus lebih murah dari harga eceran versi itu.
CREATE TRIGGER grosir_lebih_murah BEFORE INSERT ON harga_grosir
WHEN NEW.harga >= (SELECT harga FROM harga_jual WHERE id = NEW.harga_jual_id)
BEGIN SELECT RAISE(ABORT, 'harga grosir harus lebih murah dari harga eceran'); END;

-- ---------------------------------------------------------------------
-- TRIGGER: barang masuk terkunci setelah terkirim
-- ---------------------------------------------------------------------

CREATE TRIGGER bm_kunci_header BEFORE UPDATE ON barang_masuk
WHEN OLD.status = 'terkirim'
BEGIN SELECT RAISE(ABORT, 'barang masuk sudah terkirim dan terkunci; gunakan koreksi'); END;

CREATE TRIGGER bm_no_delete_header BEFORE DELETE ON barang_masuk
WHEN OLD.status = 'terkirim'
BEGIN SELECT RAISE(ABORT, 'barang masuk sudah terkirim dan tidak boleh dihapus'); END;

CREATE TRIGGER bm_kunci_item_insert BEFORE INSERT ON barang_masuk_item
WHEN (SELECT status FROM barang_masuk WHERE id = NEW.barang_masuk_id) = 'terkirim'
BEGIN SELECT RAISE(ABORT, 'barang masuk sudah terkirim dan terkunci'); END;

CREATE TRIGGER bm_kunci_item_update BEFORE UPDATE ON barang_masuk_item
WHEN (SELECT status FROM barang_masuk WHERE id = OLD.barang_masuk_id) = 'terkirim'
BEGIN SELECT RAISE(ABORT, 'barang masuk sudah terkirim dan terkunci; gunakan koreksi'); END;

CREATE TRIGGER bm_kunci_item_delete BEFORE DELETE ON barang_masuk_item
WHEN (SELECT status FROM barang_masuk WHERE id = OLD.barang_masuk_id) = 'terkirim'
BEGIN SELECT RAISE(ABORT, 'barang masuk sudah terkirim dan terkunci'); END;

-- Koreksi yang sudah diputuskan tidak boleh diubah lagi.
CREATE TRIGGER koreksi_final BEFORE UPDATE ON koreksi_barang_masuk
WHEN OLD.status <> 'menunggu'
BEGIN SELECT RAISE(ABORT, 'koreksi sudah diputuskan'); END;

-- ---------------------------------------------------------------------
-- VIEW
-- ---------------------------------------------------------------------

-- Barang yang boleh dijual di sebuah toko (dipakai layar kasir & pencarian).
CREATE VIEW barang_toko AS
SELECT bc.cabang_id, b.id AS barang_id, b.barcode, b.nama, b.satuan, b.kategori_id, bc.stok_minimum
FROM barang_cabang bc
JOIN barang b ON b.id = bc.barang_id
WHERE bc.aktif = 1 AND b.aktif = 1;

CREATE VIEW stok_sekarang AS
SELECT cabang_id, barang_id, SUM(jumlah) AS stok
FROM mutasi_stok
GROUP BY cabang_id, barang_id;

-- Versi harga terbaru per (barang, cabang). cabang_id NULL = harga semua cabang.
-- Aplikasi memilih baris cabang sendiri; kalau tidak ada, baris cabang_id NULL.
CREATE VIEW harga_jual_terkini AS
SELECT id, barang_id, cabang_id, harga, berlaku_mulai
FROM (
    SELECT hj.*,
           ROW_NUMBER() OVER (
               PARTITION BY hj.barang_id, IFNULL(hj.cabang_id, '')
               ORDER BY hj.berlaku_mulai DESC, hj.created_at DESC
           ) AS urut
    FROM harga_jual hj
    WHERE hj.berlaku_mulai <= strftime('%Y-%m-%dT%H:%M:%SZ', 'now')   -- harga terjadwal belum berlaku
)
WHERE urut = 1;

CREATE VIEW hpp_terkini AS
SELECT cabang_id, barang_id, hpp
FROM (
    SELECT hb.*,
           ROW_NUMBER() OVER (
               PARTITION BY hb.cabang_id, hb.barang_id
               ORDER BY hb.created_at DESC
           ) AS urut
    FROM hpp_barang hb
)
WHERE urut = 1;
''';
