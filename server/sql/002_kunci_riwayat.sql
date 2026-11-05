-- Tabel riwayat hanya boleh ditambah (sama seperti di Aplikasi Toko).
-- Catatan: kalau MySQL memakai binary log, membuat trigger perlu hak SUPER
-- atau `log_bin_trust_function_creators = 1`. Lihat server/README.md.

CREATE TRIGGER no_update_transaksi BEFORE UPDATE ON transaksi FOR EACH ROW SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'transaksi tidak boleh diubah';
CREATE TRIGGER no_delete_transaksi BEFORE DELETE ON transaksi FOR EACH ROW SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'transaksi tidak boleh dihapus';
CREATE TRIGGER no_update_transaksi_item BEFORE UPDATE ON transaksi_item FOR EACH ROW SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'transaksi_item tidak boleh diubah';
CREATE TRIGGER no_delete_transaksi_item BEFORE DELETE ON transaksi_item FOR EACH ROW SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'transaksi_item tidak boleh dihapus';
CREATE TRIGGER no_update_pembayaran BEFORE UPDATE ON pembayaran FOR EACH ROW SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'pembayaran tidak boleh diubah';
CREATE TRIGGER no_delete_pembayaran BEFORE DELETE ON pembayaran FOR EACH ROW SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'pembayaran tidak boleh dihapus';
CREATE TRIGGER no_update_pembatalan BEFORE UPDATE ON pembatalan FOR EACH ROW SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'pembatalan tidak boleh diubah';
CREATE TRIGGER no_delete_pembatalan BEFORE DELETE ON pembatalan FOR EACH ROW SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'pembatalan tidak boleh dihapus';
CREATE TRIGGER no_update_retur BEFORE UPDATE ON retur FOR EACH ROW SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'retur tidak boleh diubah';
CREATE TRIGGER no_delete_retur BEFORE DELETE ON retur FOR EACH ROW SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'retur tidak boleh dihapus';
CREATE TRIGGER no_update_retur_item BEFORE UPDATE ON retur_item FOR EACH ROW SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'retur_item tidak boleh diubah';
CREATE TRIGGER no_delete_retur_item BEFORE DELETE ON retur_item FOR EACH ROW SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'retur_item tidak boleh dihapus';
CREATE TRIGGER no_update_mutasi_stok BEFORE UPDATE ON mutasi_stok FOR EACH ROW SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'mutasi_stok tidak boleh diubah';
CREATE TRIGGER no_delete_mutasi_stok BEFORE DELETE ON mutasi_stok FOR EACH ROW SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'mutasi_stok tidak boleh dihapus';
CREATE TRIGGER no_update_harga_jual BEFORE UPDATE ON harga_jual FOR EACH ROW SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'harga_jual tidak boleh diubah, tambahkan versi baru';
CREATE TRIGGER no_delete_harga_jual BEFORE DELETE ON harga_jual FOR EACH ROW SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'harga_jual tidak boleh dihapus';
CREATE TRIGGER no_update_harga_grosir BEFORE UPDATE ON harga_grosir FOR EACH ROW SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'harga_grosir tidak boleh diubah';
CREATE TRIGGER no_delete_harga_grosir BEFORE DELETE ON harga_grosir FOR EACH ROW SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'harga_grosir tidak boleh dihapus';
CREATE TRIGGER no_update_hpp_barang BEFORE UPDATE ON hpp_barang FOR EACH ROW SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'hpp_barang tidak boleh diubah';
CREATE TRIGGER no_delete_hpp_barang BEFORE DELETE ON hpp_barang FOR EACH ROW SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'hpp_barang tidak boleh dihapus';
CREATE TRIGGER no_update_shift_tutup BEFORE UPDATE ON shift_tutup FOR EACH ROW SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'shift_tutup tidak boleh diubah';
CREATE TRIGGER no_delete_shift_tutup BEFORE DELETE ON shift_tutup FOR EACH ROW SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'shift_tutup tidak boleh dihapus';
CREATE TRIGGER no_update_log BEFORE UPDATE ON log_aktivitas FOR EACH ROW SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'log_aktivitas tidak boleh diubah';
CREATE TRIGGER no_delete_log BEFORE DELETE ON log_aktivitas FOR EACH ROW SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'log_aktivitas tidak boleh dihapus';
CREATE TRIGGER no_update_sinkron_diterima BEFORE UPDATE ON sinkron_diterima FOR EACH ROW SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'sinkron_diterima tidak boleh diubah';
