import { nilaiJB, nilaiPL } from "@/lib/export/sp-docx.mjs";
import tpl from "@/lib/qurban/sp-template.json";

type Block = { t?: string; b?: boolean; c?: boolean; pb?: boolean; ind?: number; tbl?: string[][] };
type Vals = Record<string, string | number>;

// Pratinjau isi surat. Bagian berlatar kuning terisi otomatis; file Word hasil unduhan tanpa warna kuning.
function Letter({ title, blocks, vals }: { title: string; blocks: Block[]; vals: Vals }) {
  const fill = (s: string) =>
    s.split(/(«[\d#]+»)/).map((part, i) => {
      const m = part.match(/^«(\d+)»$/);
      if (!m) return part;
      const v = vals[`${m[1]}#0`] ?? vals[m[1]] ?? "";
      return <mark key={i} className="bg-yellow-200 px-0.5 text-black">{String(v)}</mark>;
    });
  return (
    <section>
      <h2 className="mb-2 text-xl font-bold">{title}</h2>
      <div className="max-h-[62vh] overflow-auto rounded-lg bg-neutral-200 p-3">
        <div className="mx-auto max-w-[720px] bg-white px-12 py-10 text-[0.72rem] leading-normal text-black shadow" style={{ fontFamily: "Arial, Helvetica, sans-serif" }}>
          {blocks.map((b, i) => {
            if (b.tbl) {
              return (
                <table key={i} className="my-2 w-full border-collapse">
                  <tbody>
                    {b.tbl.map((r, ri) => (
                      <tr key={ri}>{r.map((c, ci) => {
                        const Cell = ri === 0 ? "th" : "td";
                        return <Cell key={ci} className={`border border-black px-1.5 py-0.5 text-center ${ri === 0 ? "bg-neutral-300" : ""}`}>{fill(c)}</Cell>;
                      })}</tr>
                    ))}
                  </tbody>
                </table>
              );
            }
            const t = b.t ?? "";
            const bold = b.b || (t === t.toUpperCase() && t.trim().length > 3);
            return (
              <div key={i}>
                {b.pb && <hr className="my-4 border-t border-dashed border-neutral-400" />}
                <p className="mb-1.5" style={{ textAlign: b.c ? "center" : "justify", fontWeight: bold ? 700 : 400, marginLeft: b.ind ? Math.min(b.ind / 20, 60) : 0 }}>{fill(t).map((x) => typeof x === "string" ? x.replace(/\t/g, "    ") : x)}</p>
              </div>
            );
          })}
        </div>
      </div>
    </section>
  );
}

export function SpPaper({ jb, pl }: { jb: unknown; pl: unknown }) {
  return (
    <div className="space-y-8">
      <Letter title="Pratinjau SP-JB (Jual Beli)" blocks={tpl.jb as Block[]} vals={nilaiJB(jb) as Vals} />
      <Letter title="Pratinjau SP-PL (Pemeliharaan)" blocks={tpl.pl as Block[]} vals={nilaiPL(pl) as Vals} />
    </div>
  );
}
