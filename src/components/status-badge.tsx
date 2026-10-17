import { STATUS_LABEL, STATUS_STYLE, type PrStatus } from "@/lib/pr/constants";

export function StatusBadge({ status }: { status: string }) {
  const s = status as PrStatus;
  return (
    <span className={`inline-block rounded px-2.5 py-1 text-base font-semibold ${STATUS_STYLE[s] ?? "bg-neutral-200"}`}>
      {STATUS_LABEL[s] ?? status}
    </span>
  );
}
