"use client";

import Link from "next/link";
import { useActionState } from "react";
import { saveUser, type UserState } from "@/app/(app)/user/actions";

const inputCls = "w-full rounded-md border-2 border-line bg-white px-4 py-3 text-lg";
export function UserForm({ userId, fullName, roleId, deptId, active, roles, depts }: {
  userId: string; fullName: string; roleId: string; deptId: string; active: boolean;
  roles: { id: string; name: string }[]; depts: { id: string; name: string }[];
}) {
  const [state, action, pending] = useActionState<UserState, FormData>(saveUser.bind(null, userId), {});
  return (
    <form action={action} className="max-w-xl space-y-5" noValidate>
      <div><label htmlFor="full_name" className="mb-1 block text-lg font-semibold">Nama</label><input id="full_name" name="full_name" defaultValue={fullName} className={inputCls} /></div>
      <div><label htmlFor="role_id" className="mb-1 block text-lg font-semibold">Role</label>
        <select id="role_id" name="role_id" defaultValue={roleId} className={inputCls}>{roles.map((r) => <option key={r.id} value={r.id}>{r.name}</option>)}</select></div>
      <div><label htmlFor="department_id" className="mb-1 block text-lg font-semibold">Departemen</label>
        <select id="department_id" name="department_id" defaultValue={deptId} className={inputCls}><option value="">Tidak dipilih</option>{depts.map((d) => <option key={d.id} value={d.id}>{d.name}</option>)}</select></div>
      <label className="flex items-center gap-3 text-lg"><input type="checkbox" name="is_active" defaultChecked={active} className="h-6 w-6" /> Akun aktif (boleh masuk)</label>
      {state.error && <p role="alert" className="rounded-md bg-danger-bg px-4 py-3 text-danger">{state.error}</p>}
      <div className="flex gap-3">
        <button type="submit" disabled={pending} className="rounded-md bg-brand px-8 py-3 text-lg font-semibold text-white hover:bg-brand-dark disabled:opacity-60">{pending ? "Menyimpan..." : "Simpan"}</button>
        <Link href="/user" className="rounded-md border-2 border-line px-8 py-3 text-lg font-semibold hover:bg-background">Batal</Link>
      </div>
    </form>
  );
}
