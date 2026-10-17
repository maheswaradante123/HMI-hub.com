import { requireSession } from "@/lib/auth";
import { Sidebar } from "@/components/sidebar";
import { NavProgress } from "@/components/nav-progress";

export default async function AppLayout({ children }: { children: React.ReactNode }) {
  const session = await requireSession();
  return (
    <div className="md:flex">
      <NavProgress />
      <Sidebar session={session} />
      <main className="min-w-0 flex-1 px-4 pb-10 pt-6 md:px-8 md:pt-8">{children}</main>
    </div>
  );
}
