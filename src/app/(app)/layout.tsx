import { requireSession } from "@/lib/auth";
import { Sidebar } from "@/components/sidebar";

export default async function AppLayout({ children }: { children: React.ReactNode }) {
  const session = await requireSession();
  return (
    <div className="md:flex">
      <Sidebar session={session} />
      <main className="min-w-0 flex-1 p-6 md:p-10">{children}</main>
    </div>
  );
}
