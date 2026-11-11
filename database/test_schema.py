"""Uji skema_toko.sql dengan data contoh.

Jalankan:  python database/test_schema.py
Tidak butuh library tambahan (hanya sqlite3 bawaan Python).
"""
import sqlite3
import uuid
from pathlib import Path

SCHEMA = Path(__file__).with_name("schema_toko.sql").read_text(encoding="utf-8")
# Migrasi lanjutan (002, 003, ...) dijalankan berurutan setelah skema awal, sama seperti di Aplikasi Toko.
MIGRASI = [f.read_text(encoding="utf-8") for f in sorted((Path(__file__).parent / "migrasi").glob("[0-9][0-9][0-9]_*.sql"))]
T0 = "2026-11-01T01:00:00Z"
lulus = 0


def uid():
    return str(uuid.uuid4())


def cek(nama, kondisi):
    global lulus
    assert kondisi, f"GAGAL: {nama}"
    lulus += 1
    print(f"  ok  {nama}")


def harus_ditolak(db, nama, sql, args=()):
    try:
        db.execute(sql, args)
    except sqlite3.DatabaseError as e:
        cek(f"{nama}  ({e})", True)
        return
    raise AssertionError(f"GAGAL: {nama} seharusnya ditolak")


def harga_berlaku(db, barang, cabang):
    row = db.execute(
        """SELECT id, harga FROM harga_jual_terkini
           WHERE barang_id = ? AND (cabang_id = ? OR cabang_id IS NULL)
           ORDER BY cabang_id IS NULL LIMIT 1""",
        (barang, cabang),
    ).fetchone()
    return row


def harga_untuk_qty(db, harga_jual_id, eceran, qty):
    row = db.execute(
        """SELECT harga FROM harga_grosir
           WHERE harga_jual_id = ? AND min_qty <= ?
           ORDER BY min_qty DESC LIMIT 1""",
        (harga_jual_id, qty),
    ).fetchone()
    return (row[0], True) if row else (eceran, False)


db = sqlite3.connect(":memory:")
db.executescript(SCHEMA)
for m in MIGRASI:
    db.executescript(m)
print(f"SQLite {sqlite3.sqlite_version}: skema dibuat")

# --- master data ---------------------------------------------------------
cab_a, cab_b = uid(), uid()
for c, kode in ((cab_a, "A01"), (cab_b, "B01")):
    db.execute("INSERT INTO cabang VALUES (?,?,?,?,?,1,?,?)", (c, kode, f"Toko {kode}", "", "", T0, T0))
kasir, spv, admin = uid(), uid(), uid()
db.execute("INSERT INTO pengguna (id,cabang_id,nama,peran,pin_hash,created_at,updated_at) VALUES (?,?,?,?,?,?,?)",
           (kasir, cab_a, "Siti", "kasir", "$2b$hash", T0, T0))
db.execute("INSERT INTO pengguna (id,cabang_id,nama,peran,pin_hash,created_at,updated_at) VALUES (?,?,?,?,?,?,?)",
           (spv, cab_a, "Dewi", "spv", "$2b$hash", T0, T0))
db.execute("INSERT INTO pengguna (id,nama,nama_pengguna,peran,sandi_hash,created_at,updated_at) VALUES (?,?,?,?,?,?,?)",
           (admin, "Admin", "admin.toko", "admin", "$2b$hash", T0, T0))
harus_ditolak(db, "kasir tanpa PIN ditolak",
              "INSERT INTO pengguna (id,nama,peran,created_at,updated_at) VALUES (?,?,?,?,?)",
              (uid(), "Tanpa PIN", "kasir", T0, T0))

kat = uid()
db.execute("INSERT INTO kategori VALUES (?,?,1,?)", (kat, "Sembako", T0))
harus_ditolak(db, "kategori dobel (beda huruf besar) ditolak",
              "INSERT INTO kategori VALUES (?,?,1,?)", (uid(), "sembako", T0))
