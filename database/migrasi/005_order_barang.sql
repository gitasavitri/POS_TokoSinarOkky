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
