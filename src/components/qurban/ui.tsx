import Link from "next/link";
import { STATUS_LABEL, STATUS_STYLE } from "@/lib/qurban/format";

export function Pill({ status }: { status: string }) {
  return (
    <span className={`inline-block whitespace-nowrap rounded-full px-3 py-0.5 text-sm font-semibold ${STATUS_STYLE[status] ?? "bg-neutral-200 text-neutral-900"}`}>
      {STATUS_LABEL[status] ?? status}
    </span>
  );
}

export function Head({ title, hint, action }: { title: string; hint?: string; action?: { href: string; label: string } }) {
  return (
    <>
      <div className="flex flex-wrap items-center justify-between gap-4">
        <h1 className="text-3xl font-bold">{title}</h1>
        {action && <Link href={action.href} className="rounded-md bg-brand px-6 py-3 text-lg font-semibold text-white hover:bg-brand-dark">{action.label}</Link>}
      </div>
      {hint && <p className="mt-1 max-w-3xl text-muted">{hint}</p>}
    </>
  );
}

export function Card({ title, children, className = "" }: { title?: string; children: React.ReactNode; className?: string }) {
  return (
    <section className={`rounded-lg border border-line bg-surface p-5 ${className}`}>
      {title && <h2 className="mb-3 text-xl font-bold">{title}</h2>}
      {children}
    </section>
  );
}

export const th = "px-4 py-3";
export const td = "px-4 py-3";
export function Table({ children }: { children: React.ReactNode }) {
  return (
    <div className="mt-6 overflow-x-auto rounded-lg border border-line bg-surface">
      <table className="w-full text-left text-lg">{children}</table>
    </div>
  );
}
export function Empty({ children }: { children: React.ReactNode }) {
  return <p className="mt-6 rounded-lg border border-line bg-surface px-5 py-6 text-muted">{children}</p>;
}
export function Dl({ rows }: { rows: [string, React.ReactNode][] }) {
  return (
    <dl className="grid gap-x-8 gap-y-2 sm:grid-cols-2">
      {rows.map(([k, v]) => (
        <div key={k} className="flex justify-between gap-4 border-b border-line py-1.5">
          <dt className="text-muted">{k}</dt><dd className="text-right font-semibold">{v}</dd>
        </div>
      ))}
    </dl>
  );
}
