-- Migrasi 003 (11 Nov 2026): tutup shift "Belum dihitung" (revisi P).
-- Saat ganti shift tidak sempat menghitung uang: uang (kecuali modal tetap) dimasukkan ke amplop berlabel
-- nama kasir, shift berstatus "menunggu dihitung". SPV/Admin mengisi hasil hitungan amplop belakangan;
-- saat itu sistem menulis shift_hitung (dihitung_oleh = SPV/Admin) dan shift_tutup (ditutup_oleh = SPV/Admin,
-- ditutup_pada = waktu amplop dihitung), dan selisihnya tercatat ke kasir shift itu (shift.kasir_id).

-- Shift yang ditutup kasir tanpa menghitung uang. Satu baris per shift. Hanya INSERT.
CREATE TABLE shift_belum_dihitung (
    shift_id        TEXT PRIMARY KEY REFERENCES shift(id),
    cabang_id       TEXT NOT NULL REFERENCES cabang(id),
    kas_sistem      INTEGER NOT NULL,                       -- uang tunai seharusnya saat kasir menutup shift
    modal_ditinggal INTEGER NOT NULL CHECK (modal_ditinggal >= 0), -- modal tetap yang tetap di kasir (tidak masuk amplop)
    label_amplop    TEXT NOT NULL CHECK (label_amplop <> ''),
    ditutup_oleh    TEXT NOT NULL REFERENCES pengguna(id),  -- kasir yang menutup
    ditutup_pada    TEXT NOT NULL
);
CREATE INDEX idx_shift_belum_dihitung ON shift_belum_dihitung(cabang_id, ditutup_pada);

CREATE TRIGGER no_update_shift_belum_dihitung BEFORE UPDATE ON shift_belum_dihitung BEGIN SELECT RAISE(ABORT, 'shift_belum_dihitung tidak boleh diubah'); END;
CREATE TRIGGER no_delete_shift_belum_dihitung BEFORE DELETE ON shift_belum_dihitung BEGIN SELECT RAISE(ABORT, 'shift_belum_dihitung tidak boleh dihapus'); END;

-- Shift yang sudah ditutup (dihitung atau belum) tidak bisa ditutup "belum dihitung" lagi.
CREATE TRIGGER shift_belum_dihitung_tutup BEFORE INSERT ON shift_belum_dihitung
WHEN EXISTS (SELECT 1 FROM shift_tutup WHERE shift_id = NEW.shift_id)
BEGIN SELECT RAISE(ABORT, 'shift sudah ditutup'); END;

-- Shift menunggu dihitung tidak boleh diberi kas keluar/masuk atau transaksi baru.
CREATE TRIGGER kas_shift_belum_dihitung BEFORE INSERT ON kas_shift
WHEN EXISTS (SELECT 1 FROM shift_belum_dihitung WHERE shift_id = NEW.shift_id)
BEGIN SELECT RAISE(ABORT, 'shift sudah ditutup'); END;
CREATE TRIGGER transaksi_shift_ditutup BEFORE INSERT ON transaksi
WHEN EXISTS (SELECT 1 FROM shift_belum_dihitung WHERE shift_id = NEW.shift_id)
  OR EXISTS (SELECT 1 FROM shift_tutup WHERE shift_id = NEW.shift_id)
BEGIN SELECT RAISE(ABORT, 'shift sudah ditutup'); END;
