-- Revisi P (11 Nov 2026): tutup shift "Belum dihitung".
-- Sama dengan database/migrasi/003_shift_belum_dihitung.sql di Aplikasi Toko.

CREATE TABLE shift_belum_dihitung (
    shift_id        CHAR(36)      NOT NULL PRIMARY KEY,
    cabang_id       CHAR(36)      NOT NULL,
    kas_sistem      BIGINT        NOT NULL,
    modal_ditinggal BIGINT        NOT NULL,
    label_amplop    VARCHAR(120)  NOT NULL,
    ditutup_oleh    CHAR(36)      NOT NULL,
    ditutup_pada    VARCHAR(25)   NOT NULL,
    KEY idx_shift_belum_dihitung (cabang_id, ditutup_pada),
    CONSTRAINT chk_belum_modal CHECK (modal_ditinggal >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TRIGGER no_update_shift_belum_dihitung BEFORE UPDATE ON shift_belum_dihitung FOR EACH ROW SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'shift_belum_dihitung tidak boleh diubah';
CREATE TRIGGER no_delete_shift_belum_dihitung BEFORE DELETE ON shift_belum_dihitung FOR EACH ROW SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'shift_belum_dihitung tidak boleh dihapus';
