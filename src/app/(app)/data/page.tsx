import Link from "next/link";
import { requireSession } from "@/lib/auth";
import { LOOKUP_RESOURCES } from "@/lib/master/config";
import { Forbidden } from "@/components/forbidden";

export default async function DataHubPage() {
  const session = await requireSession();
  if (!session.can("master_data", "view")) {
    return <Forbidden roleName={session.roleName} what="Data Master" />;
  }
  return (
    <div className="max-w-3xl">
      <h1 className="text-3xl font-bold">Data Master Lain</h1>
      <p className="mt-1 text-muted">Pilih data yang ingin dilihat atau diubah.</p>
      <ul className="mt-6 grid gap-3 sm:grid-cols-2">
        {LOOKUP_RESOURCES.map((r) => (
          <li key={r.key}>
            <Link
              href={`/data/${r.key}`}
              className="block rounded-lg border-2 border-line bg-surface px-5 py-4 text-lg font-semibold hover:border-brand"
            >
              {r.label}
            </Link>
          </li>
        ))}
      </ul>
    </div>
  );
}
