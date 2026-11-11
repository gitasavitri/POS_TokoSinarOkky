// FILE INI DIBUAT OTOMATIS dari database/migrasi/*.sql.
// Jangan diedit langsung. Tambah file migrasi baru, lalu jalankan:
//   dart run tool/salin_skema.dart
// ignore_for_file: unnecessary_raw_strings

/// Migrasi setelah versi 1, berurutan. Elemen ke-0 = versi 2.
const skemaMigrasi = <String>[
  // 002_kas_dan_hitung_shift.sql
  r'''
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
''',
  // 003_shift_belum_dihitung.sql
  r'''
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
''',
];