gula = uid()
db.execute("INSERT INTO barang VALUES (?,?,?,?,?,1,?,?)", (gula, "8990001", "Gula Pasir 1 kg", kat, "pak", T0, T0))
kopi = uid()
db.execute("INSERT INTO barang VALUES (?,?,?,?,?,1,?,?)", (kopi, "8990002", "Kopi Sachet", kat, "renceng", T0, T0))
db.execute("INSERT INTO barang_cabang VALUES (?,?,1,10,?,?)", (cab_a, gula, T0, T0))
db.execute("INSERT INTO barang_cabang VALUES (?,?,1,5,?,?)", (cab_b, gula, T0, T0))
db.execute("INSERT INTO barang_cabang VALUES (?,?,1,5,?,?)", (cab_b, kopi, T0, T0))
dijual = lambda c: {r[0] for r in db.execute("SELECT nama FROM barang_toko WHERE cabang_id = ?", (c,))}
cek("toko A hanya menjual gula", dijual(cab_a) == {"Gula Pasir 1 kg"})
cek("toko B menjual gula dan kopi", dijual(cab_b) == {"Gula Pasir 1 kg", "Kopi Sachet"})
harus_ditolak(db, "barang yang sama tidak bisa didaftarkan dua kali di satu toko",
              "INSERT INTO barang_cabang VALUES (?,?,1,0,?,?)", (cab_a, gula, T0, T0))

sup = uid()
db.execute("INSERT INTO supplier (id,nama,jenis,created_at) VALUES (?,?,?,?)", (sup, "Toko Utama", "toko_utama", T0))

# --- harga: semua cabang, lalu khusus cabang B ---------------------------
hj1 = uid()
db.execute("INSERT INTO harga_jual VALUES (?,?,?,?,?,?,?,?,?,?,?)",
           (hj1, gula, None, 17500, "pusat", None, "", admin, None, T0, T0))
db.execute("INSERT INTO harga_grosir VALUES (?,?,?,?,?)", (uid(), hj1, 10, 17000, T0))
db.execute("INSERT INTO harga_grosir VALUES (?,?,?,?,?)", (uid(), hj1, 50, 16800, T0))
harus_ditolak(db, "harga grosir lebih mahal dari eceran ditolak",
              "INSERT INTO harga_grosir VALUES (?,?,?,?,?)", (uid(), hj1, 100, 18000, T0))

hj_b = uid()
db.execute("INSERT INTO harga_jual VALUES (?,?,?,?,?,?,?,?,?,?,?)",
           (hj_b, gula, cab_b, 18000, "ubah_harga", None, "Harga dari supplier naik", admin, None,
            "2026-11-02T01:00:00Z", "2026-11-02T01:00:00Z"))
cek("cabang A memakai harga semua cabang (17.500)", harga_berlaku(db, gula, cab_a)[1] == 17500)
cek("cabang B memakai harga khusus (18.000)", harga_berlaku(db, gula, cab_b)[1] == 18000)

db.execute("INSERT INTO harga_jual VALUES (?,?,?,?,?,?,?,?,?,?,?)",
           (uid(), gula, None, 99999, "pusat", None, "terjadwal", admin, None,
            "2099-01-01T00:00:00Z", T0))
cek("harga terjadwal di masa depan belum berlaku", harga_berlaku(db, gula, cab_a)[1] == 17500)
harus_ditolak(db, "harga_jual tidak bisa diubah", "UPDATE harga_jual SET harga = 1 WHERE id = ?", (hj1,))

# --- harga grosir bertingkat --------------------------------------------
cek("beli 9 -> eceran 17.500", harga_untuk_qty(db, hj1, 17500, 9) == (17500, False))
cek("beli 15 -> tingkat min 10 = 17.000 untuk semua 15", harga_untuk_qty(db, hj1, 17500, 15) == (17000, True))
cek("beli 60 -> tingkat min 50 = 16.800", harga_untuk_qty(db, hj1, 17500, 60) == (16800, True))

# --- barang masuk: draft -> terkirim -> terkunci -------------------------
bm = uid()
db.execute("INSERT INTO barang_masuk (id,cabang_id,supplier_id,no_faktur,dibuat_oleh,created_at) VALUES (?,?,?,?,?,?)",
           (bm, cab_a, sup, "F-001", kasir, T0))
