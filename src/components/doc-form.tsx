"use client";

import Link from "next/link";
import { useActionState, useMemo, useState } from "react";
import type { Child, Field } from "@/lib/docs/types";
import type { RefOption } from "@/lib/master/refs";
import { lineTotal, parseQty } from "@/lib/docs/parse";
import { parseMoney } from "@/lib/pricing/schema";
import { fmtQty, fmtRupiah } from "@/lib/docs/format";
import { refKey } from "@/lib/docs/ref-key";
import { saveDoc, type DocFormState } from "@/app/(app)/d/actions";

const inputCls = "w-full rounded-md border-2 border-line bg-white px-3 py-2.5 text-lg";
type Row = Record<string, string>;
export type FormValues = { header: Row; children: Record<string, Row[]> };

function Control({ f, value, onChange, refs, id }: {
  f: Field; value: string; onChange: (v: string) => void; refs: Record<string, RefOption[]>; id: string;
}) {
  const common = { id, value, onChange: (e: React.ChangeEvent<HTMLInputElement | HTMLSelectElement | HTMLTextAreaElement>) => onChange(e.target.value), className: inputCls };
  if (f.kind === "textarea") return <textarea {...common} rows={2} />;
  if (f.kind === "date") return <input {...common} type="date" />;
  if (f.kind === "select")
    return (
      <select {...common}>
        <option value="">Pilih...</option>
        {f.options!.map((o) => <option key={o.value} value={o.value}>{o.label}</option>)}
      </select>
    );
  if (f.kind === "ref") {
    const opts = refs[refKey(f)] ?? [];
    return (
      <select {...common}>
        <option value="">{f.required ? "Pilih..." : "Tidak dipilih"}</option>
        {opts.filter((o) => o.active || o.value === value).map((o) => (
          <option key={o.value} value={o.value}>{o.label}{o.active ? "" : " (nonaktif)"}</option>
        ))}
      </select>
    );
  }
  if (f.kind === "qty" || f.kind === "money") return <input {...common} type="text" inputMode="decimal" autoComplete="off" />;
  return <input {...common} type="text" autoComplete="off" />;
}

export function DocForm({ slug, id, header, lines, refs, initial, cancelHref }: {
  slug: string; id: string; header: Field[]; lines: Child[];
  refs: Record<string, RefOption[]>; initial: FormValues; cancelHref: string;
}) {
  const [state, action, pending] = useActionState<DocFormState, FormData>(saveDoc.bind(null, slug, id), {});
  const restored = useMemo<FormValues | null>(() => {
    if (!state.payload) return null;
    try { const p = JSON.parse(state.payload); return { header: p.header ?? {}, children: p.children ?? {} }; } catch { return null; }
  }, [state.payload]);
  const [h, setH] = useState<Row>(restored?.header ?? initial.header);
  const [rows, setRows] = useState<Record<string, Row[]>>(restored?.children ?? initial.children);

  const blank = (c: Child): Row => Object.fromEntries(c.fields.map((f) => [f.name, f.blankAs0 ? "" : ""]));
  const setCell = (key: string, i: number, name: string, v: string) =>
    setRows((r) => ({ ...r, [key]: r[key].map((row, j) => (j === i ? { ...row, [name]: v } : row)) }));

  return (
    <form action={action} className="max-w-5xl space-y-8" noValidate>
      <input type="hidden" name="payload" value={JSON.stringify({ header: h, children: rows })} />

      <div className="grid gap-5 md:grid-cols-2">
        {header.map((f) => (
          <div key={f.name} className={f.kind === "textarea" ? "md:col-span-2" : ""}>
            <label htmlFor={`h-${f.name}`} className="mb-1 block text-lg font-semibold">
              {f.label}{f.required && <span className="text-danger"> *</span>}
            </label>
            <Control f={f} id={`h-${f.name}`} value={h[f.name] ?? ""} onChange={(v) => setH((x) => ({ ...x, [f.name]: v }))} refs={refs} />
            {f.help && <p className="mt-1 text-sm text-muted">{f.help}</p>}
          </div>
        ))}
      </div>

      {lines.map((c) => {
        const list = rows[c.key] ?? [];
        const total = c.total ? list.reduce((s, r) => s + lineTotal(r[c.total!.qty] ?? "", r[c.total!.price] ?? ""), 0) : 0;
        const sum = c.sum
          ? list.reduce((s, r) => {
              const raw = r[c.sum!.field] ?? "";
              const n = c.fields.find((f) => f.name === c.sum!.field)?.kind === "money" ? parseMoney(raw) : parseQty(raw);
              return s + (typeof n === "number" ? n : 0);
            }, 0)
          : 0;
        return (
          <section key={c.key} aria-labelledby={`t-${c.key}`}>
            <h2 id={`t-${c.key}`} className="text-2xl font-bold">{c.title}</h2>
            {c.hint && <p className="mt-1 text-muted">{c.hint}</p>}
            <div className="mt-3 space-y-3">
              {list.map((row, i) => (
                <div key={i} className="rounded-lg border border-line bg-surface p-4">
                  <div className="grid gap-3 md:grid-cols-4">
                    {c.fields.map((f) => (
                      <div key={f.name}>
                        <label htmlFor={`${c.key}-${i}-${f.name}`} className="mb-1 block font-semibold">{f.label}</label>
                        <Control f={f} id={`${c.key}-${i}-${f.name}`} value={row[f.name] ?? ""} onChange={(v) => setCell(c.key, i, f.name, v)} refs={refs} />
                      </div>
                    ))}
                  </div>
                  <button type="button" onClick={() => setRows((r) => ({ ...r, [c.key]: r[c.key].filter((_, j) => j !== i) }))}
                    className="mt-3 rounded-md border-2 border-line px-4 py-2 font-semibold hover:bg-background">
                    Hapus baris {i + 1}
                  </button>
                </div>
              ))}
            </div>
            <div className="mt-3 flex flex-wrap items-center gap-4">
              <button type="button" onClick={() => setRows((r) => ({ ...r, [c.key]: [...(r[c.key] ?? []), blank(c)] }))}
                className="rounded-md border-2 border-brand px-5 py-2.5 text-lg font-semibold text-brand hover:bg-background">
                + Tambah baris
              </button>
              {c.total && <p className="text-lg font-semibold">{c.total.label}: {fmtRupiah(total)}</p>}
              {c.sum && <p className="text-lg font-semibold">{c.sum.label}: {c.fields.find((f) => f.name === c.sum!.field)?.kind === "money" ? fmtRupiah(sum) : `${fmtQty(sum)} kg`}</p>}
            </div>
          </section>
        );
      })}

      {state.error && <p role="alert" className="rounded-md bg-danger-bg px-4 py-3 text-lg text-danger">{state.error}</p>}

      <div className="flex gap-3">
        <button type="submit" disabled={pending} className="rounded-md bg-brand px-8 py-3 text-lg font-semibold text-white hover:bg-brand-dark disabled:opacity-60">
          {pending ? "Menyimpan..." : "Simpan"}
        </button>
        <Link href={cancelHref} className="rounded-md border-2 border-line px-8 py-3 text-lg font-semibold hover:bg-background">Batal</Link>
      </div>
    </form>
  );
}
