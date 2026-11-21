-- Migrasi 006 (21 Nov 2026): usulan harga dari kasir (perlu persetujuan SPV/Admin).
-- Sama dengan database/migrasi/006_usulan_harga.sql di Aplikasi Toko.

CREATE TABLE usulan_harga (
    id              CHAR(36)     NOT NULL PRIMARY KEY,
    cabang_id       CHAR(36)     NOT NULL,
    barang_id       CHAR(36)     NOT NULL,
    harga_lama      BIGINT       NULL,
    harga_baru      BIGINT       NOT NULL,
    grosir_json     TEXT         NOT NULL,
    hpp             BIGINT       NULL,
    sumber          VARCHAR(15)  NOT NULL,
    ref_id          CHAR(36)     NULL,
    alasan          VARCHAR(300) NOT NULL,
    diminta_oleh    CHAR(36)     NOT NULL,
    status          VARCHAR(10)  NOT NULL,
    diputuskan_oleh CHAR(36)     NULL,
    diputuskan_di   VARCHAR(5)   NULL,
    diputuskan_pada VARCHAR(25)  NULL,
    harga_jual_id   CHAR(36)     NULL,
    created_at      VARCHAR(25)  NOT NULL,
    KEY idx_usulan_harga_status (cabang_id, status, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
