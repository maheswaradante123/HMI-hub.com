// Pesanan yang digabung dalam satu proforma/invoice. Murni data, aman dipakai di server dan uji.
type G = { id: string; group_id: string | null; status: string };

/** Satu baris per kelompok (atau per pesanan tunggal). Anggota yang dibatalkan disembunyikan kecuali semuanya batal. */
export function collapseGroups<T extends G>(rows: T[]): { head: T; members: T[] }[] {
  const order: string[] = [];
  const map = new Map<string, T[]>();
  for (const r of rows) {
    const k = r.group_id ?? r.id;
    if (!map.has(k)) { map.set(k, []); order.push(k); }
    map.get(k)!.push(r);
  }
  return order.map((k) => {
    const all = map.get(k)!;
    const active = all.filter((o) => o.status !== "CANCELLED");
    const members = active.length ? active : all;
    return { head: members[0], members };
  });
}

/** Jumlah sapi aktif per kelompok. */
export function groupSizes<T extends G>(rows: T[]): Map<string, number> {
  const m = new Map<string, number>();
  for (const r of rows) if (r.group_id && r.status !== "CANCELLED") m.set(r.group_id, (m.get(r.group_id) ?? 0) + 1);
  return m;
}