item = uid()
db.execute("INSERT INTO barang_masuk_item VALUES (?,?,?,?,?,?,?)", (item, bm, gula, 50, 16200, None, T0))
db.execute("UPDATE barang_masuk_item SET jumlah = 48 WHERE id = ?", (item,))
cek("draft masih bisa diubah", db.execute("SELECT jumlah FROM barang_masuk_item WHERE id=?", (item,)).fetchone()[0] == 48)

with db:  # satu transaksi database
    db.execute("UPDATE barang_masuk SET status='terkirim', dikirim_pada=? WHERE id=?", (T0, bm))
    db.execute("INSERT INTO mutasi_stok VALUES (?,?,?,?,?,?,?,?)", (uid(), cab_a, gula, 48, "masuk", bm, kasir, T0))
    db.execute("INSERT INTO hpp_barang VALUES (?,?,?,?,?,?)", (uid(), cab_a, gula, 16200, bm, T0))

harus_ditolak(db, "item barang masuk terkirim tidak bisa diubah",
              "UPDATE barang_masuk_item SET jumlah = 45 WHERE id = ?", (item,))
harus_ditolak(db, "item baru tidak bisa ditambah ke barang masuk terkirim",
              "INSERT INTO barang_masuk_item VALUES (?,?,?,?,?,?,?)", (uid(), bm, uid(), 1, 1, None, T0))
harus_ditolak(db, "header barang masuk terkirim tidak bisa diubah",
              "UPDATE barang_masuk SET no_faktur='X' WHERE id = ?", (bm,))

# koreksi lewat SPV
kor = uid()
db.execute("INSERT INTO koreksi_barang_masuk (id,barang_masuk_item_id,jumlah_baru,alasan,diminta_oleh,created_at) VALUES (?,?,?,?,?,?)",
           (kor, item, 45, "salah ketik", kasir, T0))
with db:
    db.execute("UPDATE koreksi_barang_masuk SET status='disetujui', diputuskan_oleh=?, diputuskan_pada=? WHERE id=?",
               (spv, T0, kor))
    db.execute("INSERT INTO mutasi_stok VALUES (?,?,?,?,?,?,?,?)", (uid(), cab_a, gula, -3, "koreksi", kor, spv, T0))
harus_ditolak(db, "koreksi yang sudah disetujui tidak bisa diubah",
              "UPDATE koreksi_barang_masuk SET jumlah_baru = 1 WHERE id = ?", (kor,))

stok = lambda: db.execute("SELECT stok FROM stok_sekarang WHERE cabang_id=? AND barang_id=?", (cab_a, gula)).fetchone()[0]
cek("stok setelah masuk 48 lalu koreksi -3 = 45", stok() == 45)

# --- penjualan -----------------------------------------------------------
sh = uid()
db.execute("INSERT INTO shift VALUES (?,?,?,?,?)", (sh, cab_a, kasir, 500000, T0))
trx, ti = uid(), uid()
with db:
    db.execute("INSERT INTO transaksi VALUES (?,?,?,?,?,?,?,?)",
               (trx, cab_a, "TRX-A01-261101-0001", sh, kasir, 255000, 15, T0))
    db.execute("INSERT INTO transaksi_item VALUES (?,?,?,?,?,?,?,?,?)",
               (ti, trx, gula, "Gula Pasir 1 kg", 15, 17000, 1, 16200, 255000))
    db.execute("INSERT INTO pembayaran (id, transaksi_id, metode, jumlah_diterima, kembalian, no_referensi, created_at)"
               " VALUES (?,?,?,?,?,?,?)", (uid(), trx, "tunai", 300000, 45000, None, T0))
    db.execute("INSERT INTO mutasi_stok VALUES (?,?,?,?,?,?,?,?)", (uid(), cab_a, gula, -15, "jual", trx, kasir, T0))
cek("stok setelah jual 15 = 30", stok() == 30)

harus_ditolak(db, "subtotal yang tidak sama dengan qty x harga ditolak",
              "INSERT INTO transaksi_item VALUES (?,?,?,?,?,?,?,?,?)",
              (uid(), trx, gula, "Gula", 2, 17500, 0, 16200, 30000))
