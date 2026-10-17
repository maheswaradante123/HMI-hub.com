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
      <h1 className="text-3xl font-bold">HMI Internal System</h1>
      <p className="mb-8 mt-1 text-muted">PT Harmoni Mitra Inovindo</p>
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
