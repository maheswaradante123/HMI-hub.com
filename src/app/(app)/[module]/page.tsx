import { notFound } from "next/navigation";
import { requireSession } from "@/lib/auth";
import { ALL_ITEMS } from "@/lib/nav";

// Halaman sementara untuk modul yang dibangun di fase berikutnya.
// Pemeriksaan izin tetap dilakukan di server, jadi mengetik alamat
// secara langsung tidak membuka modul yang tidak diizinkan.
export default async function ModulePage({ params }: { params: Promise<{ module: string }> }) {
  const { module: slug } = await params;
  const item = ALL_ITEMS.find((i) => i.slug === slug);
  if (!item) notFound();

  const session = await requireSession();
  if (!session.can(item.module, "view")) {
    return (
      <div className="max-w-2xl">
        <h1 className="text-3xl font-bold">Akses ditolak</h1>
        <p className="mt-3 rounded-md bg-danger-bg px-4 py-3 text-danger">
          Role Anda ({session.roleName}) tidak memiliki izin untuk membuka {item.label}. Hubungi Owner jika
          Anda memerlukan akses.
        </p>
      </div>
    );
  }

  return (
    <div className="max-w-2xl">
      <h1 className="text-3xl font-bold">{item.label}</h1>
      <p className="mt-3 rounded-md border border-line bg-surface px-4 py-3">
        Modul ini akan dibangun pada fase berikutnya.
      </p>
    </div>
  );
}
