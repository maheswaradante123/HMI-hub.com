import { redirect } from "next/navigation";
import { getSession } from "@/lib/auth";
import { LoginForm } from "./login-form";

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string }>;
}) {
  const session = await getSession();
  if (session) redirect("/");
  const { error } = await searchParams;

  return (
    <main className="mx-auto flex min-h-screen max-w-md flex-col justify-center px-6 py-12">
      <div
        className="mb-6 flex items-center gap-3 rounded-2xl px-5 py-5 text-white"
        style={{ background: "linear-gradient(135deg,#c2410c 0%,#e8590c 55%,#f59e0b 100%)" }}
      >
        <span className="grid h-11 w-11 place-items-center rounded-lg bg-black/25 text-xl font-bold">H</span>
        <div className="leading-tight">
          <h1 className="text-2xl font-bold">HMI Hub</h1>
          <p className="text-sm opacity-90">PT Harmoni Mitra Inovindo</p>
        </div>
      </div>
      {error === "akses" && (
        <p role="alert" className="mb-5 rounded-md bg-warn-bg px-4 py-3">
          Akun ini belum aktif atau belum memiliki role. Hubungi Owner, atau masuk dengan akun lain.
        </p>
      )}
      <div className="rounded-lg border border-line bg-surface p-6">
        <LoginForm />
      </div>
    </main>
  );
}
