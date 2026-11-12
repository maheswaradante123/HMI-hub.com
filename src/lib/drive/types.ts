// Dipakai server dan browser: tanpa import dari modul server.
// Jenis berkas bukti realisasi CPJ; menjadi awalan nama file di Drive ("Invoice - scan.pdf").
export const CPJ_REQUIRED = ["PO", "Surat Jalan", "Invoice", "Bukti Penerimaan", "Bukti Transfer"] as const;
export const DOC_TYPES = [...CPJ_REQUIRED, "Lainnya"] as const;
export type DocType = (typeof DOC_TYPES)[number];
export const isDocType = (v: unknown): v is DocType => typeof v === "string" && (DOC_TYPES as readonly string[]).includes(v);
export const typedName = (t: DocType, name: string) => `${t} - ${name}`.slice(0, 200);
export type FolderFile = { id: string; name: string; link: string; docType: string; parent: string };
