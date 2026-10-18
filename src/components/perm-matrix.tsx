"use client";

import Link from "next/link";
import { useState, useTransition } from "react";
import { setRolePermission } from "@/app/(app)/role/actions";
import { ACTION_LABEL, ACTIONS } from "@/lib/modules";

export type MatrixRole = { id: string; name: string; superuser: boolean };
export type MatrixGroup = { title: string; rows: { module: string; label: string; perms: Record<string, string> }[] };

const LETTER: Record<(typeof ACTIONS)[number], string> = { view: "V", create: "C", edit: "E", delete: "D", approve: "A", export: "X" };
// Warna tiap huruf; semuanya memakai pasangan latar terang + teks gelap supaya terbaca.
const TONE: Record<(typeof ACTIONS)[number], string> = {
  view: "bg-blue-100 text-blue-900", create: "bg-green-100 text-green-900", edit: "bg-amber-100 text-amber-900",
  delete: "bg-danger-bg text-danger", approve: "bg-purple-100 text-purple-900", export: "bg-teal-100 text-teal-900",
};
const slot = "inline-flex h-7 w-7 items-center justify-center rounded text-sm font-bold";

function Chip({ a, on, className = "" }: { a: (typeof ACTIONS)[number]; on: boolean; className?: string }) {
  return <span className={`${slot} ${on ? TONE[a] : "border border-line text-muted/50"} ${className}`}>{LETTER[a]}</span>;
}

export function PermMatrix({ roles, groups, granted, canEdit }: { roles: MatrixRole[]; groups: MatrixGroup[]; granted: string[]; canEdit: boolean }) {
  const [on, setOn] = useState<Set<string>>(new Set(granted));
  const [error, setError] = useState("");
  const [, start] = useTransition();
  const key = (r: string, p: string) => `${r}:${p}`;

  const toggle = (role: MatrixRole, perm: string) => {
    const k = key(role.id, perm);
    const next = !on.has(k);
    setError("");
    setOn((s) => { const n = new Set(s); if (next) n.add(k); else n.delete(k); return n; });
    start(async () => {
      const res = await setRolePermission(role.id, perm, next);
      if (res.error) {
        setError(res.error);
        setOn((s) => { const n = new Set(s); if (next) n.delete(k); else n.add(k); return n; }); // kembalikan
      }
    });
  };

  return (
    <div>
      <ul className="flex flex-wrap gap-x-6 gap-y-2" aria-label="Arti huruf">
        {ACTIONS.map((a) => <li key={a} className="flex items-center gap-2"><Chip a={a} on />{ACTION_LABEL[a]}</li>)}
      </ul>
      {canEdit
        ? <p className="mt-4 rounded-md bg-background px-4 py-3">Klik huruf untuk menyalakan atau mematikan hak. Kolom Owner terkunci. Perubahan langsung tersimpan dan berlaku pada halaman berikutnya yang dibuka user.</p>
        : <p className="mt-4 rounded-md bg-background px-4 py-3">Anda hanya bisa melihat daftar ini.</p>}
      {error && <p role="alert" className="mt-3 rounded-md bg-danger-bg px-4 py-3 text-danger">{error}</p>}
      <div className="mt-4 overflow-x-auto rounded-lg border border-line bg-surface">
        <table className="w-full min-w-[900px] text-left">
          <thead className="border-b border-line bg-background">
            <tr>
              <th scope="col" className="px-4 py-3">Modul</th>
              {roles.map((r) => (
                <th key={r.id} scope="col" className="px-2 py-3 text-center">
                  <Link href={`/role/${r.id}`} className="underline" title="Atur semua izin role ini sekaligus">{r.name}</Link>
                  {r.superuser && <span className="block text-sm font-normal text-muted">penuh</span>}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {groups.map((g) => (
              <MatrixBlock key={g.title} g={g} roles={roles} on={on} canEdit={canEdit} toggle={toggle} />
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

function MatrixBlock({ g, roles, on, canEdit, toggle }: { g: MatrixGroup; roles: MatrixRole[]; on: Set<string>; canEdit: boolean; toggle: (r: MatrixRole, p: string) => void }) {
  return (
    <>
      <tr className="border-b border-line bg-background"><th scope="colgroup" colSpan={roles.length + 1} className="px-4 py-2 text-sm font-bold uppercase tracking-widest text-muted">{g.title}</th></tr>
      {g.rows.map((m) => (
        <tr key={m.module} className="border-b border-line last:border-0">
          <th scope="row" className="px-4 py-2 font-semibold">{m.label}</th>
          {roles.map((r) => {
            const has = (a: (typeof ACTIONS)[number]) => !!m.perms[a] && (r.superuser || on.has(`${r.id}:${m.perms[a]}`));
            const any = ACTIONS.some((a) => has(a));
            return (
              <td key={r.id} className="px-2 py-2 text-center">
                <span className="inline-flex gap-1">
                  {ACTIONS.map((a) => {
                    const pid = m.perms[a];
                    if (!pid) return canEdit && !r.superuser ? <span key={a} className={slot} aria-hidden /> : null;
                    if (canEdit && !r.superuser) {
                      const pressed = has(a);
                      return (
                        <button key={a} type="button" aria-pressed={pressed} aria-label={`${r.name}: ${m.label}: ${ACTION_LABEL[a]}`} onClick={() => toggle(r, pid)}
                          className={`${slot} cursor-pointer ${pressed ? TONE[a] : "border border-line text-muted/50 hover:bg-background"}`}>{LETTER[a]}</button>
                      );
                    }
                    return has(a) ? <Chip key={a} a={a} on /> : null;
                  })}
                  {!(canEdit && !r.superuser) && !any && <span className="text-muted" aria-label="tanpa izin">—</span>}
                </span>
              </td>
            );
          })}
        </tr>
      ))}
    </>
  );
}
