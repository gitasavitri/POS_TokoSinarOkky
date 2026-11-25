// Aturan harga grosir — sama persis dengan periksaTingkatGrosir di packages/pos_core/lib/src/harga.dart.

/**
 * @param {{eceran:number, hpp:number|null, tingkat:{min_qty:number, harga:number}[]}} p
 * @returns {Record<number,string>} indeks tingkat → pesan salah (kosong = semua benar)
 */
export function periksaTingkatGrosir({ eceran, hpp, tingkat }) {
  const salah = {};
  tingkat.forEach((t, i) => {
    if (!Number.isSafeInteger(t.min_qty) || t.min_qty < 2) salah[i] = 'Jumlah minimal harus 2 atau lebih.';
    else if (i > 0 && t.min_qty <= tingkat[i - 1].min_qty) salah[i] = 'Jumlah minimal harus lebih besar dari tingkat sebelumnya.';
    else if (!Number.isSafeInteger(t.harga) || t.harga <= 0) salah[i] = 'Harga grosir harus diisi.';
    else if (t.harga >= eceran) salah[i] = 'Harga grosir harus lebih murah dari harga eceran.';
    else if (hpp != null && t.harga <= hpp) salah[i] = 'Rugi: harga grosir sama dengan atau di bawah HPP.';
    else if (i > 0 && t.harga > tingkat[i - 1].harga) salah[i] = 'Harga tingkat ini lebih mahal dari tingkat sebelumnya.';
  });
  return salah;
}

/** Harga satuan untuk sejumlah barang: tingkat dengan min_qty terbesar yang ≤ qty berlaku untuk seluruh qty. */
export function hargaUntukQty(eceran, tingkat, qty) {
  let harga = eceran;
  let grosir = false;
  for (const t of [...tingkat].sort((a, b) => a.min_qty - b.min_qty)) {
    if (qty >= t.min_qty) {
      harga = t.harga;
      grosir = true;
    }
  }
  return { harga, grosir, subtotal: harga * qty };
}
