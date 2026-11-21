-- ---------------------------------------------------------------------
-- Migrasi 006 (21 Nov 2026): usulan harga dari kasir (perlu persetujuan SPV/Admin).
-- Perubahan harga oleh kasir (lewat barang masuk atau ubah harga) TIDAK langsung berlaku:
-- ditulis sebagai usulan berstatus 'menunggu'. Harga lama tetap berlaku sampai disetujui.
-- Disetujui -> sistem menulis baris baru di harga_jual (+ harga_grosir) dengan disetujui_oleh. Ditolak -> tidak ada perubahan harga.
-- Yang memutuskan lebih dulu yang berlaku (SPV/Admin di toko atau Admin di pusat); keputusan kedua ditolak.
-- Tingkat grosir usulan disimpan sebagai teks JSON: [[min_qty, harga], ...] (bilangan bulat rupiah).
-- Baris tidak boleh dihapus; UPDATE hanya sekali: dari 'menunggu' ke keputusan (trigger).

CREATE TABLE usulan_harga (
    id              TEXT PRIMARY KEY,
    cabang_id       TEXT NOT NULL REFERENCES cabang(id),
    barang_id       TEXT NOT NULL REFERENCES barang(id),
    harga_lama      INTEGER CHECK (harga_lama >= 0),        -- harga eceran saat usulan dibuat (NULL kalau belum punya harga)
    harga_baru      INTEGER NOT NULL CHECK (harga_baru > 0),
    grosir_json     TEXT NOT NULL DEFAULT '[]',
    hpp             INTEGER,                                -- HPP saat usulan dibuat (keterangan untuk pemutus)
    sumber          TEXT NOT NULL CHECK (sumber IN ('barang_masuk', 'ubah_harga')),
    ref_id          TEXT,                                   -- id barang_masuk kalau dari barang masuk
    alasan          TEXT NOT NULL CHECK (alasan <> ''),
    diminta_oleh    TEXT NOT NULL REFERENCES pengguna(id),
    status          TEXT NOT NULL DEFAULT 'menunggu'
                        CHECK (status IN ('menunggu', 'disetujui', 'ditolak')),
    diputuskan_oleh TEXT REFERENCES pengguna(id),           -- NULL kalau diputuskan dari Aplikasi Pusat
    diputuskan_di   TEXT CHECK (diputuskan_di IN ('toko', 'pusat')),
    diputuskan_pada TEXT,
    harga_jual_id   TEXT REFERENCES harga_jual(id),         -- versi harga yang ditulis saat disetujui
    created_at      TEXT NOT NULL
);
CREATE INDEX idx_usulan_harga_status ON usulan_harga(cabang_id, status, created_at);

CREATE TRIGGER no_delete_usulan_harga BEFORE DELETE ON usulan_harga BEGIN SELECT RAISE(ABORT, 'usulan_harga tidak boleh dihapus'); END;

-- Usulan yang sudah diputuskan tidak boleh diubah lagi.
CREATE TRIGGER usulan_harga_final BEFORE UPDATE ON usulan_harga
WHEN OLD.status <> 'menunggu'
BEGIN SELECT RAISE(ABORT, 'usulan harga sudah diputuskan'); END;

-- Saat diputuskan, hanya kolom keputusan yang boleh berubah.
CREATE TRIGGER usulan_harga_hanya_keputusan BEFORE UPDATE ON usulan_harga
WHEN OLD.status = 'menunggu' AND (
       NEW.id <> OLD.id OR NEW.cabang_id <> OLD.cabang_id OR NEW.barang_id <> OLD.barang_id
    OR NEW.harga_baru <> OLD.harga_baru OR NEW.grosir_json <> OLD.grosir_json OR NEW.sumber <> OLD.sumber
    OR NEW.alasan <> OLD.alasan OR NEW.diminta_oleh <> OLD.diminta_oleh OR NEW.created_at <> OLD.created_at
    OR NEW.status = 'menunggu')
BEGIN SELECT RAISE(ABORT, 'usulan harga hanya boleh diubah untuk keputusan'); END;