harus_ditolak(db, "nomor transaksi dobel di cabang yang sama ditolak",
              "INSERT INTO transaksi VALUES (?,?,?,?,?,?,?,?)",
              (uid(), cab_a, "TRX-A01-261101-0001", sh, kasir, 1, 1, T0))
harus_ditolak(db, "pembayaran kartu tanpa nomor referensi ditolak",
              "INSERT INTO pembayaran (id, transaksi_id, metode, jumlah_diterima, kembalian, no_referensi, created_at)"
              " VALUES (?,?,?,?,?,?,?)", (uid(), uid(), "kartu", 1, 0, None, T0))
harus_ditolak(db, "transaksi tidak bisa diubah", "UPDATE transaksi SET total = 0 WHERE id = ?", (trx,))
harus_ditolak(db, "transaksi tidak bisa dihapus", "DELETE FROM transaksi WHERE id = ?", (trx,))
harus_ditolak(db, "mutasi stok tidak bisa dihapus", "DELETE FROM mutasi_stok")

# pembatalan = baris baru + stok kembali
with db:
    db.execute("INSERT INTO pembatalan VALUES (?,?,?,?,?)", (trx, "salah input", kasir, spv, T0))
    db.execute("INSERT INTO mutasi_stok VALUES (?,?,?,?,?,?,?,?)", (uid(), cab_a, gula, 15, "batal_jual", trx, spv, T0))
cek("stok kembali 45 setelah pembatalan", stok() == 45)
cek("transaksi asli tetap ada", db.execute("SELECT COUNT(*) FROM transaksi").fetchone()[0] == 1)

# --- shift & log ---------------------------------------------------------
harus_ditolak(db, "selisih kas harus = dihitung - sistem",
              "INSERT INTO shift_tutup VALUES (?,?,?,?,?,?)", (sh, 495000, 500000, 0, kasir, T0))
db.execute("INSERT INTO log_aktivitas VALUES (?,?,?,?,?,?,?)", (uid(), cab_a, kasir, spv, "batal_transaksi", "{}", T0))
harus_ditolak(db, "log tidak bisa dihapus", "DELETE FROM log_aktivitas")

# --- kas keluar/masuk & hitung buta (migrasi 002) -----------------------
kk = uid()
db.execute("INSERT INTO kas_shift VALUES (?,?,?,?,?,?,?,?,?)", (kk, cab_a, sh, "keluar", 20000, "Beli galon", kasir, None, T0))
harus_ditolak(db, "kas keluar jumlah 0 ditolak",
              "INSERT INTO kas_shift VALUES (?,?,?,?,?,?,?,?,?)", (uid(), cab_a, sh, "keluar", 0, "x", kasir, None, T0))
harus_ditolak(db, "kas keluar tanpa keterangan ditolak",
              "INSERT INTO kas_shift VALUES (?,?,?,?,?,?,?,?,?)", (uid(), cab_a, sh, "keluar", 5000, "", kasir, None, T0))
harus_ditolak(db, "jenis kas selain keluar/masuk ditolak",
              "INSERT INTO kas_shift VALUES (?,?,?,?,?,?,?,?,?)", (uid(), cab_a, sh, "pinjam", 5000, "x", kasir, None, T0))
harus_ditolak(db, "kas_shift tidak bisa diubah", "UPDATE kas_shift SET jumlah = 1 WHERE id = ?", (kk,))
harus_ditolak(db, "kas_shift tidak bisa dihapus", "DELETE FROM kas_shift")
db.execute("INSERT INTO shift_hitung VALUES (?,?,?,?,?,?,?,?,?,?)", (uid(), cab_a, sh, 1, 480000, 500000, -20000, kasir, None, T0))
db.execute("INSERT INTO shift_hitung VALUES (?,?,?,?,?,?,?,?,?,?)", (uid(), cab_a, sh, 2, 500000, 500000, 0, kasir, None, T0))
harus_ditolak(db, "hitungan ke-2 dobel ditolak",
              "INSERT INTO shift_hitung VALUES (?,?,?,?,?,?,?,?,?,?)", (uid(), cab_a, sh, 2, 1, 500000, -499999, kasir, None, T0))
