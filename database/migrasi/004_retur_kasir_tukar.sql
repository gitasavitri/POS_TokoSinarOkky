-- Migrasi 004 (11 Nov 2026): tukar / kembalikan barang oleh kasir (revisi F).
-- - Kasir boleh memproses retur sendiri; lewat 3 hari dari tanggal struk perlu PIN SPV (disetujui_oleh).
-- - Struk retur bernomor RTR-<kode cabang>-<YYMMDD>-<urut 4 digit>, urut per cabang per hari.
-- - Uang retur selalu tunai, keluar dari uang kasir shift yang sedang aktif (shift_id).
-- - Tukar barang: retur ditautkan ke transaksi baru (transaksi_tukar_id). Bagian nilai retur yang memotong
--   belanja baru dicatat di retur.dipotong DAN pembayaran.potongan_retur (jumlahnya sama). Sisa nilai retur
--   (total_kembali - dipotong) dikembalikan tunai.
-- Kolom lama tetap; baris retur lama (sebelum migrasi ini) berisi NULL / 0 di kolom baru.

ALTER TABLE retur ADD COLUMN cabang_id TEXT REFERENCES cabang(id);
ALTER TABLE retur ADD COLUMN no_retur TEXT;
ALTER TABLE retur ADD COLUMN shift_id TEXT REFERENCES shift(id);
ALTER TABLE retur ADD COLUMN disetujui_oleh TEXT REFERENCES pengguna(id);
ALTER TABLE retur ADD COLUMN transaksi_tukar_id TEXT REFERENCES transaksi(id);
ALTER TABLE retur ADD COLUMN dipotong INTEGER NOT NULL DEFAULT 0 CHECK (dipotong >= 0);

CREATE UNIQUE INDEX uq_retur_no ON retur(cabang_id, no_retur) WHERE no_retur IS NOT NULL;
CREATE UNIQUE INDEX uq_retur_tukar ON retur(transaksi_tukar_id) WHERE transaksi_tukar_id IS NOT NULL;
CREATE INDEX idx_retur_cabang_waktu ON retur(cabang_id, created_at);

-- Potongan dari barang yang ditukar (0 untuk transaksi biasa). Uang yang diterima lewat metode bayar
-- = transaksi.total - potongan_retur.
ALTER TABLE pembayaran ADD COLUMN potongan_retur INTEGER NOT NULL DEFAULT 0 CHECK (potongan_retur >= 0);

-- Potongan tidak boleh melebihi nilai retur.
CREATE TRIGGER retur_dipotong_batas BEFORE INSERT ON retur
WHEN NEW.dipotong > NEW.total_kembali OR (NEW.dipotong > 0 AND NEW.transaksi_tukar_id IS NULL)
BEGIN SELECT RAISE(ABORT, 'potongan retur tidak sah'); END;

-- Transaksi yang sudah dibatalkan tidak bisa diretur.
CREATE TRIGGER retur_transaksi_batal BEFORE INSERT ON retur
WHEN EXISTS (SELECT 1 FROM pembatalan WHERE transaksi_id = NEW.transaksi_id)
BEGIN SELECT RAISE(ABORT, 'transaksi sudah dibatalkan'); END;

-- Transaksi hasil tukar barang tidak bisa dibatalkan (nilai barang lama sudah dipakai sebagai potongan).
-- Kalau salah, retur barangnya seperti biasa.
CREATE TRIGGER pembatalan_transaksi_tukar BEFORE INSERT ON pembatalan
WHEN EXISTS (SELECT 1 FROM retur WHERE transaksi_tukar_id = NEW.transaksi_id)
BEGIN SELECT RAISE(ABORT, 'transaksi tukar tidak bisa dibatalkan'); END;

-- Jumlah retur per barang tidak boleh melebihi yang dibeli.
CREATE TRIGGER retur_item_lebih BEFORE INSERT ON retur_item
WHEN NEW.qty + IFNULL((SELECT SUM(qty) FROM retur_item WHERE transaksi_item_id = NEW.transaksi_item_id), 0)
     > (SELECT qty FROM transaksi_item WHERE id = NEW.transaksi_item_id)
BEGIN SELECT RAISE(ABORT, 'jumlah retur melebihi yang dibeli'); END;
