-- Revisi F (11 Nov 2026): tukar / kembalikan barang oleh kasir.
-- Sama dengan database/migrasi/004_retur_kasir_tukar.sql di Aplikasi Toko.

ALTER TABLE retur
    ADD COLUMN cabang_id          CHAR(36)    NULL,
    ADD COLUMN no_retur           VARCHAR(30) NULL,
    ADD COLUMN shift_id           CHAR(36)    NULL,
    ADD COLUMN disetujui_oleh     CHAR(36)    NULL,
    ADD COLUMN transaksi_tukar_id CHAR(36)    NULL,
    ADD COLUMN dipotong           BIGINT      NOT NULL DEFAULT 0,
    ADD UNIQUE KEY uq_retur_no (cabang_id, no_retur),
    ADD UNIQUE KEY uq_retur_tukar (transaksi_tukar_id),
    ADD CONSTRAINT chk_retur_dipotong CHECK (dipotong >= 0 AND dipotong <= total_kembali);

ALTER TABLE pembayaran
    ADD COLUMN potongan_retur BIGINT NOT NULL DEFAULT 0,
    ADD CONSTRAINT chk_pembayaran_potongan CHECK (potongan_retur >= 0);