harus_ditolak(db, "selisih hitungan harus = dihitung - sistem",
              "INSERT INTO shift_hitung VALUES (?,?,?,?,?,?,?,?,?,?)", (uid(), cab_a, sh, 3, 1, 500000, 0, kasir, None, T0))
harus_ditolak(db, "hitungan tidak bisa diubah", "UPDATE shift_hitung SET kas_dihitung = 500000")
db.execute("INSERT INTO shift_tutup VALUES (?,?,?,?,?,?)", (sh, 500000, 500000, 0, kasir, T0))
harus_ditolak(db, "kas keluar setelah shift ditutup ditolak",
              "INSERT INTO kas_shift VALUES (?,?,?,?,?,?,?,?,?)", (uid(), cab_a, sh, "masuk", 5000, "Tambah uang kecil", kasir, None, T0))
harus_ditolak(db, "hitungan setelah shift ditutup ditolak",
              "INSERT INTO shift_hitung VALUES (?,?,?,?,?,?,?,?,?,?)", (uid(), cab_a, sh, 3, 1, 1, 0, kasir, None, T0))

harus_ditolak(db, "transaksi baru di shift yang sudah ditutup ditolak",
              "INSERT INTO transaksi VALUES (?,?,?,?,?,?,?,?)", (uid(), cab_a, "TRX-A01-261101-0999", sh, kasir, 1000, 1, T0))

# Revisi P: tutup shift "Belum dihitung" (migrasi 003)
sh2 = uid()
db.execute("INSERT INTO shift VALUES (?,?,?,?,?)", (sh2, cab_a, kasir, 200000, T0))
db.execute("INSERT INTO shift_belum_dihitung VALUES (?,?,?,?,?,?,?)", (sh2, cab_a, 845000, 200000, "Siti · 08.00–16.05", kasir, T0))
cek("shift ditutup belum dihitung tersimpan", db.execute("SELECT COUNT(*) FROM shift_belum_dihitung").fetchone()[0] == 1)
harus_ditolak(db, "shift belum dihitung tidak bisa dicatat dua kali",
              "INSERT INTO shift_belum_dihitung VALUES (?,?,?,?,?,?,?)", (sh2, cab_a, 1, 0, "x", kasir, T0))
harus_ditolak(db, "modal ditinggal minus ditolak",
              "INSERT INTO shift_belum_dihitung VALUES (?,?,?,?,?,?,?)", (uid(), cab_a, 1, -1, "x", kasir, T0))
harus_ditolak(db, "shift_belum_dihitung tidak bisa diubah", "UPDATE shift_belum_dihitung SET kas_sistem = 1")
harus_ditolak(db, "shift_belum_dihitung tidak bisa dihapus", "DELETE FROM shift_belum_dihitung")
harus_ditolak(db, "kas keluar di shift menunggu dihitung ditolak",
              "INSERT INTO kas_shift VALUES (?,?,?,?,?,?,?,?,?)", (uid(), cab_a, sh2, "keluar", 5000, "Beli galon", kasir, None, T0))
harus_ditolak(db, "transaksi di shift menunggu dihitung ditolak",
              "INSERT INTO transaksi VALUES (?,?,?,?,?,?,?,?)", (uid(), cab_a, "TRX-A01-261101-0998", sh2, kasir, 1000, 1, T0))
# SPV menghitung amplop belakangan: hitungan + shift_tutup tetap boleh.
db.execute("INSERT INTO shift_hitung VALUES (?,?,?,?,?,?,?,?,?,?)", (uid(), cab_a, sh2, 1, 830000, 845000, -15000, kasir, None, T0))
db.execute("INSERT INTO shift_tutup VALUES (?,?,?,?,?,?)", (sh2, 830000, 845000, -15000, kasir, T0))
cek("amplop dihitung belakangan → shift_tutup", db.execute("SELECT selisih FROM shift_tutup WHERE shift_id = ?", (sh2,)).fetchone()[0] == -15000)
harus_ditolak(db, "shift yang sudah ditutup tidak bisa ditutup belum dihitung",
              "INSERT INTO shift_belum_dihitung VALUES (?,?,?,?,?,?,?)", (sh, cab_a, 1, 0, "x", kasir, T0))

