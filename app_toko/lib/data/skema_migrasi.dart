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
  // 004_retur_kasir_tukar.sql
  r'''
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
''',
  // 005_order_barang.sql
  r'''
-- Migrasi 005 (11 Nov 2026): order barang ke toko utama / supplier luar (revisi G).
-- Order disimpan di PC toko supaya nomornya urut dan surat pesanan bisa dicetak ulang.
-- Nomor order ORD-<kode cabang>-<YYMMDD>-<urut 4 digit>, urut per cabang per hari (WIB).
-- "Kirim order ke pusat" BELUM dibuat: tabel ini belum dikirim ke Server Pusat (yang terkirim hanya
-- log_aktivitas 'buat_order'). Kalau nanti dikirim, tambahkan tabel yang sama di server.
-- Order yang sudah disimpan tidak bisa diubah/dihapus (buat order baru kalau salah).

CREATE TABLE order_barang (
    id              TEXT PRIMARY KEY,
    cabang_id       TEXT NOT NULL REFERENCES cabang(id),
    no_order        TEXT NOT NULL,                  -- ORD-A01-261111-0001
    supplier_id     TEXT NOT NULL REFERENCES supplier(id),   -- toko utama (jenis toko_utama) atau supplier luar
    catatan         TEXT NOT NULL DEFAULT '',
    dibuat_oleh     TEXT NOT NULL REFERENCES pengguna(id),
    created_at      TEXT NOT NULL,
    UNIQUE (cabang_id, no_order)
);
CREATE INDEX idx_order_barang_waktu ON order_barang(cabang_id, created_at);

CREATE TABLE order_barang_item (
    id              TEXT PRIMARY KEY,
    order_id        TEXT NOT NULL REFERENCES order_barang(id),
    barang_id       TEXT NOT NULL REFERENCES barang(id),
    nama_barang     TEXT NOT NULL,                  -- salinan nama saat order
    satuan          TEXT NOT NULL,
    jumlah          INTEGER NOT NULL CHECK (jumlah > 0),
    stok_saat_order INTEGER NOT NULL,               -- keterangan saja (stok saat order dibuat)
    urut            INTEGER NOT NULL CHECK (urut >= 1),
    UNIQUE (order_id, barang_id)
);

CREATE TRIGGER no_update_order_barang BEFORE UPDATE ON order_barang BEGIN SELECT RAISE(ABORT, 'order_barang tidak boleh diubah'); END;
CREATE TRIGGER no_delete_order_barang BEFORE DELETE ON order_barang BEGIN SELECT RAISE(ABORT, 'order_barang tidak boleh dihapus'); END;
CREATE TRIGGER no_update_order_barang_item BEFORE UPDATE ON order_barang_item BEGIN SELECT RAISE(ABORT, 'order_barang_item tidak boleh diubah'); END;
CREATE TRIGGER no_delete_order_barang_item BEFORE DELETE ON order_barang_item BEGIN SELECT RAISE(ABORT, 'order_barang_item tidak boleh dihapus'); END;
''',
];
