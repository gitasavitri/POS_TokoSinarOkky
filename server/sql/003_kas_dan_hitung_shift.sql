-- Revisi K & H (11 Nov 2026): kas keluar/masuk dan hitung buta tutup shift.
-- Sama dengan database/migrasi/002_kas_dan_hitung_shift.sql di Aplikasi Toko.

CREATE TABLE kas_shift (
    id              CHAR(36)      NOT NULL PRIMARY KEY,
    cabang_id       CHAR(36)      NOT NULL,
    shift_id        CHAR(36)      NOT NULL,
    jenis           VARCHAR(10)   NOT NULL,
    jumlah          BIGINT        NOT NULL,
    keterangan      VARCHAR(200)  NOT NULL,
    dibuat_oleh     CHAR(36)      NOT NULL,
    disetujui_oleh  CHAR(36)      NULL,
    created_at      VARCHAR(25)   NOT NULL,
    KEY idx_kas_shift (shift_id),
    KEY idx_kas_waktu (cabang_id, created_at),
    CONSTRAINT chk_kas_jenis CHECK (jenis IN ('keluar', 'masuk')),
    CONSTRAINT chk_kas_jumlah CHECK (jumlah > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE shift_hitung (
    id              CHAR(36)     NOT NULL PRIMARY KEY,
    cabang_id       CHAR(36)     NOT NULL,
    shift_id        CHAR(36)     NOT NULL,
    ke              INT          NOT NULL,
    kas_dihitung    BIGINT       NOT NULL,
    kas_sistem      BIGINT       NOT NULL,
    selisih         BIGINT       NOT NULL,
    dihitung_oleh   CHAR(36)     NOT NULL,
    disetujui_oleh  CHAR(36)     NULL,
    created_at      VARCHAR(25)  NOT NULL,
    UNIQUE KEY uq_shift_hitung (shift_id, ke),
    CONSTRAINT chk_hitung_selisih CHECK (selisih = kas_dihitung - kas_sistem)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TRIGGER no_update_kas_shift BEFORE UPDATE ON kas_shift FOR EACH ROW SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'kas_shift tidak boleh diubah';
CREATE TRIGGER no_delete_kas_shift BEFORE DELETE ON kas_shift FOR EACH ROW SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'kas_shift tidak boleh dihapus';
CREATE TRIGGER no_update_shift_hitung BEFORE UPDATE ON shift_hitung FOR EACH ROW SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'shift_hitung tidak boleh diubah';
CREATE TRIGGER no_delete_shift_hitung BEFORE DELETE ON shift_hitung FOR EACH ROW SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'shift_hitung tidak boleh dihapus';
