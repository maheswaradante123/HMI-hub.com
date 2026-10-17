export type Rule = { doc_type: string; from_status: string; to_status: string; module: string; action: string; needs_note: boolean; label: string };

// Gaya tombol per tujuan status.
export const RULE_STYLE = (to: string) =>
  ["CANCELLED", "VOID", "REJECTED"].includes(to) ? "border-2 border-danger text-danger hover:bg-danger-bg" : "bg-brand text-white hover:bg-brand-dark";
