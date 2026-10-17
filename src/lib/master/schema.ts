import { z } from "zod";
import type { Field, Resource } from "./config";

// Membuat validasi dari definisi field. Dipakai di server; tidak bergantung pada
// framework supaya mudah diuji.
export function buildSchema(resource: Resource, mode: "create" | "edit") {
  const shape: Record<string, z.ZodType> = {};

  for (const f of resource.fields) {
    if (mode === "edit" && f.fixedOnEdit) continue;
    shape[f.name] = fieldSchema(f);
  }
  return z.object(shape);
}

function fieldSchema(f: Field): z.ZodType {
  const requiredMsg = `${f.label} wajib diisi.`;

  if (f.type === "number") {
    return z.preprocess(
      (v) => (v === "" || v == null ? undefined : String(v).replace(",", ".")),
      (f.required
        ? z.string({ error: requiredMsg })
        : z.string().optional()
      ).transform((s, ctx) => {
        if (s === undefined) return f.integer ? 0 : 0;
        const n = Number(s);
        if (!Number.isFinite(n)) {
          ctx.addIssue({ code: "custom", message: `${f.label} harus berupa angka.` });
          return z.NEVER;
        }
        if (n < 0) {
          ctx.addIssue({ code: "custom", message: `${f.label} tidak boleh kurang dari 0.` });
          return z.NEVER;
        }
        if (f.integer && !Number.isInteger(n)) {
          ctx.addIssue({ code: "custom", message: `${f.label} harus berupa bilangan bulat.` });
          return z.NEVER;
        }
        return n;
      }),
    );
  }

  if (f.type === "select") {
    const allowed = (f.options ?? []).map((o) => o.value);
    return z
      .string({ error: requiredMsg })
      .min(1, requiredMsg)
      .refine((v) => allowed.includes(v), `${f.label} belum dipilih dengan benar.`);
  }

  if (f.type === "ref") {
    const base = z.string().uuid(`${f.label} belum dipilih dengan benar.`);
    return f.required
      ? z.string({ error: requiredMsg }).min(1, requiredMsg).pipe(base)
      : z.preprocess((v) => (v === "" || v == null ? null : v), base.nullable());
  }

  // text, textarea
  let s = z.string({ error: requiredMsg }).trim();
  if (f.required) s = s.min(1, requiredMsg); // dicek lebih dulu agar pesan "wajib diisi" muncul
  if (f.upper) {
    s = s
      .toUpperCase()
      .regex(/^[A-Z0-9][A-Z0-9._-]*$/, `${f.label} hanya boleh huruf, angka, titik, strip, dan garis bawah tanpa spasi.`);
  }
  if (f.required) return s.max(200, `${f.label} terlalu panjang.`);
  return z.preprocess(
    (v) => (typeof v === "string" && v.trim() === "" ? null : v ?? null),
    z.string().trim().max(1000, `${f.label} terlalu panjang.`).nullable(),
  );
}
