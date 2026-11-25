-- Migrasi 002 (11 Nov 2026): kas keluar/masuk di layar kasir (revisi K)
-- dan tutup shift hitung buta (revisi H). Dijalankan setelah schema_toko.sql (versi 1).

-- Uang yang diambil dari / ditambahkan ke uang kasir selama shift. Hanya INSERT.
CREATE TABLE kas_shift (
    id              TEXT PRIMARY KEY,
    cabang_id       TEXT NOT NULL REFERENCES cabang(id),
    shift_id        TEXT NOT NULL REFERENCES shift(id),
    jenis           TEXT NOT NULL CHECK (jenis IN ('keluar', 'masuk')),
    jumlah          INTEGER NOT NULL CHECK (jumlah > 0),
    keterangan      TEXT NOT NULL CHECK (keterangan <> ''),
    dibuat_oleh     TEXT NOT NULL REFERENCES pengguna(id),
    disetujui_oleh  TEXT REFERENCES pengguna(id),       -- PIN SPV (kasir, jumlah >= Rp100.000)
    created_at      TEXT NOT NULL
);
CREATE INDEX idx_kas_shift ON kas_shift(shift_id, created_at);

-- Setiap hitungan uang saat tutup shift (hitung buta). Hitungan pertama dan semua hitung ulang tercatat.
-- Hitungan terakhir yang dipakai ada di shift_tutup. Hanya INSERT.
CREATE TABLE shift_hitung (
    id              TEXT PRIMARY KEY,
    cabang_id       TEXT NOT NULL REFERENCES cabang(id),
    shift_id        TEXT NOT NULL REFERENCES shift(id),
    ke              INTEGER NOT NULL CHECK (ke >= 1),
    kas_dihitung    INTEGER NOT NULL CHECK (kas_dihitung >= 0),
    kas_sistem      INTEGER NOT NULL,
    selisih         INTEGER NOT NULL,
    dihitung_oleh   TEXT NOT NULL REFERENCES pengguna(id),
    disetujui_oleh  TEXT REFERENCES pengguna(id),       -- PIN SPV (hitung ulang ke-3 dst. oleh kasir)
    created_at      TEXT NOT NULL,
    UNIQUE (shift_id, ke),
    CHECK (selisih = kas_dihitung - kas_sistem)
);

CREATE TRIGGER no_update_kas_shift BEFORE UPDATE ON kas_shift BEGIN SELECT RAISE(ABORT, 'kas_shift tidak boleh diubah'); END;
CREATE TRIGGER no_delete_kas_shift BEFORE DELETE ON kas_shift BEGIN SELECT RAISE(ABORT, 'kas_shift tidak boleh dihapus'); END;
CREATE TRIGGER no_update_shift_hitung BEFORE UPDATE ON shift_hitung BEGIN SELECT RAISE(ABORT, 'shift_hitung tidak boleh diubah'); END;
CREATE TRIGGER no_delete_shift_hitung BEFORE DELETE ON shift_hitung BEGIN SELECT RAISE(ABORT, 'shift_hitung tidak boleh dihapus'); END;

-- Shift yang sudah ditutup tidak boleh diberi kas keluar/masuk atau hitungan baru.
CREATE TRIGGER kas_shift_tutup BEFORE INSERT ON kas_shift
WHEN EXISTS (SELECT 1 FROM shift_tutup WHERE shift_id = NEW.shift_id)
BEGIN SELECT RAISE(ABORT, 'shift sudah ditutup'); END;
CREATE TRIGGER shift_hitung_tutup BEFORE INSERT ON shift_hitung
WHEN EXISTS (SELECT 1 FROM shift_tutup WHERE shift_id = NEW.shift_id)
BEGIN SELECT RAISE(ABORT, 'shift sudah ditutup'); END;
