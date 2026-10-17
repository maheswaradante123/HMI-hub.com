"use client";

import Link from "next/link";
import { useActionState } from "react";
import type { Resource } from "@/lib/master/config";
import type { RefMap } from "@/lib/master/refs";
import { saveRecord, type FormState } from "@/app/(app)/data/actions";

const inputCls = "w-full rounded-md border-2 border-line bg-white px-4 py-3 text-lg";

export function RecordForm({
  resource,
  refs,
  id,
  initial,
}: {
  resource: Resource;
  refs: RefMap;
  id: string | null;
  initial: Record<string, string>;
}) {
  const [state, action, pending] = useActionState<FormState, FormData>(
    saveRecord.bind(null, resource.key, id),
    {},
  );
  const values = state.values ?? initial;

  return (
    <form action={action} className="max-w-2xl space-y-5" noValidate>
      {resource.fields.map((f) => {
        const value = values[f.name] ?? "";
        const common = { id: f.name, name: f.name, defaultValue: value, className: inputCls };
        return (
          <div key={f.name}>
            <label htmlFor={f.name} className="mb-1 block text-lg font-semibold">
              {f.label}
              {f.required && <span className="text-danger"> *</span>}
            </label>
            {f.type === "textarea" ? (
              <textarea {...common} rows={3} />
            ) : f.type === "select" ? (
              <select {...common}>
                <option value="">Pilih...</option>
                {f.options!.map((o) => (
                  <option key={o.value} value={o.value}>
                    {o.label}
                  </option>
                ))}
              </select>
            ) : f.type === "ref" ? (
              <select {...common}>
                <option value="">{f.required ? "Pilih..." : "Tidak dipilih"}</option>
                {(refs[f.ref!] ?? [])
                  .filter((o) => o.active || o.value === value)
                  .map((o) => (
                    <option key={o.value} value={o.value}>
                      {o.label}
                      {o.active ? "" : " (nonaktif)"}
                    </option>
                  ))}
              </select>
            ) : f.type === "number" ? (
              <input {...common} type="text" inputMode="decimal" />
            ) : (
              <input {...common} type="text" autoComplete="off" />
            )}
            {f.help && <p className="mt-1 text-sm text-muted">{f.help}</p>}
          </div>
        );
      })}

      {state.error && (
        <p role="alert" className="rounded-md bg-danger-bg px-4 py-3 text-danger">
          {state.error}
        </p>
      )}

      <div className="flex gap-3">
        <button
          type="submit"
          disabled={pending}
          className="rounded-md bg-brand px-6 py-3 text-lg font-semibold text-white hover:bg-brand-dark disabled:opacity-60"
        >
          {pending ? "Menyimpan..." : "Simpan"}
        </button>
        <Link
          href={`/data/${resource.key}`}
          className="rounded-md border-2 border-line px-6 py-3 text-lg font-semibold hover:bg-background"
        >
          Batal
        </Link>
      </div>
    </form>
  );
}
