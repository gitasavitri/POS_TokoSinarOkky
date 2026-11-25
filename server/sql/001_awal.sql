-- =====================================================================
-- Skema Server Pusat (MySQL 8 / MariaDB 10.6+)
--
-- Tabel data toko meniru skema SQLite Aplikasi Toko (database/schema_toko.sql)
-- supaya baris dari toko bisa disimpan apa adanya:
--   * ID = UUID teks (CHAR(36)), uang & jumlah = BIGINT, waktu = teks ISO 8601 UTC
--   * Tidak memakai FOREIGN KEY: data datang dari banyak toko secara tidak berurutan,
--     keabsahan dicek di kode sinkronisasi (cabang pengirim harus cocok).
-- Tabel khusus server: perangkat, kode_pendaftaran, sesi_admin, sinkron_diterima, perubahan.
-- =====================================================================

CREATE TABLE cabang (
    id              CHAR(36)     NOT NULL PRIMARY KEY,
    kode            VARCHAR(6)   NOT NULL,
    nama            VARCHAR(100) NOT NULL,
    alamat          VARCHAR(300) NOT NULL DEFAULT '',
    pesan_struk     VARCHAR(300) NOT NULL DEFAULT '',
    aktif           TINYINT      NOT NULL DEFAULT 1,
    created_at      VARCHAR(25)  NOT NULL,
    updated_at      VARCHAR(25)  NOT NULL,
    UNIQUE KEY uq_cabang_kode (kode)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- cabang_id NULL = Admin pusat (login di Aplikasi Pusat). Kolom totp_secret hanya diisi untuk Admin pusat;
-- rahasia TOTP Admin toko tidak pernah dikirim ke server.
CREATE TABLE pengguna (
    id              CHAR(36)     NOT NULL PRIMARY KEY,
    cabang_id       CHAR(36)     NULL,
    nama            VARCHAR(100) NOT NULL,
    nama_pengguna   VARCHAR(60)  NULL,
    peran           VARCHAR(10)  NOT NULL,
    pin_hash        VARCHAR(200) NULL,
    sandi_hash      VARCHAR(200) NULL,
    totp_secret     VARCHAR(100) NULL,
    gagal_login     INT          NOT NULL DEFAULT 0,
    terkunci        TINYINT      NOT NULL DEFAULT 0,
    aktif           TINYINT      NOT NULL DEFAULT 1,
    created_at      VARCHAR(25)  NOT NULL,
    updated_at      VARCHAR(25)  NOT NULL,
    KEY idx_pengguna_cabang (cabang_id),
    KEY idx_pengguna_login (nama_pengguna),
    CONSTRAINT ck_pengguna_peran CHECK (peran IN ('kasir', 'spv', 'admin'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE kategori (
    id              CHAR(36)     NOT NULL PRIMARY KEY,
    nama            VARCHAR(100) NOT NULL,
    aktif           TINYINT      NOT NULL DEFAULT 1,
    created_at      VARCHAR(25)  NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Barcode TIDAK unik di server: dua toko bisa membuat barang baru dengan barcode sama saat offline.
-- Barang ganda seperti itu ditampilkan di Aplikasi Pusat (view barang_ganda) untuk dirapikan.
CREATE TABLE barang (
    id              CHAR(36)     NOT NULL PRIMARY KEY,
    barcode         VARCHAR(64)  NULL,
    nama            VARCHAR(200) NOT NULL,
    kategori_id     CHAR(36)     NOT NULL,
    satuan          VARCHAR(20)  NOT NULL,
    aktif           TINYINT      NOT NULL DEFAULT 1,
    created_at      VARCHAR(25)  NOT NULL,
    updated_at      VARCHAR(25)  NOT NULL,
    KEY idx_barang_barcode (barcode),
    KEY idx_barang_nama (nama)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE barang_cabang (
    cabang_id       CHAR(36)     NOT NULL,
    barang_id       CHAR(36)     NOT NULL,
    aktif           TINYINT      NOT NULL DEFAULT 1,
    stok_minimum    BIGINT       NOT NULL DEFAULT 0,
    created_at      VARCHAR(25)  NOT NULL,
    updated_at      VARCHAR(25)  NOT NULL,
    PRIMARY KEY (cabang_id, barang_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE supplier (
    id              CHAR(36)     NOT NULL PRIMARY KEY,
    nama            VARCHAR(150) NOT NULL,
    jenis           VARCHAR(12)  NOT NULL DEFAULT 'luar',
    telepon         VARCHAR(40)  NOT NULL DEFAULT '',
    aktif           TINYINT      NOT NULL DEFAULT 1,
    created_at      VARCHAR(25)  NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE harga_jual (
    id              CHAR(36)     NOT NULL PRIMARY KEY,
    barang_id       CHAR(36)     NOT NULL,
    cabang_id       CHAR(36)     NULL,
    harga           BIGINT       NOT NULL,
    sumber          VARCHAR(15)  NOT NULL,
    ref_id          CHAR(36)     NULL,
    alasan          VARCHAR(300) NOT NULL DEFAULT '',
    dibuat_oleh     CHAR(36)     NOT NULL,
    disetujui_oleh  CHAR(36)     NULL,
    berlaku_mulai   VARCHAR(25)  NOT NULL,
    created_at      VARCHAR(25)  NOT NULL,
    KEY idx_harga_jual_barang (barang_id, cabang_id, berlaku_mulai),
    CONSTRAINT ck_harga_jual_positif CHECK (harga > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE harga_grosir (
    id              CHAR(36)     NOT NULL PRIMARY KEY,
    harga_jual_id   CHAR(36)     NOT NULL,
    min_qty         BIGINT       NOT NULL,
    harga           BIGINT       NOT NULL,
    created_at      VARCHAR(25)  NOT NULL,
    UNIQUE KEY uq_grosir (harga_jual_id, min_qty),
    CONSTRAINT ck_grosir CHECK (min_qty >= 2 AND harga > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE hpp_barang (
    id              CHAR(36)     NOT NULL PRIMARY KEY,
    cabang_id       CHAR(36)     NOT NULL,
    barang_id       CHAR(36)     NOT NULL,
    hpp             BIGINT       NOT NULL,
    ref_id          CHAR(36)     NULL,
    created_at      VARCHAR(25)  NOT NULL,
    KEY idx_hpp (cabang_id, barang_id, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE mutasi_stok (
    id              CHAR(36)     NOT NULL PRIMARY KEY,
    cabang_id       CHAR(36)     NOT NULL,
    barang_id       CHAR(36)     NOT NULL,
    jumlah          BIGINT       NOT NULL,
    jenis           VARCHAR(12)  NOT NULL,
    ref_id          CHAR(36)     NULL,
    dibuat_oleh     CHAR(36)     NOT NULL,
    created_at      VARCHAR(25)  NOT NULL,
    KEY idx_mutasi (cabang_id, barang_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE barang_masuk (
    id              CHAR(36)     NOT NULL PRIMARY KEY,
    cabang_id       CHAR(36)     NOT NULL,
    supplier_id     CHAR(36)     NOT NULL,
    no_faktur       VARCHAR(100) NOT NULL,
    status          VARCHAR(10)  NOT NULL,
    dibuat_oleh     CHAR(36)     NOT NULL,
    dikirim_pada    VARCHAR(25)  NULL,
    created_at      VARCHAR(25)  NOT NULL,
    KEY idx_bm_cabang (cabang_id, dikirim_pada)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE barang_masuk_item (
    id                  CHAR(36)    NOT NULL PRIMARY KEY,
    barang_masuk_id     CHAR(36)    NOT NULL,
    barang_id           CHAR(36)    NOT NULL,
    jumlah              BIGINT      NOT NULL,
    hpp_satuan          BIGINT      NOT NULL,
    harga_jual_baru     BIGINT      NULL,
    created_at          VARCHAR(25) NOT NULL,
    KEY idx_bmi (barang_masuk_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE koreksi_barang_masuk (
    id                      CHAR(36)     NOT NULL PRIMARY KEY,
    barang_masuk_item_id    CHAR(36)     NOT NULL,
    jumlah_baru             BIGINT       NOT NULL,
    hpp_baru                BIGINT       NULL,
    alasan                  VARCHAR(300) NOT NULL,
    diminta_oleh            CHAR(36)     NOT NULL,
    status                  VARCHAR(10)  NOT NULL,
    diputuskan_oleh         CHAR(36)     NULL,
    diputuskan_pada         VARCHAR(25)  NULL,
    created_at              VARCHAR(25)  NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE shift (
    id              CHAR(36)     NOT NULL PRIMARY KEY,
    cabang_id       CHAR(36)     NOT NULL,
    kasir_id        CHAR(36)     NOT NULL,
    modal_awal      BIGINT       NOT NULL,
    dibuka_pada     VARCHAR(25)  NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE shift_tutup (
    shift_id        CHAR(36)     NOT NULL PRIMARY KEY,
    kas_dihitung    BIGINT       NOT NULL,
    kas_sistem      BIGINT       NOT NULL,
    selisih         BIGINT       NOT NULL,
    ditutup_oleh    CHAR(36)     NOT NULL,
    ditutup_pada    VARCHAR(25)  NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE transaksi (
    id              CHAR(36)     NOT NULL PRIMARY KEY,
    cabang_id       CHAR(36)     NOT NULL,
    no_transaksi    VARCHAR(30)  NOT NULL,
    shift_id        CHAR(36)     NOT NULL,
    kasir_id        CHAR(36)     NOT NULL,
    total           BIGINT       NOT NULL,
    jumlah_barang   BIGINT       NOT NULL,
    created_at      VARCHAR(25)  NOT NULL,
    UNIQUE KEY uq_transaksi_no (cabang_id, no_transaksi),
    KEY idx_transaksi_waktu (cabang_id, created_at),
    KEY idx_transaksi_waktu_semua (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE transaksi_item (
    id              CHAR(36)     NOT NULL PRIMARY KEY,
    transaksi_id    CHAR(36)     NOT NULL,
    barang_id       CHAR(36)     NOT NULL,
    nama_barang     VARCHAR(200) NOT NULL,
    qty             BIGINT       NOT NULL,
    harga_satuan    BIGINT       NOT NULL,
    harga_grosir    TINYINT      NOT NULL DEFAULT 0,
    hpp_satuan      BIGINT       NOT NULL,
    subtotal        BIGINT       NOT NULL,
    KEY idx_ti_transaksi (transaksi_id),
    KEY idx_ti_barang (barang_id),
    CONSTRAINT ck_subtotal CHECK (subtotal = qty * harga_satuan)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE pembayaran (
    id              CHAR(36)     NOT NULL PRIMARY KEY,
    transaksi_id    CHAR(36)     NOT NULL,
    metode          VARCHAR(10)  NOT NULL,
    jumlah_diterima BIGINT       NOT NULL,
    kembalian       BIGINT       NOT NULL,
    no_referensi    VARCHAR(100) NULL,
    created_at      VARCHAR(25)  NOT NULL,
    UNIQUE KEY uq_pembayaran_transaksi (transaksi_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE pembatalan (
    transaksi_id    CHAR(36)     NOT NULL PRIMARY KEY,
    alasan          VARCHAR(300) NOT NULL,
    diminta_oleh    CHAR(36)     NOT NULL,
    disetujui_oleh  CHAR(36)     NOT NULL,
    created_at      VARCHAR(25)  NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE retur (
    id              CHAR(36)     NOT NULL PRIMARY KEY,
    transaksi_id    CHAR(36)     NOT NULL,
    alasan          VARCHAR(300) NOT NULL,
    total_kembali   BIGINT       NOT NULL,
    diproses_oleh   CHAR(36)     NOT NULL,
    created_at      VARCHAR(25)  NOT NULL,
    KEY idx_retur_transaksi (transaksi_id),
    KEY idx_retur_waktu (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE retur_item (
    id                  CHAR(36)    NOT NULL PRIMARY KEY,
    retur_id            CHAR(36)    NOT NULL,
    transaksi_item_id   CHAR(36)    NOT NULL,
    qty                 BIGINT      NOT NULL,
    kembali_ke_stok     TINYINT     NOT NULL,
    KEY idx_ri_retur (retur_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE log_aktivitas (
    id              CHAR(36)     NOT NULL PRIMARY KEY,
    cabang_id       CHAR(36)     NULL,
    pengguna_id     CHAR(36)     NULL,
    disetujui_oleh  CHAR(36)     NULL,
    aksi            VARCHAR(60)  NOT NULL,
    detail          TEXT         NOT NULL,
    created_at      VARCHAR(25)  NOT NULL,
    KEY idx_log_waktu (cabang_id, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- Khusus server
-- ---------------------------------------------------------------------

-- Satu PC toko = satu perangkat. Token disimpan sebagai hash SHA-256, token asli hanya di PC toko.
CREATE TABLE perangkat (
    id                  CHAR(36)     NOT NULL PRIMARY KEY,
    cabang_id           CHAR(36)     NOT NULL,
    nama                VARCHAR(100) NOT NULL,
    token_hash          CHAR(64)     NOT NULL,
    aktif               TINYINT      NOT NULL DEFAULT 1,
    terdaftar_pada      VARCHAR(25)  NOT NULL,
    terakhir_sinkron    VARCHAR(25)  NULL,
    UNIQUE KEY uq_perangkat_token (token_hash),
    KEY idx_perangkat_cabang (cabang_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Kode sekali pakai yang dibuat Admin pusat untuk mendaftarkan PC toko baru.
CREATE TABLE kode_pendaftaran (
    kode_hash       CHAR(64)     NOT NULL PRIMARY KEY,
    dibuat_oleh     CHAR(36)     NULL,
    dibuat_pada     VARCHAR(25)  NOT NULL,
    kedaluwarsa     VARCHAR(25)  NOT NULL,
    dipakai_pada    VARCHAR(25)  NULL,
    perangkat_id    CHAR(36)     NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE sesi_admin (
    token_hash      CHAR(64)     NOT NULL PRIMARY KEY,
    pengguna_id     CHAR(36)     NOT NULL,
    dibuat_pada     VARCHAR(25)  NOT NULL,
    terakhir_dipakai VARCHAR(25) NOT NULL,
    berakhir_pada   VARCHAR(25)  NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Id outbox yang sudah diterima, supaya kiriman ulang dari toko tidak diproses dua kali.
CREATE TABLE sinkron_diterima (
    outbox_id       CHAR(36)     NOT NULL PRIMARY KEY,
    perangkat_id    CHAR(36)     NOT NULL,
    tabel           VARCHAR(40)  NOT NULL,
    diterima_pada   VARCHAR(25)  NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Umpan perubahan untuk dikirim ke toko. `seq` hanya penanda urutan di server ini (bukan ID data),
-- toko menyimpan seq terakhir yang sudah diambil.
CREATE TABLE perubahan (
    seq             BIGINT       NOT NULL AUTO_INCREMENT PRIMARY KEY,
    tabel           VARCHAR(40)  NOT NULL,
    baris_id        VARCHAR(80)  NOT NULL,
    cabang_id       CHAR(36)     NULL,          -- NULL = berlaku untuk semua toko
    perangkat_id    CHAR(36)     NULL,          -- NULL = dibuat di pusat
    created_at      VARCHAR(25)  NOT NULL,
    KEY idx_perubahan_cabang (cabang_id, seq)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE VIEW barang_ganda AS
SELECT barcode, COUNT(*) AS jumlah, GROUP_CONCAT(id ORDER BY created_at) AS id_barang
FROM barang
WHERE barcode IS NOT NULL AND barcode <> ''
GROUP BY barcode
HAVING COUNT(*) > 1;