# Revisi F: tukar / kembalikan barang oleh kasir (migrasi 004)
sh3 = uid()
db.execute("INSERT INTO shift VALUES (?,?,?,?,?)", (sh3, cab_a, kasir, 100000, T0))
RETUR = ("INSERT INTO retur (id, transaksi_id, alasan, total_kembali, diproses_oleh, created_at, cabang_id, no_retur,"
         " shift_id, disetujui_oleh, transaksi_tukar_id, dipotong) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)")
def jual_baru(no, qty):
    t, i = uid(), uid()
    with db:
        db.execute("INSERT INTO transaksi VALUES (?,?,?,?,?,?,?,?)", (t, cab_a, no, sh3, kasir, qty * 17500, qty, T0))
        db.execute("INSERT INTO transaksi_item VALUES (?,?,?,?,?,?,?,?,?)", (i, t, gula, "Gula Pasir 1 kg", qty, 17500, 0, 16200, qty * 17500))
    return t, i
t1, i1 = jual_baru("TRX-A01-261101-0101", 2)
r1 = uid()
db.execute(RETUR, (r1, t1, "kemasan sobek", 17500, kasir, T0, cab_a, "RTR-A01-261101-0001", sh3, None, None, 0))
db.execute("INSERT INTO retur_item VALUES (?,?,?,?,?)", (uid(), r1, i1, 1, 0))
cek("kasir mencatat retur dengan nomor RTR", db.execute("SELECT no_retur FROM retur WHERE id = ?", (r1,)).fetchone()[0] == "RTR-A01-261101-0001")
harus_ditolak(db, "jumlah retur melebihi yang dibeli ditolak",
              "INSERT INTO retur_item VALUES (?,?,?,?,?)", (uid(), r1, i1, 2, 1))
harus_ditolak(db, "nomor retur dobel di cabang yang sama ditolak", RETUR,
              (uid(), t1, "x", 0, kasir, T0, cab_a, "RTR-A01-261101-0001", sh3, None, None, 0))
harus_ditolak(db, "potongan tanpa transaksi tukar ditolak", RETUR,
              (uid(), t1, "x", 17500, kasir, T0, cab_a, "RTR-A01-261101-0002", sh3, None, None, 1000))
harus_ditolak(db, "retur transaksi yang dibatalkan ditolak", RETUR,
              (uid(), trx, "x", 0, kasir, T0, cab_a, "RTR-A01-261101-0003", sh3, None, None, 0))
t2, _ = jual_baru("TRX-A01-261101-0102", 1)
harus_ditolak(db, "potongan lebih besar dari nilai retur ditolak", RETUR,
              (uid(), t1, "x", 1000, kasir, T0, cab_a, "RTR-A01-261101-0004", sh3, None, t2, 2000))
db.execute(RETUR, (uid(), t1, "tukar", 17500, kasir, T0, cab_a, "RTR-A01-261101-0005", sh3, None, t2, 17500))
db.execute("INSERT INTO pembayaran (id, transaksi_id, metode, jumlah_diterima, kembalian, no_referensi, potongan_retur, created_at)"
           " VALUES (?,?,?,?,?,?,?,?)", (uid(), t2, "tunai", 0, 0, None, 17500, T0))
cek("pembayaran mencatat potongan tukar", db.execute("SELECT potongan_retur FROM pembayaran WHERE transaksi_id = ?", (t2,)).fetchone()[0] == 17500)
harus_ditolak(db, "transaksi hasil tukar tidak bisa dibatalkan",
              "INSERT INTO pembatalan VALUES (?,?,?,?,?)", (t2, "x", kasir, spv, T0))
harus_ditolak(db, "satu transaksi tukar hanya untuk satu retur", RETUR,
              (uid(), t1, "x", 0, kasir, T0, cab_a, "RTR-A01-261101-0006", sh3, None, t2, 0))

print(f"\nSemua {lulus} pengujian lulus.")
