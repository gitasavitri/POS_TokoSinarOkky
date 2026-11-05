"""Uji skema_toko.sql dengan data contoh.

Jalankan:  python database/test_schema.py
Tidak butuh library tambahan (hanya sqlite3 bawaan Python).
"""
import sqlite3
import uuid
from pathlib import Path

SCHEMA = Path(__file__).with_name("schema_toko.sql").read_text(encoding="utf-8")
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
    db.execute("INSERT INTO pembayaran VALUES (?,?,?,?,?,?,?)", (uid(), trx, "tunai", 300000, 45000, None, T0))
    db.execute("INSERT INTO mutasi_stok VALUES (?,?,?,?,?,?,?,?)", (uid(), cab_a, gula, -15, "jual", trx, kasir, T0))
cek("stok setelah jual 15 = 30", stok() == 30)

harus_ditolak(db, "subtotal yang tidak sama dengan qty x harga ditolak",
              "INSERT INTO transaksi_item VALUES (?,?,?,?,?,?,?,?,?)",
              (uid(), trx, gula, "Gula", 2, 17500, 0, 16200, 30000))
harus_ditolak(db, "nomor transaksi dobel di cabang yang sama ditolak",
              "INSERT INTO transaksi VALUES (?,?,?,?,?,?,?,?)",
              (uid(), cab_a, "TRX-A01-261101-0001", sh, kasir, 1, 1, T0))
harus_ditolak(db, "pembayaran kartu tanpa nomor referensi ditolak",
              "INSERT INTO pembayaran VALUES (?,?,?,?,?,?,?)", (uid(), uid(), "kartu", 1, 0, None, T0))
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

print(f"\nSemua {lulus} pengujian lulus.")
