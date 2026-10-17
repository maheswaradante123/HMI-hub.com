import { DOC_STATUS_LABEL, DOC_STATUS_STYLE } from "@/lib/docs/status";

export function DocStatusBadge({ status }: { status: string }) {
  return (
    <span className={`inline-block rounded px-2.5 py-1 text-base font-semibold ${DOC_STATUS_STYLE[status] ?? "bg-neutral-200"}`}>
      {DOC_STATUS_LABEL[status] ?? status}
    </span>
  );
}
